library(testthat)
library(hvtiRutilities)

test_that("cohort_counts counts rows and events from the manifest columns", {
  cfg <- list(cohort = list(event = "dead", time = "iv_dead"))
  d   <- data.frame(dead = c(1, 1, 0, 0, 0), iv_dead = 1:5)

  expect_equal(cohort_counts(d, cfg),
               list(n = 5L, n_events = 2L, n_censored = 3L))
})

test_that("cohort_counts excludes rows missing either the event or the time", {
  cfg <- list(cohort = list(event = "dead", time = "iv_dead"))
  d   <- data.frame(dead    = c(1, 1, 0, NA, 0),
                    iv_dead = c(1, 2, NA, 4, 5))

  expect_equal(cohort_counts(d, cfg),
               list(n = 3L, n_events = 2L, n_censored = 1L))
})

test_that("cohort_counts treats logical and numeric event columns alike", {
  cfg <- list(cohort = list(event = "dead", time = "iv_dead"))
  num <- data.frame(dead = c(1, 0, 1), iv_dead = 1:3)
  log <- data.frame(dead = c(TRUE, FALSE, TRUE), iv_dead = 1:3)

  expect_equal(cohort_counts(num, cfg), cohort_counts(log, cfg))
})

test_that("cohort_counts errors when a named column is absent", {
  cfg <- list(cohort = list(event = "dead", time = "iv_dead"))
  d   <- data.frame(dead = c(1, 0))

  expect_error(cohort_counts(d, cfg), "iv_dead")
})

test_that("assert_cohort passes when the data matches the manifest", {
  cfg <- list(cohort = list(n = 5L, n_events = 2L, n_censored = 3L,
                            event = "dead", time = "iv_dead"))
  d   <- data.frame(dead = c(1, 1, 0, 0, 0), iv_dead = 1:5)

  expect_true(assert_cohort(d, cfg))
})

test_that("assert_cohort errors and reports both expected and observed", {
  cfg <- list(cohort = list(n = 5L, n_events = 2L, n_censored = 3L,
                            event = "dead", time = "iv_dead"))
  d   <- data.frame(dead = c(1, 1, 1, 0, 0), iv_dead = 1:5)

  expect_error(assert_cohort(d, cfg), "expected")
  expect_error(assert_cohort(d, cfg), "events=2")
  expect_error(assert_cohort(d, cfg), "events=3")
})

test_that("assert_cohort fails on a fixture whose data no longer matches", {
  skip_if_not_installed("haven")
  root <- withr::local_tempdir()
  make_study_fixture(root, n = 20L, n_events = 8L)
  cfg  <- study_config(root)

  # Rewrite the data with a different event count, leaving the manifest alone.
  make_study_fixture(root, n = 20L, n_events = 9L)
  d <- read_built(cfg)

  expect_error(assert_cohort(d, cfg), "events=8")
})
