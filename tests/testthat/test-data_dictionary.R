library(testthat)
library(hvtiRutilities)

# Basic functionality ----

test_that("data_dictionary returns correct structure", {
  dta <- generate_survival_data(n = 20, seed = 1)
  dict <- data_dictionary(dta)

  expect_s3_class(dict, "data.frame")
  expect_named(dict, c("variable", "label", "class", "n_unique",
                        "pct_missing", "summary"))
  expect_equal(nrow(dict), ncol(dta))
})

test_that("data_dictionary extracts labels", {
  dta <- generate_survival_data(n = 20, seed = 1)
  dict <- data_dictionary(dta)

  expect_equal(dict$label[dict$variable == "age"], "Age at surgery (years)")
  expect_equal(dict$label[dict$variable == "ccfid"], "Patient ID")
})

test_that("data_dictionary reports correct classes", {
  dta <- data.frame(
    x = 1:5,
    y = c("a", "b", "c", "d", "e"),
    z = c(TRUE, FALSE, TRUE, FALSE, TRUE),
    stringsAsFactors = FALSE
  )
  dict <- data_dictionary(dta)

  expect_equal(dict$class[dict$variable == "x"], "integer")
  expect_equal(dict$class[dict$variable == "y"], "character")
  expect_equal(dict$class[dict$variable == "z"], "logical")
})

test_that("data_dictionary reports n_unique correctly", {
  dta <- data.frame(a = c(1, 1, 2, 3, NA), b = c("x", "x", "x", "x", "x"))
  dict <- data_dictionary(dta)

  expect_equal(dict$n_unique[dict$variable == "a"], 3L)
  expect_equal(dict$n_unique[dict$variable == "b"], 1L)
})

test_that("data_dictionary reports pct_missing correctly", {
  dta <- data.frame(
    no_na = 1:10,
    half_na = c(rep(NA, 5), 1:5),
    all_na = rep(NA_real_, 10)
  )
  dict <- data_dictionary(dta)

  expect_equal(dict$pct_missing[dict$variable == "no_na"], 0)
  expect_equal(dict$pct_missing[dict$variable == "half_na"], 50)
  expect_equal(dict$pct_missing[dict$variable == "all_na"], 100)
})

# Summary column ----

test_that("numeric summary shows min/median/max", {
  dta <- data.frame(x = c(1, 2, 3, 4, 5))
  dict <- data_dictionary(dta)

  expect_match(dict$summary[1], "1 / 3 / 5")
})

test_that("logical summary shows TRUE percentage", {
  dta <- data.frame(x = c(TRUE, TRUE, FALSE, FALSE))
  dict <- data_dictionary(dta)

  expect_match(dict$summary[1], "TRUE: 50%")
})

test_that("factor summary shows levels", {
  dta <- data.frame(x = factor(c("A", "B", "C")))
  dict <- data_dictionary(dta)

  expect_match(dict$summary[1], "3 levels: A, B, C")
})

test_that("all-NA summary handled", {
  dta <- data.frame(x = rep(NA_real_, 5))
  dict <- data_dictionary(dta)

  expect_equal(dict$summary[1], "all NA")
})

# Edge cases ----

test_that("data_dictionary handles empty data frame", {
  dta <- data.frame()
  dict <- data_dictionary(dta)

  expect_s3_class(dict, "data.frame")
  expect_equal(nrow(dict), 0)
  expect_named(dict, c("variable", "label", "class", "n_unique",
                        "pct_missing", "summary"))
})

test_that("data_dictionary handles single-column data frame", {
  dta <- data.frame(only = c(1, 2, 3))
  labelled::var_label(dta$only) <- "The Only Column"
  dict <- data_dictionary(dta)

  expect_equal(nrow(dict), 1)
  expect_equal(dict$label, "The Only Column")
})

test_that("data_dictionary works after r_data_types conversion", {
  dta <- sample_data(n = 50)
  dta_clean <- r_data_types(dta, skip_vars = "id")
  dict <- data_dictionary(dta_clean)

  expect_equal(nrow(dict), ncol(dta_clean))
  # Labels should be preserved
  expect_equal(dict$label[dict$variable == "char"], "Gender")
})

# Validation ----

test_that("data_dictionary rejects non-data-frame", {
  expect_error(data_dictionary("not a df"), "must be a data frame")
  expect_error(data_dictionary(1:10), "must be a data frame")
})

# Factor with many levels ----

test_that("factor summary truncates at 5 levels", {
  dta <- data.frame(x = factor(LETTERS[1:10]))
  dict <- data_dictionary(dta)

  expect_match(dict$summary[1], "\\.\\.\\.")
  expect_match(dict$summary[1], "10 levels:")
})

# Characterization — pins behaviour across the proc_contents refactor ----

test_that("data_dictionary output is stable for labelled survival data", {
  dict <- data_dictionary(generate_survival_data(n = 100, seed = 42))

  expect_named(dict, c("variable", "label", "class", "n_unique",
                       "pct_missing", "summary"))
  expect_equal(dict$variable, names(generate_survival_data(n = 100, seed = 42)))
  expect_equal(dict$label[dict$variable == "age"], "Age at surgery (years)")
  expect_equal(dict$class[dict$variable == "age"], "numeric")
})

test_that("data_dictionary preserves original column order", {
  dta <- data.frame(zeta = 1:3, alpha = 4:6, Mid = 7:9)
  dict <- data_dictionary(dta)

  expect_equal(dict$variable, c("zeta", "alpha", "Mid"))
})

test_that("data_dictionary summary strings are stable per column type", {
  dta <- data.frame(
    num = c(1, 2, 3, 4),
    lgl = c(TRUE, FALSE, TRUE, TRUE),
    fct = factor(c("a", "b", "a", "c")),
    chr = c("p", "q", "p", "r"),
    empty = as.numeric(c(NA, NA, NA, NA)),
    stringsAsFactors = FALSE
  )
  dict <- data_dictionary(dta)

  expect_equal(dict$summary[dict$variable == "num"], "1 / 2.5 / 4")
  expect_equal(dict$summary[dict$variable == "lgl"], "TRUE: 75%")
  expect_equal(dict$summary[dict$variable == "fct"], "3 levels: a, b, c")
  expect_equal(dict$summary[dict$variable == "chr"], "3 levels: p, q, r")
  expect_equal(dict$summary[dict$variable == "empty"], "all NA")
})

test_that("data_dictionary summarises Date and labelled columns", {
  dta <- data.frame(
    d = as.Date(c("2020-01-01", "2020-12-31")),
    lab = c(1, 2)
  )
  labelled::val_labels(dta$lab) <- c(no = 1, yes = 2)
  labelled::var_label(dta$lab) <- "Coded outcome"
  dict <- data_dictionary(dta)

  expect_equal(dict$summary[dict$variable == "d"], "2020-01-01 / 2020-12-31")
  expect_equal(dict$label[dict$variable == "lab"], "Coded outcome")
  expect_equal(dict$summary[dict$variable == "lab"], "1 / 1.5 / 2")
})

test_that("data_dictionary handles zero-column input", {
  dict <- data_dictionary(data.frame())

  expect_equal(nrow(dict), 0L)
  expect_named(dict, c("variable", "label", "class", "n_unique",
                       "pct_missing", "summary"))
})
