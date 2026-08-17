library(testthat)
library(hvtiRutilities)

test_that("study_config finds the manifest in the starting directory", {
  root <- make_study_fixture(withr::local_tempdir())
  cfg  <- study_config(root)

  expect_equal(normalizePath(cfg$root), normalizePath(root))
  expect_equal(cfg$built, "built_test.sas7bdat")
  expect_equal(cfg$cohort$n, 20L)
  expect_equal(cfg$cohort$n_events, 8L)
  expect_equal(cfg$cohort$n_censored, 12L)
  expect_equal(cfg$cohort$event, "dead")
  expect_equal(cfg$cohort$time, "iv_dead")
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
})

test_that("study_config errors on a missing required key, naming the key", {
  root <- make_study_fixture(withr::local_tempdir(), omit = "built")
  expect_error(study_config(root), "built")

  root2 <- make_study_fixture(withr::local_tempdir(), omit = "cohort.n_events")
  expect_error(study_config(root2), "cohort:n_events")
})

test_that("study_config errors when built has no file extension", {
  root <- make_study_fixture(withr::local_tempdir(),
                             built = "built080426", write_data = FALSE)
  expect_error(study_config(root), "extension")
})

test_that("study_config returns integer cohort counts, not doubles", {
  root <- make_study_fixture(withr::local_tempdir())
  cfg  <- study_config(root)

  expect_type(cfg$cohort$n, "integer")
  expect_type(cfg$cohort$n_events, "integer")
  expect_type(cfg$cohort$n_censored, "integer")
})

test_that("study_config errors when the cohort counts are inconsistent", {
  root <- withr::local_tempdir()
  make_study_fixture(root, write_data = FALSE)
  cfg <- yaml::read_yaml(file.path(root, "_study.yml"))
  cfg$cohort$n_censored <- 999L
  yaml::write_yaml(cfg, file.path(root, "_study.yml"))

  expect_error(study_config(root), "n_censored")
})
