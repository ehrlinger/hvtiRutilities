library(testthat)
library(hvtiRutilities)

d <- data.frame(dead = c(1, 0, NA, 0, 1, 0))

test_that("missing = FALSE drops NA and reports frequency_missing", {
  res <- proc_freq(d, "dead")
  expect_equal(res$dead, c(0, 1))
  expect_equal(res$Frequency, c(3L, 2L))
  expect_equal(res$Percent, c(60, 40))
  expect_identical(attr(res, "frequency_missing"), 1L)
})

test_that("missing = TRUE counts NA as a level that sorts first", {
  res <- proc_freq(d, "dead", missing = TRUE)
  expect_equal(res$dead, c(NA, 0, 1))
  expect_equal(res$Frequency, c(1L, 3L, 2L))
  expect_equal(res$Percent, c(100 / 6, 50, 100 / 3))
  expect_equal(res$Cum_Frequency, c(1L, 4L, 6L))
  expect_equal(res$Cum_Percent, c(100 / 6, 200 / 3, 100))
  expect_identical(attr(res, "frequency_missing"), 0L)
})

test_that("frequency_missing is 0, not absent, when nothing is missing", {
  res <- proc_freq(data.frame(g = c("a", "b")), "g")
  expect_identical(attr(res, "frequency_missing"), 0L)
})

test_that("a row missing in any table variable is dropped from n-way tables", {
  d2 <- data.frame(a = c("x", "x", NA, "y"),
                   b = c(0, NA, 1, 1))
  res <- proc_freq(d2, c("a", "b"), list = TRUE)
  expect_equal(res$Frequency, c(1L, 1L))
  expect_equal(res$Percent, c(50, 50))
  expect_identical(attr(res, "frequency_missing"), 2L)
})

test_that("missing = TRUE keeps partial-NA combinations in n-way tables", {
  d2 <- data.frame(a = c("x", "x", NA, "y"),
                   b = c(0, NA, 1, 1))
  res <- proc_freq(d2, c("a", "b"), missing = TRUE, list = TRUE)
  expect_equal(res$a, c(NA, "x", "x", "y"))
  expect_equal(res$b, c(1, NA, 0, 1))
  expect_equal(res$Percent, c(25, 25, 25, 25))
})

test_that("a table with every row missing returns zero rows, not an error", {
  res <- proc_freq(data.frame(g = c(NA, NA)), "g")
  expect_equal(nrow(res), 0L)
  expect_named(res, c("g", "Frequency", "Percent", "Cum_Frequency",
                      "Cum_Percent"))
  expect_identical(attr(res, "frequency_missing"), 2L)
})

test_that("an all-missing two-way crosstab keeps its columns", {
  res <- proc_freq(data.frame(a = c(NA, "x"), b = c(1, NA)), c("a", "b"))
  expect_equal(nrow(res), 0L)
  expect_named(res, c("a", "b", "Frequency", "Percent", "Row_Percent",
                      "Col_Percent"))
})

test_that("blank character values are missing and dropped by default", {
  d2 <- data.frame(s = c("a", "", "a", NA, "  "))
  res <- proc_freq(d2, "s")
  expect_equal(res$s, "a")
  expect_equal(res$Frequency, 2L)
  expect_equal(res$Percent, 100)
  expect_identical(attr(res, "frequency_missing"), 3L)
})

test_that("blank character values form the missing level", {
  d2 <- data.frame(s = c("a", "", "a", NA, "  "))
  res <- proc_freq(d2, "s", missing = TRUE)
  expect_equal(res$s, c(NA, "a"))
  expect_equal(res$Frequency, c(3L, 2L))
  expect_equal(res$Percent, c(60, 40))
})
