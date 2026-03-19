library(testthat)
library(hvtiRutilities)

# apply_label_overrides (canonical name) ----

test_that("apply_label_overrides applies overrides from YAML file", {
  tmp <- tempfile(fileext = ".yml")
  on.exit(unlink(tmp))

  writeLines(c(
    "age: 'Patient Age (years)'",
    "bmi: 'Body Mass Index'"
  ), tmp)

  dta <- data.frame(age = 1:3, sex = c("M", "F", "M"))
  labelled::var_label(dta$age) <- "Patient Age"
  labelled::var_label(dta$sex) <- "Patient Sex"

  lmap <- label_map(dta)
  result <- apply_label_overrides(lmap, overrides_file = tmp)

  expect_equal(result$label[result$key == "age"], "Patient Age (years)")
  expect_equal(result$label[result$key == "sex"], "Patient Sex")
  expect_equal(result$label[result$key == "bmi"], "Body Mass Index")
})

test_that("apply_label_overrides honors label maps with metadata columns", {
  tmp <- tempfile(fileext = ".yml")
  on.exit(unlink(tmp))

  writeLines("bmi: 'Body Mass Index'", tmp)

  dta <- data.frame(age = 1:3, bmi = 4:6)
  labelled::var_label(dta$age) <- "Patient Age"
  labelled::var_label(dta$bmi) <- "BMI"

  lmap <- label_map(dta)
  lmap$notes <- c("baseline", "baseline")

  result <- apply_label_overrides(lmap, overrides_file = tmp)

  expect_equal(result$label[result$key == "bmi"], "Body Mass Index")
  expect_equal(result$notes[result$key == "age"], "baseline")
  expect_equal(result$notes[result$key == "bmi"], "baseline")
})

test_that("apply_label_overrides returns unchanged map when file does not exist", {
  dta <- data.frame(age = 1:3)
  labelled::var_label(dta$age) <- "Patient Age"

  lmap <- label_map(dta)
  result <- apply_label_overrides(lmap, overrides_file = "nonexistent_file.yml")

  expect_identical(result, lmap)
})

test_that("apply_label_overrides returns unchanged map for empty YAML", {
  tmp <- tempfile(fileext = ".yml")
  on.exit(unlink(tmp))
  writeLines("", tmp)

  dta <- data.frame(age = 1:3)
  labelled::var_label(dta$age) <- "Patient Age"

  lmap <- label_map(dta)
  result <- apply_label_overrides(lmap, overrides_file = tmp)

  expect_identical(result, lmap)
})

test_that("apply_label_overrides rejects invalid label_map_df", {
  expect_error(
    apply_label_overrides(data.frame(a = 1), overrides_file = "x.yml"),
    "data frame with 'key' and 'label' columns"
  )
})

test_that("apply_label_overrides supports study-specific abbreviation overrides", {
  tmp <- tempfile(fileext = ".yml")
  on.exit(unlink(tmp))

  writeLines(c(
    "cavv_area: 'Common AVV Area'",
    "ed_area: 'End-Diastolic Area'",
    "es_area: 'End-Systolic Area'"
  ), tmp)

  dta <- data.frame(
    cavv_area = 1:3, ed_area = 4:6,
    es_area = 7:9, other = 10:12
  )
  labelled::var_label(dta$cavv_area) <- "Common atrioventricular valve area"
  labelled::var_label(dta$ed_area) <- "area in End-diastole"
  labelled::var_label(dta$es_area) <- "area in End-systole"
  labelled::var_label(dta$other) <- "Other Variable"

  lmap <- label_map(dta)
  result <- apply_label_overrides(lmap, overrides_file = tmp)

  expect_equal(result$label[result$key == "cavv_area"], "Common AVV Area")
  expect_equal(result$label[result$key == "ed_area"], "End-Diastolic Area")
  expect_equal(result$label[result$key == "other"], "Other Variable")
})

# clean_labels backward compatibility ----

test_that("clean_labels is a working alias for apply_label_overrides", {
  tmp <- tempfile(fileext = ".yml")
  on.exit(unlink(tmp))
  writeLines("age: 'Age (years)'", tmp)

  dta <- data.frame(age = 1:3)
  labelled::var_label(dta$age) <- "Patient Age"
  lmap <- label_map(dta)

  expect_warning(
    result <- clean_labels(lmap, overrides_file = tmp),
    "apply_label_overrides"
  )
  expect_equal(result$label[result$key == "age"], "Age (years)")
})
