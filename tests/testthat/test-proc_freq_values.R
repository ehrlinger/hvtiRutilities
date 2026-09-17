library(testthat)
library(hvtiRutilities)

## Expected values in this file are hand-computed and frozen as literals. No
## SAS listing exists for these fixtures yet; they await the Phase 1 oracle.

test_that("a one-way table counts, percents and cumulates", {
  d <- data.frame(dead = c(1, 0, 0, 0, 1))
  res <- proc_freq(d, "dead")
  expect_equal(res$dead, c(0, 1))
  expect_equal(res$Frequency, c(3L, 2L))
  expect_equal(res$Percent, c(60, 40))
  expect_equal(res$Cum_Frequency, c(3L, 5L))
  expect_equal(res$Cum_Percent, c(60, 100))
})

test_that("unweighted frequencies are integers", {
  res <- proc_freq(data.frame(g = c("a", "b", "a")), "g")
  expect_type(res$Frequency, "integer")
  expect_type(res$Cum_Frequency, "integer")
})

test_that("percentages are not rounded", {
  res <- proc_freq(data.frame(g = c("a", "b", "b")), "g")
  expect_equal(res$Percent, c(100 / 3, 200 / 3))
})

test_that("character levels sort by byte value, as SAS does", {
  res <- proc_freq(data.frame(g = c("b", "B", "a", "b")), "g")
  expect_equal(res$g, c("B", "a", "b"))
  expect_equal(res$Frequency, c(1L, 1L, 2L))
})

test_that("factor levels keep declared order and drop unused levels", {
  f <- factor(c("III", "I", "II", "I"), levels = c("I", "II", "III", "IV"))
  res <- proc_freq(data.frame(nyha = f), "nyha")
  expect_equal(as.character(res$nyha), c("I", "II", "III"))
  expect_equal(res$Frequency, c(2L, 1L, 1L))
})

test_that("doubles that print alike are not merged", {
  res <- proc_freq(data.frame(x = c(0.1 + 0.2, 0.3, 0.3)), "x")
  expect_equal(nrow(res), 2L)
  expect_equal(res$Frequency, c(2L, 1L))
})

test_that("a two-way crosstab gives cell, row and column percents", {
  d <- data.frame(a = c("x", "x", "x", "y", "y"),
                  b = c(0, 1, 1, 0, 0))
  res <- proc_freq(d, c("a", "b"))
  expect_equal(res$a, c("x", "x", "y"))
  expect_equal(res$b, c(0, 1, 0))
  expect_equal(res$Frequency, c(1L, 2L, 2L))
  expect_equal(res$Percent, c(20, 40, 40))
  expect_equal(res$Row_Percent, c(100 / 3, 200 / 3, 100))
  expect_equal(res$Col_Percent, c(100 / 3, 100, 200 / 3))
})

test_that("a two-way list table cumulates over the grand total", {
  d <- data.frame(a = c("x", "x", "x", "y", "y"),
                  b = c(0, 1, 1, 0, 0))
  res <- proc_freq(d, c("a", "b"), list = TRUE)
  expect_equal(res$Percent, c(20, 40, 40))
  expect_equal(res$Cum_Frequency, c(1L, 3L, 5L))
  expect_equal(res$Cum_Percent, c(20, 60, 100))
})

test_that("three-way percent is within stratum, but list is of the total", {
  d <- data.frame(s = c(1, 1, 1, 2),
                  a = c("x", "x", "y", "x"),
                  b = c(0, 1, 0, 0))
  cross <- proc_freq(d, c("s", "a", "b"))
  expect_equal(cross$Percent, c(100 / 3, 100 / 3, 100 / 3, 100))
  expect_equal(cross$Row_Percent, c(50, 50, 100, 100))
  expect_equal(cross$Col_Percent, c(50, 100, 50, 100))

  listed <- proc_freq(d, c("s", "a", "b"), list = TRUE)
  expect_equal(listed$Percent, c(25, 25, 25, 25))
  expect_equal(listed$Cum_Percent, c(25, 50, 75, 100))
})

test_that("list = TRUE on a one-way table changes nothing", {
  d <- data.frame(g = c("a", "b", "b"))
  expect_identical(proc_freq(d, "g", list = TRUE), proc_freq(d, "g"))
})
