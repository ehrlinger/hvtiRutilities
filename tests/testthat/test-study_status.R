library(testthat)
library(hvtiRutilities)

# Pulls one row out of the checks frame by item name, so a test asserts on the
# check it means rather than on a row position that a later edit could shift.
check_for <- function(st, item) {
  row <- st$checks[st$checks$item == item, , drop = FALSE]
  expect_equal(nrow(row), 1L, info = paste("no check named", item))
  row
}

test_that("study_status on a bare directory reports MISSING, not an error", {
  bare <- withr::local_tempdir()
  st   <- study_status(bare)

  expect_s3_class(st, "study_status")
  expect_equal(check_for(st, "_study.yml")$status, "MISSING")
  expect_equal(check_for(st, "renv.lock")$status, "MISSING")
  expect_equal(check_for(st, "manifest.yaml")$status, "MISSING")
})

test_that("study_status returns the six checks in a fixed order", {
  st <- study_status(withr::local_tempdir())

  expect_equal(st$checks$item,
               c("_study.yml", "renv.lock", "manifest.yaml",
                 "dataset", "cohort", "provenance"))
  expect_type(st$checks$item, "character")
  expect_type(st$checks$status, "character")
  expect_type(st$checks$detail, "character")
})

test_that("study_status reports OK for a valid manifest and its dataset", {
  skip_if_not_installed("haven")
  root <- make_study_fixture(withr::local_tempdir())
  st   <- study_status(root)

  expect_equal(check_for(st, "_study.yml")$status, "OK")
  expect_equal(check_for(st, "dataset")$status, "OK")
  expect_equal(check_for(st, "cohort")$status, "OK")
})

test_that("study_status reports FAIL when _study.yml is present but invalid", {
  root <- make_study_fixture(withr::local_tempdir(), omit = "built",
                             write_data = FALSE)
  st   <- study_status(root)

  row <- check_for(st, "_study.yml")
  expect_equal(row$status, "FAIL")
  expect_match(row$detail, "built")
})

test_that("study_status reports MISSING, not FAIL, for checks it cannot run", {
  # dataset and cohort both need a valid _study.yml. A check that could not
  # run is not a check that failed.
  bare <- withr::local_tempdir()
  st   <- study_status(bare)

  expect_equal(check_for(st, "dataset")$status, "MISSING")
  expect_equal(check_for(st, "cohort")$status, "MISSING")
  expect_match(check_for(st, "dataset")$detail, "_study.yml")
})

test_that("study_status reports FAIL when the cohort no longer matches", {
  skip_if_not_installed("haven")
  root <- withr::local_tempdir()
  make_study_fixture(root, n = 20L, n_events = 8L)
  # Rewrite the data with a different event count, leaving the manifest alone.
  make_study_fixture(root, n = 20L, n_events = 9L)
  # make_study_fixture rewrote _study.yml too, so restore the original counts.
  cfg <- yaml::read_yaml(file.path(root, "_study.yml"))
  cfg$cohort$n_events   <- 8L
  cfg$cohort$n_censored <- 12L
  yaml::write_yaml(cfg, file.path(root, "_study.yml"))

  row <- check_for(study_status(root), "cohort")
  expect_equal(row$status, "FAIL")
  expect_match(row$detail, "events=8")
})

test_that("study_status verifies manifest.yaml and reports drift as FAIL", {
  skip_if_not_installed("haven")
  root  <- make_study_fixture(withr::local_tempdir())
  built <- file.path(root, "datasets", "built_test.sas7bdat")

  update_manifest(file          = built,
                  manifest_path = file.path(root, "manifest.yaml"),
                  n_rows        = 20L)
  expect_equal(check_for(study_status(root), "manifest.yaml")$status, "OK")

  # Perturb the dataset; the recorded SHA-256 no longer matches.
  make_study_fixture(root, n = 20L, n_events = 9L)
  row <- check_for(study_status(root), "manifest.yaml")
  expect_equal(row$status, "FAIL")
  expect_match(row$detail, "built_test.sas7bdat")
})

test_that("study_status reports renv.lock when present", {
  root <- withr::local_tempdir()
  writeLines('{"R": {"Version": "4.5.1"}}', file.path(root, "renv.lock"))

  expect_equal(check_for(study_status(root), "renv.lock")$status, "OK")
})

test_that("provenance is FAIL when a .qmd source has no sidecar", {
  root <- withr::local_tempdir()
  writeLines("---\ntitle: x\n---", file.path(root, "01.hz.dead_JR.qmd"))

  row <- check_for(study_status(root), "provenance")
  expect_equal(row$status, "FAIL")
  expect_match(row$detail, "01.hz.dead_JR")
})

test_that("provenance is OK when every .qmd source has a matching sidecar", {
  root <- withr::local_tempdir()
  writeLines("---\ntitle: x\n---", file.path(root, "01.hz.dead_JR.qmd"))
  writeLines("{}", file.path(root, "01.hz.dead_JR.provenance.json"))

  expect_equal(check_for(study_status(root), "provenance")$status, "OK")
})

test_that("provenance counts distinct source names and names duplicates", {
  # Two index.qmd in different directories: matching is by name, so they
  # cannot be told apart. The counts must be over distinct names, or the
  # detail reads "1 of 2" for three files and looks like a miscount.
  root <- withr::local_tempdir()
  dir.create(file.path(root, "a"))
  dir.create(file.path(root, "b"))
  writeLines("x", file.path(root, "a", "index.qmd"))
  writeLines("x", file.path(root, "b", "index.qmd"))
  writeLines("x", file.path(root, "solo.qmd"))

  row <- check_for(study_status(root), "provenance")
  expect_equal(row$status, "FAIL")
  # Two distinct names (index, solo), both unrecorded.
  expect_match(row$detail, "2 of 2")
  expect_match(row$detail, "indistinguishable")
  expect_match(row$detail, "index")
  expect_equal(study_status(root)$counts$qmd, 3L)
})

test_that("provenance is MISSING when there are no .qmd sources at all", {
  root <- withr::local_tempdir()
  writeLines("proc means data=x;", file.path(root, "bh.dead_s1.sas"))

  expect_equal(check_for(study_status(root), "provenance")$status, "MISSING")
})

test_that("counts exclude renv/ and count SAS jobs", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "renv", "library", "pkg", "R"), recursive = TRUE)
  writeLines("f <- 1", file.path(root, "renv", "library", "pkg", "R", "a.R"))
  writeLines("g <- 1", file.path(root, "helper.R"))
  writeLines("proc means data=x;", file.path(root, "bh.dead_s1.sas"))

  st <- study_status(root)
  expect_equal(st$counts$r_files, 1L)   # helper.R only, not renv's a.R
  expect_equal(st$counts$sas_jobs, 1L)
})

test_that("study_status errors only when root does not exist", {
  expect_error(study_status(file.path(tempdir(), "no-such-dir-xyz")))
})

test_that("print.study_status returns its argument invisibly", {
  st <- study_status(withr::local_tempdir())

  expect_output(print(st), "_study.yml")
  expect_invisible(print(st))
})
