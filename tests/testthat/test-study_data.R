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

test_that("built_path resolves under numbered datasets", {
  skip_if_not_installed("haven")
  root <- make_study_fixture(withr::local_tempdir())
  file.rename(file.path(root, "datasets"),
              file.path(root, "00_datasets"))

  expect_equal(
    normalizePath(built_path(study_config(root))),
    normalizePath(file.path(root, "00_datasets", "built_test.sas7bdat"))
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

test_that("read_built errors when lowercasing collides rather than duplicating a column", {
  # SAS variable names are case-insensitive, so this collision cannot be built
  # with haven::write_sas(). A .csv source reaches the same code path.
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "datasets"), recursive = TRUE)

  yaml::write_yaml(
    list(study = "Collision fixture", population = "n=2",
         built = "built_test.csv", citation = "Fixture.",
         cohort = list(n = 2L, n_events = 1L, n_censored = 1L,
                       event = "dead", time = "iv_dead")),
    file.path(dir, "_study.yml")
  )

  d <- data.frame(FOO = 1:2, foo = 3:4, dead = c(1L, 0L),
                  iv_dead = c(1, 2), check.names = FALSE)
  write.csv(d, file.path(dir, "datasets", "built_test.csv"), row.names = FALSE)

  expect_error(read_built(study_config(dir)), "FOO")
  expect_error(read_built(study_config(dir)), "foo")

  # The collision must abort before .cache_read() writes anything for a
  # dataset that can never be read: no parquet, no schema sidecar, and no
  # manifest entry recorded for it.
  skip_if_not_installed("arrow")
  expect_false(file.exists(file.path(dir, "datasets", "built_test.parquet")))
  expect_false(file.exists(file.path(dir, "datasets", "built_test.schema.csv")))
  mp <- file.path(dir, "manifest.yaml")
  if (file.exists(mp)) {
    m <- yaml::read_yaml(mp)
    expect_false(any(vapply(m$datasets %||% list(),
                            function(e) identical(e$file, "built_test.csv"),
                            logical(1))))
  }
})

test_that("read_built still lowercases names when there is no collision", {
  dir <- withr::local_tempdir()
  make_study_fixture(dir)

  d <- read_built(study_config(dir))

  expect_true(all(names(d) == tolower(names(d))))
})

test_that("data helpers select a named dataset", {
  root <- make_registered_study(withr::local_tempdir())
  cfg <- study_config(root)

  expect_identical(
    basename(built_path(cfg, dataset = "complete_cases")),
    "complete.csv"
  )
  expect_identical(
    built_manifest(cfg, dataset = "complete_cases")$file,
    "complete.csv"
  )
  expect_equal(nrow(read_built(cfg, dataset = "complete_cases")), 2L)
})

test_that("data helpers list registered choices for an unknown dataset", {
  root <- make_registered_study(withr::local_tempdir())

  expect_error(
    built_path(study_config(root), dataset = "unknown"),
    "study, complete_cases"
  )
})

test_that("data helpers reject a non-character dataset name", {
  root <- make_registered_study(withr::local_tempdir())

  expect_error(
    built_path(study_config(root), dataset = 1),
    "character"
  )
})
