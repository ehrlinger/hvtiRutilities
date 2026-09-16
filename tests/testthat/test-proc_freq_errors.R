library(testthat)
library(hvtiRutilities)

d <- data.frame(g = c("a", "b"), h = c(1, 2), wt = c(1, 2))

test_that("data must be a data frame", {
  expect_error(proc_freq(list(g = "a"), "g"), "must be a data frame")
})

test_that("tables must be a non-empty character vector", {
  expect_error(proc_freq(d, character(0)), "non-empty character vector")
  expect_error(proc_freq(d, 1), "non-empty character vector")
  expect_error(proc_freq(d, NA_character_), "non-empty character vector")
})

test_that("tables may not repeat a column", {
  expect_error(proc_freq(d, c("g", "g")), "more than once: g")
})

test_that("tables must name columns present in data", {
  expect_error(proc_freq(d, c("g", "nope")), "not found in 'data': nope")
})

test_that("missing and list must be a single TRUE or FALSE", {
  expect_error(proc_freq(d, "g", missing = "yes"),
               "'missing' must be a single TRUE or FALSE")
  expect_error(proc_freq(d, "g", list = NA),
               "'list' must be a single TRUE or FALSE")
  expect_error(proc_freq(d, "g", list = c(TRUE, FALSE)),
               "'list' must be a single TRUE or FALSE")
})

test_that("a weight column cannot also be a table variable", {
  expect_error(proc_freq(d, c("g", "wt"), weights = "wt"),
               "also named in 'tables'")
})

test_that("weights must name a numeric column", {
  expect_error(proc_freq(d, "h", weights = "g"), "must be numeric")
})
