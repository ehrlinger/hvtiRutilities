library(testthat)
library(hvtiRutilities)

cs <- function(x, stat, w = NULL) hvtiRutilities:::.compute_stat(x, stat, w)

# A deliberately skewed, non-symmetric sample.
xs <- c(1, 2, 2, 3, 3, 3, 4, 4, 8, 15)

test_that("skewness matches the SAS definition (e1071 type 2)", {
  skip_if_not_installed("e1071")
  expect_equal(cs(xs, "skewness"), e1071::skewness(xs, type = 2))
})

test_that("kurtosis matches the SAS definition (e1071 type 2)", {
  skip_if_not_installed("e1071")
  expect_equal(cs(xs, "kurtosis"), e1071::kurtosis(xs, type = 2))
})

test_that("skewness ignores missing values", {
  skip_if_not_installed("e1071")
  expect_equal(cs(c(xs, NA), "skewness"), e1071::skewness(xs, type = 2))
})

test_that("skewness is NA below three observations", {
  expect_true(is.na(cs(c(1, 2), "skewness")))
})

test_that("kurtosis is NA below four observations", {
  expect_true(is.na(cs(c(1, 2, 3), "kurtosis")))
})

test_that("skewness and kurtosis are NA for a constant column", {
  # s == 0 gives 0/0; SAS returns missing, not NaN.
  k <- rep(4, 10)
  expect_true(is.na(cs(k, "skewness")))
  expect_true(is.na(cs(k, "kurtosis")))
  expect_false(is.nan(cs(k, "skewness")))
  expect_false(is.nan(cs(k, "kurtosis")))
})

test_that("proc_means accepts the shape keywords", {
  skip_if_not_installed("e1071")
  d <- data.frame(a = xs)
  res <- proc_means(d, stats = c("skewness", "kurtosis"))
  expect_equal(res$skewness, e1071::skewness(xs, type = 2))
  expect_equal(res$kurtosis, e1071::kurtosis(xs, type = 2))
})
