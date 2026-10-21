manual_study <- function(...) {
  root <- file.path(withr::local_tempdir(.local_envir = parent.frame()), "study")
  study_setup(root, "typed  title", 42L, identity_source = "manual",
              renv = FALSE, ...)
  root
}

test_that("study_update_identity marks the identity verified and fills fields", {
  root <- manual_study(owner = "Typed Owner")

  changed <- study_update_identity(
    list(study_tracker_id = 42L, study = "Typed Title", umbrella = "Aorta",
         owner = NULL),
    start = root
  )

  cfg <- study_config(root, require_data = FALSE)
  expect_identical(cfg$study, "Typed Title")
  expect_identical(cfg$umbrella, "Aorta")
  expect_identical(cfg$owner, "Typed Owner")
  expect_identical(cfg$identity_source, "tracker")
  expect_true(cfg$identity_verified)
  expect_setequal(changed, c("study", "umbrella", "identity_source",
                             "identity_verified"))
})

test_that("study_update_identity keeps the data contract byte for byte", {
  root <- manual_study()
  yml <- file.path(root, "_study.yml")
  raw <- yaml::read_yaml(yml)
  raw$built <- "built.sas7bdat"
  raw$population <- "Adults: first operation"
  raw$additional_datasets <- list(echo = list(built = "echo.csv"))
  yaml::write_yaml(raw, yml)
  contract <- function() {
    lines <- readLines(yml)
    lines[grepl("^(built|population|citation|additional_datasets|  )", lines)]
  }
  before <- contract()

  study_update_identity(list(study_tracker_id = 42L, study = "Typed Title"),
                        start = root)

  expect_identical(contract(), before)
})

test_that("study_update_identity refuses another study's record", {
  root <- manual_study()
  before <- readLines(file.path(root, "_study.yml"))

  expect_error(
    study_update_identity(list(study_tracker_id = 43L, study = "Other"),
                          start = root),
    "does not match"
  )
  expect_identical(readLines(file.path(root, "_study.yml")), before)
})

test_that("study_update_identity rejects malformed records", {
  root <- manual_study()
  expect_error(study_update_identity("x", start = root), "named list")
  expect_error(
    study_update_identity(list(study_tracker_id = 42L, study = "T", path = "/x"),
                          start = root),
    "unknown identity field: path"
  )
  expect_error(
    study_update_identity(list(study_tracker_id = 42L, study = ""),
                          start = root),
    "'study' is required"
  )
  expect_error(
    study_update_identity(list(study_tracker_id = 42L, study = "T", owner = 1),
                          start = root),
    "'owner' must be one string"
  )
})

test_that("study_update_identity writes nothing when already verified", {
  root <- manual_study()
  study_update_identity(list(study_tracker_id = 42L, study = "Typed Title"),
                        start = root)
  stamp <- file.mtime(file.path(root, "_study.yml"))

  changed <- study_update_identity(
    list(study_tracker_id = 42L, study = "Typed Title"), start = root
  )

  expect_identical(changed, character(0))
  expect_identical(file.mtime(file.path(root, "_study.yml")), stamp)
})
