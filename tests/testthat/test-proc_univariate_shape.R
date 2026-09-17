library(testthat)
library(hvtiRutilities)

dta <- data.frame(g = c("b", "a", "b", "a", NA),
                  x = c(1, 2, 3, 4, 5),
                  y = c(2, 4, 6, 8, 10),
                  w = c(1, 2, 1, 2, 1))

test_that("default statistics are the unistats default, in order", {
  res <- proc_univariate(dta, vars = "x")
  expect_named(res, c("variable", "label", "n", "median", "mean", "std",
                      "cv", "min", "max"))
})

test_that("stats columns come in the order given, then pctlpts columns", {
  res <- proc_univariate(dta, vars = c("x", "y"), stats = c("max", "n"),
                         pctlpts = c(97.5, 0, 50, 100, 2.5))
  expect_named(res, c("variable", "label", "max", "n", "p97_5", "p0",
                      "p50", "p100", "p2_5"))
  expect_equal(res$variable, c("x", "y"))
  expect_equal(res$label, c("x", "y"))
})

test_that("pctlpre prefixes the percentile columns", {
  res <- proc_univariate(dta, vars = "x", stats = "n", pctlpts = 16,
                         pctlpre = "pp_")
  expect_named(res, c("variable", "label", "n", "pp_16"))
})

test_that("count statistics are integer and the rest numeric", {
  res <- proc_univariate(dta, vars = "x",
                         stats = c("n", "nmiss", "nobs", "msign", "t"),
                         pctlpts = 50)
  expect_type(res$n, "integer")
  expect_type(res$nmiss, "integer")
  expect_type(res$nobs, "integer")
  expect_type(res$msign, "double")
  expect_type(res$t, "double")
  expect_type(res$p50, "double")
})

test_that("class rows lead, drop a missing class value, and sort", {
  res <- proc_univariate(dta, vars = "x", class = "g", stats = "n")
  expect_named(res, c("g", "variable", "label", "n"))
  expect_equal(res$g, c("a", "b"))
  expect_equal(res$n, c(2L, 2L))
})

test_that("vars = NULL analyses numeric columns other than weights", {
  res <- proc_univariate(dta, stats = "n", weights = "w")
  expect_equal(res$variable, c("x", "y"))
})

test_that("a zero-row result keeps stats and percentile columns and types", {
  expect_warning(
    res <- proc_univariate(data.frame(g = c("a", "b")), stats = c("n", "t"),
                           pctlpts = 2.5),
    "No numeric columns"
  )
  expect_equal(nrow(res), 0L)
  expect_named(res, c("variable", "label", "n", "t", "p2_5"))
  expect_type(res$n, "integer")
  expect_type(res$p2_5, "double")
})

test_that("a class level whose every weight is missing is dropped", {
  # SAS 9.4 M8 PROC UNIVARIATE (2026-09-17) writes no row for level y.
  # PROC MEANS keeps such a level, with N = 0.
  cw <- data.frame(g = c("x", "x", "y", "y"), a = 1:4,
                   wt = c(1, 2, NA, NA))
  res <- proc_univariate(cw, vars = "a", class = "g",
                         stats = c("n", "nobs"), weights = "wt")
  expect_identical(res$g, "x")
  expect_identical(res$n, 2L)
  expect_identical(res$nobs, 2L)
})

test_that("pctlpts = numeric(0) gives the same columns as NULL", {
  res0 <- proc_univariate(dta, vars = "x", stats = "n", pctlpts = numeric(0))
  resn <- proc_univariate(dta, vars = "x", stats = "n", pctlpts = NULL)
  expect_named(res0, c("variable", "label", "n"))
  expect_equal(res0, resn)
})

test_that("all-missing weights under class warns about the weight", {
  cw <- data.frame(x = 1:4, g = c("a", "a", "b", "b"), w = NA_real_)
  expect_warning(
    res <- proc_univariate(cw, vars = "x", class = "g",
                           stats = c("n", "nobs"), weights = "w"),
    "missing weight"
  )
  expect_equal(nrow(res), 0L)
})

test_that("cv is NA for a zero-mean constant column, 0 otherwise", {
  res_zero <- proc_univariate(data.frame(x = rep(0, 4)), vars = "x",
                              stats = "cv")
  res_five <- proc_univariate(data.frame(x = rep(5, 4)), vars = "x",
                              stats = "cv")
  expect_true(is.na(res_zero$cv))
  expect_equal(res_five$cv, 0)
})
