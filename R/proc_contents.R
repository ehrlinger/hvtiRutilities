#' Describe a dataset's variables, in the style of SAS PROC CONTENTS
#'
#' @description
#' Reports the variable-level metadata that SAS `PROC CONTENTS` prints:
#' creation position, name, SAS type, format, and label, alongside the R class
#' and simple completeness counts.
#'
#' @details
#' Reading a `.sas7bdat` through \pkg{haven} is lossy. Variable name,
#' label, `format.sas`, and creation order survive; SAS storage
#' `LENGTH`, `POS` (position within the observation), informat, and
#' the dataset's created/modified timestamps do not. Those fields are omitted
#' rather than inferred, because inferred values would look authoritative and
#' would disagree with the source dataset whenever its `LENGTH` statement
#' differed from the default.
#'
#' "Survive" means preserved *when the source carries them*, not present
#' on every variable. A SAS variable need not have a label or a format, and
#' many do not: in one 879-variable clinical build, 865 variables carried a
#' label and 395 carried a `format.sas`. An `NA` in `format`
#' therefore reports that the source variable had no format, not that one was
#' lost in reading. `label` does not behave this way — see *Value*.
#'
#' The SAS `Type` column is two-valued, so the mapping from R is
#' deliberately lossy: `character` and `factor` become `"Char"`;
#' everything else, including `logical`, `Date`, and `POSIXct`,
#' becomes `"Num"`. A SAS date is a number carrying a date format, so
#' `type` reports `"Num"` while `class` reports `"Date"` —
#' keeping the disagreement visible rather than hiding it.
#'
#' For a data frame with columns but zero rows — a fully filtered cohort, say —
#' `pct_missing` is `NaN` rather than a number in 0-100, because
#' `mean(is.na(x))` on an empty vector is `0/0`. The proportion of
#' missing values among no values is genuinely undefined, and reporting
#' `0` would assert that nothing is missing. Callers formatting this
#' column for display should handle `NaN` explicitly.
#'
#' @param data A data frame, tibble, or similar tabular object.
#' @param order Variable ordering. `"alpha"` (default) sorts
#'   case-insensitively by name, matching SAS's default *Alphabetic List
#'   of Variables and Attributes*; `"varnum"` keeps creation order. The
#'   `num` column always reports creation position regardless of sort.
#'
#' @return An object of class `proc_contents`: a list with two elements.
#' \describe{
#'   \item{header}{One-row data frame with `observations` (row count),
#'     `variables` (column count), and `label` (dataset label, or
#'     `NA`)}
#'   \item{variables}{Data frame with one row per column and the columns
#'     `num` (creation position), `variable`, `type`
#'     (`"Num"`/`"Char"`), `format` (SAS format, or `NA`),
#'     `label`, `class` (R class), `n_unique` (distinct
#'     non-`NA` values), and `pct_missing` (0-100, 1 decimal place,
#'     or `NaN` when `data` has zero rows)}
#' }
#'
#' `label` is never `NA`: it falls back to the variable's own name
#' when the source carries no label, via
#' `labelled::var_label(null_action = "fill")`. An unlabelled variable is
#' therefore indistinguishable here from one whose label equals its name, and
#' both are common. Callers recording this output as a durable description of
#' a source dataset — a schema sidecar, a data dictionary kept after the
#' source is retired — should read labels from the source attributes directly
#' rather than from this column, or they will record a fallback as though it
#' were the dataset's own metadata.
#'
#' @seealso [proc_means()] for numeric summaries,
#'   [data_dictionary()] for a flattened documentation table.
#'
#' @export
#'
#' @examples
#' dta <- sample_data(n = 50)
#' pc <- proc_contents(dta)
#' pc$header
#' pc$variables
#'
#' # Creation order rather than alphabetical
#' proc_contents(dta, order = "varnum")$variables
proc_contents <- function(data, order = c("alpha", "varnum")) {
  if (!is.data.frame(data)) {
    stop("'data' must be a data frame.", call. = FALSE)
  }
  ord <- match.arg(order)

  header <- data.frame(
    observations = nrow(data),
    variables    = ncol(data),
    label        = .dataset_label(data),
    stringsAsFactors = FALSE
  )

  if (ncol(data) == 0L) {
    return(structure(list(header = header, variables = .empty_contents()),
                     class = "proc_contents"))
  }

  labels <- labelled::var_label(data, unlist = TRUE, null_action = "fill")

  variables <- data.frame(
    num         = seq_len(ncol(data)),
    variable    = names(data),
    type        = vapply(data, .sas_type, character(1)),
    format      = vapply(data, .sas_format, character(1)),
    label       = unname(labels),
    class       = vapply(data, function(x) class(x)[1L], character(1)),
    n_unique    = vapply(data, function(x) length(unique(x[!is.na(x)])),
                         integer(1)),
    pct_missing = vapply(data, function(x) round(mean(is.na(x)) * 100, 1),
                         numeric(1)),
    stringsAsFactors = FALSE
  )

  if (ord == "alpha") {
    variables <- variables[base::order(tolower(variables$variable),
                                       method = "radix"), ,
                           drop = FALSE]
  }
  rownames(variables) <- NULL

  structure(list(header = header, variables = variables),
            class = "proc_contents")
}

#' @export
print.proc_contents <- function(x, ...) {
  cat("Observations: ", x$header$observations, "\n", sep = "")
  cat("Variables:    ", x$header$variables, "\n", sep = "")
  if (!is.na(x$header$label)) {
    cat("Label:        ", x$header$label, "\n", sep = "")
  }
  cat("\n")
  print(x$variables)
  invisible(x)
}

## Internal: SAS two-valued type from an R vector
.sas_type <- function(x) {
  if (is.character(x) || is.factor(x)) "Char" else "Num"
}

## Internal: SAS format attribute, NA when absent
.sas_format <- function(x) {
  fmt <- attr(x, "format.sas", exact = TRUE)
  if (is.null(fmt) || length(fmt) == 0L) NA_character_ else as.character(fmt)[1L]
}

## Internal: dataset-level label attribute, NA when absent
.dataset_label <- function(data) {
  lab <- attr(data, "label", exact = TRUE)
  if (is.null(lab) || length(lab) == 0L) NA_character_ else as.character(lab)[1L]
}

## Internal: zero-row variables frame with the correct column types
.empty_contents <- function() {
  data.frame(
    num         = integer(),
    variable    = character(),
    type        = character(),
    format      = character(),
    label       = character(),
    class       = character(),
    n_unique    = integer(),
    pct_missing = numeric(),
    stringsAsFactors = FALSE
  )
}
