#' Compare two versions of a dataset
#'
#' @description
#' Summarises the differences between two data pulls of the same dataset:
#' added or dropped columns, row count changes, type changes, label changes
#' and factor-level changes. This is useful for auditing data drift when a new
#' extract arrives, and pairs naturally with the manifest system.
#'
#' **Values are not compared.** Matching rows across two pulls needs a
#' key, and this function takes none, so two datasets with the same shape,
#' classes, labels and levels but different values compare as equal. The
#' printed summary says so. Compare values on a key with `merge()` when
#' that is the question.
#'
#' @param old A data frame representing the previous version of the dataset.
#' @param new A data frame representing the current version of the dataset.
#'
#' @return A list with the following elements:
#' \describe{
#'   \item{rows_old}{Number of rows in `old`}
#'   \item{rows_new}{Number of rows in `new`}
#'   \item{cols_added}{Character vector of column names present in `new`
#'     but not `old`}
#'   \item{cols_dropped}{Character vector of column names present in
#'     `old` but not `new`}
#'   \item{type_changes}{Data frame with columns `variable`,
#'     `old_class`, `new_class` for shared columns whose primary
#'     class changed}
#'   \item{label_changes}{Data frame with columns `variable`,
#'     `old_label`, `new_label` for shared columns whose label
#'     changed}
#'   \item{level_changes}{Data frame with columns `variable`,
#'     `old_levels`, `new_levels` (levels joined with
#'     `", "`) for shared columns that are factors in both and whose
#'     levels, or their order, changed}
#' }
#'
#' @seealso [update_manifest()], [verify_manifest()]
#'
#' @export
#'
#' @examples
#' # Simulate two data pulls
#' v1 <- generate_survival_data(n = 100, seed = 1)
#' v2 <- generate_survival_data(n = 120, seed = 2)
#'
#' # Add a column to v2 and drop one
#' v2$new_var <- rnorm(120)
#' v2$dead <- NULL
#'
#' diff <- compare_datasets(v1, v2)
#' diff$rows_old
#' diff$rows_new
#' diff$cols_added
#' diff$cols_dropped
compare_datasets <- function(old, new) {
  if (!is.data.frame(old)) {
    stop("'old' must be a data frame.", call. = FALSE)
  }
  if (!is.data.frame(new)) {
    stop("'new' must be a data frame.", call. = FALSE)
  }

  old_names <- names(old)
  new_names <- names(new)
  shared <- intersect(old_names, new_names)

  # Type changes on shared columns
  if (length(shared) > 0L) {
    old_types <- vapply(old[shared], function(x) class(x)[1L], character(1))
    new_types <- vapply(new[shared], function(x) class(x)[1L], character(1))
    changed <- old_types != new_types
    type_changes <- data.frame(
      variable  = shared[changed],
      old_class = unname(old_types[changed]),
      new_class = unname(new_types[changed]),
      stringsAsFactors = FALSE
    )
  } else {
    type_changes <- data.frame(
      variable = character(), old_class = character(),
      new_class = character(), stringsAsFactors = FALSE
    )
  }

  # Label changes on shared columns
  if (length(shared) > 0L) {
    old_labels <- labelled::var_label(old[shared], unlist = TRUE,
                                      null_action = "fill")
    new_labels <- labelled::var_label(new[shared], unlist = TRUE,
                                      null_action = "fill")
    label_changed <- old_labels != new_labels
    label_changes <- data.frame(
      variable  = shared[label_changed],
      old_label = unname(old_labels[label_changed]),
      new_label = unname(new_labels[label_changed]),
      stringsAsFactors = FALSE
    )
  } else {
    label_changes <- data.frame(
      variable = character(), old_label = character(),
      new_label = character(), stringsAsFactors = FALSE
    )
  }

  # Level changes on shared columns that are factors in both
  both_factor <- shared[vapply(shared, function(v) {
    is.factor(old[[v]]) && is.factor(new[[v]])
  }, logical(1))]
  lev_changed <- both_factor[!vapply(both_factor, function(v) {
    identical(levels(old[[v]]), levels(new[[v]]))
  }, logical(1))]
  level_changes <- data.frame(
    variable   = lev_changed,
    old_levels = vapply(lev_changed, function(v) paste(levels(old[[v]]), collapse = ", "),
                        character(1), USE.NAMES = FALSE),
    new_levels = vapply(lev_changed, function(v) paste(levels(new[[v]]), collapse = ", "),
                        character(1), USE.NAMES = FALSE),
    stringsAsFactors = FALSE
  )

  structure(
    list(
      rows_old      = nrow(old),
      rows_new      = nrow(new),
      cols_added    = setdiff(new_names, old_names),
      cols_dropped  = setdiff(old_names, new_names),
      type_changes  = type_changes,
      label_changes = label_changes,
      level_changes = level_changes
    ),
    class = "dataset_comparison"
  )
}

#' @export
print.dataset_comparison <- function(x, ...) {
  cat("Dataset Comparison\n")
  cat("  Rows: ", x$rows_old, " -> ", x$rows_new, "\n", sep = "")

  if (length(x$cols_added) > 0L) {
    cat("  Columns added:   ", paste(x$cols_added, collapse = ", "), "\n")
  }
  if (length(x$cols_dropped) > 0L) {
    cat("  Columns dropped: ", paste(x$cols_dropped, collapse = ", "), "\n")
  }
  if (nrow(x$type_changes) > 0L) {
    cat("  Type changes:\n")
    for (i in seq_len(nrow(x$type_changes))) {
      cat("    ", x$type_changes$variable[i], ": ",
          x$type_changes$old_class[i], " -> ",
          x$type_changes$new_class[i], "\n", sep = "")
    }
  }
  if (nrow(x$label_changes) > 0L) {
    cat("  Label changes:\n")
    for (i in seq_len(nrow(x$label_changes))) {
      cat("    ", x$label_changes$variable[i], ": '",
          x$label_changes$old_label[i], "' -> '",
          x$label_changes$new_label[i], "'\n", sep = "")
    }
  }
  # An object saved before level_changes existed has none to print.
  level_changes <- x$level_changes
  if (is.null(level_changes)) level_changes <- data.frame(variable = character())
  if (nrow(level_changes) > 0L) {
    cat("  Level changes:\n")
    for (i in seq_len(nrow(level_changes))) {
      cat("    ", level_changes$variable[i], ": [",
          level_changes$old_levels[i], "] -> [",
          level_changes$new_levels[i], "]\n", sep = "")
    }
  }
  if (length(x$cols_added) == 0L && length(x$cols_dropped) == 0L &&
        nrow(x$type_changes) == 0L && nrow(x$label_changes) == 0L &&
        nrow(level_changes) == 0L && x$rows_old == x$rows_new) {
    cat("  No differences in row count, columns, classes, labels or factor",
        "levels.\n")
  }
  cat("  Values were not compared.\n")
  invisible(x)
}
