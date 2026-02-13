library(testthat)
library(hvtiRutilities)

# Basic functionality tests ----

test_that("label_map returns data.frame with correct structure", {
  dta <- data.frame(age = c(25, 30), sex = c("M", "F"))
  labelled::var_label(dta$age) <- "Patient Age"
  labelled::var_label(dta$sex) <- "Patient Sex"

  result <- label_map(dta)

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 2)
  expect_equal(ncol(result), 2)
  expect_named(result, c("key", "label"))
})

test_that("label_map extracts correct key-label pairs", {
  dta <- data.frame(age = c(25, 30), sex = c("M", "F"))
  labelled::var_label(dta$age) <- "Patient Age"
  labelled::var_label(dta$sex) <- "Patient Sex"

  result <- label_map(dta)

  expect_equal(result$key, c("age", "sex"))
  expect_equal(result$label, c("Patient Age", "Patient Sex"))
})

test_that("label_map can be used for matching operations", {
  dta <- data.frame(age = c(25, 30), sex = c("M", "F"))
  labelled::var_label(dta$age) <- "Patient Age"
  labelled::var_label(dta$sex) <- "Patient Sex"

  result <- label_map(dta)

  # Simulate the documented usage pattern
  lookup <- data.frame(name = c("age", "sex"))
  lookup$label <- result$label[match(lookup$name, result$key)]

  expect_equal(lookup$label, c("Patient Age", "Patient Sex"))
})

# Unlabeled data tests ----

test_that("label_map handles dataset without labels", {
  dta <- data.frame(a = 1:3, b = 4:6)
  result <- label_map(dta)

  expect_s3_class(result, "data.frame")
  expect_equal(result$key, c("a", "b"))
  # null_action = "fill" means unlabeled columns get their name as label
  expect_equal(result$label, c("a", "b"))
})

test_that("label_map handles mixed labeled and unlabeled columns", {
  dta <- data.frame(x = 1:3, y = 4:6, z = 7:9)
  labelled::var_label(dta$x) <- "X Variable"
  labelled::var_label(dta$z) <- "Z Variable"
  # y has no label

  result <- label_map(dta)

  expect_equal(result$key, c("x", "y", "z"))
  expect_equal(result$label, c("X Variable", "y", "Z Variable"))
})

# Edge cases ----

test_that("label_map handles empty dataset", {
  dta <- data.frame()
  result <- label_map(dta)

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0)
  # Empty dataset only has "key" column due to how var_label returns empty named vector
  expect_true("key" %in% names(result))
})

test_that("label_map handles single column dataset", {
  dta <- data.frame(only_col = 1:5)
  labelled::var_label(dta$only_col) <- "The Only Column"

  result <- label_map(dta)

  expect_equal(nrow(result), 1)
  expect_equal(result$key, "only_col")
  expect_equal(result$label, "The Only Column")
})

# Special characters and formatting ----

test_that("label_map preserves special characters in labels", {
  dta <- data.frame(var1 = 1:3)
  labelled::var_label(dta$var1) <- "Label with (parens) & symbols!"

  result <- label_map(dta)

  expect_equal(result$label, "Label with (parens) & symbols!")
})

test_that("label_map handles long labels", {
  dta <- data.frame(var1 = 1:3)
  long_label <- paste(rep("Very long label text", 10), collapse = " ")
  labelled::var_label(dta$var1) <- long_label

  result <- label_map(dta)

  expect_equal(result$label, long_label)
})

test_that("label_map handles Unicode characters in labels", {
  dta <- data.frame(var1 = 1:3)
  labelled::var_label(dta$var1) <- "Température (°C)"

  result <- label_map(dta)

  expect_equal(result$label, "Température (°C)")
})

# Multiple columns ----

test_that("label_map handles many columns", {
  # Create dataset with 50 columns
  dta <- as.data.frame(matrix(1:150, ncol = 50))
  col_names <- paste0("var", 1:50)
  col_labels <- paste("Variable", 1:50)
  names(dta) <- col_names

  for (i in 1:50) {
    labelled::var_label(dta[[i]]) <- col_labels[i]
  }

  result <- label_map(dta)

  expect_equal(nrow(result), 50)
  expect_equal(result$key, col_names)
  expect_equal(result$label, col_labels)
})
