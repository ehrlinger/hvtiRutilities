## Internal: the statistic engine, moved unchanged from R/proc_means.R: the
## weighted helpers, the statistic registry and the dispatcher.

## Internal: weighted mean, or the plain mean when w is NULL
.wmean <- function(v, w) {
  if (is.null(w)) mean(v) else sum(w * v) / sum(as.numeric(w))
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
    # SAS divides by sqrt(sum(w)), which is sqrt(n) when unweighted.
    fun = function(x, v, w) {
      sqrt(.wvar(v, w) / if (is.null(w)) length(v) else sum(as.numeric(w)))
    },
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
      if (length(v) == 1L) {
        return(v)                 # SAS: a single observation is its own mode
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
