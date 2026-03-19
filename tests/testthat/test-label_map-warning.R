library(testthat)
library(hvtiRutilities)

test_that("label_map warns when >50% of columns lack labels", {
  dta <- data.frame(a = 1:3, b = 4:6, c = 7:9, d = 10:12)
  # No labels at all — 100% missing
  expect_warning(
    label_map(dta),
    "lack descriptive labels"
  )
})

test_that("label_map warns with specific counts", {
  dta <- data.frame(a = 1:3, b = 4:6, c = 7:9)
  labelled::var_label(dta$a) <- "Alpha"
  # b and c unlabeled = 67%
  expect_warning(
    label_map(dta),
    "2 of 3 variables"
  )
})

test_that("label_map suggests overrides file in warning", {
  dta <- data.frame(a = 1:3, b = 4:6)
  expect_warning(
    label_map(dta),
    "labels_overrides.yml"
  )
})

test_that("label_map does not warn when most columns have labels", {
  dta <- data.frame(a = 1:3, b = 4:6, c = 7:9)
  labelled::var_label(dta$a) <- "Alpha"
  labelled::var_label(dta$b) <- "Beta"
  # Only 1 of 3 unlabeled = 33%
  expect_no_warning(label_map(dta))
})

test_that("label_map does not warn when all columns have labels", {
  dta <- data.frame(a = 1:3, b = 4:6)
  labelled::var_label(dta$a) <- "Alpha"
  labelled::var_label(dta$b) <- "Beta"
  expect_no_warning(label_map(dta))
})

test_that("label_map does not warn for empty dataset", {
  dta <- data.frame()
  expect_no_warning(label_map(dta))
})

test_that("label_map warns at exactly 50% boundary", {
  dta <- data.frame(a = 1:3, b = 4:6)
  labelled::var_label(dta$a) <- "Alpha"
  # b unlabeled = 50%, not > 50%
  expect_no_warning(label_map(dta))
})
