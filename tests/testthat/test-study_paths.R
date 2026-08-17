library(testthat)
library(hvtiRutilities)

test_that("study_root returns the directory holding _study.yml", {
  root <- make_study_fixture(withr::local_tempdir())
  expect_equal(normalizePath(study_root(root)), normalizePath(root))
})

test_that("study_root walks up from a nested subdirectory", {
  root <- make_study_fixture(withr::local_tempdir())
  deep <- file.path(root, "distributions")
  dir.create(deep, recursive = TRUE)

  expect_equal(normalizePath(study_root(deep)), normalizePath(root))
})

test_that("study_root errors outside a study tree", {
  expect_error(study_root(withr::local_tempdir()), "_study.yml")
})

test_that("sas_path joins components under the study root", {
  root <- make_study_fixture(withr::local_tempdir())

  expect_equal(
    normalizePath(sas_path("datasets", start = root)),
    normalizePath(file.path(root, "datasets"))
  )
  expect_equal(
    sas_path("distributions", "hz.dead_JR.sas", start = root),
    file.path(study_root(root), "distributions", "hz.dead_JR.sas")
  )
})

test_that("sas_path with no components returns the root", {
  root <- make_study_fixture(withr::local_tempdir())
  expect_equal(sas_path(start = root), study_root(root))
})
