library(testthat)
library(hvtiRutilities)

test_that("study_checklist ticks OK items and leaves others open", {
  root <- withr::local_tempdir()
  writeLines('{"R": {"Version": "4.5.1"}}', file.path(root, "renv.lock"))

  md <- study_checklist(study_status(root))

  expect_type(md, "character")
  expect_true(any(grepl("^- \\[x\\] \\*\\*renv.lock\\*\\*", md)))
  expect_true(any(grepl("^- \\[ \\] \\*\\*_study.yml\\*\\*", md)))
})

test_that("study_checklist reports counts", {
  root <- withr::local_tempdir()
  writeLines("proc means data=x;", file.path(root, "bh.dead_s1.sas"))

  md <- study_checklist(study_status(root))
  expect_true(any(grepl("`\\.sas` jobs: 1", md)))
})

test_that("study_checklist labels the source count as .qmd/.Rmd", {
  root <- withr::local_tempdir()
  writeLines("---\ntitle: x\n---", file.path(root, "01.legacy_JR.Rmd"))

  md <- study_checklist(study_status(root))
  # study_status() counts .qmd and .Rmd together, so the checklist must not
  # label the total as .qmd alone.
  expect_true(any(grepl("`.qmd`/`.Rmd` sources: 1", md, fixed = TRUE)))
})

test_that("study_checklist names the study root", {
  root <- withr::local_tempdir()
  md   <- study_checklist(study_status(root))
  expect_true(any(grepl(basename(root), md, fixed = TRUE)))
})

test_that("study_checklist writes to path and returns it invisibly", {
  root <- withr::local_tempdir()
  out  <- file.path(root, "CLOSEOUT.md")

  expect_invisible(study_checklist(study_status(root), path = out))
  expect_true(file.exists(out))
  expect_true(any(grepl("Study readiness", readLines(out))))
})

test_that("study_checklist rejects anything that is not a study_status", {
  expect_error(study_checklist(list(root = "x")), "study_status")
})

test_that("study_checklist errors on an unwritable path", {
  skip_on_os("windows")
  root <- withr::local_tempdir()
  bad  <- file.path(root, "no-such-dir", "CLOSEOUT.md")

  expect_error(study_checklist(study_status(root), path = bad),
               "could not write")
})
