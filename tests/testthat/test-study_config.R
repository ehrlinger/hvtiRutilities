library(testthat)
library(hvtiRutilities)

test_that("study_config requires a registered file but not a cohort", {
  root <- make_study_fixture(withr::local_tempdir())
  cfg <- study_config(root)

  expect_identical(cfg$built, "built_test.sas7bdat")
  expect_null(cfg$cohort)
})

test_that("study_config walks up from a nested subdirectory", {
  root <- make_study_fixture(withr::local_tempdir())
  deep <- file.path(root, "analyses", "R_hazard", "scripts")
  dir.create(deep, recursive = TRUE)

  expect_equal(normalizePath(study_config(deep)$root), normalizePath(root))
})

test_that("study_config errors when no manifest exists, naming what it walked", {
  bare <- withr::local_tempdir()

  expect_error(study_config(bare), "_study.yml")
  expect_error(study_config(bare), "Walked")
  expect_error(study_config(bare), "study-setup --recover")
})

test_that("study_config errors on a missing required built key", {
  root <- make_study_fixture(withr::local_tempdir(), omit = "built")
  expect_error(study_config(root), "built")
})

test_that("study_config errors when built has no file extension", {
  root <- make_study_fixture(withr::local_tempdir(),
                             built = "built080426", write_data = FALSE)
  expect_error(study_config(root), "extension")
})

test_that("legacy cohort fields are additive but not dataset contracts", {
  root <- make_study_fixture(withr::local_tempdir())
  raw <- yaml::read_yaml(file.path(root, "_study.yml"))
  raw$cohort <- list(
    n = 20L,
    n_events = 8L,
    n_censored = 12L,
    event = "dead",
    time = "iv_dead"
  )
  yaml::write_yaml(raw, file.path(root, "_study.yml"))

  cfg <- study_config(root)

  expect_identical(cfg$cohort, raw$cohort)
  expect_false("cohort" %in% names(hvtiRutilities:::.study_dataset(cfg)))
})

test_that("legacy named cohort fields are not dataset contracts", {
  root <- make_study_fixture(withr::local_tempdir())
  raw <- yaml::read_yaml(file.path(root, "_study.yml"))
  raw$additional_datasets <- list(
    imaging = list(
      built = "imaging.csv",
      cohort = list(
        n = 2L,
        n_events = 1L,
        n_censored = 1L,
        event = "finding",
        time = "scan_day"
      )
    )
  )
  yaml::write_yaml(raw, file.path(root, "_study.yml"))

  contract <- hvtiRutilities:::.study_dataset(study_config(root), "imaging")

  expect_named(contract, c("dataset", "built", "population", "release"))
  expect_false("cohort" %in% names(contract))
})

test_that("study_config can read identity before data registration", {
  root <- withr::local_tempdir()
  yaml::write_yaml(
    list(
      study = "Identity-only study",
      study_tracker_id = 42L,
      population = NULL,
      built = NULL,
      citation = NULL
    ),
    file.path(root, "_study.yml")
  )

  cfg <- study_config(root, require_data = FALSE)

  expect_identical(cfg$study, "Identity-only study")
  expect_identical(cfg$study_tracker_id, 42L)
  expect_null(cfg$built)
  expect_null(cfg$cohort)
  expect_error(study_config(root), "register_data")
})

test_that("study_config preserves additive identity fields", {
  root <- withr::local_tempdir()
  yaml::write_yaml(
    list(
      study = "Identity-only study",
      study_tracker_id = 42L,
      future_identity = "preserve",
      built = NULL
    ),
    file.path(root, "_study.yml")
  )

  cfg <- study_config(root, require_data = FALSE)

  expect_identical(cfg$future_identity, "preserve")
})

test_that("study_config preserves a valid default release block", {
  root <- make_study_fixture(withr::local_tempdir())
  raw <- yaml::read_yaml(file.path(root, "_study.yml"))
  raw$release <- list(
    dataset_id = "surgery_cohort",
    release_id = "surgery_cohort-20260920-r1"
  )
  yaml::write_yaml(raw, file.path(root, "_study.yml"))

  cfg <- study_config(root)

  expect_identical(cfg$release, raw$release)
  expect_identical(.study_dataset(cfg)$release, raw$release)
})

test_that("study_config rejects incomplete named release metadata", {
  root <- make_registered_study(withr::local_tempdir())
  raw <- yaml::read_yaml(file.path(root, "_study.yml"))
  raw$additional_datasets$complete_cases$release <- list(
    dataset_id = "complete_cases"
  )
  yaml::write_yaml(raw, file.path(root, "_study.yml"))

  expect_error(study_config(root), "release_id")
})

test_that("study_config validates release metadata", {
  cases <- list(
    list(value = "not a mapping", pattern = "mapping"),
    list(
      value = list(dataset_id = "", release_id = "cohort-1"),
      pattern = "dataset_id"
    ),
    list(
      value = list(dataset_id = "Surgery Cohort", release_id = "cohort-1"),
      pattern = "dataset_id"
    ),
    list(
      value = list(dataset_id = "surgery_cohort", release_id = "../cohort"),
      pattern = "release_id"
    )
  )

  for (case in cases) {
    root <- make_study_fixture(withr::local_tempdir())
    raw <- yaml::read_yaml(file.path(root, "_study.yml"))
    raw$release <- case$value
    yaml::write_yaml(raw, file.path(root, "_study.yml"))

    expect_error(study_config(root), case$pattern)
  }
})

test_that("legacy study contracts remain release-unaware", {
  root <- make_study_fixture(withr::local_tempdir())
  cfg <- study_config(root)

  expect_null(cfg$release)
  expect_null(.study_dataset(cfg)$release)
})
