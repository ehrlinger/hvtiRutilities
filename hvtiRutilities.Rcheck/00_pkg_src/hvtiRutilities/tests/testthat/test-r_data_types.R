library(testthat)
library(hvtiRutilities)

# Basic functionality tests ----

test_that("r_data_types returns a data.frame", {
  dta <- sample_data(n = 100)
  result <- r_data_types(dta)

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), nrow(dta))
})

test_that("r_data_types converts character columns to factors", {
  dta <- data.frame(
    a = c("x", "y", "x"),
    b = c(1, 0, 1),
    stringsAsFactors = FALSE
  )
  result <- r_data_types(dta)

  expect_s3_class(result$a, "factor")
  expect_equal(levels(result$a), c("x", "y"))
})

test_that("r_data_types converts binary numeric to logical", {
  dta <- data.frame(
    binary = c(1, 0, 1, 0),
    stringsAsFactors = FALSE
  )
  result <- r_data_types(dta)

  expect_type(result$binary, "logical")
  expect_equal(as.logical(result$binary), c(TRUE, FALSE, TRUE, FALSE))
})

test_that("r_data_types handles character and binary together correctly", {
  dta <- data.frame(
    a = c("x", "y", "x"),
    b = c(1, 0, 1),
    stringsAsFactors = FALSE
  )
  result <- r_data_types(dta)

  expect_s3_class(result$a, "factor")
  expect_type(result$b, "logical")
})

# Binary factor option tests ----

test_that("binary_factor=TRUE converts binary to factor instead of logical", {
  dta <- data.frame(binary = c(1, 0, 1), stringsAsFactors = FALSE)
  result <- r_data_types(dta, binary_factor = TRUE)

  expect_s3_class(result$binary, "factor")
  expect_length(levels(result$binary), 2)
})

test_that("binary_factor=FALSE keeps default logical conversion", {
  dta <- data.frame(binary = c(1, 0, 1), stringsAsFactors = FALSE)
  result <- r_data_types(dta, binary_factor = FALSE)

  expect_type(result$binary, "logical")
})

# Factor size parameter tests ----

test_that("factor_size controls numeric to factor conversion", {
  dta <- data.frame(
    small = c(1, 2, 2, 1, 3),
    stringsAsFactors = FALSE
  )
  result <- r_data_types(dta, factor_size = 6)

  expect_s3_class(result$small, "factor")
  expect_equal(levels(result$small), c("1", "2", "3"))
})

test_that("factor_size prevents conversion when unique values >= threshold", {
  dta <- data.frame(
    many = 1:20,
    stringsAsFactors = FALSE
  )
  result <- r_data_types(dta, factor_size = 10)

  expect_type(result$many, "integer")
})

# Skip variables tests ----

test_that("skip_vars preserves specified columns unchanged", {
  dta <- data.frame(
    a = c(1, 0, 1),
    b = c("x", "y", "z"),
    stringsAsFactors = FALSE
  )
  result <- r_data_types(dta, skip_vars = "a")

  expect_type(result$a, "double")  # Unchanged
  expect_s3_class(result$b, "factor")  # Still converted
})

test_that("skip_vars works with multiple columns", {
  dta <- data.frame(
    a = 1:100,
    b = rep(c("x", "y", "z"), length.out = 100),
    d = 1:100,  # Many unique values, won't be converted to factor
    stringsAsFactors = FALSE
  )
  result <- r_data_types(dta, skip_vars = c("a", "b"))

  # Skipped columns remain unchanged
  expect_type(result$a, "integer")
  expect_type(result$b, "character")
  # Non-skipped column is processed normally (stays numeric with many unique values)
  expect_type(result$d, "integer")
})

# Error handling tests ----

test_that("skip_vars errors on non-existent column names", {
  dta <- data.frame(a = 1:3)

  expect_error(
    r_data_types(dta, skip_vars = "nonexistent"),
    "not found in dataset"
  )
})

test_that("factor_size errors on invalid values", {
  dta <- data.frame(a = 1:3)

  expect_error(r_data_types(dta, factor_size = 1), "greater than 1")
  expect_error(r_data_types(dta, factor_size = 0), "greater than 1")
  expect_error(r_data_types(dta, factor_size = -5), "greater than 1")
})

test_that("factor_size errors on non-integer values", {
  dta <- data.frame(a = 1:3)

  expect_error(r_data_types(dta, factor_size = 2.5), "whole number")
  expect_error(r_data_types(dta, factor_size = 3.14), "whole number")
})

test_that("factor_size errors on values over 50", {
  dta <- data.frame(a = 1:3)

  expect_error(r_data_types(dta, factor_size = 100), "must be 50 or less")
  expect_error(r_data_types(dta, factor_size = 51), "must be 50 or less")
})

# NA handling tests ----

test_that("character NA variants are converted to actual NA", {
  dta <- data.frame(
    a = c("NA", "na", "nA", "Na", "x"),
    stringsAsFactors = FALSE
  )
  result <- r_data_types(dta)

  expect_true(all(is.na(result$a[1:4])))
  expect_false(is.na(result$a[5]))
  expect_s3_class(result$a, "factor")
})

test_that("NA conversion preserves non-NA character values", {
  dta <- data.frame(
    mixed = c("NA", "valid", "na", "data", "nA"),
    stringsAsFactors = FALSE
  )
  result <- r_data_types(dta)

  expect_equal(sum(is.na(result$mixed)), 3)
  expect_true("valid" %in% levels(result$mixed))
  expect_true("data" %in% levels(result$mixed))
})

# Label preservation tests ----

test_that("r_data_types preserves variable labels", {
  dta <- data.frame(age = c(25, 30, 35), sex = c("M", "F", "M"))
  labelled::var_label(dta$age) <- "Patient Age"
  labelled::var_label(dta$sex) <- "Patient Sex"

  result <- r_data_types(dta)

  expect_equal(labelled::var_label(result$age), "Patient Age")
  expect_equal(labelled::var_label(result$sex), "Patient Sex")
})
