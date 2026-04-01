library(testthat)
library(hvtiRutilities)

# Basic functionality ----

test_that("compare_datasets returns correct structure", {
  v1 <- data.frame(a = 1:3, b = 4:6)
  v2 <- data.frame(a = 1:5, b = 6:10)

  result <- compare_datasets(v1, v2)

  expect_type(result, "list")
  expect_s3_class(result, "dataset_comparison")
  expect_named(result, c("rows_old", "rows_new", "cols_added",
                          "cols_dropped", "type_changes", "label_changes"))
})

test_that("compare_datasets detects row count changes", {
  v1 <- data.frame(x = 1:10)
  v2 <- data.frame(x = 1:20)

  result <- compare_datasets(v1, v2)

  expect_equal(result$rows_old, 10)
  expect_equal(result$rows_new, 20)
})

# Column changes ----

test_that("compare_datasets detects added columns", {
  v1 <- data.frame(a = 1:3)
  v2 <- data.frame(a = 1:3, b = 4:6, c = 7:9)

  result <- compare_datasets(v1, v2)

  expect_equal(result$cols_added, c("b", "c"))
  expect_length(result$cols_dropped, 0)
})

test_that("compare_datasets detects dropped columns", {
  v1 <- data.frame(a = 1:3, b = 4:6, c = 7:9)
  v2 <- data.frame(a = 1:3)

  result <- compare_datasets(v1, v2)

  expect_length(result$cols_added, 0)
  expect_equal(result$cols_dropped, c("b", "c"))
})

test_that("compare_datasets detects both added and dropped", {
  v1 <- data.frame(a = 1:3, old_col = 4:6)
  v2 <- data.frame(a = 1:3, new_col = 7:9)

  result <- compare_datasets(v1, v2)

  expect_equal(result$cols_added, "new_col")
  expect_equal(result$cols_dropped, "old_col")
})

# Type changes ----

test_that("compare_datasets detects type changes", {
  v1 <- data.frame(a = 1:3, b = c("x", "y", "z"), stringsAsFactors = FALSE)
  v2 <- data.frame(a = c("1", "2", "3"), b = c("x", "y", "z"),
                    stringsAsFactors = FALSE)

  result <- compare_datasets(v1, v2)

  expect_equal(nrow(result$type_changes), 1)
  expect_equal(result$type_changes$variable, "a")
  expect_equal(result$type_changes$old_class, "integer")
  expect_equal(result$type_changes$new_class, "character")
})

test_that("compare_datasets ignores matching types", {
  v1 <- data.frame(a = 1:3, b = 4:6)
  v2 <- data.frame(a = 7:9, b = 10:12)

  result <- compare_datasets(v1, v2)

  expect_equal(nrow(result$type_changes), 0)
})

# Label changes ----

test_that("compare_datasets detects label changes", {
  v1 <- data.frame(age = 1:3)
  labelled::var_label(v1$age) <- "Patient Age"
  v2 <- data.frame(age = 1:5)
  labelled::var_label(v2$age) <- "Age at Surgery (years)"

  result <- compare_datasets(v1, v2)

  expect_equal(nrow(result$label_changes), 1)
  expect_equal(result$label_changes$variable, "age")
  expect_equal(result$label_changes$old_label, "Patient Age")
  expect_equal(result$label_changes$new_label, "Age at Surgery (years)")
})

test_that("compare_datasets ignores matching labels", {
  v1 <- data.frame(age = 1:3)
  labelled::var_label(v1$age) <- "Patient Age"
  v2 <- data.frame(age = 4:6)
  labelled::var_label(v2$age) <- "Patient Age"

  result <- compare_datasets(v1, v2)

  expect_equal(nrow(result$label_changes), 0)
})

# Identical datasets ----

test_that("compare_datasets finds no differences for identical data", {
  dta <- generate_survival_data(n = 20, seed = 1)

  result <- compare_datasets(dta, dta)

  expect_equal(result$rows_old, result$rows_new)
  expect_length(result$cols_added, 0)
  expect_length(result$cols_dropped, 0)
  expect_equal(nrow(result$type_changes), 0)
  expect_equal(nrow(result$label_changes), 0)
})

# No shared columns ----

test_that("compare_datasets handles no shared columns", {
  v1 <- data.frame(a = 1:3)
  v2 <- data.frame(b = 4:6)

  result <- compare_datasets(v1, v2)

  expect_equal(result$cols_added, "b")
  expect_equal(result$cols_dropped, "a")
  expect_equal(nrow(result$type_changes), 0)
  expect_equal(nrow(result$label_changes), 0)
})

# Validation ----

test_that("compare_datasets rejects non-data-frames", {
  expect_error(compare_datasets("not a df", data.frame(a = 1)),
               "must be a data frame")
  expect_error(compare_datasets(data.frame(a = 1), 42),
               "must be a data frame")
})

# Print method ----

test_that("print.dataset_comparison produces output", {
  v1 <- data.frame(a = 1:3, old = 4:6)
  v2 <- data.frame(a = c("x", "y", "z"), new = 1:3,
                    stringsAsFactors = FALSE)

  result <- compare_datasets(v1, v2)
  output <- capture.output(print(result))

  expect_true(any(grepl("Dataset Comparison", output)))
  expect_true(any(grepl("Rows:", output)))
  expect_true(any(grepl("added", output)))
  expect_true(any(grepl("dropped", output)))
})

test_that("print shows no differences for identical data", {
  dta <- data.frame(x = 1:3)
  result <- compare_datasets(dta, dta)
  output <- capture.output(print(result))

  expect_true(any(grepl("No differences", output)))
})
