library(testthat)
library(hvtiRutilities)

# Structure ----

test_that("proc_means defaults to SAS's five statistics", {
  dta <- data.frame(a = c(1, 2, 3, 4), b = c(10, 20, 30, 40))
  res <- proc_means(dta)

  expect_s3_class(res, "data.frame")
  expect_named(res, c("variable", "label", "n", "mean", "std", "min", "max"))
  expect_equal(res$variable, c("a", "b"))
})

test_that("proc_means keeps the requested statistic order", {
  dta <- data.frame(a = c(1, 2, 3, 4))
  res <- proc_means(dta, stats = c("max", "n", "mean"))

  expect_named(res, c("variable", "label", "max", "n", "mean"))
})

test_that("proc_means selects only numeric columns by default", {
  dta <- data.frame(num = c(1, 2), chr = c("x", "y"),
                    fct = factor(c("p", "q")), stringsAsFactors = FALSE)
  res <- proc_means(dta)

  expect_equal(res$variable, "num")
})

test_that("proc_means carries variable labels", {
  res <- proc_means(sample_data(n = 20), vars = "float")
  expect_equal(res$label, "Random Normal Value")
})

# Statistic values ----

test_that("proc_means computes the default five correctly", {
  dta <- data.frame(a = c(2, 4, 4, 4, 5, 5, 7, 9))
  res <- proc_means(dta)

  expect_equal(res$n, 8L)
  expect_equal(res$mean, 5)
  expect_equal(res$std, sd(c(2, 4, 4, 4, 5, 5, 7, 9)))
  expect_equal(res$min, 2)
  expect_equal(res$max, 9)
})

test_that("proc_means computes n, nmiss, sum, range, stderr and cv", {
  dta <- data.frame(a = c(1, 2, 3, NA))
  res <- proc_means(dta, stats = c("n", "nmiss", "sum", "range",
                                   "stderr", "cv"))

  expect_equal(res$n, 3L)
  expect_equal(res$nmiss, 1L)
  expect_equal(res$sum, 6)
  expect_equal(res$range, 2)
  expect_equal(res$stderr, sd(c(1, 2, 3)) / sqrt(3))
  expect_equal(res$cv, 100 * sd(c(1, 2, 3)) / 2)
})

# Quantile definition ----

test_that("proc_means uses the SAS QNTLDEF=5 quantile, not R's default", {
  dta <- data.frame(a = c(1, 2, 3, 4))
  res <- proc_means(dta, stats = c("q1", "median", "q3"))

  # SAS QNTLDEF=5 (R type 2) gives 1.5; R's default type 7 would give 1.75.
  expect_equal(res$q1, 1.5)
  expect_equal(res$median, 2.5)
  expect_equal(res$q3, 3.5)
})

test_that("proc_means accepts pNN percentile keywords", {
  dta <- data.frame(a = as.numeric(1:100))
  res <- proc_means(dta, stats = c("p15", "p50", "p99"))

  expect_named(res, c("variable", "label", "p15", "p50", "p99"))
  expect_equal(res$p15, unname(quantile(1:100, 0.15, type = 2)))
})

# Edge cases ----

test_that("proc_means returns NA statistics for an all-NA column", {
  dta <- data.frame(a = as.numeric(c(NA, NA)))
  res <- proc_means(dta, stats = c("n", "nmiss", "mean", "min"))

  expect_equal(res$n, 0L)
  expect_equal(res$nmiss, 2L)
  expect_true(is.na(res$mean))
  expect_true(is.na(res$min))
})

test_that("proc_means returns NA std for a single observation", {
  dta <- data.frame(a = 5)
  res <- proc_means(dta, stats = c("n", "mean", "std"))

  expect_equal(res$n, 1L)
  expect_equal(res$mean, 5)
  expect_true(is.na(res$std))
})

test_that("proc_means summarises a logical column when named explicitly", {
  dta <- data.frame(flag = c(TRUE, TRUE, FALSE, FALSE))
  res <- proc_means(dta, vars = "flag", stats = c("n", "mean"))

  expect_equal(res$n, 4L)
  expect_equal(res$mean, 0.5)
})

test_that("proc_means excludes logical columns from the default var set", {
  dta <- data.frame(num = c(1, 2), flag = c(TRUE, FALSE))
  res <- proc_means(dta)

  expect_equal(res$variable, "num")
})

test_that("proc_means includes labelled numerics and summarises their codes", {
  dta <- data.frame(coded = c(1, 2, 1, 2))
  labelled::val_labels(dta$coded) <- c(no = 1, yes = 2)
  res <- proc_means(dta, stats = c("n", "mean"))

  expect_equal(res$variable, "coded")
  expect_equal(res$n, 4L)
  expect_equal(res$mean, 1.5)
})

# Errors ----

test_that("proc_means errors on non-data-frame input", {
  expect_error(proc_means(1:10), "must be a data frame")
})

test_that("proc_means errors on an unknown statistic keyword", {
  dta <- data.frame(a = c(1, 2))
  expect_error(proc_means(dta, stats = c("mean", "bogus")),
               "Unrecognised statistic keyword")
  expect_error(proc_means(dta, stats = "p100"),
               "Unrecognised statistic keyword")
})

test_that("proc_means errors on a missing column name", {
  dta <- data.frame(a = c(1, 2))
  expect_error(proc_means(dta, vars = "nope"), "not found in 'data'")
  expect_error(proc_means(dta, class = "nope"), "not found in 'data'")
})

test_that("proc_means errors when vars names a non-numeric column", {
  dta <- data.frame(chr = c("x", "y"), stringsAsFactors = FALSE)
  expect_error(proc_means(dta, vars = "chr"), "Non-numeric column")
})

test_that("proc_means warns and returns zero rows when nothing is numeric", {
  dta <- data.frame(chr = c("x", "y"), stringsAsFactors = FALSE)
  expect_warning(res <- proc_means(dta), "No numeric columns")

  expect_equal(nrow(res), 0L)
  expect_named(res, c("variable", "label", "n", "mean", "std", "min", "max"))
})
