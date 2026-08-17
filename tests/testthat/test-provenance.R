library(testthat)
library(hvtiRutilities)

# A rendered output to sit beside. record_provenance() does not require the
# output to exist -- it names the sidecar from the path -- but the realistic
# case has it there.
make_output <- function(root, name = "01.hz.dead_JR.html") {
  dir.create(file.path(root, "_output"), recursive = TRUE,
             showWarnings = FALSE)
  p <- file.path(root, "_output", name)
  writeLines("<html></html>", p)
  p
}

test_that("provenance_path swaps the extension for .provenance.json", {
  expect_equal(basename(provenance_path("a/b/01.hz.dead_JR.html")),
               "01.hz.dead_JR.provenance.json")
  expect_equal(basename(provenance_path("a/b/01.hz.dead_JR.qmd")),
               "01.hz.dead_JR.provenance.json")
})

test_that("record_provenance writes a sidecar next to the output", {
  skip_if_not_installed("haven")
  root <- make_study_fixture(withr::local_tempdir())
  out  <- make_output(root)

  record_provenance(out, cfg = study_config(root))

  expect_true(file.exists(provenance_path(out)))
})

test_that("the sidecar carries every required key with the right type", {
  skip_if_not_installed("haven")
  root <- make_study_fixture(withr::local_tempdir())
  out  <- make_output(root)

  record_provenance(out, cfg = study_config(root))
  j <- jsonlite::fromJSON(provenance_path(out), simplifyVector = FALSE)

  req <- hvtiRutilities:::.provenance_required()
  for (key in names(req)) {
    expect_true(key %in% names(j), info = paste("missing key:", key))
  }

  expect_equal(j$job, "01.hz.dead_JR")
  expect_match(j$rendered, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$")
  expect_equal(j$study$file, "_study.yml")
  expect_match(j$study$sha256, "^[0-9a-f]{64}$")
  expect_equal(j$r$version, paste(R.version$major, R.version$minor, sep = "."))
  expect_true(length(j$packages) > 0)
  expect_equal(j$cohort$n, 20L)
  expect_equal(j$cohort$n_events, 8L)
  expect_equal(j$data[[1]]$file, "built_test.sas7bdat")
  expect_match(j$data[[1]]$sha256, "^[0-9a-f]{64}$")
})

test_that("renv_lock is present as null when the study has no lock", {
  skip_if_not_installed("haven")
  root <- make_study_fixture(withr::local_tempdir())
  out  <- make_output(root)

  record_provenance(out, cfg = study_config(root))
  txt <- paste(readLines(provenance_path(out)), collapse = "\n")

  expect_match(txt, "renv_lock")
  expect_null(jsonlite::fromJSON(provenance_path(out),
                                 simplifyVector = FALSE)$renv_lock)
})

test_that("renv_lock records path and sha256 when a lock exists", {
  skip_if_not_installed("haven")
  root <- make_study_fixture(withr::local_tempdir())
  writeLines('{"R": {"Version": "4.5.1"}}', file.path(root, "renv.lock"))
  out <- make_output(root)

  record_provenance(out, cfg = study_config(root))
  j <- jsonlite::fromJSON(provenance_path(out), simplifyVector = FALSE)

  expect_equal(j$renv_lock$path, "renv.lock")
  expect_match(j$renv_lock$sha256, "^[0-9a-f]{64}$")
})

test_that("two runs differ only in the rendered timestamp", {
  skip_if_not_installed("haven")
  root <- make_study_fixture(withr::local_tempdir())
  out  <- make_output(root)

  record_provenance(out, cfg = study_config(root))
  first <- readLines(provenance_path(out))

  record_provenance(out, cfg = study_config(root))
  second <- readLines(provenance_path(out))

  drop_rendered <- function(x) x[!grepl('"rendered"', x)]
  expect_equal(drop_rendered(first), drop_rendered(second))
})

test_that("extra fields are merged in and do not displace required keys", {
  skip_if_not_installed("haven")
  root <- make_study_fixture(withr::local_tempdir())
  out  <- make_output(root)

  record_provenance(out, extra = list(template = list(name = "hz",
                                                      version = "1.0.0")),
                    cfg = study_config(root))
  j <- jsonlite::fromJSON(provenance_path(out), simplifyVector = FALSE)

  expect_equal(j$template$name, "hz")
  expect_equal(j$job, "01.hz.dead_JR")
})

test_that("an unwritable sidecar location is an error, not a warning", {
  skip_if_not_installed("haven")
  skip_on_os("windows")
  root <- make_study_fixture(withr::local_tempdir())
  out  <- file.path(root, "_output", "nope", "01.hz.dead_JR.html")

  expect_error(record_provenance(out, cfg = study_config(root)),
               "provenance")
})

test_that("record_provenance returns the record invisibly", {
  skip_if_not_installed("haven")
  root <- make_study_fixture(withr::local_tempdir())
  out  <- make_output(root)

  expect_invisible(record_provenance(out, cfg = study_config(root)))
  rec <- record_provenance(out, cfg = study_config(root))
  expect_type(rec, "list")
  expect_equal(rec$job, "01.hz.dead_JR")
})
