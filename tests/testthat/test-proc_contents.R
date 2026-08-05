library(testthat)
library(hvtiRutilities)

# Structure ----

test_that("proc_contents returns header and variables", {
  dta <- sample_data(n = 20)
  pc <- proc_contents(dta)

  expect_s3_class(pc, "proc_contents")
  expect_named(pc, c("header", "variables"))
  expect_equal(pc$header$observations, 20L)
  expect_equal(pc$header$variables, 7L)
  expect_named(pc$variables, c("num", "variable", "type", "format",
                               "label", "class", "n_unique", "pct_missing"))
  expect_equal(nrow(pc$variables), ncol(dta))
})

test_that("proc_contents never emits len, pos or informat", {
  pc <- proc_contents(sample_data(n = 5))
  expect_false(any(c("len", "pos", "informat") %in% names(pc$variables)))
})

# SAS type mapping ----

test_that("proc_contents maps R classes to SAS Num/Char", {
  dta <- data.frame(
    a = 1:3,
    b = c(1.5, 2.5, 3.5),
    c = c("x", "y", "z"),
    d = factor(c("p", "q", "p")),
    e = c(TRUE, FALSE, TRUE),
    f = as.Date(c("2020-01-01", "2020-01-02", "2020-01-03")),
    stringsAsFactors = FALSE
  )
  pc <- proc_contents(dta, order = "varnum")

  expect_equal(pc$variables$type,
               c("Num", "Num", "Char", "Char", "Num", "Num"))
})

test_that("proc_contents reports Date as Num while class shows Date", {
  dta <- data.frame(d = as.Date(c("2020-01-01", "2020-06-01")))
  pc <- proc_contents(dta)

  expect_equal(pc$variables$type, "Num")
  expect_equal(pc$variables$class, "Date")
})

# Formats and labels ----

test_that("proc_contents surfaces the SAS format attribute", {
  dta <- data.frame(d = c(1, 2), x = c(3, 4))
  attr(dta$d, "format.sas") <- "DATE9."
  pc <- proc_contents(dta, order = "varnum")

  expect_equal(pc$variables$format, c("DATE9.", NA_character_))
})

test_that("proc_contents falls back to the variable name when unlabelled", {
  dta <- data.frame(nolabel = 1:3)
  pc <- proc_contents(dta)

  expect_equal(pc$variables$label, "nolabel")
})

test_that("proc_contents reports labels from labelled data", {
  pc <- proc_contents(sample_data(n = 10))
  expect_equal(pc$variables$label[pc$variables$variable == "id"],
               "Patient Identifier")
})

# Ordering ----

test_that("proc_contents sorts alphabetically by default", {
  dta <- data.frame(zeta = 1:3, alpha = 4:6, Mid = 7:9)
  pc <- proc_contents(dta)

  expect_equal(pc$variables$variable, c("alpha", "Mid", "zeta"))
  expect_equal(pc$variables$num, c(2L, 3L, 1L))
})

test_that("proc_contents order = 'varnum' keeps creation order", {
  dta <- data.frame(zeta = 1:3, alpha = 4:6, Mid = 7:9)
  pc <- proc_contents(dta, order = "varnum")

  expect_equal(pc$variables$variable, c("zeta", "alpha", "Mid"))
  expect_equal(pc$variables$num, 1:3)
})

# Counts ----

test_that("proc_contents computes n_unique and pct_missing", {
  dta <- data.frame(a = c(1, 1, 2, 3, NA))
  pc <- proc_contents(dta)

  expect_equal(pc$variables$n_unique, 3L)
  expect_equal(pc$variables$pct_missing, 20)
})

# Edge cases ----

test_that("proc_contents errors on non-data-frame input", {
  expect_error(proc_contents(1:10), "must be a data frame")
})

test_that("proc_contents handles zero-column input", {
  pc <- proc_contents(data.frame())

  expect_equal(pc$header$observations, 0L)
  expect_equal(pc$header$variables, 0L)
  expect_equal(nrow(pc$variables), 0L)
  expect_named(pc$variables, c("num", "variable", "type", "format",
                               "label", "class", "n_unique", "pct_missing"))
})

test_that("proc_contents reports NaN pct_missing for zero-row input", {
  # Documented behaviour: mean(is.na(x)) on an empty vector is 0/0, and the
  # proportion missing among no values is undefined. Reporting 0 would assert
  # that nothing is missing. Pinned so the documented contract is enforced.
  pc <- proc_contents(data.frame(a = numeric(), b = character()))

  expect_equal(pc$header$observations, 0L)
  expect_equal(pc$header$variables, 2L)
  expect_true(all(is.nan(pc$variables$pct_missing)))
  expect_equal(pc$variables$n_unique, c(0L, 0L))
})

test_that("print.proc_contents returns its input invisibly", {
  pc <- proc_contents(sample_data(n = 5))
  expect_output(out <- print(pc), "Observations")
  expect_identical(out, pc)
})
