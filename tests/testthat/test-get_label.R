library(testthat)
library(hvtiRutilities)

# Basic functionality ----

test_that("get_label returns the correct label", {
  dta <- generate_survival_data(n = 20, seed = 1)
  lmap <- label_map(dta)

  expect_equal(get_label(lmap, "age"), "Age at surgery (years)")
  expect_equal(get_label(lmap, "hgb_bs"), "Baseline hemoglobin (g/dL)")
  expect_equal(get_label(lmap, "ccfid"), "Patient ID")
})

test_that("get_label works with sample_data", {
  dta <- sample_data(n = 10)
  lmap <- label_map(dta)

  expect_equal(get_label(lmap, "id"), "Patient Identifier")
  expect_equal(get_label(lmap, "char"), "Gender")
})

# Error handling ----

test_that("get_label errors on missing variable", {
  dta <- sample_data(n = 10)
  lmap <- label_map(dta)

  expect_error(get_label(lmap, "nonexistent"), "not found in label map")
})

test_that("get_label errors on typo with informative message", {
  dta <- generate_survival_data(n = 10, seed = 1)
  lmap <- label_map(dta)

  expect_error(get_label(lmap, "ages"), "'ages' not found")
})

test_that("get_label rejects non-string input", {
  dta <- sample_data(n = 10)
  lmap <- label_map(dta)

  expect_error(get_label(lmap, 42), "single character string")
  expect_error(get_label(lmap, c("id", "char")), "single character string")
})

test_that("get_label rejects invalid label map", {
  expect_error(get_label(data.frame(a = 1), "a"),
               "data frame with 'key' and 'label' columns")
})
