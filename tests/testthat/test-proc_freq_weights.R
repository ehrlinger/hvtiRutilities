library(testthat)
library(hvtiRutilities)

test_that("weighted frequency is the sum of weights", {
  d <- data.frame(g = c("a", "a", "b"), wt = c(1, 2.5, 4))
  res <- proc_freq(d, "g", weights = "wt")
  expect_equal(res$Frequency, c(3.5, 4))
  expect_equal(res$Percent, c(3.5 / 7.5 * 100, 4 / 7.5 * 100))
  expect_equal(res$Cum_Frequency, c(3.5, 7.5))
})

test_that("weighted frequency_missing sums the weights of dropped rows", {
  d <- data.frame(g = c("a", NA, "b"), wt = c(1, 2, 3))
  res <- proc_freq(d, "g", weights = "wt")
  expect_equal(res$Frequency, c(1, 3))
  expect_equal(res$Percent, c(25, 75))
  expect_identical(attr(res, "frequency_missing"), 2)
})

test_that("a missing weight excludes the row entirely", {
  d <- data.frame(g = c("a", "a", "b"), wt = c(1, NA, 3))
  res <- proc_freq(d, "g", weights = "wt")
  expect_equal(res$Frequency, c(1, 3))
  expect_identical(attr(res, "frequency_missing"), 0)
})

test_that("weights apply to crosstab denominators", {
  d <- data.frame(a = c("x", "x", "y"), b = c(0, 1, 0), wt = c(1, 3, 4))
  res <- proc_freq(d, c("a", "b"), weights = "wt")
  expect_equal(res$Percent, c(12.5, 37.5, 50))
  expect_equal(res$Row_Percent, c(25, 75, 100))
  expect_equal(res$Col_Percent, c(20, 100, 80))
})

test_that("a non-positive weight is an error naming the row", {
  d <- data.frame(g = c("a", "b"), wt = c(1, 0))
  expect_error(proc_freq(d, "g", weights = "wt"), "row\\(s\\): 2")
})
