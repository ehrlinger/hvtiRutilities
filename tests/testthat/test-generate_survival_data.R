library(testthat)
library(hvtiRutilities)

# Basic structure ----

test_that("returns data.frame with correct dimensions", {
  dta <- generate_survival_data(n = 100)

  expect_s3_class(dta, "data.frame")
  expect_equal(nrow(dta), 100)
  expect_equal(ncol(dta), 22)
})

test_that("returns all expected columns in the correct order", {
  dta <- generate_survival_data(n = 10)

  expected_cols <- c(
    "ccfid", "iv_dead", "dead", "reop", "iv_reop",
    "age", "sex", "bmi",
    "hgb_bs", "wbc_bs", "plate_bs", "gfr_bs",
    "lvefvs_b", "lvmass_b", "lvmsi_b", "stvoli_b", "stvold_b",
    "bypass_time", "xclamp_time",
    "nyha_class", "diabetes", "hypertension"
  )
  expect_equal(names(dta), expected_cols)
})

# Column types ----

test_that("column types are correct", {
  dta <- generate_survival_data(n = 200)

  expect_type(dta$ccfid, "character")
  expect_type(dta$iv_dead, "double")
  expect_type(dta$dead, "integer")
  expect_type(dta$reop, "integer")
  expect_type(dta$age, "double")
  expect_s3_class(dta$sex, "factor")
  expect_s3_class(dta$nyha_class, "ordered")
  expect_s3_class(dta$diabetes, "factor")
  expect_s3_class(dta$hypertension, "factor")
})

test_that("nyha_class levels are correct and ordered", {
  dta <- generate_survival_data(n = 200)

  expect_equal(levels(dta$nyha_class), c("I", "II", "III", "IV"))
  expect_true(is.ordered(dta$nyha_class))
})

test_that("sex factor has correct levels", {
  dta <- generate_survival_data(n = 200)

  expect_setequal(levels(dta$sex), c("Male", "Female"))
})

test_that("diabetes and hypertension have correct levels", {
  dta <- generate_survival_data(n = 200)

  expect_setequal(levels(dta$diabetes), c("No", "Yes"))
  expect_setequal(levels(dta$hypertension), c("No", "Yes"))
})

# Outcome validity ----

test_that("dead is always 0 or 1", {
  dta <- generate_survival_data(n = 500)

  expect_true(all(dta$dead %in% c(0L, 1L)))
})

test_that("reop is always 0 or 1", {
  dta <- generate_survival_data(n = 500)

  expect_true(all(dta$reop %in% c(0L, 1L)))
})

test_that("iv_dead is always positive", {
  dta <- generate_survival_data(n = 500)

  expect_true(all(dta$iv_dead > 0))
})

test_that("iv_reop is NA when reop is 0", {
  dta <- generate_survival_data(n = 500)

  expect_true(all(is.na(dta$iv_reop[dta$reop == 0])))
})

test_that("iv_reop is not NA when reop is 1", {
  dta <- generate_survival_data(n = 500)

  expect_true(all(!is.na(dta$iv_reop[dta$reop == 1])))
})

test_that("iv_reop is always <= iv_dead", {
  dta <- generate_survival_data(n = 500)

  reops <- dta[dta$reop == 1, ]
  expect_true(all(reops$iv_reop <= reops$iv_dead))
})

test_that("iv_reop is always >= 0", {
  dta <- generate_survival_data(n = 500)

  reops <- dta[dta$reop == 1, ]
  expect_true(all(reops$iv_reop >= 0))
})

test_that("no NaN values in iv_reop", {
  dta <- generate_survival_data(n = 500)

  expect_false(any(is.nan(dta$iv_reop), na.rm = TRUE))
})

# Patient IDs ----

test_that("ccfid values are unique and correctly formatted", {
  dta <- generate_survival_data(n = 50)

  expect_equal(length(unique(dta$ccfid)), 50)
  expect_true(all(grepl("^PT\\d{5}$", dta$ccfid)))
})

# Clinical plausibility ----

test_that("death rate is in a plausible range", {
  dta <- generate_survival_data(n = 1000)

  rate <- mean(dta$dead)
  expect_gt(rate, 0.10)
  expect_lt(rate, 0.90)
})

test_that("age stays within bounds", {
  dta <- generate_survival_data(n = 500)

  expect_true(all(dta$age >= 1))
  expect_true(all(dta$age <= 85))
})

test_that("xclamp_time is always less than bypass_time", {
  dta <- generate_survival_data(n = 500)

  expect_true(all(dta$xclamp_time < dta$bypass_time))
})

# Reproducibility ----

test_that("same seed produces identical output", {
  dta_a <- generate_survival_data(n = 100, seed = 42)
  dta_b <- generate_survival_data(n = 100, seed = 42)

  expect_equal(dta_a, dta_b)
})

test_that("different seeds produce different output", {
  dta_a <- generate_survival_data(n = 100, seed = 1)
  dta_b <- generate_survival_data(n = 100, seed = 2)

  expect_false(identical(dta_a$iv_dead, dta_b$iv_dead))
})

test_that("does not permanently alter the global RNG state", {
  set.seed(99)
  x_before <- rnorm(5)

  set.seed(99)
  generate_survival_data(n = 50, seed = 42)
  x_after <- rnorm(5)

  expect_equal(x_before, x_after)
})

# Variable labels ----

test_that("all 22 columns have variable labels", {
  dta <- generate_survival_data(n = 10)
  lmap <- label_map(dta)

  expect_equal(nrow(lmap), 22)
  # Labels should differ from column names (i.e., they are real labels)
  expect_false(all(lmap$key == lmap$label))
})

test_that("specific labels are correct", {
  dta <- generate_survival_data(n = 10)
  lmap <- label_map(dta)

  expect_equal(
    lmap$label[lmap$key == "dead"],
    "Death indicator (1=dead, 0=censored)"
  )
  expect_equal(
    lmap$label[lmap$key == "age"],
    "Age at surgery (years)"
  )
  expect_equal(
    lmap$label[lmap$key == "nyha_class"],
    "NYHA functional class"
  )
})

test_that("labels are preserved through r_data_types()", {
  dta <- generate_survival_data(n = 50)

  lmap_before <- label_map(dta)

  converted <- r_data_types(
    dta,
    factor_size = 5,
    skip_vars = c("ccfid", "iv_dead", "iv_reop")
  )
  lmap_after <- label_map(converted)

  expect_equal(lmap_before, lmap_after)
})
