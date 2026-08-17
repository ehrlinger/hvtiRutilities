library(testthat)
library(hvtiRutilities)

test_that("a directory of assignments only is clean", {
  d <- withr::local_tempdir()
  writeLines(c("f <- function(x) x + 1", "K <- 42"), file.path(d, "ok.R"))

  expect_equal(r_dir_impurities(d), character(0))
})

test_that("a top-level call is reported with file and expression", {
  d <- withr::local_tempdir()
  writeLines(c("f <- function(x) x + 1", "print(f(1))"),
             file.path(d, "bad.R"))

  out <- r_dir_impurities(d)
  expect_length(out, 1L)
  expect_match(out, "bad.R")
  expect_match(out, "print")
})

test_that("library() at the top level is reported", {
  d <- withr::local_tempdir()
  writeLines("library(stats)", file.path(d, "lib.R"))

  expect_length(r_dir_impurities(d), 1L)
})

test_that("an empty directory is clean", {
  expect_equal(r_dir_impurities(withr::local_tempdir()), character(0))
})

test_that("a bare constant is clean -- the roxygen package-doc idiom", {
  d <- withr::local_tempdir()
  writeLines(c("#' @name pkg-package", "NULL"), file.path(d, "help.R"))
  writeLines("\"_PACKAGE\"", file.path(d, "pkg.R"))

  expect_equal(r_dir_impurities(d), character(0))
})

test_that("the package's own R/ directory is pure", {
  # test_path() resolves from tests/testthat/, so this is <pkg>/R. Do not use
  # system.file("..", "R", ...): it returns "" and the test skips forever.
  r_dir <- testthat::test_path("..", "..", "R")
  expect_true(dir.exists(r_dir))

  expect_equal(r_dir_impurities(r_dir), character(0))
})
