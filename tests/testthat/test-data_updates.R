test_that("check_data_updates reports current and every later release", {
  fx <- make_release_aware_study(
    withr::local_tempdir(),
    pinned_sequence = 1L
  )

  report <- check_data_updates(study_config(fx$root))

  expect_s3_class(report, "data_update_report")
  expect_named(report, c(
    "dataset", "scope", "pinned_release_id", "candidate_release_id",
    "sequence", "file", "status", "is_latest", "detail"
  ))
  expect_identical(report$status,
                   c("CURRENT", "UPDATE AVAILABLE"))
  expect_identical(report$candidate_release_id[[2L]],
                   "surgery_cohort-20260921-r1")
  expect_true(report$is_latest[[2L]])
})

test_that("same-day candidates follow sequence rather than filename order", {
  fx <- make_release_aware_study(
    withr::local_tempdir(),
    pinned_sequence = 1L
  )
  append_release_fixture(
    fx,
    release_id = "surgery_cohort-20260921-r2",
    sequence = 3L,
    file = "aaa_20260921_r2.csv",
    extract_date = "2026-09-21",
    revision = 2L
  )

  available <- check_data_updates(study_config(fx$root))
  available <- available[available$scope == "candidate", ]

  expect_identical(available$sequence, c(2L, 3L))
  expect_identical(available$is_latest, c(FALSE, TRUE))
})

test_that("check_data_updates selects named data and all aware contracts", {
  fx <- make_release_aware_study(
    withr::local_tempdir(),
    pinned_sequence = 1L,
    named = TRUE
  )
  cfg <- study_config(fx$root)

  named <- check_data_updates(cfg, dataset = "named_data")
  all <- check_data_updates(cfg)

  expect_true(all(named$dataset == "named_data"))
  expect_true(all(all$dataset == "named_data"))
  expect_error(check_data_updates(cfg, dataset = "not_registered"),
               "unknown dataset")
})

test_that("legacy data has no update rows", {
  root <- make_registered_study(withr::local_tempdir())

  report <- check_data_updates(study_config(root))

  expect_s3_class(report, "data_update_report")
  expect_equal(nrow(report), 0L)
  expect_named(report, c(
    "dataset", "scope", "pinned_release_id", "candidate_release_id",
    "sequence", "file", "status", "is_latest", "detail"
  ))
})

test_that("missing and malformed catalogs have distinct outcomes", {
  missing <- make_release_aware_study(withr::local_tempdir())
  unlink(missing$catalog_path)

  unavailable <- check_data_updates(study_config(missing$root))
  expect_identical(unavailable$scope, "catalog")
  expect_identical(unavailable$status, "UPDATE STATUS UNKNOWN")

  malformed <- make_release_aware_study(withr::local_tempdir())
  catalog <- yaml::read_yaml(malformed$catalog_path)
  catalog$format_version <- 2L
  yaml::write_yaml(catalog, malformed$catalog_path)

  failed <- check_data_updates(study_config(malformed$root))
  expect_identical(failed$scope, "catalog")
  expect_identical(failed$status, "FAIL")
  expect_match(failed$detail, "format_version")
})

test_that("a withdrawn pinned release is visible", {
  fx <- make_release_aware_study(withr::local_tempdir())
  catalog <- yaml::read_yaml(fx$catalog_path)
  catalog$datasets$surgery_cohort$releases[[1L]]$status <- "withdrawn"
  catalog$datasets$surgery_cohort$releases[[1L]]$withdrawal_reason <-
    "Incorrect cohort"
  yaml::write_yaml(catalog, fx$catalog_path)

  report <- check_data_updates(study_config(fx$root))

  expect_identical(report$status[[1L]], "WITHDRAWN")
  expect_match(report$detail[[1L]], "Incorrect cohort")
})

test_that("candidate failures do not change a valid pinned result", {
  missing <- make_release_aware_study(withr::local_tempdir())
  unlink(file.path(missing$data_dir, "cohort_20260921.csv"))

  missing_report <- check_data_updates(study_config(missing$root))
  expect_identical(missing_report$status, c("CURRENT", "FAIL"))
  expect_identical(missing_report$scope, c("pinned", "candidate"))

  changed <- make_release_aware_study(withr::local_tempdir())
  writeLines("changed", file.path(changed$data_dir, "cohort_20260921.csv"))

  changed_report <- check_data_updates(study_config(changed$root))
  expect_identical(changed_report$status, c("CURRENT", "FAIL"))
  expect_match(changed_report$detail[[2L]], "changed in place")
})

test_that("pinned identity disagreement fails the pin", {
  fx <- make_release_aware_study(withr::local_tempdir())
  manifest <- yaml::read_yaml(file.path(fx$root, "manifest.yaml"))
  manifest$datasets[[1L]]$sha256 <- paste(rep("0", 64L), collapse = "")
  yaml::write_yaml(manifest, file.path(fx$root, "manifest.yaml"))

  report <- check_data_updates(study_config(fx$root))

  expect_identical(report$scope, "pinned")
  expect_identical(report$status, "FAIL")
  expect_match(report$detail, "manifest")
})
