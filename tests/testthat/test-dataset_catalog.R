test_that("catalog v1 validates and resolves a release", {
  fx <- write_release_fixture(withr::local_tempdir())
  catalog <- .read_dataset_catalog(fx$catalog_path)
  release <- .catalog_release(
    catalog,
    "surgery_cohort",
    "surgery_cohort-20260921-r1"
  )

  expect_identical(release$sequence, 2L)
  expect_identical(release$revision, 1L)
  expect_identical(
    .verify_catalog_file(release, fx$data_dir),
    file.path(fx$data_dir, release$file)
  )
})

test_that("catalog rejects a file reused by different datasets", {
  fx <- write_release_fixture(withr::local_tempdir())
  catalog <- yaml::read_yaml(fx$catalog_path)
  catalog$datasets$imaging <- catalog$datasets$surgery_cohort
  catalog$datasets$imaging$releases[[1L]]$release_id <- "imaging-1"
  catalog$datasets$imaging$releases[[1L]]$sequence <- 1L
  catalog$datasets$imaging$releases <-
    catalog$datasets$imaging$releases[1L]
  yaml::write_yaml(catalog, fx$catalog_path)

  expect_error(
    .read_dataset_catalog(fx$catalog_path),
    "listed more than once"
  )
})

test_that("catalog rejects paths that escape the datasets directory", {
  fx <- write_release_fixture(withr::local_tempdir())
  catalog <- yaml::read_yaml(fx$catalog_path)
  catalog$datasets$surgery_cohort$releases[[1L]]$file <- "../cohort.csv"
  yaml::write_yaml(catalog, fx$catalog_path)

  expect_error(.read_dataset_catalog(fx$catalog_path), "basename")
})

test_that("catalog rejects malformed release fields and collections", {
  cases <- list(
    list(
      name = "format_version",
      pattern = "format_version",
      change = function(x) {
        x$format_version <- 2L
        x
      }
    ),
    list(
      name = "named datasets",
      pattern = "named mapping",
      change = function(x) {
        names(x$datasets) <- NULL
        x
      }
    ),
    list(
      name = "required fields",
      pattern = "sha256",
      change = function(x) {
        x$datasets$surgery_cohort$releases[[1L]]$sha256 <- NULL
        x
      }
    ),
    list(
      name = "sha256",
      pattern = "sha256",
      change = function(x) {
        x$datasets$surgery_cohort$releases[[1L]]$sha256 <- "abc"
        x
      }
    ),
    list(
      name = "extract_date",
      pattern = "extract_date",
      change = function(x) {
        x$datasets$surgery_cohort$releases[[1L]]$extract_date <-
          "2026-02-31"
        x
      }
    ),
    list(
      name = "published_at",
      pattern = "published_at",
      change = function(x) {
        x$datasets$surgery_cohort$releases[[1L]]$published_at <-
          "2026-09-20 16:00"
        x
      }
    ),
    list(
      name = "positive sequence",
      pattern = "sequence",
      change = function(x) {
        x$datasets$surgery_cohort$releases[[1L]]$sequence <- 0L
        x
      }
    ),
    list(
      name = "whole sequence",
      pattern = "sequence",
      change = function(x) {
        x$datasets$surgery_cohort$releases[[1L]]$sequence <- 1.5
        x
      }
    ),
    list(
      name = "release order",
      pattern = "increasing",
      change = function(x) {
        x$datasets$surgery_cohort$releases[[1L]]$sequence <- 2L
        x$datasets$surgery_cohort$releases[[2L]]$sequence <- 1L
        x
      }
    ),
    list(
      name = "release IDs",
      pattern = "release_id",
      change = function(x) {
        first <- x$datasets$surgery_cohort$releases[[1L]]$release_id
        x$datasets$surgery_cohort$releases[[2L]]$release_id <- first
        x
      }
    ),
    list(
      name = "reserved release ID",
      pattern = "release_id",
      change = function(x) {
        x$datasets$surgery_cohort$releases[[2L]]$release_id <- "latest"
        x
      }
    ),
    list(
      name = "sequences",
      pattern = "sequence",
      change = function(x) {
        x$datasets$surgery_cohort$releases[[2L]]$sequence <- 1L
        x$datasets$surgery_cohort$releases <-
          rev(x$datasets$surgery_cohort$releases)
        x
      }
    ),
    list(
      name = "status",
      pattern = "status",
      change = function(x) {
        x$datasets$surgery_cohort$releases[[1L]]$status <- "draft"
        x
      }
    ),
    list(
      name = "withdrawal reason",
      pattern = "withdrawal_reason",
      change = function(x) {
        x$datasets$surgery_cohort$releases[[1L]]$status <- "withdrawn"
        x
      }
    ),
    list(
      name = "replacement release",
      pattern = "replacement_release_id",
      change = function(x) {
        x$datasets$surgery_cohort$releases[[1L]]$status <- "withdrawn"
        x$datasets$surgery_cohort$releases[[1L]]$withdrawal_reason <-
          "Incorrect cohort"
        x$datasets$surgery_cohort$releases[[1L]]$replacement_release_id <-
          "missing-release"
        x
      }
    )
  )

  for (case in cases) {
    fx <- write_release_fixture(withr::local_tempdir())
    catalog <- case$change(yaml::read_yaml(fx$catalog_path))
    yaml::write_yaml(catalog, fx$catalog_path)
    expect_error(
      .read_dataset_catalog(fx$catalog_path),
      case$pattern,
      info = case$name
    )
  }
})

test_that("catalog revisions are contiguous within each extract date", {
  cases <- list(
    initial = c(2L, 3L),
    duplicate = c(1L, 1L),
    descending = c(2L, 1L),
    skipped = c(1L, 3L)
  )
  for (case in names(cases)) {
    fx <- write_release_fixture(withr::local_tempdir())
    catalog <- yaml::read_yaml(fx$catalog_path)
    releases <- catalog$datasets$surgery_cohort$releases
    releases[[2L]]$extract_date <- releases[[1L]]$extract_date
    releases[[1L]]$revision <- cases[[case]][[1L]]
    releases[[2L]]$revision <- cases[[case]][[2L]]
    catalog$datasets$surgery_cohort$releases <- releases
    yaml::write_yaml(catalog, fx$catalog_path)

    expect_error(
      .read_dataset_catalog(fx$catalog_path),
      "revision",
      info = case
    )
  }
})

test_that("catalog rejects missing and changed published bytes", {
  fx <- write_release_fixture(withr::local_tempdir())
  catalog <- .read_dataset_catalog(fx$catalog_path)
  release <- .catalog_release(
    catalog,
    "surgery_cohort",
    "surgery_cohort-20260921-r1"
  )
  path <- file.path(fx$data_dir, release$file)

  writeLines("changed", path)
  expect_error(
    .verify_catalog_file(release, fx$data_dir),
    "changed in place",
    class = "hvtiRutilities_release_integrity"
  )

  unlink(path)
  expect_error(
    .verify_catalog_file(release, fx$data_dir),
    "missing",
    class = "hvtiRutilities_release_integrity"
  )
})
