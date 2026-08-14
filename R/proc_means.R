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
#' no value repeats, both matching SAS. \code{skewness} and \code{kurtosis} are
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
#'   \code{WEIGHT} statement. Observations whose weight is missing are excluded.
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
  if (!is.null(wvec)) {
    keep_w <- !is.na(wvec)
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
    groups <- unique(data[, class, drop = FALSE])
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
  }

  rows <- list()
  for (v in vars) {
    if (is.null(groups)) {
      rows[[length(rows) + 1L]] <-
        .means_row(data[[v]], v, unname(labels[v]), stats, wvec)
    } else {
      for (i in seq_len(nrow(groups))) {
        rows[[length(rows) + 1L]] <- cbind(
          groups[i, , drop = FALSE],
          .means_row(data[[v]][grp_idx[[i]]], v, unname(labels[v]), stats,
                     if (is.null(wvec)) NULL else wvec[grp_idx[[i]]]),
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

## Internal: weighted mean, or the plain mean when w is NULL
.wmean <- function(v, w) {
  if (is.null(w)) mean(v) else sum(w * v) / sum(w)
}

## Internal: weighted variance at SAS VARDEF=DF -- the divisor is the count of
## non-missing observations minus one, not the sum of the weights.
.wvar <- function(v, w) {
  n <- length(v)
  if (n < 2L) {
    return(NA_real_)
  }
  m <- .wmean(v, w)
  css <- if (is.null(w)) sum((v - m)^2) else sum(w * (v - m)^2)
  css / (n - 1)
}

## Internal: SAS skewness -- the adjusted Fisher-Pearson standardised third
## moment, not R's naive moment ratio. Equals e1071::skewness(type = 2).
## The weighted form raises each weight to 3/2, per the SAS documentation.
.wskew <- function(v, w) {
  n <- length(v)
  if (n < 3L) {
    return(NA_real_)
  }
  s <- sqrt(.wvar(v, w))
  if (is.na(s) || s == 0) {
    return(NA_real_)
  }
  z <- (v - .wmean(v, w)) / s
  acc <- if (is.null(w)) sum(z^3) else sum(w^(3 / 2) * z^3)
  (n / ((n - 1) * (n - 2))) * acc
}

## Internal: SAS kurtosis -- excess kurtosis, adjusted Fisher-Pearson.
## Equals e1071::kurtosis(type = 2). The weighted form squares each weight.
.wkurt <- function(v, w) {
  n <- length(v)
  if (n < 4L) {
    return(NA_real_)
  }
  s <- sqrt(.wvar(v, w))
  if (is.na(s) || s == 0) {
    return(NA_real_)
  }
  z <- (v - .wmean(v, w)) / s
  acc <- if (is.null(w)) sum(z^4) else sum(w^2 * z^4)
  (n * (n + 1) / ((n - 1) * (n - 2) * (n - 3))) * acc -
    3 * (n - 1)^2 / ((n - 2) * (n - 3))
}

## =============================================================================
## Internal: the statistic registry.
##
## Each entry carries its compute function plus two flags. `weighted` is the
## contract from the design: .compute_stat() passes weights to a statistic only
## when its flag is TRUE, so a statistic cannot become weighted by someone
## editing its body. `integer` types the zero-row result.
##
## fun(x, v, w): x is the raw vector including NA, v is x with NA removed, and w
## is a numeric vector aligned to v, or NULL.
.STATS <- list(
  n = list(
    fun = function(x, v, w) length(v),
    weighted = FALSE, integer = TRUE
  ),
  nmiss = list(
    fun = function(x, v, w) sum(is.na(x)),
    weighted = FALSE, integer = TRUE
  ),
  nobs = list(
    fun = function(x, v, w) length(x),
    weighted = FALSE, integer = TRUE
  ),
  sumwgt = list(
    fun = function(x, v, w) {
      # Both branches coerce to double. `length()` is integer, and `sum()` of an
      # integer weight column stays integer -- either would make the column type
      # depend on the weights supplied, contradicting `integer = FALSE` and the
      # zero-row path. Coercing before the sum also avoids integer overflow.
      if (length(v) == 0L) {
        NA_real_
      } else if (is.null(w)) {
        as.numeric(length(v))
      } else {
        sum(as.numeric(w))
      }
    },
    weighted = TRUE, integer = FALSE
  ),
  mean = list(
    fun = function(x, v, w) if (length(v) == 0L) NA_real_ else .wmean(v, w),
    weighted = TRUE, integer = FALSE
  ),
  std = list(
    fun = function(x, v, w) sqrt(.wvar(v, w)),
    weighted = TRUE, integer = FALSE
  ),
  min = list(
    fun = function(x, v, w) if (length(v) == 0L) NA_real_ else min(v),
    weighted = FALSE, integer = FALSE
  ),
  max = list(
    fun = function(x, v, w) if (length(v) == 0L) NA_real_ else max(v),
    weighted = FALSE, integer = FALSE
  ),
  sum = list(
    fun = function(x, v, w) {
      if (length(v) == 0L) NA_real_ else if (is.null(w)) sum(v) else sum(w * v)
    },
    weighted = TRUE, integer = FALSE
  ),
  range = list(
    fun = function(x, v, w) if (length(v) == 0L) NA_real_ else max(v) - min(v),
    weighted = FALSE, integer = FALSE
  ),
  stderr = list(
    fun = function(x, v, w) sqrt(.wvar(v, w) / length(v)),
    weighted = TRUE, integer = FALSE
  ),
  cv = list(
    fun = function(x, v, w) {
      s <- sqrt(.wvar(v, w))
      # Return before computing the mean: .wvar() is NA below two observations,
      # and .wmean() of an empty vector is a NaN nothing would use.
      if (is.na(s)) {
        return(NA_real_)
      }
      m <- .wmean(v, w)
      # SAS emits missing when the mean is zero; R would give Inf.
      if (m == 0) NA_real_ else 100 * s / m
    },
    weighted = TRUE, integer = FALSE
  ),
  var = list(
    fun = function(x, v, w) .wvar(v, w),
    weighted = TRUE, integer = FALSE
  ),
  uss = list(
    fun = function(x, v, w) {
      if (length(v) == 0L) NA_real_ else if (is.null(w)) sum(v^2) else sum(w * v^2)
    },
    weighted = TRUE, integer = FALSE
  ),
  css = list(
    fun = function(x, v, w) {
      if (length(v) == 0L) {
        return(NA_real_)
      }
      m <- .wmean(v, w)
      if (is.null(w)) sum((v - m)^2) else sum(w * (v - m)^2)
    },
    weighted = TRUE, integer = FALSE
  ),
  skewness = list(
    fun = function(x, v, w) .wskew(v, w),
    weighted = TRUE, integer = FALSE
  ),
  kurtosis = list(
    fun = function(x, v, w) .wkurt(v, w),
    weighted = TRUE, integer = FALSE
  ),
  qrange = list(
    fun = function(x, v, w) {
      if (length(v) == 0L) {
        return(NA_real_)
      }
      .quantile_stat(v, "q3") - .quantile_stat(v, "q1")
    },
    weighted = FALSE, integer = FALSE
  ),
  mode = list(
    fun = function(x, v, w) {
      if (length(v) == 0L) {
        return(NA_real_)
      }
      u <- unique(v)
      counts <- tabulate(match(v, u))
      top <- max(counts)
      if (top == 1L) {
        return(NA_real_)          # SAS: no mode when nothing repeats
      }
      # SAS reports the smallest value among tied modes.
      min(u[counts == top])
    },
    weighted = FALSE, integer = FALSE
  ),
  median = list(
    fun = function(x, v, w) .quantile_stat(v, "median"),
    weighted = FALSE, integer = FALSE
  ),
  q1 = list(
    fun = function(x, v, w) .quantile_stat(v, "q1"),
    weighted = FALSE, integer = FALSE
  ),
  q3 = list(
    fun = function(x, v, w) .quantile_stat(v, "q3"),
    weighted = FALSE, integer = FALSE
  )
)

## Internal: reject unknown statistic keywords
.validate_stats <- function(stats) {
  known <- names(.STATS)
  ok <- stats %in% known | grepl("^p([1-9]|[1-9][0-9])$", stats)
  if (!all(ok)) {
    stop("Unrecognised statistic keyword(s): ",
         paste(stats[!ok], collapse = ", "),
         ". Valid keywords are: ", paste(known, collapse = ", "),
         ", and pNN for NN from 1 to 99.", call. = FALSE)
  }
  invisible(TRUE)
}

## Internal: one statistic from one vector, SAS semantics.
## `w` is a weight vector aligned to `x`, or NULL. Statistics whose registry
## entry is not marked `weighted` never see it.
.compute_stat <- function(x, stat, w = NULL) {
  x <- as.numeric(x)
  keep <- !is.na(x)
  v <- x[keep]

  entry <- .STATS[[stat]]
  if (is.null(entry)) {
    return(.quantile_stat(v, stat))
  }
  wv <- if (isTRUE(entry$weighted) && !is.null(w)) w[keep] else NULL
  entry$fun(x, v, wv)
}

## Internal: quantile statistics at SAS QNTLDEF=5 (R type 2)
.quantile_stat <- function(v, stat) {
  if (length(v) == 0L) {
    return(NA_real_)
  }
  p <- switch(stat,
    median = 0.5,
    q1     = 0.25,
    q3     = 0.75,
    as.numeric(sub("^p", "", stat)) / 100
  )
  stats::quantile(v, probs = p, type = 2, names = FALSE)
}

## Internal: one output row for one variable
.means_row <- function(x, variable, label, stats, w = NULL) {
  vals <- lapply(stats, function(s) .compute_stat(x, s, w))
  names(vals) <- stats
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
