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
