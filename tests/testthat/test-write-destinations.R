# No exported function writes into the working directory by default. A writer
# either requires its destination or finds the study that contains the working
# directory by its _study.yml, and outside a study it stops and writes nothing.
# The CRAN Cookbook's code chapter asks for this; see
# dev/specs/2026-10-27-write-destinations-design.md.

no_study_dir <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_dir(dir, .local_envir = env)
  dir
}

expect_left_empty <- function(dir) {
  testthat::expect_identical(list.files(dir, all.files = TRUE, no.. = TRUE), character(0))
}

test_that("update_manifest(file) needs manifest_path outside a study", {
  data_dir <- withr::local_tempdir()
  csv <- file.path(data_dir, "tiny.csv")
  utils::write.csv(data.frame(id = 1:2), csv, row.names = FALSE)
  here <- no_study_dir()

  expect_error(update_manifest(csv), "manifest_path")
  expect_left_empty(here)
  expect_identical(list.files(data_dir), "tiny.csv")

  # Naming the manifest still works anywhere.
  out <- file.path(data_dir, "manifest.yaml")
  update_manifest(csv, manifest_path = out)
  expect_true(file.exists(out))
  expect_left_empty(here)
})

test_that("update_manifest(file) inside a study writes the study's manifest", {
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Manifest default", 42L, renv = FALSE))
  csv <- file.path(root, "00_datasets", "tiny.csv")
  utils::write.csv(data.frame(id = 1:2), csv, row.names = FALSE)
  withr::local_dir(file.path(root, "30_analyses"))

  update_manifest(csv)

  expect_false(file.exists(file.path(root, "30_analyses", "manifest.yaml")))
  entries <- yaml::read_yaml(file.path(root, "manifest.yaml"))$datasets
  expect_true("tiny.csv" %in% vapply(entries, `[[`, "", "file"))
})

test_that("study_setup() needs root outside a study", {
  here <- no_study_dir()
  expect_error(
    study_setup(study = "Nowhere", study_tracker_id = 42L, renv = FALSE),
    "no study contains the working directory"
  )
  expect_left_empty(here)
})

test_that("walk-up writers stop and write nothing outside a study", {
  here <- no_study_dir()
  calls <- list(
    declare_data          = quote(declare_data(built = "x.csv")),
    register_data         = quote(register_data(built = "x.csv")),
    add_abbreviation      = quote(add_abbreviation("Example phrase", "ex")),
    study_update_identity = quote(study_update_identity(list(study = "x", study_tracker_id = 42L))),
    cache_fit             = quote(cache_fit("x", 1 + 1)),
    study_declare         = quote(study_declare("stats")),
    study_checkpoint      = quote(study_checkpoint("milestone", note = "x")),
    study_close           = quote(study_close("published")),
    study_reopen          = quote(study_reopen("x"))
  )
  for (fn in names(calls)) {
    expect_error(eval(calls[[fn]]), "no _study.yml found", info = fn)
    expect_left_empty(here)
  }
})
