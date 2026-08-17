library(testthat)
library(hvtiRutilities)

# A study root holding a dataset and nothing else. make_study_fixture() writes
# the _study.yml that study_init() is supposed to create, so it is removed.
bare_study <- function(n = 20L, n_events = 8L) {
  root <- withr::local_tempdir(.local_envir = parent.frame())
  make_study_fixture(root, n = n, n_events = n_events)
  file.remove(file.path(root, "_study.yml"))
  root
}

test_that("study_init writes a manifest that study_config accepts", {
  skip_if_not_installed("haven")
  root <- bare_study(n = 20L, n_events = 8L)

  study_init(root, study = "Test", built = "built_test.sas7bdat",
             event = "dead", time = "iv_dead")

  cfg <- study_config(root)               # must not error
  expect_equal(cfg$study, "Test")
  expect_equal(cfg$built, "built_test.sas7bdat")
  expect_equal(cfg$cohort$n, 20L)
  expect_equal(cfg$cohort$n_events, 8L)
  expect_equal(cfg$cohort$n_censored, 12L)
  expect_true(assert_cohort(read_built(cfg), cfg))
})

test_that("study_init derives integer cohort counts, never doubles", {
  skip_if_not_installed("haven")
  root <- bare_study(n = 20L, n_events = 8L)
  study_init(root, study = "Test", built = "built_test.sas7bdat",
             event = "dead", time = "iv_dead")

  cfg <- study_config(root)
  expect_type(cfg$cohort$n, "integer")
  expect_type(cfg$cohort$n_events, "integer")
  expect_type(cfg$cohort$n_censored, "integer")
})

test_that("study_init writes citation as an explicit null", {
  skip_if_not_installed("haven")
  root <- bare_study()
  study_init(root, study = "Test", built = "built_test.sas7bdat",
             event = "dead", time = "iv_dead")

  # The key must be visible in the file, so a future close-out has somewhere
  # obvious to write, and must round-trip as NULL.
  txt <- paste(readLines(file.path(root, "_study.yml")), collapse = "\n")
  expect_match(txt, "citation")
  expect_null(study_config(root)$citation)
})

test_that("study_init seeds manifest.yaml and verify_manifest passes on it", {
  skip_if_not_installed("haven")
  root <- bare_study()
  study_init(root, study = "Test", built = "built_test.sas7bdat",
             event = "dead", time = "iv_dead")

  man <- file.path(root, "manifest.yaml")
  expect_true(file.exists(man))

  rep <- suppressWarnings(
    verify_manifest(man, data_dir = file.path(root, "datasets"),
                    stop_on_error = FALSE)
  )
  expect_equal(nrow(rep), 1L)
  expect_equal(rep$file, "built_test.sas7bdat")
})

test_that("study_init records n_rows without the heavy-rowcount option", {
  skip_if_not_installed("haven")
  # A bare call: if study_init() let update_manifest() auto-count, this would
  # error with "Automatic row counting for SAS files ... is disabled".
  # expect_no_error() is avoided here because it postdates the package's
  # declared testthat floor (>= 3.0.0).
  withr::local_options(manifest.allow_heavy_rowcount = FALSE)
  root <- bare_study(n = 20L)

  study_init(root, study = "Test", built = "built_test.sas7bdat",
             event = "dead", time = "iv_dead")

  man <- yaml::read_yaml(file.path(root, "manifest.yaml"))
  expect_equal(man$datasets[[1]]$n_rows, 20L)
})

test_that("study_init defaults extract_date to the dataset's mtime", {
  skip_if_not_installed("haven")
  root  <- bare_study()
  built <- file.path(root, "datasets", "built_test.sas7bdat")
  Sys.setFileTime(built, as.POSIXct("2006-05-03 14:03:00", tz = "UTC"))

  study_init(root, study = "Test", built = "built_test.sas7bdat",
             event = "dead", time = "iv_dead")

  man <- yaml::read_yaml(file.path(root, "manifest.yaml"))
  expect_equal(man$datasets[[1]]$extract_date, "2006-05-03")
})

test_that("study_init honours an explicit extract_date and source", {
  skip_if_not_installed("haven")
  root <- bare_study()
  study_init(root, study = "Test", built = "built_test.sas7bdat",
             event = "dead", time = "iv_dead",
             extract_date = "2026-08-17", source = "SAS build, vars.sas")

  man <- yaml::read_yaml(file.path(root, "manifest.yaml"))
  expect_equal(man$datasets[[1]]$extract_date, "2026-08-17")
  expect_equal(man$datasets[[1]]$source, "SAS build, vars.sas")
})

test_that("study_init refuses to overwrite an existing _study.yml", {
  skip_if_not_installed("haven")
  root   <- withr::local_tempdir()
  make_study_fixture(root)
  before <- readLines(file.path(root, "_study.yml"))

  expect_error(
    study_init(root, study = "Other", built = "built_test.sas7bdat",
               event = "dead", time = "iv_dead"),
    "already exists"
  )
  expect_equal(readLines(file.path(root, "_study.yml")), before)
})

test_that("study_init errors when built has no extension, writing nothing", {
  skip_if_not_installed("haven")
  root <- bare_study()

  expect_error(
    study_init(root, study = "Test", built = "built_test",
               event = "dead", time = "iv_dead"),
    "extension"
  )
  expect_false(file.exists(file.path(root, "_study.yml")))
  expect_false(file.exists(file.path(root, "manifest.yaml")))
})

test_that("study_init errors when the dataset is absent, writing nothing", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "datasets"))

  expect_error(
    study_init(root, study = "Test", built = "nope.sas7bdat",
               event = "dead", time = "iv_dead"),
    "missing"
  )
  expect_false(file.exists(file.path(root, "_study.yml")))
})

test_that("study_init errors when event or time names no column", {
  skip_if_not_installed("haven")
  root <- bare_study()

  expect_error(
    study_init(root, study = "Test", built = "built_test.sas7bdat",
               event = "dead", time = "no_such_column"),
    "no_such_column"
  )
  expect_false(file.exists(file.path(root, "_study.yml")))
})

test_that("study_init returns a study_status visibly", {
  skip_if_not_installed("haven")
  root <- bare_study()

  st <- study_init(root, study = "Test", built = "built_test.sas7bdat",
                   event = "dead", time = "iv_dead")

  expect_s3_class(st, "study_status")
  expect_equal(st$checks$status[st$checks$item == "_study.yml"], "OK")
  expect_equal(st$checks$status[st$checks$item == "renv.lock"], "MISSING")
})
