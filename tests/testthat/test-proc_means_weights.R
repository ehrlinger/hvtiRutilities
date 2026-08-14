library(testthat)
library(hvtiRutilities)

d <- data.frame(a = c(1, 2, 3, 4), wt = c(1, 1, 2, 4))

test_that("sumwgt sums the weight column", {
  res <- proc_means(d, vars = "a", stats = "sumwgt", weights = "wt")
  expect_equal(res$sumwgt, 8)
})

test_that("sumwgt equals n when no weights are given", {
  res <- proc_means(d, vars = "a", stats = c("n", "sumwgt"))
  expect_equal(res$sumwgt, res$n)
})

test_that("weights must name a column present in data", {
  expect_error(proc_means(d, vars = "a", stats = "sumwgt", weights = "nope"),
               "Column\\(s\\) not found")
})

test_that("weights must name a numeric column", {
  d2 <- data.frame(a = c(1, 2), g = c("x", "y"))
  expect_error(proc_means(d2, vars = "a", stats = "sumwgt", weights = "g"),
               "must be numeric")
})

test_that("weights must be a single column name", {
  expect_error(proc_means(d, vars = "a", stats = "sumwgt",
                          weights = c("wt", "a")),
               "single column")
})

test_that("a zero weight is an error naming the row", {
  dz <- data.frame(a = c(1, 2, 3), wt = c(1, 0, 2))
  expect_error(proc_means(dz, vars = "a", stats = "sumwgt", weights = "wt"),
               "row\\(s\\): 2")
})

test_that("a negative weight is an error naming the row", {
  dn <- data.frame(a = c(1, 2, 3), wt = c(1, 2, -3))
  expect_error(proc_means(dn, vars = "a", stats = "sumwgt", weights = "wt"),
               "row\\(s\\): 3")
})

test_that("a missing weight excludes that observation", {
  dm <- data.frame(a = c(1, 2, 3), wt = c(1, NA, 2))
  res <- proc_means(dm, vars = "a", stats = c("n", "sumwgt"), weights = "wt")
  expect_equal(res$n, 2L)
  expect_equal(res$sumwgt, 3)
})

test_that("weights apply within each class level", {
  dc <- data.frame(a = c(1, 2, 3, 4),
                   g = c("x", "x", "y", "y"),
                   wt = c(1, 3, 2, 5))
  res <- proc_means(dc, vars = "a", class = "g", stats = "sumwgt",
                    weights = "wt")
  expect_equal(res$sumwgt[res$g == "x"], 4)
  expect_equal(res$sumwgt[res$g == "y"], 7)
})

test_that("the weight column is not itself analysed by default", {
  res <- proc_means(d, stats = "n", weights = "wt")
  expect_equal(res$variable, "a")
})

test_that("naming the weight column in vars is an error", {
  expect_error(proc_means(d, vars = "wt", stats = "n", weights = "wt"),
               "also named in 'vars' or 'class'")
})

test_that("naming the weight column in class is an error", {
  expect_error(proc_means(d, vars = "a", class = "wt", stats = "n",
                          weights = "wt"),
               "also named in 'vars' or 'class'")
})
