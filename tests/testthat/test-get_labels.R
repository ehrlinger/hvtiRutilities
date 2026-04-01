library(testthat)
library(hvtiRutilities)

# Basic functionality ----

test_that("get_labels returns named character vector", {
  dta <- generate_survival_data(n = 20, seed = 1)
  lmap <- label_map(dta)

  result <- get_labels(lmap, c("age", "bmi"))

  expect_type(result, "character")
  expect_named(result, c("age", "bmi"))
  expect_length(result, 2)
})

test_that("get_labels returns correct labels", {
  dta <- generate_survival_data(n = 20, seed = 1)
  lmap <- label_map(dta)

  result <- get_labels(lmap, c("age", "hgb_bs", "ccfid"))

  expect_equal(result[["age"]], "Age at surgery (years)")
  expect_equal(result[["hgb_bs"]], "Baseline hemoglobin (g/dL)")
  expect_equal(result[["ccfid"]], "Patient ID")
})

test_that("get_labels works with single variable", {
  dta <- sample_data(n = 10)
  lmap <- label_map(dta)

  result <- get_labels(lmap, "id")

  expect_equal(result[["id"]], "Patient Identifier")
})

test_that("get_labels preserves input order", {
  dta <- generate_survival_data(n = 10, seed = 1)
  lmap <- label_map(dta)

  vars <- c("bmi", "age", "sex")
  result <- get_labels(lmap, vars)

  expect_equal(names(result), vars)
})

# Error handling ----

test_that("get_labels errors on missing variable", {
  dta <- sample_data(n = 10)
  lmap <- label_map(dta)

  expect_error(get_labels(lmap, c("id", "nonexistent")),
               "not found in label map")
})

test_that("get_labels errors on multiple missing variables", {
  dta <- sample_data(n = 10)
  lmap <- label_map(dta)

  expect_error(get_labels(lmap, c("nope", "also_nope")),
               "Variables not found")
  expect_error(get_labels(lmap, c("nope", "also_nope")),
               "'nope'")
})

test_that("get_labels rejects empty vector", {
  dta <- sample_data(n = 10)
  lmap <- label_map(dta)

  expect_error(get_labels(lmap, character(0)),
               "at least one element")
})

test_that("get_labels rejects non-character input", {
  dta <- sample_data(n = 10)
  lmap <- label_map(dta)

  expect_error(get_labels(lmap, 42), "character vector")
})

test_that("get_labels rejects invalid label map", {
  expect_error(get_labels(data.frame(a = 1), "a"),
               "data frame with 'key' and 'label' columns")
})
