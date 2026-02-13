library(testthat)
library(hvtiRutilities)

test_that("sample_data returns data.frame with correct structure", {
  dta <- sample_data(n = 100)

  expect_s3_class(dta, "data.frame")
  expect_equal(nrow(dta), 100)
  expect_named(dta, c("id", "boolean", "logical", "f_real", "float", "char", "factor"))
})

test_that("sample_data columns have expected types", {
  dta <- sample_data(n = 100)

  expect_type(dta$id, "integer")
  expect_type(dta$logical, "character")
  expect_type(dta$boolean, "integer")
  expect_type(dta$float, "double")
  expect_s3_class(dta$factor, "factor")
  expect_type(dta$f_real, "double")
  expect_type(dta$char, "character")
})

test_that("sample_data respects n parameter", {
  expect_equal(nrow(sample_data(n = 50)), 50)
  expect_equal(nrow(sample_data(n = 200)), 200)
  expect_equal(nrow(sample_data(n = 5)), 5)
})

test_that("sample_data factor has expected levels", {
  dta <- sample_data(n = 100)
  expect_setequal(levels(dta$factor), c("C1", "C2", "C3", "C4", "C5"))
})

test_that("sample_data char column has expected values", {
  dta <- sample_data(n = 100)
  expect_true(all(dta$char %in% c("male", "female")))
})

test_that("sample_data logical column has expected values", {
  dta <- sample_data(n = 100)
  expect_true(all(dta$logical %in% c("F", "T")))
})
