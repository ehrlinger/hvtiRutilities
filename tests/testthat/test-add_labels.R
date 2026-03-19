library(testthat)
library(hvtiRutilities)

# Label map mode ----

test_that("add_labels appends new labels to a label map", {
  dta <- data.frame(age = c(25, 30), sex = c("M", "F"))
  labelled::var_label(dta$age) <- "Patient Age"
  labelled::var_label(dta$sex) <- "Patient Sex"

  lmap <- label_map(dta)
  result <- add_labels(lmap, c(age_binned = "Age Group", bsa_ratio = "BSA Ratio"))

  expect_equal(nrow(result), 4)
  expect_equal(result$key[3], "age_binned")
  expect_equal(result$label[3], "Age Group")
  expect_equal(result$key[4], "bsa_ratio")
  expect_equal(result$label[4], "BSA Ratio")
})

test_that("add_labels updates existing labels in map", {
  dta <- data.frame(age = c(25, 30))
  labelled::var_label(dta$age) <- "Patient Age"

  lmap <- label_map(dta)
  result <- add_labels(lmap, c(age = "Age (years)"))

  expect_equal(nrow(result), 1)
  expect_equal(result$label[1], "Age (years)")
})

test_that("add_labels handles mix of new and existing keys in map", {
  dta <- data.frame(age = c(25, 30), sex = c("M", "F"))
  labelled::var_label(dta$age) <- "Patient Age"
  labelled::var_label(dta$sex) <- "Patient Sex"

  lmap <- label_map(dta)
  result <- add_labels(lmap, c(age = "Age (years)", bmi = "Body Mass Index"))

  expect_equal(nrow(result), 3)
  expect_equal(result$label[result$key == "age"], "Age (years)")
  expect_equal(result$label[result$key == "bmi"], "Body Mass Index")
  expect_equal(result$label[result$key == "sex"], "Patient Sex")
})

test_that("add_labels treats label maps with metadata columns as label maps", {
  lmap <- data.frame(
    key = c("age", "sex"),
    label = c("Patient Age", "Patient Sex"),
    notes = c("primary", "demographics"),
    stringsAsFactors = FALSE
  )

  result <- add_labels(lmap, c(bmi = "Body Mass Index"))

  expect_equal(result$label[result$key == "bmi"], "Body Mass Index")
  expect_true("notes" %in% names(result))
  expect_true(is.na(result$notes[result$key == "bmi"]))
})

# Data frame mode (labels applied directly) ----

test_that("add_labels applies labels directly to a data frame", {
  dta <- data.frame(age = c(25, 30), bmi = c(22.1, 27.3))
  result <- add_labels(dta, c(age = "Patient Age", bmi = "Body Mass Index"))

  expect_equal(labelled::var_label(result$age), "Patient Age")
  expect_equal(labelled::var_label(result$bmi), "Body Mass Index")
})

test_that("add_labels on data frame ignores columns not in data", {
  dta <- data.frame(age = c(25, 30))
  result <- add_labels(dta, c(age = "Age", nonexistent = "Missing"))

  expect_equal(labelled::var_label(result$age), "Age")
  expect_equal(ncol(result), 1)
})

test_that("add_labels on data frame preserves existing labels", {
  dta <- data.frame(age = c(25, 30), sex = c("M", "F"))
  labelled::var_label(dta$age) <- "Patient Age"
  labelled::var_label(dta$sex) <- "Patient Sex"

  result <- add_labels(dta, c(age = "Age (years)"))

  expect_equal(labelled::var_label(result$age), "Age (years)")
  expect_equal(labelled::var_label(result$sex), "Patient Sex")
})

# Validation ----

test_that("add_labels rejects non-data-frame", {
  expect_error(add_labels("not a df", c(x = "X")),
               "must be a data frame")
})

test_that("add_labels rejects unnamed vector", {
  dta <- data.frame(age = 1:3)
  expect_error(add_labels(dta, c("Age Group")),
               "named character vector")
})

test_that("add_labels rejects non-character input", {
  dta <- data.frame(age = 1:3)
  expect_error(add_labels(dta, c(age = 42)),
               "named character vector")
})

# Edge cases ----

test_that("add_labels works with single new label on map", {
  dta <- data.frame(x = 1:3)
  lmap <- suppressWarnings(label_map(dta))
  result <- add_labels(lmap, c(y = "Y Variable"))

  expect_equal(nrow(result), 2)
  expect_equal(result$key[2], "y")
  expect_equal(result$label[2], "Y Variable")
})

test_that("add_labels preserves original rows unchanged", {
  dta <- data.frame(a = 1:3, b = 4:6)
  labelled::var_label(dta$a) <- "Alpha"
  labelled::var_label(dta$b) <- "Beta"

  lmap <- label_map(dta)
  result <- add_labels(lmap, c(c = "Gamma"))

  expect_equal(result$label[1], "Alpha")
  expect_equal(result$label[2], "Beta")
})
