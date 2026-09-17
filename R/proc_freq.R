#' Frequency tables, in the style of SAS PROC FREQ
#'
#' @description
#' Produces the table SAS \code{PROC FREQ} prints for a \code{TABLES}
#' statement: one row per observed combination of levels, with frequencies
#' and percentages. One call is one table; a SAS step with several
#' \code{TABLES} statements is several calls.
#'
#' @details
#' The last name in \code{tables} is the column variable, the one before it
#' the row variable, and any earlier names are strata, as in SAS
#' \code{TABLES a*b*c}.
#'
#' \strong{Percentages depend on \code{list}, not only the columns shown.}
#' For a crosstab of three or more variables, SAS prints one row-by-column
#' table per stratum and computes \code{Percent} within that stratum. With
#' \code{list = TRUE}, \code{Percent} is of the grand total. The two agree for
#' one- and two-way tables and disagree from three variables on.
#'
#' \strong{Missing values sort first.} SAS treats missing as the smallest
#' value, so under \code{missing = TRUE} the missing level heads the table and
#' the cumulative columns count it first. \code{dplyr::count()} places
#' \code{NA} last, which moves every cumulative value.
#'
#' Rows follow SAS \code{ORDER=INTERNAL}: factors in declared level order,
#' numbers by value, character values by byte value (the C locale, so
#' \code{"B"} sorts before \code{"a"}). Unused factor levels are omitted, as
#' SAS omits zero-count levels without \code{SPARSE}.
#'
#' A \code{haven_labelled} variable is grouped on its value label, as SAS
#' forms levels from formatted values: stored codes sharing a label form one
#' row, shown as the smallest of those codes, and a \code{<var>_label} column
#' holding the label follows it. A value with no label is its own row.
#' Variable labels on the \code{tables} columns are kept.
#'
#' \strong{What counts as missing.} As in SAS, a blank or whitespace-only
#' character value is missing, and so is \code{NaN}. SAS special missing
#' values, read by \code{haven} as \code{\link[haven]{tagged_na}}, are
#' separate missing levels in SAS order: \code{._}, then \code{.}, then
#' \code{.A} to \code{.Z}.
#'
#' \strong{Where this differs from SAS.} Unlabelled doubles are grouped on
#' their exact values, whereas SAS groups on the printed (\code{BEST12.})
#' value, so values that differ past about 12 significant digits stay separate
#' rows here. Non-positive weights are an error, whereas SAS drops zero
#' weights and ignores negative ones; \code{\link{proc_means}} makes the same
#' deliberate choice.
#'
#' Percentages are not rounded. SAS rounds only for display, and a rounded
#' result would fail \code{\link{compare_parity}} against SAS output.
#'
#' Tests of association (\code{CHISQ}, \code{FISHER}, \code{MEASURES} and the
#' rest) are deliberately absent, for the same reason \code{\link{proc_means}}
#' has no inference statistics.
#'
#' @param data A data frame.
#' @param tables Character vector of one or more column names defining the
#'   table.
#' @param missing Logical. \code{FALSE} (the SAS default) excludes rows with a
#'   missing value in any \code{tables} variable from the table and from every
#'   denominator, and reports their count in the \code{frequency_missing}
#'   attribute. \code{TRUE}, SAS \code{/ MISSING}, treats missing as a level,
#'   with each SAS special missing value a level of its own.
#' @param list Logical. \code{TRUE}, SAS \code{/ LIST}, gives cumulative
#'   columns and percentages of the grand total for an n-way table. It has no
#'   effect on a one-way table.
#' @param weights Character or \code{NULL}. Name of a single numeric column of
#'   weights, SAS \code{WEIGHT}. \code{Frequency} becomes the sum of weights.
#'   Rows with a missing weight are excluded entirely; non-positive weights
#'   are an error, as in \code{\link{proc_means}}.
#'
#' @return A data frame with one column per \code{tables} variable (each
#'   followed by a \code{<var>_label} column when the variable carries value
#'   labels), then:
#'   \itemize{
#'     \item for a one-way table, or \code{list = TRUE}: \code{Frequency},
#'       \code{Percent}, \code{Cum_Frequency}, \code{Cum_Percent};
#'     \item for an n-way crosstab: \code{Frequency}, \code{Percent} (within
#'       stratum), \code{Row_Percent}, \code{Col_Percent}.
#'   }
#'   \code{Frequency} is integer when unweighted and double when weighted.
#'   The attribute \code{frequency_missing} holds the count (or weight) of
#'   excluded missing rows, and is \code{0} when none were excluded. A table
#'   with no remaining rows is returned with zero rows, not an error.
#'
#' @seealso \code{\link{proc_means}}, \code{\link{proc_contents}}
#'
#' @export
#'
#' @examples
#' dta <- generate_survival_data(n = 200, seed = 42)
#'
#' # proc freq; table dead / missing;
#' proc_freq(dta, "dead", missing = TRUE)
#'
#' # proc freq; table sex * dead;
#' proc_freq(dta, c("sex", "dead"))
#'
#' # proc freq; table sex * dead / list;
#' proc_freq(dta, c("sex", "dead"), list = TRUE)
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
  .check_output_clash(tables, data)
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

  keys <- as.data.frame(lapply(data[tables], function(x) {
    .sas_missing(.strip_labels(x))
  }), stringsAsFactors = FALSE)
  names(keys) <- tables
  for (v in tables) {
    keys[[v]] <- .label_representative(keys[[v]], val_labels[[v]])
  }

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
  ## by byte value (radix sorts in the C locale, as SAS does). Each variable
  ## sorts on its missing rank first, so special missing values keep SAS order.
  sort_keys <- unlist(lapply(tables, function(v) {
    list(.missing_rank(out[[v]]), out[[v]])
  }), recursive = FALSE)
  ord <- do.call(base::order, c(sort_keys,
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

## Internal: stop when a tables name would be overwritten by an output column,
## either a statistic or the <var>_label column of a value-labelled variable.
.check_output_clash <- function(tables, data) {
  stat_cols <- c("Frequency", "Percent", "Cum_Frequency", "Cum_Percent",
                 "Row_Percent", "Col_Percent")
  has_labels <- vapply(data[tables],
                       function(x) !is.null(labelled::val_labels(x)),
                       logical(1))
  label_cols <- paste0(tables[has_labels], "_label")
  clash <- tables[tables %in% c(stat_cols, label_cols)]
  if (length(clash) > 0L) {
    stop("'tables' names column(s) that clash with output columns: ",
         paste(clash, collapse = ", "), call. = FALSE)
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

## Internal: recode values SAS reads as missing to NA. A blank or
## whitespace-only character value is missing in SAS; haven gives it as "".
## NaN in a double column becomes plain NA, so the two form one level.
.sas_missing <- function(x) {
  if (is.character(x)) {
    x[!is.na(x) & !nzchar(trimws(x))] <- NA
  }
  if (is.double(x)) {
    x[is.nan(x)] <- NA
  }
  x
}

## Internal: SAS forms levels from formatted values, so stored codes sharing
## a value label are one level. Replace each labelled, non-missing value with
## the smallest code (byte order for character) carrying the same label.
## Values without a label, and missing values, are left as they are.
.label_representative <- function(x, labs) {
  if (is.null(labs)) {
    return(x)
  }
  labs <- labs[order(unname(labs), method = "radix")]
  lab <- names(labs)[match(x, unname(labs))]
  hit <- !is.na(x) & !is.na(lab)
  x[hit] <- unname(labs)[match(lab[hit], names(labs))]
  x
}

## Internal: sort rank of each value's missingness, in SAS order
## ._ < . < .A < ... < .Z < any non-missing value. A haven tagged NA carries
## the SAS special missing letter as its tag.
.missing_rank <- function(x) {
  rank <- ifelse(is.na(x), 1L, 28L)
  if (is.double(x)) {
    tag <- tolower(haven::na_tag(x))
    rank[tag %in% "_"] <- 0L
    is_letter <- tag %in% letters
    rank[is_letter] <- 1L + match(tag[is_letter], letters)
  }
  rank
}

## Internal: integer group id per row, and one row of keys per group.
## Groups on exact values (not as.character()), so doubles that agree to 15
## significant digits are not merged. Unused factor levels form no group.
## Each double column also groups on its NA tag, so SAS special missing
## values stay apart; the returned keys are the first row of each group in
## the original keys, which keeps the tag that group_keys() would lose.
.group_ids <- function(keys) {
  gk <- stats::setNames(keys, paste0("k", seq_along(keys)))
  for (i in which(vapply(keys, is.double, logical(1)))) {
    gk[[paste0("t", i)]] <- haven::na_tag(keys[[i]])
  }
  g <- dplyr::group_by(gk, dplyr::across(dplyr::everything()))
  id <- dplyr::group_indices(g)
  first <- match(seq_len(dplyr::n_groups(g)), id)
  list(id = id, keys = keys[first, , drop = FALSE])
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
