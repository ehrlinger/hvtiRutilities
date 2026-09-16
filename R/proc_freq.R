#' Frequency tables, in the style of SAS PROC FREQ
#'
#' @export
proc_freq <- function(data, tables, missing = FALSE, list = FALSE) {
  if (!is.data.frame(data)) {
    stop("'data' must be a data frame.", call. = FALSE)
  }
  .check_columns(tables, data)

  keys <- as.data.frame(lapply(data[tables], .strip_labels),
                        stringsAsFactors = FALSE)
  names(keys) <- tables

  is_missing <- Reduce(`|`, lapply(keys, is.na))
  if (missing) {
    frequency_missing <- 0L
  } else {
    frequency_missing <- sum(is_missing)
    keys <- keys[!is_missing, , drop = FALSE]
  }

  grouped <- .group_ids(keys)
  n_groups <- nrow(grouped$keys)
  out <- grouped$keys
  out$Frequency <- tabulate(grouped$id, nbins = n_groups)

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

  attr(out, "frequency_missing") <- frequency_missing
  out
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
