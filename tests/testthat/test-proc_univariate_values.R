library(testthat)
library(hvtiRutilities)

# Hand-computed literals, independent of the SAS oracle.

test_that("weighted percentile averages neighbours when S_i equals pW", {
  # w = 1, 1, 1, 1: W = 4, the median's pW = 2 equals S_2, so (2 + 3) / 2.
  d <- data.frame(x = c(4, 1, 3, 2), w = c(1, 1, 1, 1))
  res <- proc_univariate(d, vars = "x", stats = "median", weights = "w",
                         pctlpts = c(0, 30, 100))
  expect_equal(res$median, 2.5)
  # pW = 1.2: the first S_i above it is S_2 = 2, so x_2 = 2.
  expect_equal(res$p30, 2)
  expect_equal(res$p0, 1)
  expect_equal(res$p100, 4)
})

test_that("weighted percentile takes the first S_i above pW", {
  # S = 1, 4, 5, 6 and pW = 3 for the median: first S_i > 3 is S_2, so 2.
  d <- data.frame(x = c(1, 2, 3, 4), w = c(1, 3, 1, 1))
  res <- proc_univariate(d, vars = "x", stats = c("median", "q3", "mode"),
                         weights = "w")
  expect_equal(res$median, 2)
  # pW = 4.5 for q3: S_3 = 5 is the first above it, so 3.
  expect_equal(res$q3, 3)
  # mode stays unweighted: no value repeats.
  expect_true(is.na(res$mode))
})

test_that("unweighted decimal percentiles follow PCTLDEF=5", {
  d <- data.frame(x = c(1, 2, 3, 4))
  res <- proc_univariate(d, stats = "n", pctlpts = c(2.5, 25, 50))
  expect_equal(res$p2_5, 1)
  expect_equal(res$p25, 1.5)
  expect_equal(res$p50, 2.5)
})

test_that("signed rank exact p on a small tied sample", {
  # d = 1, -1, 2, 3: ranks 1.5, 1.5, 3, 4, S = (1.5 - 1.5 + 3 + 4) / 2 = 3.5.
  # Positive-rank sums over the 16 sign assignments reach 8.5 or more in 3
  # (8.5, 8.5, 10) and 1.5 or less in 3 (0, 1.5, 1.5): p = 6 / 16.
  d <- data.frame(x = c(1, -1, 2, 3))
  res <- proc_univariate(d, stats = c("signrank", "probs"))
  expect_equal(res$signrank, 3.5)
  expect_equal(res$probs, 0.375)
})

test_that("sign test drops values equal to mu0", {
  # d = -1, 0, 1, 2, 3 with mu0 = 2: one zero, 3 above, 1 below.
  d <- data.frame(x = c(1, 2, 3, 4, 5))
  res <- proc_univariate(d, stats = c("msign", "probm"), mu0 = 2)
  expect_equal(res$msign, 1)
  # Twice the binomial probability of one or fewer in four: 2 * 5 / 16.
  expect_equal(res$probm, 0.625)
})

test_that("each vardef divisor", {
  # x = 1, 2, 3, 4: CSS = 5; w = 1, 1, 1, 2: W = 5, weighted CSS = 6.8.
  d <- data.frame(x = c(1, 2, 3, 4), w = c(1, 1, 1, 2))
  var_for <- function(vardef, weights = NULL) {
    proc_univariate(d, vars = "x", stats = "var", weights = weights,
                    vardef = vardef)$var
  }
  expect_equal(var_for("df"), 5 / 3)
  expect_equal(var_for("n"), 5 / 4)
  expect_equal(var_for("df", "w"), 6.8 / 3)
  expect_equal(var_for("n", "w"), 6.8 / 4)
  expect_equal(var_for("wdf", "w"), 6.8 / 4)
  expect_equal(var_for("weight", "w"), 6.8 / 5)
})

test_that("stdmean and t divide by sqrt(sum of weights)", {
  # weighted mean 14 / 5 = 2.8, CSS = 6.8, std = sqrt(6.8 / 3), W = 5.
  d <- data.frame(x = c(1, 2, 3, 4), w = c(1, 1, 1, 2))
  res <- proc_univariate(d, vars = "x", stats = c("stdmean", "t"),
                         weights = "w", mu0 = 1)
  expect_equal(res$stdmean, sqrt(6.8 / 3) / sqrt(5))
  expect_equal(res$t, 1.8 / (sqrt(6.8 / 3) / sqrt(5)))
})

test_that("statistics SAS does not compute are NA", {
  d <- data.frame(x = c(1, 2, 3, 5, 8), w = c(1, 2, 1, 1, 1))
  tests <- c("msign", "probm", "signrank", "probs", "normal", "probn")
  wtd <- proc_univariate(d, vars = "x", stats = c(tests, "t"),
                         weights = "w")
  expect_true(all(is.na(unlist(wtd[tests]))))
  expect_false(is.na(wtd$t))

  vn <- proc_univariate(d, vars = "x", vardef = "wdf", weights = "w",
                        stats = c("t", "probt", "stdmean", "skewness",
                                  "kurtosis"))
  expect_true(all(is.na(unlist(vn[-(1:2)]))))

  k <- proc_univariate(data.frame(x = rep(5, 6)),
                       stats = c("t", "probt", "skewness", "kurtosis",
                                 "normal", "probn", "cv"))
  expect_true(all(is.na(unlist(k[3:8]))))
  expect_equal(k$cv, 0)

  zero <- proc_univariate(data.frame(x = c(0, 0)),
                          stats = c("msign", "probm", "signrank", "probs"))
  expect_true(all(is.na(unlist(zero[-(1:2)]))))
})

test_that("normality at n = 2 is W = 1, p = 1", {
  res <- proc_univariate(data.frame(x = c(1, 4)),
                         stats = c("normal", "probn"))
  expect_equal(res$normal, 1)
  expect_equal(res$probn, 1)
})
