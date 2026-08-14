library(testthat)
library(hvtiRutilities)

cs <- function(x, stat, w = NULL) hvtiRutilities:::.compute_stat(x, stat, w)

# Worked by hand:
#   v = 1, 2, 3, 4   w = 1, 1, 2, 4
#   sum(w)            = 8
#   sum(w*v)          = 1 + 2 + 6 + 16 = 25
#   xbar_w            = 25 / 8 = 3.125
#   sum(w*v^2)        = 1 + 4 + 18 + 64 = 87            (uss)
#   css = sum(w*(v - 3.125)^2)
#       = 1*(-2.125)^2 + 1*(-1.125)^2 + 2*(-0.125)^2 + 4*(0.875)^2
#       = 4.515625 + 1.265625 + 0.03125 + 3.0625 = 8.875
#   var = css / (n - 1) = 8.875 / 3 = 2.9583333...
v <- c(1, 2, 3, 4)
w <- c(1, 1, 2, 4)

test_that("weighted sum and sumwgt match the hand calculation", {
  expect_equal(cs(v, "sum", w), 25)
  expect_equal(cs(v, "sumwgt", w), 8)
})

test_that("weighted mean matches the hand calculation", {
  expect_equal(cs(v, "mean", w), 3.125)
})

test_that("weighted uss and css match the hand calculation", {
  expect_equal(cs(v, "uss", w), 87)
  expect_equal(cs(v, "css", w), 8.875)
})

test_that("weighted var uses the VARDEF=DF divisor n-1, not sum(w)-1", {
  expect_equal(cs(v, "var", w), 8.875 / 3)
  expect_false(isTRUE(all.equal(cs(v, "var", w), 8.875 / 7)))
})

test_that("weighted std, stderr and cv follow from weighted var", {
  vw <- 8.875 / 3
  expect_equal(cs(v, "std", w), sqrt(vw))
  expect_equal(cs(v, "stderr", w), sqrt(vw / 4))
  expect_equal(cs(v, "cv", w), 100 * sqrt(vw) / 3.125)
})

test_that("equal weights reproduce the unweighted values", {
  ones <- rep(1, length(v))
  for (s in c("mean", "var", "std", "css", "uss", "cv", "stderr",
              "skewness", "kurtosis")) {
    expect_equal(cs(v, s, ones), cs(v, s), info = s)
  }
})

# ---------------------------------------------------------------------------
# The contract from the design: PROC MEANS does not weight these.
# ---------------------------------------------------------------------------

test_that("unweighted statistics ignore weights entirely", {
  for (s in c("n", "nmiss", "nobs", "min", "max", "range", "mode",
              "median", "q1", "q3", "p90", "qrange")) {
    expect_equal(cs(v, s, w), cs(v, s), info = s)
  }
})

test_that("proc_means reports unweighted quantiles when weights are given", {
  d <- data.frame(a = v, wt = w)
  wt  <- proc_means(d, vars = "a", stats = c("median", "q1", "q3"),
                    weights = "wt")
  raw <- proc_means(d, vars = "a", stats = c("median", "q1", "q3"))
  expect_equal(wt$median, raw$median)
  expect_equal(wt$q1, raw$q1)
  expect_equal(wt$q3, raw$q3)
})
