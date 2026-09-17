## =============================================================================
## Internal: the statistic engine shared by proc_means() and proc_univariate().
##
## One registry of SAS statistic keywords, one dispatcher (.compute_stat()) and
## the weighted helpers. A procedure selects its keywords and its weighting
## rules through a context built by .stat_ctx(); the defaults reproduce
## proc_means() exactly, so data_dictionary()'s positional calls are unchanged.
## =============================================================================

## Internal: the calling context for .compute_stat().
##
## procedure: "means" or "univariate". vardef: the SAS VARDEF= divisor, always
## "df" under "means". mu0: the null value for the location tests. flags: an
## environment a statistic can write to, so the caller can warn once per call
## rather than once per cell (normality requested above n = 2000).
.stat_ctx <- function(procedure = "means", vardef = "df", mu0 = 0) {
  list(procedure = procedure, vardef = vardef, mu0 = mu0,
       flags = new.env(parent = emptyenv()))
}

## Internal: does stderr divide by sqrt(sum of weights) rather than sqrt(n)?
## SAS PROC MEANS and PROC UNIVARIATE both divide by sqrt(W) (oracle,
## 2026-09-17). Kept per procedure as a hook, should a procedure's oracle
## ever differ.
.stderr_sqrt_w <- c(means = TRUE, univariate = TRUE)

## Internal: weighted mean, or the plain mean when w is NULL
.wmean <- function(v, w) {
  if (is.null(w)) mean(v) else sum(w * v) / sum(as.numeric(w))
}

## Internal: weighted corrected sum of squares
.wcss <- function(v, w) {
  m <- .wmean(v, w)
  if (is.null(w)) sum((v - m)^2) else sum(w * (v - m)^2)
}

## Internal: weighted variance at SAS VARDEF=. Under "df" (the only divisor
## proc_means() uses) the divisor is the count of non-missing observations
## minus one, not the sum of the weights.
.wvar <- function(v, w, vardef = "df") {
  n <- length(v)
  if (n < 2L) {
    return(NA_real_)
  }
  big_w <- if (is.null(w)) n else sum(as.numeric(w))
  d <- switch(vardef,
    df     = n - 1,
    n      = n,
    wdf    = big_w - 1,
    weight = big_w
  )
  if (d <= 0) {
    return(NA_real_)
  }
  .wcss(v, w) / d
}

## Internal: SAS skewness. Under VARDEF=DF, the adjusted Fisher-Pearson
## standardised third moment, not R's naive moment ratio; equals
## e1071::skewness(type = 2). Under VARDEF=N, the moment form with
## s^2 = CSS / n. SAS computes neither under WDF or WEIGHT. The weighted forms
## raise each weight to 3/2, per the SAS documentation.
.wskew <- function(v, w, vardef = "df") {
  n <- length(v)
  if (n < 3L || !vardef %in% c("df", "n")) {
    return(NA_real_)
  }
  s <- sqrt(.wvar(v, w, vardef))
  if (is.na(s) || s == 0) {
    return(NA_real_)
  }
  z <- (v - .wmean(v, w)) / s
  acc <- if (is.null(w)) sum(z^3) else sum(w^(3 / 2) * z^3)
  if (vardef == "n") {
    return(acc / n)
  }
  (n / ((n - 1) * (n - 2))) * acc
}

## Internal: SAS kurtosis, excess. Under VARDEF=DF the adjusted Fisher-Pearson
## form, equal to e1071::kurtosis(type = 2); under VARDEF=N the moment form.
## The weighted forms square each weight.
.wkurt <- function(v, w, vardef = "df") {
  n <- length(v)
  if (n < 4L || !vardef %in% c("df", "n")) {
    return(NA_real_)
  }
  s <- sqrt(.wvar(v, w, vardef))
  if (is.na(s) || s == 0) {
    return(NA_real_)
  }
  z <- (v - .wmean(v, w)) / s
  acc <- if (is.null(w)) sum(z^4) else sum(w^2 * z^4)
  if (vardef == "n") {
    return(acc / n - 3)
  }
  (n * (n + 1) / ((n - 1) * (n - 2) * (n - 3))) * acc -
    3 * (n - 1)^2 / ((n - 2) * (n - 3))
}

## Internal: standard error of the mean. NA unless VARDEF=DF, as in SAS.
.stderr_stat <- function(v, w, ctx) {
  if (ctx$vardef != "df") {
    return(NA_real_)
  }
  use_w <- !is.null(w) && isTRUE(.stderr_sqrt_w[[ctx$procedure]])
  .wvar(v, w) / (if (use_w) sum(as.numeric(w)) else length(v))
}

## Internal: Student's t for H0: mean = mu0, and its two-sided p-value
.t_test_stat <- function(v, w, ctx, what) {
  n <- length(v)
  if (ctx$vardef != "df" || n < 2L) {
    return(NA_real_)
  }
  s <- sqrt(.wvar(v, w))
  if (s == 0) {
    return(NA_real_)
  }
  big_w <- if (is.null(w)) n else sum(as.numeric(w))
  t <- (.wmean(v, w) - ctx$mu0) / (s / sqrt(big_w))
  if (what == "t") t else 2 * stats::pt(-abs(t), n - 1)
}

## Internal: the sign test. NA under weights (SAS computes only the t test
## there) and when no value differs from mu0 (SAS behaviour unobserved).
.sign_test_stat <- function(v, w, ctx, what) {
  if (!is.null(w)) {
    return(NA_real_)
  }
  d <- v - ctx$mu0
  n_plus <- sum(d > 0)
  n_minus <- sum(d < 0)
  if (n_plus + n_minus == 0L) {
    return(NA_real_)
  }
  if (what == "msign") {
    return((n_plus - n_minus) / 2)
  }
  min(1, 2 * stats::pbinom(min(n_plus, n_minus), n_plus + n_minus, 0.5))
}

## Internal: the Wilcoxon signed rank test. NA under weights and when no value
## differs from mu0. At 20 or fewer non-zero differences the p-value is exact,
## from the null distribution of the signed rank sum computed by dynamic
## programming over doubled ranks (average ranks are integers once doubled);
## above 20 it is SAS's tie-corrected t approximation.
.signrank_stat <- function(v, w, ctx, what) {
  if (!is.null(w)) {
    return(NA_real_)
  }
  d <- v - ctx$mu0
  d <- d[d != 0]
  n <- length(d)
  if (n == 0L) {
    return(NA_real_)
  }
  r <- rank(abs(d))
  s <- sum(sign(d) * r) / 2
  if (what == "signrank") {
    return(s)
  }
  if (n <= 20L) {
    r2 <- as.integer(round(2 * r))
    total <- sum(r2)
    # Entry k + 1 counts the sign assignments whose positive doubled ranks
    # sum to k.
    counts <- c(1, numeric(total))
    for (ri in r2) {
      counts <- counts + c(numeric(ri), counts[seq_len(total + 1L - ri)])
    }
    pos <- 0:total
    obs <- as.integer(round(4 * s))     # sum(sign * doubled ranks)
    return(sum(counts[abs(2L * pos - total) >= abs(obs)]) / 2^n)
  }
  ties <- table(r)
  v_s <- n * (n + 1) * (2 * n + 1) / 24 - sum(ties^3 - ties) / 48
  t <- s * sqrt((n - 1) / (n * v_s - s^2))
  2 * stats::pt(-abs(t), n - 1)
}

## Internal: the Shapiro-Wilk test. W = 1, p = 1 at n = 2, as SAS reports. NA
## under weights, below two observations, for a constant column, and above
## 2000 observations, where SAS switches to a Kolmogorov D test that is not
## ported; that last case sets ctx$flags$normal_n2000 for the caller to warn.
.normal_stat <- function(v, w, ctx, what) {
  n <- length(v)
  if (!is.null(w) || n < 2L) {
    return(NA_real_)
  }
  # Size first, so a constant column above 2000 values still warns.
  if (n > 2000L) {
    assign("normal_n2000", TRUE, envir = ctx$flags)
    return(NA_real_)
  }
  if (all(v == v[1L])) {
    return(NA_real_)
  }
  if (n == 2L) {
    return(1)
  }
  sw <- stats::shapiro.test(v)
  if (what == "normal") unname(sw$statistic) else sw$p.value
}

## Internal: build one registry entry. `weighted` is a single logical, or a
## named logical giving the flag per procedure.
.stat <- function(fun, weighted, integer = FALSE,
                  procedures = c("means", "univariate")) {
  list(fun = fun, weighted = weighted, integer = integer,
       procedures = procedures)
}

## Internal: the weighted flag of an entry for one procedure
.resolve_weighted <- function(weighted, procedure) {
  if (length(weighted) == 1L && is.null(names(weighted))) {
    return(isTRUE(weighted))
  }
  isTRUE(weighted[[procedure]])
}

## Quantiles are unweighted under PROC MEANS and weighted under PROC
## UNIVARIATE.
.quantile_weighted <- c(means = FALSE, univariate = TRUE)

## =============================================================================
## Internal: the statistic registry.
##
## Each entry carries its compute function plus three flags. `weighted` is the
## contract from the design: .compute_stat() passes weights to a statistic only
## when its flag is TRUE for the calling procedure, so a statistic cannot
## become weighted by someone editing its body. The location and normality
## tests are flagged weighted only so that they see the weights and return NA
## under them, as SAS does. `integer` types the zero-row result. `procedures`
## lists the procedures that accept the keyword.
##
## fun(x, v, w, ctx): x is the raw vector including NA, v is x with NA removed,
## w is a numeric vector aligned to v or NULL, and ctx is from .stat_ctx().
.stat_registry <- list(
  n = .stat(function(x, v, w, ctx) length(v), FALSE, integer = TRUE),
  nmiss = .stat(function(x, v, w, ctx) sum(is.na(x)), FALSE, integer = TRUE),
  nobs = .stat(function(x, v, w, ctx) length(x), FALSE, integer = TRUE),
  sumwgt = .stat(
    function(x, v, w, ctx) {
      # Both branches coerce to double. `length()` is integer, and `sum()` of
      # an integer weight column stays integer -- either would make the column
      # type depend on the weights supplied, contradicting `integer = FALSE`
      # and the zero-row path. Coercing before the sum also avoids integer
      # overflow.
      if (length(v) == 0L) {
        NA_real_
      } else if (is.null(w)) {
        as.numeric(length(v))
      } else {
        sum(as.numeric(w))
      }
    },
    TRUE
  ),
  mean = .stat(
    function(x, v, w, ctx) if (length(v) == 0L) NA_real_ else .wmean(v, w),
    TRUE
  ),
  std = .stat(function(x, v, w, ctx) sqrt(.wvar(v, w, ctx$vardef)), TRUE),
  min = .stat(
    function(x, v, w, ctx) if (length(v) == 0L) NA_real_ else min(v),
    FALSE
  ),
  max = .stat(
    function(x, v, w, ctx) if (length(v) == 0L) NA_real_ else max(v),
    FALSE
  ),
  sum = .stat(
    function(x, v, w, ctx) {
      if (length(v) == 0L) NA_real_ else if (is.null(w)) sum(v) else sum(w * v)
    },
    TRUE
  ),
  range = .stat(
    function(x, v, w, ctx) {
      if (length(v) == 0L) NA_real_ else max(v) - min(v)
    },
    FALSE
  ),
  stderr = .stat(function(x, v, w, ctx) sqrt(.stderr_stat(v, w, ctx)), TRUE),
  cv = .stat(
    function(x, v, w, ctx) {
      s <- sqrt(.wvar(v, w, ctx$vardef))
      # Return before computing the mean: .wvar() is NA below two
      # observations, and .wmean() of an empty vector is a NaN nothing would
      # use.
      if (is.na(s)) {
        return(NA_real_)
      }
      m <- .wmean(v, w)
      # SAS emits missing when the mean is zero; R would give Inf.
      if (m == 0) NA_real_ else 100 * s / m
    },
    TRUE
  ),
  var = .stat(function(x, v, w, ctx) .wvar(v, w, ctx$vardef), TRUE),
  uss = .stat(
    function(x, v, w, ctx) {
      if (length(v) == 0L) {
        NA_real_
      } else if (is.null(w)) {
        sum(v^2)
      } else {
        sum(w * v^2)
      }
    },
    TRUE
  ),
  css = .stat(
    function(x, v, w, ctx) if (length(v) == 0L) NA_real_ else .wcss(v, w),
    TRUE
  ),
  skewness = .stat(function(x, v, w, ctx) .wskew(v, w, ctx$vardef), TRUE),
  kurtosis = .stat(function(x, v, w, ctx) .wkurt(v, w, ctx$vardef), TRUE),
  qrange = .stat(
    function(x, v, w, ctx) {
      if (length(v) == 0L) {
        return(NA_real_)
      }
      .quantile_stat(v, "q3", w) - .quantile_stat(v, "q1", w)
    },
    .quantile_weighted
  ),
  mode = .stat(
    function(x, v, w, ctx) {
      if (length(v) == 0L) {
        return(NA_real_)
      }
      u <- unique(v)
      counts <- tabulate(match(v, u))
      top <- max(counts)
      # SAS: no mode when nothing repeats, except that a single observation
      # is its own mode (oracle, 2026-09-17).
      if (top == 1L && length(v) > 1L) {
        return(NA_real_)
      }
      # SAS reports the smallest value among tied modes.
      min(u[counts == top])
    },
    FALSE
  ),
  median = .stat(
    function(x, v, w, ctx) .quantile_stat(v, "median", w),
    .quantile_weighted
  ),
  q1 = .stat(
    function(x, v, w, ctx) .quantile_stat(v, "q1", w),
    .quantile_weighted
  ),
  q3 = .stat(
    function(x, v, w, ctx) .quantile_stat(v, "q3", w),
    .quantile_weighted
  ),
  stdmean = .stat(
    function(x, v, w, ctx) sqrt(.stderr_stat(v, w, ctx)),
    TRUE, procedures = "univariate"
  ),
  t = .stat(
    function(x, v, w, ctx) .t_test_stat(v, w, ctx, "t"),
    TRUE, procedures = "univariate"
  ),
  probt = .stat(
    function(x, v, w, ctx) .t_test_stat(v, w, ctx, "probt"),
    TRUE, procedures = "univariate"
  ),
  msign = .stat(
    function(x, v, w, ctx) .sign_test_stat(v, w, ctx, "msign"),
    TRUE, procedures = "univariate"
  ),
  probm = .stat(
    function(x, v, w, ctx) .sign_test_stat(v, w, ctx, "probm"),
    TRUE, procedures = "univariate"
  ),
  signrank = .stat(
    function(x, v, w, ctx) .signrank_stat(v, w, ctx, "signrank"),
    TRUE, procedures = "univariate"
  ),
  probs = .stat(
    function(x, v, w, ctx) .signrank_stat(v, w, ctx, "probs"),
    TRUE, procedures = "univariate"
  ),
  normal = .stat(
    function(x, v, w, ctx) .normal_stat(v, w, ctx, "normal"),
    TRUE, procedures = "univariate"
  ),
  probn = .stat(
    function(x, v, w, ctx) .normal_stat(v, w, ctx, "probn"),
    TRUE, procedures = "univariate"
  )
)

## Internal: the registry as one procedure sees it -- only the keywords it
## accepts, with `weighted` resolved to a single logical.
.stats_for <- function(procedure) {
  keep <- Filter(function(e) procedure %in% e$procedures, .stat_registry)
  lapply(keep, function(e) {
    e$weighted <- .resolve_weighted(e$weighted, procedure)
    e
  })
}

## Internal: proc_means()'s resolved registry, kept for the registry tests;
## .validate_stats() uses .stats_for() directly.
.STATS <- .stats_for("means")

## Internal: reject unknown statistic keywords
.validate_stats <- function(stats, procedure = "means") {
  known <- names(.stats_for(procedure))
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
## entry is not marked `weighted` for ctx$procedure never see it. A keyword
## not in the registry is a quantile: pNN, or the internal ".pctl:" prefix
## followed by a PCTLPTS= point.
.compute_stat <- function(x, stat, w = NULL, ctx = .stat_ctx()) {
  x <- as.numeric(x)
  keep <- !is.na(x)
  v <- x[keep]

  entry <- .stat_registry[[stat]]
  weighted <- if (is.null(entry)) .quantile_weighted else entry$weighted
  wv <- if (.resolve_weighted(weighted, ctx$procedure) && !is.null(w)) {
    w[keep]
  } else {
    NULL
  }
  if (is.null(entry)) {
    return(.quantile_stat(v, stat, wv))
  }
  entry$fun(x, v, wv, ctx)
}

## Internal: quantile statistics. Unweighted at SAS QNTLDEF=5 (R type 2);
## weighted by the PROC UNIVARIATE weighted definition.
.quantile_stat <- function(v, stat, w = NULL) {
  if (length(v) == 0L) {
    return(NA_real_)
  }
  p <- if (startsWith(stat, ".pctl:")) {
    as.numeric(sub("^\\.pctl:", "", stat)) / 100
  } else {
    switch(stat,
      median = 0.5,
      q1     = 0.25,
      q3     = 0.75,
      as.numeric(sub("^p", "", stat)) / 100
    )
  }
  if (is.null(w)) {
    return(stats::quantile(v, probs = p, type = 2, names = FALSE))
  }
  .wquantile(v, w, p)
}

## Internal: SAS PROC UNIVARIATE weighted percentile. Sort ascending with
## cumulative weights S_i. p = 0 is the minimum and p = 1 the maximum;
## otherwise the mean of x_i and x_(i+1) when S_i equals pW (within a relative
## tolerance), else x_i for the first S_i above pW. PCTLDEF= does not apply.
.wquantile <- function(v, w, p) {
  o <- order(v)
  v <- v[o]
  cum <- cumsum(w[o])
  big_w <- cum[length(cum)]
  if (p <= 0) {
    return(v[1L])
  }
  if (p >= 1) {
    return(v[length(v)])
  }
  target <- p * big_w
  hit <- which(abs(cum - target) <= 1e-12 * big_w)
  if (length(hit) > 0L && hit[1L] < length(v)) {
    i <- hit[1L]
    return((v[i] + v[i + 1L]) / 2)
  }
  above <- which(cum > target)
  if (length(above) == 0L) v[length(v)] else v[above[1L]]
}
