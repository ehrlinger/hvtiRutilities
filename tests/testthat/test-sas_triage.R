library(testthat)
library(hvtiRutilities)

fx_dir <- function() testthat::test_path("fixtures")

# ---------------------------------------------------------------------------
# Visibility classification
# ---------------------------------------------------------------------------

test_that(".classify_visibility marks an exact basename match public", {
  expect_equal(
    hvtiRutilities:::.classify_visibility("std_dif", "std_dif.sas"),
    "public"
  )
})

test_that(".classify_visibility marks a variant-suffixed file public?", {
  expect_equal(
    hvtiRutilities:::.classify_visibility("std_dif", "std_dif_wt.sas"),
    "public?"
  )
  expect_equal(
    hvtiRutilities:::.classify_visibility("std_dif", "std_difma.sas"),
    "public?"
  )
})

test_that(".classify_visibility marks an inline helper private", {
  expect_equal(
    hvtiRutilities:::.classify_visibility("skip", "readin.sas"),
    "private"
  )
  expect_equal(
    hvtiRutilities:::.classify_visibility("numobs", "lgtphcurv9.sas"),
    "private"
  )
})

test_that(".strip_variant_suffix removes known variant markers", {
  expect_equal(hvtiRutilities:::.strip_variant_suffix("std_dif_wt"), "std_dif")
  expect_equal(hvtiRutilities:::.strip_variant_suffix("std_difma"), "std_dif")
  expect_equal(hvtiRutilities:::.strip_variant_suffix("cr_compare_cp_old"), "cr_compare_cp")
  expect_equal(hvtiRutilities:::.strip_variant_suffix("epsilon"), "epsilon")
})
