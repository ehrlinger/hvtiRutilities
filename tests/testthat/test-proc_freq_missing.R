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

test_that("NaN and NA form a single missing level", {
  res <- proc_freq(data.frame(v = c(1, NA, NaN, 2)), "v", missing = TRUE)
  expect_equal(nrow(res), 3L)
  expect_true(is.na(res$v[1]))
  expect_equal(res$Frequency[1], 2L)
})

v_tagged <- c(1, haven::tagged_na("b"), haven::tagged_na("a"), NA,
              haven::tagged_na("a"), 1)

test_that("SAS special missing values are separate levels in SAS order", {
  res <- proc_freq(data.frame(v = v_tagged), "v", missing = TRUE)
  expect_equal(nrow(res), 4L)
  expect_equal(res$Frequency, c(1L, 2L, 1L, 2L))
  expect_equal(haven::na_tag(res$v), c(NA, "a", "b", NA))
  expect_equal(res$v[4], 1)
  expect_equal(res$Cum_Frequency, c(1L, 3L, 4L, 6L))
})

test_that("SAS special missing values are dropped under missing = FALSE", {
  res <- proc_freq(data.frame(v = v_tagged), "v")
  expect_equal(res$v, 1)
  expect_identical(attr(res, "frequency_missing"), 4L)
})

test_that("._ sorts before plain NA among special missing values", {
  v <- c(haven::tagged_na("z"), haven::tagged_na("_"), NA, 3)
  res <- proc_freq(data.frame(v = v), "v", missing = TRUE)
  expect_equal(haven::na_tag(res$v), c("_", NA, "z", NA))
  expect_equal(res$Frequency, c(1L, 1L, 1L, 1L))
})

test_that("tagged NAs stay apart in a two-way crosstab", {
  a <- c(haven::tagged_na("a"), haven::tagged_na("b"),
        haven::tagged_na("a"), 1)
  b <- c("x", "x", "y", "y")
  res <- proc_freq(data.frame(a = a, b = b), c("a", "b"), missing = TRUE)
  expect_equal(res$Frequency, c(1L, 1L, 1L, 1L))
  expect_equal(res$Row_Percent, c(50, 50, 100, 100))
  expect_equal(res$Col_Percent, c(50, 50, 50, 50))
  expect_equal(haven::na_tag(res$a), c("a", "a", "b", NA))
})
