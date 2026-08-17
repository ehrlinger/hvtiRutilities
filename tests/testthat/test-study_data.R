library(testthat)
library(hvtiRutilities)

test_that("built_path resolves under datasets/ using the manifest name", {
  root <- make_study_fixture(withr::local_tempdir())
  cfg  <- study_config(root)

  expect_equal(
    normalizePath(built_path(cfg)),
    normalizePath(file.path(root, "datasets", "built_test.sas7bdat"))
  )
})

test_that("built_manifest reports file, size, mtime and sha256", {
  skip_if_not_installed("haven")
  root <- make_study_fixture(withr::local_tempdir())
  m    <- built_manifest(study_config(root))

  expect_s3_class(m, "data.frame")
  expect_equal(nrow(m), 1L)
  expect_named(m, c("file", "size_bytes", "mtime", "sha256"))
  expect_equal(m$file, "built_test.sas7bdat")
  expect_gt(m$size_bytes, 0)
  expect_match(m$sha256, "^[0-9a-f]{64}$")
})

test_that("built_manifest sha256 changes when the file changes", {
  skip_if_not_installed("haven")
  root <- withr::local_tempdir()
  make_study_fixture(root, n = 20L, n_events = 8L)
  before <- built_manifest(study_config(root))$sha256

  make_study_fixture(root, n = 20L, n_events = 9L)
  after <- built_manifest(study_config(root))$sha256

  expect_false(identical(before, after))
})

test_that("built_manifest errors when the dataset is absent", {
  root <- make_study_fixture(withr::local_tempdir(), write_data = FALSE)
  expect_error(built_manifest(study_config(root)), "missing")
})

test_that("read_built lower-cases names and returns a plain data.frame", {
  skip_if_not_installed("haven")
  root <- make_study_fixture(withr::local_tempdir())
  d    <- read_built(study_config(root))

  expect_s3_class(d, "data.frame")
  expect_false(inherits(d, "tbl_df"))
  expect_equal(names(d), tolower(names(d)))
  expect_true(all(c("dead", "iv_dead") %in% names(d)))
})

test_that("read_built returns no logical and no labelled columns", {
  skip_if_not_installed("haven")
  root <- make_study_fixture(withr::local_tempdir())
  d    <- read_built(study_config(root))

  expect_false(any(vapply(d, is.logical, logical(1))))
  expect_false(any(vapply(d, function(x) inherits(x, "haven_labelled"),
                          logical(1))))
})

test_that("read_built errors when the dataset is absent", {
  root <- make_study_fixture(withr::local_tempdir(), write_data = FALSE)
  expect_error(read_built(study_config(root)), "missing")
})
