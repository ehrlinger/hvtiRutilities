library(testthat)
library(hvtiRutilities)

test_that("cohort_counts uses explicit job columns", {
  d <- data.frame(dead = c(1, 1, 0, 0, 0), iv_dead = 1:5)

  expect_identical(
    cohort_counts(d, event = "dead", time = "iv_dead"),
    list(n = 5L, n_events = 2L, n_censored = 3L)
  )
})

test_that("cohort_counts rejects competing-event codes", {
  d <- data.frame(status = c(0L, 1L, 2L), followup = 1:3)

  expect_error(
    cohort_counts(d, event = "status", time = "followup"),
    "binary"
  )
})

test_that("cohort_counts permits an empty complete cohort", {
  d <- data.frame(
    dead = c(NA_integer_, NA_integer_),
    iv_dead = c(NA_real_, NA_real_)
  )

  expect_identical(
    cohort_counts(d, event = "dead", time = "iv_dead"),
    list(n = 0L, n_events = 0L, n_censored = 0L)
  )
})

test_that("cohort_counts excludes rows missing either the event or the time", {
  d <- data.frame(
    dead = c(1, 1, 0, NA, 0),
    iv_dead = c(1, 2, NA, 4, 5)
  )

  expect_identical(
    cohort_counts(d, event = "dead", time = "iv_dead"),
    list(n = 3L, n_events = 2L, n_censored = 1L)
  )
})

test_that("cohort_counts treats logical and numeric event columns alike", {
  num <- data.frame(dead = c(1, 0, 1), iv_dead = 1:3)
  log <- data.frame(dead = c(TRUE, FALSE, TRUE), iv_dead = 1:3)

  expect_identical(
    cohort_counts(num, event = "dead", time = "iv_dead"),
    cohort_counts(log, event = "dead", time = "iv_dead")
  )
})

test_that("cohort_counts errors when a named column is absent", {
  d <- data.frame(dead = c(1, 0))

  expect_error(
    cohort_counts(d, event = "dead", time = "iv_dead"),
    "iv_dead"
  )
})

test_that("cohort_counts rejects non-character column names", {
  d <- data.frame(dead = c(1, 0), iv_dead = 1:2)

  expect_error(cohort_counts(d, event = 1, time = "iv_dead"), "character")
  expect_error(cohort_counts(d, event = NA_character_, time = "iv_dead"), "event")
  expect_error(cohort_counts(d, event = "dead", time = 1), "character")
  expect_error(cohort_counts(d, event = "dead", time = NA_character_), "time")
})

test_that("assert_cohort uses only the supplied expectation", {
  d <- data.frame(dead = c(1, 0, 0), iv_dead = 1:3)
  expected <- list(n = 3L, n_events = 1L, n_censored = 2L)

  expect_true(assert_cohort(d, expected, "dead", "iv_dead"))
  expected$n_events <- 2L
  expect_error(
    assert_cohort(d, expected, "dead", "iv_dead"),
    "expected"
  )
})

test_that("assert_cohort reports expected and observed counts", {
  d <- data.frame(dead = c(1, 1, 1, 0, 0), iv_dead = 1:5)
  expected <- list(n = 5L, n_events = 2L, n_censored = 3L)

  expect_error(
    assert_cohort(d, expected, "dead", "iv_dead"),
    "expected"
  )
  expect_error(
    assert_cohort(d, expected, "dead", "iv_dead"),
    "events=2"
  )
  expect_error(
    assert_cohort(d, expected, "dead", "iv_dead"),
    "events=3"
  )
})

test_that("assert_cohort checks count consistency without integer overflow", {
  d <- data.frame(dead = 0, iv_dead = 1)
  expected <- list(
    n = .Machine$integer.max,
    n_events = .Machine$integer.max,
    n_censored = 1
  )

  expect_no_warning(
    expect_error(
      assert_cohort(d, expected, "dead", "iv_dead"),
      "inconsistent"
    )
  )
})
