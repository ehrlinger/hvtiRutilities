library(testthat)
library(hvtiRutilities)

# The shared statistic engine: the context, the per-procedure registry views
# and the statistics whose behaviour depends on the procedure or VARDEF=.
# Expected values are hand-computed literals or independent formulas.

eng <- function(name) utils::getFromNamespace(name, "hvtiRutilities")
ctx <- function(...) eng(".stat_ctx")(...)
cs <- function(x, stat, w = NULL, ...) {
  eng(".compute_stat")(x, stat, w, ctx(...))
}

test_that(".stat_ctx() defaults are proc_means()'s", {
  k <- ctx()
  expect_equal(k$procedure, "means")
  expect_equal(k$vardef, "df")
  expect_equal(k$mu0, 0)
  expect_true(is.environment(k$flags))
})

test_that(".STATS is the means view of the registry", {
  expect_identical(names(eng(".STATS")), names(eng(".stats_for")("means")))
  for (e in eng(".stat_registry")) {
    expect_true(all(e$procedures %in% c("means", "univariate")))
  }
})

test_that("quantiles are weighted for univariate and not for means", {
  means <- eng(".stats_for")("means")
  uni <- eng(".stats_for")("univariate")
  for (k in c("median", "q1", "q3", "qrange")) {
    expect_false(means[[k]]$weighted, info = k)
    expect_true(uni[[k]]$weighted, info = k)
  }
  expect_false(uni$mode$weighted)
})

test_that("a weighted median is weighted only for univariate", {
  # S = 1, 4, 5, 6 and pW = 3: the first S_i above 3 is S_2, so 2.
  x <- c(1, 2, 3, 4)
  w <- c(1, 3, 1, 1)
  expect_equal(cs(x, "median", w), 2.5)
  expect_equal(cs(x, "median", w, procedure = "univariate"), 2)
  expect_equal(cs(x, "p50", w, procedure = "univariate"), 2)
})

test_that("weighted percentile points follow the PROC UNIVARIATE rule", {
  x <- c(4, 1, 3, 2)
  w <- c(1, 1, 1, 1)
  pct <- function(p) cs(x, p, w, procedure = "univariate")
  expect_equal(pct(".pctl:0"), 1)
  expect_equal(pct(".pctl:100"), 4)
  expect_equal(pct(".pctl:50"), 2.5)   # S_2 = 2 equals pW = 2
  expect_equal(pct(".pctl:30"), 2)     # first S_i above pW = 1.2
  expect_equal(cs(x, ".pctl:2.5"), 1)  # unweighted, PCTLDEF=5
})

test_that("each VARDEF divisor", {
  # x = 1, 2, 3, 4: CSS = 5; w = 1, 1, 1, 2: W = 5, weighted CSS = 6.8.
  x <- c(1, 2, 3, 4)
  w <- c(1, 1, 1, 2)
  uv <- function(vardef, w = NULL) {
    cs(x, "var", w, procedure = "univariate", vardef = vardef)
  }
  expect_equal(uv("df"), 5 / 3)
  expect_equal(uv("n"), 5 / 4)
  expect_equal(uv("df", w), 6.8 / 3)
  expect_equal(uv("n", w), 6.8 / 4)
  expect_equal(uv("wdf", w), 6.8 / 4)
  expect_equal(uv("weight", w), 6.8 / 5)
  expect_equal(cs(x, "std", w, procedure = "univariate", vardef = "n"),
               sqrt(6.8 / 4))
})

test_that("VARDEF=N skewness and kurtosis are the moment forms", {
  x <- c(1, 2, 3, 10)
  z <- (x - mean(x)) / sqrt(mean((x - mean(x))^2))
  expect_equal(cs(x, "skewness", procedure = "univariate", vardef = "n"),
               mean(z^3))
  expect_equal(cs(x, "kurtosis", procedure = "univariate", vardef = "n"),
               mean(z^4) - 3)
})

test_that("skewness, kurtosis and stderr are NA where SAS omits them", {
  x <- c(1, 2, 3, 10)
  w <- c(1, 2, 1, 1)
  for (vd in c("wdf", "weight")) {
    expect_true(is.na(cs(x, "skewness", w, procedure = "univariate",
                         vardef = vd)))
    expect_true(is.na(cs(x, "kurtosis", w, procedure = "univariate",
                         vardef = vd)))
  }
  expect_true(is.na(cs(x, "stderr", procedure = "univariate",
                       vardef = "n")))
})

test_that("weighted stderr divides by sqrt(sum of weights)", {
  x <- c(1, 2, 3, 4)
  w <- c(1, 1, 1, 2)
  expect_equal(cs(x, "stderr", w, procedure = "univariate"),
               sqrt(6.8 / 3) / sqrt(5))
})

test_that(".validate_stats() lists the keywords of the procedure", {
  expect_silent(eng(".validate_stats")(c("mean", "p5"), "univariate"))
  expect_error(eng(".validate_stats")("bogus", "univariate"),
               "Unrecognised statistic keyword\\(s\\): bogus")
})

test_that("the univariate keywords belong to univariate only", {
  kw <- c("stdmean", "t", "probt", "msign", "probm", "signrank", "probs",
          "normal", "probn")
  expect_silent(eng(".validate_stats")(kw, "univariate"))
  for (k in kw) {
    expect_error(eng(".validate_stats")(k), "Unrecognised statistic")
  }
  expect_false(any(kw %in% names(eng(".STATS"))))
})

test_that("stdmean and t use sqrt(W) and mu0", {
  # Weighted mean 14 / 5 = 2.8, CSS = 6.8, std = sqrt(6.8 / 3), W = 5.
  x <- c(1, 2, 3, 4)
  w <- c(1, 1, 1, 2)
  se <- sqrt(6.8 / 3) / sqrt(5)
  expect_equal(cs(x, "stdmean", w, procedure = "univariate"), se)
  expect_equal(cs(x, "t", w, procedure = "univariate", mu0 = 1), 1.8 / se)
  expect_equal(cs(x, "probt", w, procedure = "univariate", mu0 = 1),
               2 * stats::pt(-1.8 / se, 3))
  expect_true(is.na(cs(x, "t", procedure = "univariate", vardef = "n")))
  expect_true(is.na(cs(rep(2, 3), "t", procedure = "univariate")))
})

test_that("sign test drops values equal to mu0", {
  # x - 2 = -1, 0, 1, 2, 3: 3 above and 1 below.
  x <- c(1, 2, 3, 4, 5)
  expect_equal(cs(x, "msign", procedure = "univariate", mu0 = 2), 1)
  # Twice the binomial probability of one or fewer in four: 2 * 5 / 16.
  expect_equal(cs(x, "probm", procedure = "univariate", mu0 = 2), 0.625)
})

test_that("signed rank exact p matches full enumeration with ties", {
  x <- c(1, -1, 2, 3, -2, 4, 4, -5, 6, 0.5)
  d <- x[x != 0]
  r <- rank(abs(d))
  s_obs <- sum(sign(d) * r) / 2
  signs <- as.matrix(expand.grid(rep(list(c(-1, 1)), length(r))))
  s_all <- as.vector(signs %*% r) / 2
  expect_equal(cs(x, "signrank", procedure = "univariate"), s_obs)
  expect_equal(cs(x, "probs", procedure = "univariate"),
               mean(abs(s_all) >= abs(s_obs)))
})

test_that("signed rank exact p on a small tied sample", {
  # d = 1, -1, 2, 3: ranks 1.5, 1.5, 3, 4, S = 3.5. Positive-rank sums reach
  # 8.5 or more in 3 of 16 assignments and 1.5 or less in 3: p = 6 / 16.
  expect_equal(cs(c(1, -1, 2, 3), "probs", procedure = "univariate"),
               0.375)
})

test_that("the location tests other than t are NA under weights", {
  x <- c(1, 2, 3, 5, 8)
  w <- c(1, 2, 1, 1, 1)
  for (k in c("msign", "probm", "signrank", "probs", "normal", "probn")) {
    expect_true(is.na(cs(x, k, w, procedure = "univariate")), info = k)
  }
})

test_that("normality is W = 1, p = 1 at n = 2 and NA below", {
  expect_equal(cs(c(1, 4), "normal", procedure = "univariate"), 1)
  expect_equal(cs(c(1, 4), "probn", procedure = "univariate"), 1)
  expect_true(is.na(cs(3, "normal", procedure = "univariate")))
})

test_that("normality above 2000 observations is NA and sets the flag", {
  k <- ctx("univariate")
  expect_true(is.na(
    eng(".compute_stat")(sin(seq_len(2001)), "normal", NULL, k)
  ))
  expect_true(isTRUE(k$flags$normal_n2000))
  k2 <- ctx("univariate")
  expect_false(is.na(
    eng(".compute_stat")(sin(seq_len(2000)), "normal", NULL, k2)
  ))
  expect_null(k2$flags$normal_n2000)
})
