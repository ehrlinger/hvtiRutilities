library(testthat)
library(hvtiRutilities)

# Edge cases and boundary conditions ----

test_that("r_data_types handles empty data frame", {
  dta <- data.frame()
  result <- r_data_types(dta)

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0)
  expect_equal(ncol(result), 0)
})

test_that("r_data_types handles single row data frame", {
  dta <- data.frame(
    a = "x",
    b = 1,
    c = 0,
    stringsAsFactors = FALSE
  )
  result <- r_data_types(dta)

  expect_equal(nrow(result), 1)
  expect_s3_class(result$a, "factor")
})

test_that("r_data_types handles single column data frame", {
  dta <- data.frame(x = c("a", "b", "c"), stringsAsFactors = FALSE)
  result <- r_data_types(dta)

  expect_equal(ncol(result), 1)
  expect_s3_class(result$x, "factor")
})

test_that("r_data_types handles data with all NA values", {
  dta <- data.frame(
    a = c(NA, NA, NA),
    b = c(NA_character_, NA_character_, NA_character_),
    stringsAsFactors = FALSE
  )
  result <- r_data_types(dta)

  expect_equal(sum(!is.na(result$a)), 0)
  expect_equal(sum(!is.na(result$b)), 0)
})

test_that("r_data_types preserves Date columns", {
  dta <- data.frame(
    date = as.Date(c("2023-01-01", "2023-01-02", "2023-01-03")),
    value = 1:3
  )
  result <- r_data_types(dta)

  expect_s3_class(result$date, "Date")
})

test_that("r_data_types preserves POSIXct columns with skip_vars", {
  dta <- data.frame(
    timestamp = as.POSIXct(c("2023-01-01 10:00:00", "2023-01-01 11:00:00")),
    value = 1:2
  )
  # Skip timestamp to preserve it (otherwise it might be converted)
  result <- r_data_types(dta, skip_vars = "timestamp")

  expect_s3_class(result$timestamp, "POSIXct")
})

test_that("r_data_types preserves ordered factors", {
  dta <- data.frame(
    level = ordered(c("low", "medium", "high"), levels = c("low", "medium", "high")),
    value = 1:3
  )
  result <- r_data_types(dta)

  expect_s3_class(result$level, "ordered")
  expect_equal(levels(result$level), c("low", "medium", "high"))
})

# Boundary values for factor_size ----

test_that("factor_size of 2 works correctly", {
  dta <- data.frame(x = 1:10)
  result <- r_data_types(dta, factor_size = 2)

  # x has 10 unique values, so won't be converted
  expect_type(result$x, "integer")
})

test_that("factor_size of 50 (maximum) works correctly", {
  dta <- data.frame(x = 1:49)
  result <- r_data_types(dta, factor_size = 50)

  # x has 49 unique values, less than 50, more than 2
  expect_s3_class(result$x, "factor")
})

test_that("variable with exactly factor_size unique values", {
  dta <- data.frame(x = 1:10)
  result <- r_data_types(dta, factor_size = 10)

  # x has exactly 10 unique values, should NOT be converted (< not <=)
  expect_type(result$x, "integer")
})

test_that("variable with factor_size - 1 unique values gets converted", {
  dta <- data.frame(x = 1:9)
  result <- r_data_types(dta, factor_size = 10)

  # x has 9 unique values, should be converted
  expect_s3_class(result$x, "factor")
})

# Skip vars edge cases ----

test_that("skip_vars with all columns skips all conversions", {
  dta <- data.frame(
    a = c("x", "y", "z"),
    b = c(1, 0, 1),
    stringsAsFactors = FALSE
  )
  result <- r_data_types(dta, skip_vars = c("a", "b"))

  expect_type(result$a, "character")
  expect_type(result$b, "double")
})

test_that("skip_vars preserves column order with non-contiguous columns", {
  dta <- data.frame(
    a = c("x", "y", "z"),
    b = c(1, 2, 3),
    c = c("m", "n", "o"),
    d = c(4, 5, 6),
    stringsAsFactors = FALSE
  )
  result <- r_data_types(dta, skip_vars = c("a", "d"))

  expect_equal(names(result), c("a", "b", "c", "d"))
  expect_type(result$a, "character")  # Skipped
  expect_s3_class(result$b, "factor")  # Converted
  expect_s3_class(result$c, "factor")  # Converted
  expect_type(result$d, "double")  # Skipped
})

# Mixed data types ----

test_that("r_data_types handles mix of integer and double", {
  dta <- data.frame(
    int_col = 1:3,
    dbl_col = c(1.5, 2.5, 3.5)
  )
  result <- r_data_types(dta)

  # Both have 3 unique values, should be converted to factors
  expect_s3_class(result$int_col, "factor")
  expect_s3_class(result$dbl_col, "factor")
})

test_that("r_data_types handles numeric(0) columns", {
  dta <- data.frame(x = numeric(0))
  result <- r_data_types(dta)

  expect_equal(nrow(result), 0)
  # Empty numeric vector has 0 unique values, which is < 3, so might be converted to logical
  # Just verify the column exists
  expect_true("x" %in% names(result))
})

# NA handling edge cases ----

test_that("handles mix of NA strings and real values", {
  dta <- data.frame(
    mixed = c("NA", "real", "na", "value", "nA", "data"),
    stringsAsFactors = FALSE
  )
  result <- r_data_types(dta)

  expect_equal(sum(is.na(result$mixed)), 3)
  expect_equal(sum(!is.na(result$mixed)), 3)
  expect_true(all(c("real", "value", "data") %in% levels(result$mixed)))
})

test_that("NA strings in all caps variations are handled", {
  dta <- data.frame(
    variants = c("NA", "Na", "nA", "na", "valid"),
    stringsAsFactors = FALSE
  )
  result <- r_data_types(dta)

  expect_equal(sum(is.na(result$variants)), 4)
  expect_equal(levels(result$variants), "valid")
})

test_that("preserves existing NA values in numeric columns", {
  dta <- data.frame(
    num_with_na = c(1, NA, 0, NA, 1)
  )
  result <- r_data_types(dta)

  expect_equal(sum(is.na(result$num_with_na)), 2)
  expect_type(result$num_with_na, "logical")
})

# Binary factor option ----

test_that("binary_factor converts all logical columns to factors", {
  dta <- data.frame(
    bin1 = c(1, 0, 1),
    bin2 = c(0, 0, 1),
    bin3 = c(1, 1, 0)
  )
  result <- r_data_types(dta, binary_factor = TRUE)

  expect_s3_class(result$bin1, "factor")
  expect_s3_class(result$bin2, "factor")
  expect_s3_class(result$bin3, "factor")
})

test_that("binary_factor FALSE keeps binary as logical", {
  dta <- data.frame(bin = c(1, 0, 1, 0))
  result <- r_data_types(dta, binary_factor = FALSE)

  expect_type(result$bin, "logical")
})

# Input validation ----

test_that("errors on non-data.frame input", {
  expect_error(
    r_data_types(c(1, 2, 3))
  )

  expect_error(
    r_data_types(list(a = 1, b = 2))
  )

  expect_error(
    r_data_types(matrix(1:9, nrow = 3))
  )
})

test_that("errors when skip_vars is not character", {
  dta <- data.frame(a = 1:3, b = 4:6)

  expect_error(
    r_data_types(dta, skip_vars = 1),
    "not found in dataset|'x' must be a vector"
  )
})

test_that("errors when factor_size is character", {
  dta <- data.frame(a = 1:3)

  expect_error(
    r_data_types(dta, factor_size = "ten"),
    "greater than 1"
  )
})

test_that("errors when factor_size is NULL", {
  dta <- data.frame(a = 1:3)

  expect_error(
    r_data_types(dta, factor_size = NULL),
    "greater than 1"
  )
})

test_that("errors when factor_size is NA", {
  dta <- data.frame(a = 1:3)

  expect_error(
    r_data_types(dta, factor_size = NA),
    "greater than 1"
  )
})

# Tibble and data.table compatibility ----

test_that("r_data_types works with tibbles", {
  skip_if_not_installed("tibble")

  dta <- tibble::tibble(
    a = c("x", "y", "z"),
    b = c(1, 0, 1)
  )
  result <- r_data_types(dta)

  expect_s3_class(result, "tbl_df")
  expect_s3_class(result$a, "factor")
  expect_type(result$b, "logical")
})

test_that("r_data_types preserves tibble class", {
  skip_if_not_installed("tibble")

  dta <- tibble::tibble(x = 1:5, y = letters[1:5])
  result <- r_data_types(dta)

  expect_true(inherits(result, "tbl_df"))
})

# Label preservation ----

test_that("preserves labels when no conversions happen", {
  dta <- data.frame(x = 1:100, y = 101:200)
  labelled::var_label(dta$x) <- "X Variable"
  labelled::var_label(dta$y) <- "Y Variable"

  result <- r_data_types(dta)

  expect_equal(labelled::var_label(result$x), "X Variable")
  expect_equal(labelled::var_label(result$y), "Y Variable")
})

test_that("preserves labels after type conversions", {
  dta <- data.frame(
    char = c("a", "b", "c"),
    binary = c(1, 0, 1),
    stringsAsFactors = FALSE
  )
  labelled::var_label(dta$char) <- "Character Variable"
  labelled::var_label(dta$binary) <- "Binary Variable"

  result <- r_data_types(dta)

  expect_equal(labelled::var_label(result$char), "Character Variable")
  expect_equal(labelled::var_label(result$binary), "Binary Variable")
})

test_that("preserves labels with skip_vars", {
  dta <- data.frame(a = c("x", "y"), b = 1:2)
  labelled::var_label(dta$a) <- "Label A"
  labelled::var_label(dta$b) <- "Label B"

  result <- r_data_types(dta, skip_vars = "a")

  expect_equal(labelled::var_label(result$a), "Label A")
  expect_equal(labelled::var_label(result$b), "Label B")
})

# Complex scenarios ----

test_that("handles data with many column types", {
  dta <- data.frame(
    id = 1:10,
    name = letters[1:10],
    binary = rep(c(0, 1), 5),
    category = rep(c("A", "B", "C", "D", "E"), 2),
    value = rnorm(10),
    date = seq(as.Date("2023-01-01"), by = "day", length.out = 10),
    stringsAsFactors = FALSE
  )

  result <- r_data_types(dta, factor_size = 8)

  expect_type(result$id, "integer")  # Too many unique values
  expect_s3_class(result$name, "factor")  # Character
  expect_type(result$binary, "logical")  # Binary
  expect_s3_class(result$category, "factor")  # 5 unique values
  expect_type(result$value, "double")  # Continuous
  expect_s3_class(result$date, "Date")  # Date preserved
})

test_that("handles variables at exact thresholds", {
  dta <- data.frame(
    two_values = c(1, 2, 1, 2, 1),  # Exactly 2 unique
    three_values = c(1, 2, 3, 1, 2),  # Exactly 3 unique
    ten_values = 1:10  # Exactly 10 unique (default factor_size)
  )

  result <- r_data_types(dta)

  expect_type(result$two_values, "logical")  # Binary → logical
  expect_s3_class(result$three_values, "factor")  # 3 < 10
  expect_type(result$ten_values, "integer")  # 10 not < 10
})
