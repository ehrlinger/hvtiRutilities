#' Find rows that repeat a key, and choose which to keep
#'
#' @description
#' Lists the rows of `data` that share a value of `key`, such as a
#' patient with two operations on the same day under the key
#' `c("ccfid", "dt_surg")`. Given `order_by`, it also marks the
#' first row of each repeated key to keep, which is how the SAS jobs resolve
#' them: the first operation is kept and the second is treated as a
#' complication of it.
#'
#' @details
#' `data` is never changed. Subset it with `keep`:
#' `data[dk$keep, ]` is unique on `key`, and `data[!dk$keep, ]`
#' holds the rows set aside, to record or to carry as complications. Drop rows
#' in the build, where corrections belong, not in a study job.
#'
#' "First" means first when the rows of a repeated key are sorted by the
#' `order_by` columns, in ascending order. When the first two rows of a
#' repeated key tie on `order_by`, or a row in a repeated key is missing
#' an `order_by` value, there is no first row to keep, and the function
#' stops rather than pick one. Add a column that separates them, such as the
#' time of the operation.
#'
#' A missing key value is treated as a value, as [duplicated()]
#' treats it, so two rows missing the key repeat it. Missing keys are also
#' counted in `summary`.
#'
#' Key values are left out of `rows` unless `show_key = TRUE`,
#' because a key is usually a patient identifier. Use `rows$row` to look
#' at the rows in `data`.
#'
#' @param data A data frame.
#' @param key Names of the columns that should make each row unique.
#' @param order_by `NULL` (the default), or names of the columns that
#'   order the rows of a repeated key. Required for `keep`.
#' @param show_key Include the key columns in `rows`? Default
#'   `FALSE`.
#'
#' @return An object of class `duplicate_keys`, a list of three:
#' \describe{
#'   \item{`summary`}{One row: `rows`, `keys` (distinct key
#'     values), `repeated_keys`, `rows_in_repeats` and
#'     `missing_keys` (rows missing any key column).}
#'   \item{`rows`}{One row per row of `data` in a repeated key, in
#'     data order: `row`, its row number in `data`; `.group`,
#'     numbering the repeated keys in order of appearance; `.rank`, its
#'     place within the key by `order_by` (`NA` without
#'     `order_by`); then the key columns when `show_key = TRUE`.}
#'   \item{`keep`}{A logical vector, one per row of `data`:
#'     `TRUE` for every row outside a repeated key and for the first row
#'     of each repeated key. `NULL` without `order_by`.}
#' }
#'
#' @seealso [register_data()], whose `key` argument refuses a
#'   dataset that repeats it.
#'
#' @examples
#' ops <- data.frame(
#'   id = c(1, 2, 2, 3),
#'   dt_surg = as.Date(c("2010-01-05", "2012-03-01", "2012-03-01", "2011-06-01")),
#'   op_time = c(8, 14, 9, 10)
#' )
#' dk <- duplicate_keys(ops, c("id", "dt_surg"), order_by = "op_time")
#' dk
#' dk$rows
#' ops[dk$keep, ]
#' ops[!dk$keep, ]
#' @export
duplicate_keys <- function(data, key, order_by = NULL, show_key = FALSE) {
  if (!is.data.frame(data)) stop("`data` must be a data frame.", call. = FALSE)
  if (!is.character(key) || !length(key) || anyNA(key)) {
    stop("`key` must name one or more columns.", call. = FALSE)
  }
  if (!is.null(order_by) && (!is.character(order_by) || !length(order_by) || anyNA(order_by))) {
    stop("`order_by` must be NULL or name one or more columns.", call. = FALSE)
  }
  if (!is.logical(show_key) || length(show_key) != 1L || is.na(show_key)) {
    stop("`show_key` must be TRUE or FALSE.", call. = FALSE)
  }
  absent <- setdiff(c(key, order_by), names(data))
  if (length(absent)) {
    stop("Columns not in `data`: ", toString(absent), ".", call. = FALSE)
  }

  n <- nrow(data)
  k <- data[key]
  in_repeat <- duplicated(k) | duplicated(k, fromLast = TRUE)
  rep_rows <- which(in_repeat)
  # Number the repeated keys in order of appearance, with the equality
  # duplicated() uses: match() compares doubles exactly and keeps NA apart
  # from NaN. Each column's values become integer codes, combined one column
  # at a time; only those integers are pasted, so no key value is formatted
  # as text, which would merge keys that print alike, such as 1e15 and
  # 1e15 + 1. Sorting cannot do this: order() interleaves NA and NaN.
  kr <- k[rep_rows, , drop = FALSE]
  group <- rep(1L, length(rep_rows))
  for (x in kr) {
    pair <- paste(group, match(x, unique(x)))
    group <- match(pair, unique(pair))
  }

  rank <- rep(NA_integer_, length(rep_rows))
  keep <- NULL
  if (!is.null(order_by)) {
    ob <- data[rep_rows, order_by, drop = FALSE]
    gaps <- unique(group[!stats::complete.cases(ob)])
    if (length(gaps)) {
      stop(length(gaps), if (length(gaps) == 1L) " repeated key has" else " repeated keys have",
           " a row missing a value of order_by (", toString(order_by),
           "), so its first row cannot be chosen. Fill it, or order by another column.",
           call. = FALSE)
    }
    o <- do.call(order, c(list(group), unname(as.list(ob))))
    rank[o] <- stats::ave(seq_along(o), group[o], FUN = seq_along)
    # Every repeated key has at least two rows, so the row after its first is
    # in the same key; a tie for first place is the two agreeing on order_by.
    first <- match(seq_len(max(c(0L, group))), group[o])
    tied <- .same_rows(ob, o[first], o[first + 1L])
    if (any(tied)) {
      stop(sum(tied), if (sum(tied) == 1L) " repeated key ties" else " repeated keys tie",
           " on order_by (", toString(order_by),
           ") for first place, so its first row cannot be chosen. Order by a column that separates them.",
           call. = FALSE)
    }
    keep <- rep(TRUE, n)
    keep[rep_rows[rank != 1L]] <- FALSE
  }

  rows <- data.frame(row = rep_rows, .group = group, .rank = rank)
  if (show_key) rows <- cbind(rows, k[rep_rows, , drop = FALSE], row.names = NULL)
  summary <- data.frame(
    rows = n,
    keys = nrow(unique(k)),
    repeated_keys = length(unique(group)),
    rows_in_repeats = length(rep_rows),
    missing_keys = sum(!stats::complete.cases(k))
  )
  structure(list(summary = summary, rows = rows, keep = keep), class = "duplicate_keys",
            key = key, order_by = order_by)
}

# For each pair (i[j], i2[j]), are rows i[j] and i2[j] of d equal in every
# column? Compares typed values, and a missing value equals only a missing value.
.same_rows <- function(d, i, i2) {
  same <- rep(TRUE, length(i))
  for (x in d) {
    a <- x[i]
    b <- x[i2]
    same <- same & ((is.na(a) & is.na(b)) | ((a == b) %in% TRUE))
  }
  same
}

#' @export
print.duplicate_keys <- function(x, ...) {
  s <- x$summary
  cat("Key: ", toString(attr(x, "key")), "\n", sep = "")
  cat(s$rows, " rows, ", s$keys, " distinct keys. ", sep = "")
  if (s$repeated_keys == 0L) {
    cat("No key repeats.\n")
  } else {
    cat(s$repeated_keys, if (s$repeated_keys == 1L) " key repeats" else " keys repeat",
        ", over ", s$rows_in_repeats, " rows.\n", sep = "")
  }
  if (s$missing_keys) cat(s$missing_keys, " rows are missing a key value.\n", sep = "")
  if (!is.null(x$keep)) {
    cat("Keeping the first by ", toString(attr(x, "order_by")), ": ",
        sum(!x$keep), " rows set aside.\n", sep = "")
  }
  invisible(x)
}
