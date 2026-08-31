library(testthat)
library(hvtiRutilities)

fx_dir <- function() testthat::test_path("fixtures")

## A second corpus that differs from the fixtures by exactly one file, used to
## show the fingerprint discriminates. Built in a temp dir so the fixture
## directory itself is never written to.
half_corpus <- function(env = parent.frame()) {
  d <- withr::local_tempdir(.local_envir = env)
  src <- list.files(fx_dir(), full.names = TRUE)
  file.copy(src[-1L], d)
  d
}

test_that("the report records an input-derived provenance block", {
  p <- withr::local_tempfile(fileext = ".md")
  write_collision_report(sas_triage(fx_dir()), p)
  txt <- paste(readLines(p), collapse = "\n")

  expect_match(txt, "## Provenance")
  expect_match(txt, "corpus fingerprint")
  expect_match(txt, "hvtiRutilities")
})

test_that("the fingerprint distinguishes two different corpora", {
  p1 <- withr::local_tempfile(fileext = ".md")
  p2 <- withr::local_tempfile(fileext = ".md")

  write_collision_report(sas_triage(fx_dir()), p1)
  write_collision_report(sas_triage(half_corpus()), p2)

  fp <- function(p) {
    grep("corpus fingerprint", readLines(p), value = TRUE)
  }
  expect_length(fp(p1), 1L)
  expect_false(identical(fp(p1), fp(p2)))
})

test_that("the provenance block is byte-for-byte stable across runs", {
  tbl <- sas_triage(fx_dir())
  p1 <- withr::local_tempfile(fileext = ".md")
  p2 <- withr::local_tempfile(fileext = ".md")

  write_collision_report(tbl, p1)
  write_collision_report(tbl, p2)

  expect_identical(
    digest::digest(p1, algo = "sha256", file = TRUE),
    digest::digest(p2, algo = "sha256", file = TRUE)
  )
})

test_that("the provenance block carries no clock reading", {
  p <- withr::local_tempfile(fileext = ".md")
  write_collision_report(sas_triage(fx_dir()), p)
  txt <- paste(readLines(p), collapse = "\n")

  expect_false(grepl(format(Sys.Date(), "%Y-%m-%d"), txt))
  expect_false(grepl(format(Sys.Date(), "%Y"), txt))
})

test_that("the fingerprint is independent of the corpus path", {
  ## The same files triaged from a different directory must fingerprint the
  ## same: the identity is the content scanned, not where it was scanned from.
  ## Otherwise a share remount silently invalidates every committed report.
  d <- withr::local_tempdir()
  file.copy(list.files(fx_dir(), full.names = TRUE), d)

  p1 <- withr::local_tempfile(fileext = ".md")
  p2 <- withr::local_tempfile(fileext = ".md")
  write_collision_report(sas_triage(fx_dir()), p1)
  write_collision_report(sas_triage(d), p2)

  fp <- function(p) grep("corpus fingerprint", readLines(p), value = TRUE)
  expect_identical(fp(p1), fp(p2))
})
