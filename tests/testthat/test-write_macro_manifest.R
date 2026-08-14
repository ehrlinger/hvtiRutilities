library(testthat)
library(hvtiRutilities)

fx_dir <- function() testthat::test_path("fixtures")

test_that("write_macro_manifest round-trips the canonical set", {
  tbl <- sas_triage(fx_dir())
  p <- withr::local_tempfile(fileext = ".yaml")

  write_macro_manifest(tbl, p)
  back <- yaml::read_yaml(p)

  macros <- vapply(back$macros, function(e) e$macro, character(1))
  expect_true("epsilon" %in% macros)
  expect_true("zeta" %in% macros)
})

test_that("manifest is byte-for-byte stable across runs", {
  tbl <- sas_triage(fx_dir())
  p1 <- withr::local_tempfile(fileext = ".yaml")
  p2 <- withr::local_tempfile(fileext = ".yaml")

  write_macro_manifest(tbl, p1)
  write_macro_manifest(tbl, p2)

  expect_identical(
    digest::digest(p1, algo = "sha256", file = TRUE),
    digest::digest(p2, algo = "sha256", file = TRUE)
  )
})

test_that("manifest contains no timestamp", {
  tbl <- sas_triage(fx_dir())
  p <- withr::local_tempfile(fileext = ".yaml")
  write_macro_manifest(tbl, p)

  txt <- paste(readLines(p), collapse = "\n")
  expect_false(grepl(format(Sys.Date(), "%Y-%m-%d"), txt))
})

test_that("ambiguous macros are recorded with their distinct bodies", {
  tbl <- sas_triage(fx_dir())
  p <- withr::local_tempfile(fileext = ".yaml")
  write_macro_manifest(tbl, p)
  back <- yaml::read_yaml(p)

  zeta <- Filter(function(e) e$macro == "zeta", back$macros)[[1]]
  expect_equal(zeta$status, "ambiguous")
  expect_equal(length(zeta$candidates), 2L)
})

test_that("write_collision_report lists every multiply-defined macro", {
  tbl <- sas_triage(fx_dir())
  p <- withr::local_tempfile(fileext = ".md")

  write_collision_report(tbl, p)
  txt <- paste(readLines(p), collapse = "\n")

  expect_match(txt, "zeta")
  expect_match(txt, "delta")
  expect_false(grepl("\\bepsilon\\b", txt))
})
