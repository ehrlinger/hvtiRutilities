library(testthat)
library(hvtiRutilities)

test_that(".STATS declares every non-quantile keyword", {
  expect_setequal(
    names(hvtiRutilities:::.STATS),
    c("n", "nmiss", "nobs", "sumwgt", "mean", "std", "min", "max", "sum",
      "range", "stderr", "cv", "var", "uss", "css", "skewness", "kurtosis",
      "qrange", "mode", "median", "q1", "q3")
  )
})

test_that("every .STATS name is accepted by .validate_stats", {
  expect_silent(hvtiRutilities:::.validate_stats(names(hvtiRutilities:::.STATS)))
})

test_that(".STATS marks exactly the integer-typed statistics", {
  ints <- Filter(function(s) s$integer, hvtiRutilities:::.STATS)
  expect_setequal(names(ints), c("n", "nmiss", "nobs"))
})

test_that(".STATS marks exactly the weight-responsive statistics", {
  wtd <- Filter(function(s) s$weighted, hvtiRutilities:::.STATS)
  expect_setequal(names(wtd),
                  c("sumwgt", "mean", "std", "sum", "stderr", "cv", "var",
                    "uss", "css", "skewness", "kurtosis"))
})

test_that(".compute_stat accepts a weights argument positionally after stat", {
  expect_equal(hvtiRutilities:::.compute_stat(c(1, 2, 3), "mean", NULL), 2)
})

test_that("cv is NA when the mean is zero, matching SAS", {
  # R would return Inf here; SAS emits missing.
  expect_true(is.na(hvtiRutilities:::.compute_stat(c(-2, 0, 2), "cv")))
})

test_that("cv is NA without warning when there is nothing to average", {
  # Guards against .wmean() being called on an empty vector. The result was
  # always NA, but computing an unused NaN invited repeated review findings.
  withr::local_options(warn = 2)  # any warning becomes an error
  expect_true(is.na(hvtiRutilities:::.compute_stat(c(NA_real_, NA_real_), "cv")))
  expect_true(is.na(hvtiRutilities:::.compute_stat(numeric(0), "cv")))
  expect_true(is.na(hvtiRutilities:::.compute_stat(5, "cv")))
  expect_true(is.na(
    hvtiRutilities:::.compute_stat(c(NA_real_, NA_real_), "cv", c(1, 2))
  ))
})
