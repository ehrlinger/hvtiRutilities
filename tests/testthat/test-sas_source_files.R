library(testthat)
library(hvtiRutilities)

disc_dir <- function() testthat::test_path("fixtures-discovery")

# ---------------------------------------------------------------------------
# File discovery
#
# The macro library uses dots as word separators in filenames -- `deciles.hazard`
# and `lm.cprobs` are names, not stems with extensions -- so a `\\.sas$` glob
# drops macro-bearing files. Discovery is a denylist of non-source suffixes.
# ---------------------------------------------------------------------------

test_that(".sas_source_files finds extensionless macro files", {
  found <- basename(hvtiRutilities:::.sas_source_files(disc_dir()))
  expect_true("plainmacro" %in% found)
})

test_that(".sas_source_files finds files whose dots are word separators", {
  found <- basename(hvtiRutilities:::.sas_source_files(disc_dir()))
  expect_true("dotted.name" %in% found)
})

test_that(".sas_source_files still finds ordinary .sas files", {
  found <- basename(hvtiRutilities:::.sas_source_files(disc_dir()))
  expect_true("regular.sas" %in% found)
})

test_that(".sas_source_files excludes logs, listings and text copies", {
  found <- basename(hvtiRutilities:::.sas_source_files(disc_dir()))
  expect_false("run.log" %in% found)
  expect_false("out.lst" %in% found)
  expect_false("plainmacro.txt" %in% found)
})

test_that(".sas_source_files excludes numbered RCS backups", {
  found <- basename(hvtiRutilities:::.sas_source_files(disc_dir()))
  expect_false("plainmacro.~1.1.~" %in% found)
})

test_that(".sas_source_files excludes directories", {
  d <- withr::local_tempdir()
  dir.create(file.path(d, "archive"))
  file.create(file.path(d, "keepme"))
  found <- basename(hvtiRutilities:::.sas_source_files(d))
  expect_false("archive" %in% found)
  expect_true("keepme" %in% found)
})

test_that("sas_triage() triages an extensionless macro file", {
  res <- sas_triage(disc_dir())
  expect_true("plainmacro" %in% res$file)
  expect_true("dotted" %in% res$macro)
})
