test_that("study_declare writes a project DESCRIPTION", {
  root <- withr::local_tempdir()
  out <- study_declare(c("hvtiRutilities", "arrow"), root)
  expect_identical(out, c("arrow", "hvtiRutilities"))
  dcf <- read.dcf(file.path(root, "DESCRIPTION"))
  expect_identical(unname(dcf[1L, "Type"]), "Project")
  expect_identical(unname(dcf[1L, "Depends"]), "arrow, hvtiRutilities")
})

test_that("study_declare adds to what is declared and never removes", {
  root <- withr::local_tempdir()
  study_declare("arrow", root)
  out <- study_declare("randomForestSRC", root)
  expect_identical(out, c("arrow", "randomForestSRC"))
})

test_that("study_declare leaves the file alone when nothing changes", {
  root <- withr::local_tempdir()
  study_declare("arrow", root)
  path <- file.path(root, "DESCRIPTION")
  before <- file.mtime(path)
  Sys.sleep(1.1)
  study_declare("arrow", root)
  expect_identical(file.mtime(path), before)
})

test_that("study_declare with no packages writes an empty declaration", {
  root <- withr::local_tempdir()
  expect_identical(study_declare(root = root), character(0))
  expect_true(file.exists(file.path(root, "DESCRIPTION")))
})

test_that("study_declare refuses a package DESCRIPTION", {
  root <- withr::local_tempdir()
  writeLines(c("Package: foo", "Version: 1.0.0"), file.path(root, "DESCRIPTION"))
  expect_error(study_declare("arrow", root), "not a study project DESCRIPTION")
})

test_that("study_declare keeps the other fields and the existing entries as written", {
  root <- withr::local_tempdir()
  writeLines(c("Type: Project", "Title: kept", "Imports: dplyr, tidyr", "Remotes: user/repo",
               "Depends: arrow (>= 14)"), file.path(root, "DESCRIPTION"))
  out <- study_declare(c("arrow", "hvtiRutilities"), root)
  expect_identical(out, c("arrow", "hvtiRutilities"))
  dcf <- read.dcf(file.path(root, "DESCRIPTION"))
  expect_identical(unname(dcf[1L, "Depends"]), "arrow (>= 14), hvtiRutilities")
  expect_identical(unname(dcf[1L, "Imports"]), "dplyr, tidyr")
  expect_identical(unname(dcf[1L, "Remotes"]), "user/repo")
  expect_identical(unname(dcf[1L, "Title"]), "kept")
})
