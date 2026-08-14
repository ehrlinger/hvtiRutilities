library(testthat)
library(hvtiRutilities)

test_that(".STATS declares every non-quantile keyword", {
  expect_setequal(
    names(hvtiRutilities:::.STATS),
    c("n", "nmiss", "mean", "std", "min", "max", "sum", "range",
      "stderr", "cv", "median", "q1", "q3")
  )
})

test_that("every .STATS name is accepted by .validate_stats", {
  expect_silent(hvtiRutilities:::.validate_stats(names(hvtiRutilities:::.STATS)))
})

test_that(".STATS marks exactly the integer-typed statistics", {
  ints <- Filter(function(s) s$integer, hvtiRutilities:::.STATS)
  expect_setequal(names(ints), c("n", "nmiss"))
})

test_that(".STATS marks exactly the weight-responsive statistics", {
  wtd <- Filter(function(s) s$weighted, hvtiRutilities:::.STATS)
  expect_setequal(names(wtd), c("mean", "std", "sum", "stderr", "cv"))
})

test_that(".compute_stat accepts a weights argument positionally after stat", {
  expect_equal(hvtiRutilities:::.compute_stat(c(1, 2, 3), "mean", NULL), 2)
})

test_that("cv is NA when the mean is zero, matching SAS", {
  # R would return Inf here; SAS emits missing.
  expect_true(is.na(hvtiRutilities:::.compute_stat(c(-2, 0, 2), "cv")))
})
