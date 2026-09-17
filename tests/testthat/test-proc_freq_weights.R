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

test_that("missing = TRUE with weights sums weights of the missing level", {
  d <- data.frame(g = c("a", NA, "a", NA), wt = c(1, 2, 1, 1))
  res <- proc_freq(d, "g", weights = "wt", missing = TRUE)
  expect_equal(res$g, c(NA, "a"))
  expect_equal(res$Frequency, c(3, 2))
  expect_equal(res$Percent, c(60, 40))
  expect_identical(attr(res, "frequency_missing"), 0)
})

test_that("every weight missing gives zero rows, not an error", {
  d <- data.frame(g = c("a", "b"), wt = c(NA_real_, NA_real_))
  res <- proc_freq(d, "g", weights = "wt")
  expect_equal(nrow(res), 0L)
  expect_named(res, c("g", "Frequency", "Percent", "Cum_Frequency",
                      "Cum_Percent"))
  expect_identical(attr(res, "frequency_missing"), 0)
})

test_that("tagged NAs with weights are separate levels in SAS order", {
  v <- c(1, haven::tagged_na("a"), NA, haven::tagged_na("_"),
         haven::tagged_na("a"))
  w <- c(1, 2, 3, 4, 5)
  res <- proc_freq(data.frame(v = v, w = w), "v", weights = "w",
                   missing = TRUE)
  expect_equal(res$Frequency, c(4, 3, 7, 1))
  expect_equal(haven::na_tag(res$v), c("_", NA, "a", NA))
})

test_that("integer weights summing past integer max stay exact", {
  d <- data.frame(g = c("a", "a", "b", NA),
                  wt = c(rep(1500000000L, 3), 2L))
  res <- proc_freq(d, "g", weights = "wt")
  expect_type(res$Frequency, "double")
  expect_equal(res$Frequency, c(3e9, 1.5e9))
  expect_equal(res$Percent, c(200 / 3, 100 / 3))
  expect_identical(attr(res, "frequency_missing"), 2)
})
