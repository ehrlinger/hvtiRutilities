library(testthat)
library(hvtiRutilities)

cs <- function(x, stat, w = NULL) hvtiRutilities:::.compute_stat(x, stat, w)

x9 <- c(2, 4, 4, 4, 5, 5, 7, 9, NA)

test_that("nobs counts every observation including missing", {
  expect_equal(cs(x9, "nobs"), 9L)
  expect_equal(cs(x9, "n"), 8L)
  expect_equal(cs(x9, "nmiss"), 1L)
})

test_that("var matches stats::var", {
  expect_equal(cs(x9, "var"), stats::var(c(2, 4, 4, 4, 5, 5, 7, 9)))
})

test_that("uss is the uncorrected sum of squares", {
  expect_equal(cs(x9, "uss"), sum(c(2, 4, 4, 4, 5, 5, 7, 9)^2))
})

test_that("css is the corrected sum of squares", {
  v <- c(2, 4, 4, 4, 5, 5, 7, 9)
  expect_equal(cs(x9, "css"), sum((v - mean(v))^2))
})

test_that("qrange is q3 minus q1 at QNTLDEF=5", {
  expect_equal(cs(x9, "qrange"), cs(x9, "q3") - cs(x9, "q1"))
})

test_that("mode returns the most frequent value", {
  expect_equal(cs(x9, "mode"), 4)
})

test_that("mode returns the smallest value when modes tie", {
  # 3 and 1 both occur twice; SAS reports the smallest.
  expect_equal(cs(c(3, 3, 1, 1, 5), "mode"), 1)
})

test_that("mode is NA when no value repeats", {
  expect_true(is.na(cs(c(1, 2, 3), "mode")))
})

test_that("var is NA below two observations", {
  expect_true(is.na(cs(c(5), "var")))
})

test_that("uss and css are NA with no observations", {
  expect_true(is.na(cs(c(NA_real_), "uss")))
  expect_true(is.na(cs(c(NA_real_), "css")))
})

test_that("qrange is NA with no observations", {
  expect_true(is.na(cs(c(NA_real_), "qrange")))
})

test_that("the new keywords are accepted by proc_means", {
  d <- data.frame(a = c(1, 2, 2, 8))
  res <- proc_means(d, stats = c("nobs", "var", "uss", "css", "qrange", "mode"))
  expect_equal(nrow(res), 1L)
  expect_true(all(c("nobs", "var", "uss", "css", "qrange", "mode") %in% names(res)))
})
