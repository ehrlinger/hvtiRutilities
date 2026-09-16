#' Frequency tables, in the style of SAS PROC FREQ
#'
#' @export
proc_freq <- function(data, tables, missing = FALSE, list = FALSE,
                      weights = NULL) {
  if (!is.data.frame(data)) {
    stop("'data' must be a data frame.", call. = FALSE)
  }
  if (!is.character(tables) || length(tables) == 0L || anyNA(tables)) {
    stop("'tables' must be a non-empty character vector of column names.",
         call. = FALSE)
  }
  if (anyDuplicated(tables) > 0L) {
    stop("'tables' names a column more than once: ",
         paste(unique(tables[duplicated(tables)]), collapse = ", "),
         call. = FALSE)
  }
  .check_columns(tables, data)
  .check_flag(missing, "missing")
  .check_flag(list, "list")

  wvec <- .validate_weights(weights, data)
  if (!is.null(weights) && weights %in% tables) {
    stop("Weight column '", weights, "' is also named in 'tables'. A column ",
         "cannot be both a weight and a table variable.", call. = FALSE)
  }

  ## Read labels before any row subsetting: subsetting strips them.
  var_labels <- lapply(data[tables], labelled::var_label)
  val_labels <- lapply(data[tables], labelled::val_labels)

  keys <- as.data.frame(lapply(data[tables], .strip_labels),
                        stringsAsFactors = FALSE)
  names(keys) <- tables

  if (!is.null(wvec)) {
    keep <- !is.na(wvec)
    keys <- keys[keep, , drop = FALSE]
    wvec <- wvec[keep]
  }

  is_missing <- Reduce(`|`, lapply(keys, is.na))
  if (missing) {
    frequency_missing <- if (is.null(wvec)) 0L else 0
  } else {
    frequency_missing <- if (is.null(wvec)) {
      sum(is_missing)
    } else {
      sum(wvec[is_missing])
    }
    keys <- keys[!is_missing, , drop = FALSE]
    wvec <- wvec[!is_missing]
  }

  grouped <- .group_ids(keys)
  n_groups <- nrow(grouped$keys)
  out <- grouped$keys
  out$Frequency <- if (is.null(wvec)) {
    tabulate(grouped$id, nbins = n_groups)
  } else if (n_groups == 0L) {
    numeric(0)
  } else {
    as.vector(rowsum(wvec, grouped$id))
  }

  ## SAS ORDER=INTERNAL: missing sorts first, factors by level, characters
  ## by byte value (radix sorts in the C locale, as SAS does).
  ord <- do.call(base::order, c(unname(as.list(out[tables])),
                                list(na.last = FALSE, method = "radix")))
  out <- out[ord, , drop = FALSE]
  rownames(out) <- NULL

  freq <- out$Frequency
  n_vars <- length(tables)
  if (n_vars == 1L || list) {
    total <- sum(freq)
    out$Percent <- 100 * freq / total
    out$Cum_Frequency <- cumsum(freq)
    out$Cum_Percent <- 100 * out$Cum_Frequency / total
  } else {
    strata <- tables[seq_len(n_vars - 2L)]
    row_var <- tables[n_vars - 1L]
    col_var <- tables[n_vars]
    out$Percent <- .pct_within(freq, out[strata])
    out$Row_Percent <- .pct_within(freq, out[c(strata, row_var)])
    out$Col_Percent <- .pct_within(freq, out[c(strata, col_var)])
  }

  for (v in tables) {
    labelled::var_label(out[[v]]) <- var_labels[[v]]
  }
  out <- .add_value_label_columns(out, tables, val_labels)

  attr(out, "frequency_missing") <- frequency_missing
  out
}

## Internal: stop unless x is a single TRUE or FALSE
.check_flag <- function(x, name) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    stop("'", name, "' must be a single TRUE or FALSE.", call. = FALSE)
  }
  invisible(TRUE)
}

## Internal: the stored values of a column, without value or variable labels.
## A haven_labelled vector becomes its underlying numeric or character vector;
## a factor stays a factor so its level order drives the sort.
.strip_labels <- function(x) {
  if (inherits(x, "haven_labelled")) {
    x <- haven::zap_labels(x)
  }
  attr(x, "label") <- NULL
  x
}

## Internal: integer group id per row, and one row of keys per group.
## Groups on exact values (not as.character()), so doubles that agree to 15
## significant digits are not merged. Unused factor levels form no group.
.group_ids <- function(keys) {
  g <- dplyr::group_by(keys, dplyr::across(dplyr::everything()))
  list(id = dplyr::group_indices(g),
       keys = as.data.frame(dplyr::group_keys(g)))
}

## Internal: 100 * freq as a share of its total within each group of keys.
## With no key columns the whole table is one group.
.pct_within <- function(freq, keys) {
  if (length(freq) == 0L) {
    return(numeric(0))
  }
  if (ncol(keys) == 0L) {
    return(100 * freq / sum(freq))
  }
  id <- .group_ids(keys)$id
  100 * freq / as.vector(rowsum(freq, id))[id]
}

## Internal: insert a <var>_label column after each variable that carried
## value labels, holding the label for each stored value (NA when none).
.add_value_label_columns <- function(out, tables, val_labels) {
  for (v in rev(tables)) {
    labs <- val_labels[[v]]
    if (is.null(labs)) {
      next
    }
    lab_col <- names(labs)[match(out[[v]], unname(labs))]
    pos <- match(v, names(out))
    out <- cbind(out[seq_len(pos)],
                 stats::setNames(data.frame(lab_col, stringsAsFactors = FALSE),
                                 paste0(v, "_label")),
                 out[-seq_len(pos)])
  }
  out
}
