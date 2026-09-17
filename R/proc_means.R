#' Summarise numeric variables, in the style of SAS PROC MEANS
#'
#' @description
#' Produces the table SAS \code{PROC MEANS} prints: one row per analysis
#' variable, one column per requested statistic, in the order requested.
#'
#' @details
#' Quantiles use \code{stats::quantile(type = 2)}, which is the R equivalent of
#' SAS's default \code{QNTLDEF=5}. This matters: R's own default is
#' \code{type = 7}, a different estimator that disagrees with SAS on the small
#' and even-numbered samples clinical subgroups produce. For
#' \code{c(1, 2, 3, 4)}, the first quartile is \code{1.5} in SAS and
#' \code{1.75} under R's default. The median agrees, which is why the
#' discrepancy hides.
#'
#' With \code{vars = NULL} all numeric columns are analysed, matching SAS's
#' behaviour when the \code{VAR} statement is omitted. Logical columns are not
#' \code{is.numeric()} in R and so are excluded from that default set; naming
#' one in \code{vars} coerces it to 0/1, making \code{mean} a proportion as
#' \code{PROC MEANS} would give.
#'
#' Rows are ordered by analysis variable first, then by class level. A factor
#' class variable orders by its declared level order rather than
#' alphabetically, matching SAS's default \code{ORDER=INTERNAL}; this keeps
#' ordered clinical scales such as NYHA class in their clinical sequence.
#'
#' Weights do not apply uniformly, and this follows \code{PROC MEANS} rather
#' than being a simplification. Weighted: \code{mean}, \code{std}, \code{var},
#' \code{cv}, \code{stderr}, \code{sum}, \code{uss}, \code{css},
#' \code{skewness}, \code{kurtosis}, \code{sumwgt}. Unweighted: \code{n},
#' \code{nmiss}, \code{nobs}, \code{min}, \code{max}, \code{range},
#' \code{mode}, and every quantile -- \code{median}, \code{q1}, \code{q3},
#' \code{pNN} and \code{qrange}. \code{PROC MEANS} does not compute weighted
#' quantiles at all; that is \code{PROC UNIVARIATE}. So
#' \code{proc_means(d, stats = "median", weights = "wt")} returns the
#' \emph{unweighted} median.
#'
#' \code{mode} returns the smallest value among tied modes, and \code{NA} when
#' no value repeats, except that a single observation is its own mode; all
#' three match SAS. Weighted \code{stderr} divides the weighted standard
#' deviation by the square root of the sum of the weights, as SAS does, not by
#' the square root of the count. \code{skewness} and \code{kurtosis} are
#' the adjusted Fisher-Pearson forms SAS uses, not R's naive moment ratios, and
#' are \code{NA} for a constant column rather than \code{NaN}.
#'
#' The \code{PROC UNIVARIATE} inference statistics (\code{NORMAL}, \code{PROBN},
#' \code{T}, \code{PROBT}, \code{MSIGN}, \code{PROBM}, \code{SIGNRANK},
#' \code{PROBS}) are deliberately absent: they would make this a
#' hypothesis-testing function rather than a summary one. \code{CLM}, the
#' confidence limits of the mean, is absent for the same reason.
#'
#' \code{cv} is \code{NA} when the mean is zero, matching SAS; R's arithmetic
#' would give \code{Inf}.
#'
#' @param data A data frame, tibble, or similar tabular object.
#' @param vars Character vector of columns to analyse. \code{NULL} (default)
#'   selects every numeric column not named in \code{class}.
#' @param class Character vector of grouping columns, prepended to the result
#'   as leading columns. Rows with a missing value in any class variable are
#'   dropped, matching SAS's default.
#' @param stats Character vector of SAS statistic keywords. Counts:
#'   \code{"n"}, \code{"nmiss"}, \code{"nobs"}, \code{"sumwgt"}. Location:
#'   \code{"mean"}, \code{"median"}, \code{"mode"}. Spread: \code{"std"},
#'   \code{"var"}, \code{"stderr"}, \code{"cv"}, \code{"min"}, \code{"max"},
#'   \code{"range"}, \code{"qrange"}, \code{"q1"}, \code{"q3"}, or any
#'   \code{"pNN"} for NN from 1 to 99. Sums: \code{"sum"}, \code{"uss"},
#'   \code{"css"}. Shape: \code{"skewness"}, \code{"kurtosis"}.
#' @param weights Character or \code{NULL}. Name of a single numeric column of
#'   \code{data} to use as an observation weight, mirroring the SAS
#'   \code{WEIGHT} statement. Observations whose weight is missing are excluded
#'   from every statistic except \code{nobs}, which counts them, as SAS does.
#'   A zero or negative weight is an error naming the offending rows: SAS's own
#'   handling of non-positive weights varies across procedures and versions, so
#'   this fails loudly rather than encode a guess.
#'
#' @return A data frame with one row per analysis variable per class
#'   combination. Columns are the \code{class} variables (when supplied), then
#'   \code{variable}, \code{label}, then one column per requested statistic in
#'   the order given by \code{stats}. Count statistics (\code{n},
#'   \code{nmiss}) are integer; all others are numeric.
#'
#' @seealso \code{\link{proc_contents}} for variable metadata.
#'
#' @importFrom stats quantile sd complete.cases
#'
#' @export
#'
#' @examples
#' dta <- generate_survival_data(n = 200, seed = 42)
#'
#' # SAS default statistics over every numeric variable
#' head(proc_means(dta))
#'
#' # Named variables and an explicit statistic list
#' proc_means(dta, vars = c("age", "bmi"),
#'            stats = c("n", "mean", "median", "p15"))
#'
#' # Weighted statistics
#' dta <- data.frame(age = c(51, 63, 47, 72), wt = c(1, 2, 1, 4))
#' proc_means(dta, vars = "age", stats = c("n", "sumwgt", "mean"),
#'            weights = "wt")
proc_means <- function(data, vars = NULL, class = NULL,
                       stats = c("n", "mean", "std", "min", "max"),
                       weights = NULL) {
  if (!is.data.frame(data)) {
    stop("'data' must be a data frame.", call. = FALSE)
  }
  .validate_stats(stats)

  labels <- labelled::var_label(data, unlist = TRUE, null_action = "fill")

  wvec <- .validate_weights(weights, data)
  # Rows dropped for a missing weight still count toward nobs, as in SAS.
  excluded <- data[0, , drop = FALSE]
  if (!is.null(wvec)) {
    keep_w <- !is.na(wvec)
    excluded <- data[!keep_w, , drop = FALSE]
    data <- data[keep_w, , drop = FALSE]
    wvec <- wvec[keep_w]
  }

  if (!is.null(class)) {
    .check_columns(class, data)
  }

  if (is.null(vars)) {
    numeric_cols <- names(data)[vapply(data, is.numeric, logical(1))]
    vars <- setdiff(numeric_cols, c(class, weights))
  } else {
    .check_columns(vars, data)
    usable <- vapply(data[vars], function(x) is.numeric(x) || is.logical(x),
                     logical(1))
    if (!all(usable)) {
      stop("Non-numeric column(s) named in 'vars': ",
           paste(vars[!usable], collapse = ", "), call. = FALSE)
    }
  }

  if (!is.null(weights) && weights %in% c(vars, class)) {
    stop("Weight column '", weights,
         "' is also named in 'vars' or 'class'. A column cannot be both a ",
         "weight and an analysis or class variable.", call. = FALSE)
  }

  if (length(vars) == 0L) {
    warning("No numeric columns to analyse; returning a zero-row result.",
            call. = FALSE)
    return(.empty_means(class, stats))
  }

  groups <- NULL
  grp_idx <- NULL
  if (!is.null(class) && length(class) > 0L) {
    keep <- stats::complete.cases(data[, class, drop = FALSE])
    data <- data[keep, , drop = FALSE]
    if (!is.null(wvec)) {
      wvec <- wvec[keep]
    }
    # Levels come from every row with a complete class value, including rows
    # dropped for a missing weight: SAS PROC MEANS still prints a level whose
    # every weight is missing (N = 0, with its rows counted in nobs).
    excl_cls <- excluded[, class, drop = FALSE]
    excl_cls <- excl_cls[stats::complete.cases(excl_cls), , drop = FALSE]
    groups <- unique(rbind(data[, class, drop = FALSE], excl_cls))
    groups <- groups[do.call(base::order,
                             c(unname(as.list(groups)),
                               list(method = "radix"))), ,
                     drop = FALSE]
    rownames(groups) <- NULL

    grp_idx <- lapply(seq_len(nrow(groups)), function(i) {
      ok <- rep(TRUE, nrow(data))
      for (k in class) {
        ok <- ok & (data[[k]] == groups[[k]][i])
      }
      which(ok)
    })
    grp_excluded <- vapply(seq_len(nrow(groups)), function(i) {
      ok <- rep(TRUE, nrow(excluded))
      for (k in class) {
        ok <- ok & !is.na(excluded[[k]]) & excluded[[k]] == groups[[k]][i]
      }
      sum(ok)
    }, integer(1))
  }

  rows <- list()
  for (v in vars) {
    if (is.null(groups)) {
      rows[[length(rows) + 1L]] <-
        .means_row(data[[v]], v, unname(labels[v]), stats, wvec,
                   n_excluded = nrow(excluded))
    } else {
      for (i in seq_len(nrow(groups))) {
        rows[[length(rows) + 1L]] <- cbind(
          groups[i, , drop = FALSE],
          .means_row(data[[v]][grp_idx[[i]]], v, unname(labels[v]), stats,
                     if (is.null(wvec)) NULL else wvec[grp_idx[[i]]],
                     n_excluded = grp_excluded[i]),
          stringsAsFactors = FALSE
        )
      }
    }
  }

  if (length(rows) == 0L) {
    warning("All rows dropped: every value of the class variable(s) is missing; ",
            "returning a zero-row result.", call. = FALSE)
    return(.empty_means(class, stats))
  }

  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

## Internal: stop if any named column is absent from the data
.check_columns <- function(cols, data) {
  absent <- setdiff(cols, names(data))
  if (length(absent) > 0L) {
    stop("Column(s) not found in 'data': ",
         paste(absent, collapse = ", "), call. = FALSE)
  }
  invisible(TRUE)
}

## Internal: validate the weights argument and return the weight vector.
##
## Non-positive weights are an error rather than a silent coercion. SAS's own
## handling varies across procedures and versions -- "negative treated as zero",
## "non-positive excluded", "excluded from N but not NOBS" -- so failing loudly
## is preferred to encoding a guess and calling it parity. This can be relaxed
## once the Phase 1 SAS oracle can settle it; because the current behaviour is an
## error, no existing result changes silently when it is.
.validate_weights <- function(weights, data) {
  if (is.null(weights)) {
    return(NULL)
  }
  if (!is.character(weights) || length(weights) != 1L) {
    stop("'weights' must be a single column name.", call. = FALSE)
  }
  .check_columns(weights, data)

  w <- data[[weights]]
  if (!is.numeric(w)) {
    stop("Weight column '", weights, "' must be numeric.", call. = FALSE)
  }
  bad <- which(!is.na(w) & w <= 0)
  if (length(bad) > 0L) {
    stop("Weight column '", weights, "' has non-positive value(s) at row(s): ",
         paste(bad, collapse = ", "),
         ". Weights must be positive.", call. = FALSE)
  }
  w
}

## Internal: one output row for one variable
.means_row <- function(x, variable, label, stats, w = NULL,
                       n_excluded = 0L) {
  vals <- lapply(stats, function(s) .compute_stat(x, s, w))
  names(vals) <- stats
  if ("nobs" %in% stats) {
    vals$nobs <- vals$nobs + as.integer(n_excluded)
  }
  cbind(
    data.frame(variable = variable, label = label, stringsAsFactors = FALSE),
    as.data.frame(vals, stringsAsFactors = FALSE)
  )
}

## Internal: zero-row result with the correct columns
.empty_means <- function(class, stats) {
  out <- data.frame(variable = character(), label = character(),
                    stringsAsFactors = FALSE)
  for (s in stats) {
    entry <- .STATS[[s]]
    out[[s]] <- if (isTRUE(entry$integer)) integer() else numeric()
  }
  if (!is.null(class) && length(class) > 0L) {
    pre <- as.data.frame(
      stats::setNames(replicate(length(class), character(), simplify = FALSE),
                      class),
      stringsAsFactors = FALSE
    )
    out <- cbind(pre, out)
  }
  out
}
