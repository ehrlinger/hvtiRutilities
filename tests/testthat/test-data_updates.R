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

test_that("read_built reports the latest available release once", {
  withr::local_options(hvtiRutilities.disable_parquet_cache = TRUE)
  fx <- make_release_aware_study(withr::local_tempdir())
  cfg <- study_config(fx$root)
  .reset_update_notices()

  data <- NULL
  expect_message(
    data <- read_built(cfg),
    "surgery_cohort-20260921-r1",
    class = "hvtiRutilities_update_available"
  )
  expect_equal(nrow(data), 3L)
  expect_no_message(read_built(cfg))
})

test_that("read_built continues when update status is unknown", {
  withr::local_options(hvtiRutilities.disable_parquet_cache = TRUE)
  fx <- make_release_aware_study(withr::local_tempdir())
  cfg <- study_config(fx$root)
  .reset_update_notices()
  unlink(fx$catalog_path)

  data <- NULL
  expect_message(
    data <- read_built(cfg),
    "status unknown",
    class = "hvtiRutilities_update_status_unknown"
  )
  expect_equal(nrow(data), 3L)
})

test_that("read_built continues when a candidate cannot be verified", {
  withr::local_options(hvtiRutilities.disable_parquet_cache = TRUE)
  fx <- make_release_aware_study(withr::local_tempdir())
  cfg <- study_config(fx$root)
  .reset_update_notices()
  writeLines("changed", file.path(fx$data_dir, "cohort_20260921.csv"))

  data <- NULL
  expect_message(
    data <- read_built(cfg),
    "candidate.*status unknown",
    class = "hvtiRutilities_update_status_unknown"
  )
  expect_equal(nrow(data), 3L)
})

test_that("a newly published release produces a new notice in one session", {
  withr::local_options(hvtiRutilities.disable_parquet_cache = TRUE)
  fx <- make_release_aware_study(withr::local_tempdir())
  cfg <- study_config(fx$root)
  .reset_update_notices()
  expect_message(read_built(cfg), "surgery_cohort-20260921-r1")

  append_release_fixture(
    fx,
    release_id = "surgery_cohort-20260921-r2",
    sequence = 3L,
    file = "cohort_20260921_r2.csv",
    extract_date = "2026-09-21",
    revision = 2L
  )

  expect_message(
    read_built(cfg),
    "surgery_cohort-20260921-r2",
    class = "hvtiRutilities_update_available"
  )
})

test_that("pinned integrity is checked before the cache can rewrite provenance", {
  skip_if_not_installed("arrow")
  fx <- make_release_aware_study(withr::local_tempdir())
  cfg <- study_config(fx$root)
  .reset_update_notices()
  suppressMessages(read_built(cfg))
  manifest_path <- file.path(fx$root, "manifest.yaml")
  before <- readBin(manifest_path, "raw", n = file.info(manifest_path)$size)
  writeLines("changed in place", file.path(fx$data_dir, "cohort_20260920.csv"))

  expect_error(
    read_built(cfg),
    class = "hvtiRutilities_release_integrity"
  )
  after <- readBin(manifest_path, "raw", n = file.info(manifest_path)$size)
  expect_identical(after, before)
})

test_that("withdrawn pinned releases require an explicit override", {
  withr::local_options(hvtiRutilities.disable_parquet_cache = TRUE)
  fx <- make_release_aware_study(withr::local_tempdir())
  cfg <- study_config(fx$root)
  withdraw_fixture_release(
    fx,
    "surgery_cohort-20260920-r1",
    "Incorrect cohort",
    replacement_release_id = "surgery_cohort-20260921-r1"
  )

  condition <- expect_error(
    read_built(cfg),
    "Incorrect cohort",
    class = "hvtiRutilities_withdrawn_release"
  )
  expect_match(conditionMessage(condition), "surgery_cohort-20260921-r1")
  expect_equal(nrow(suppressMessages(read_built(cfg, allow_withdrawn = TRUE))), 3L)
})

test_that("review_data_update compares an explicit valid candidate", {
  fx <- make_release_aware_study(withr::local_tempdir(), pinned_sequence = 1L)
  manifest_path <- file.path(fx$root, "manifest.yaml")
  before <- readBin(manifest_path, "raw", n = file.info(manifest_path)$size)

  review <- review_data_update(
    study_config(fx$root),
    release_id = "surgery_cohort-20260921-r1"
  )

  expect_s3_class(review, "data_update_review")
  expect_identical(review$pinned$release_id,
                   "surgery_cohort-20260920-r1")
  expect_identical(review$candidate$release_id,
                   "surgery_cohort-20260921-r1")
  expect_s3_class(review$comparison, "dataset_comparison")
  expect_identical(review$cohort_old$n, 3L)
  expect_identical(review$cohort_new$n, 4L)
  expect_output(print(review), "Rows: 3 -> 4", fixed = TRUE)
  expect_invisible(print(review))
  after <- readBin(manifest_path, "raw", n = file.info(manifest_path)$size)
  expect_identical(after, before)
  expect_false(any(file.exists(file.path(
    fx$data_dir,
    c("cohort_20260920.parquet", "cohort_20260921.parquet")
  ))))
})

test_that("review requires a real newer release ID", {
  fx <- make_release_aware_study(withr::local_tempdir(), pinned_sequence = 1L)
  cfg <- study_config(fx$root)

  expect_error(
    review_data_update(cfg, release_id = "latest"),
    "unknown release_id"
  )
  expect_error(
    review_data_update(
      cfg,
      release_id = "surgery_cohort-20260920-r1"
    ),
    "newer"
  )
})

test_that("review rejects withdrawn candidates", {
  fx <- make_release_aware_study(withr::local_tempdir())
  withdraw_fixture_release(
    fx,
    "surgery_cohort-20260921-r1",
    "Candidate withdrawn"
  )

  expect_error(
    review_data_update(
      study_config(fx$root),
      release_id = "surgery_cohort-20260921-r1"
    ),
    "published"
  )
})

test_that("review rejects missing and changed candidate bytes", {
  missing <- make_release_aware_study(withr::local_tempdir())
  unlink(file.path(missing$data_dir, "cohort_20260921.csv"))
  expect_error(
    review_data_update(
      study_config(missing$root),
      release_id = "surgery_cohort-20260921-r1"
    ),
    "missing",
    class = "hvtiRutilities_release_integrity"
  )

  changed <- make_release_aware_study(withr::local_tempdir())
  writeLines("changed", file.path(changed$data_dir, "cohort_20260921.csv"))
  expect_error(
    review_data_update(
      study_config(changed$root),
      release_id = "surgery_cohort-20260921-r1"
    ),
    "changed in place",
    class = "hvtiRutilities_release_integrity"
  )
})

test_that("review checks observed dimensions against the catalog", {
  fx <- make_release_aware_study(withr::local_tempdir())
  catalog <- yaml::read_yaml(fx$catalog_path)
  catalog$datasets$surgery_cohort$releases[[2L]]$n_rows <- 999L
  yaml::write_yaml(catalog, fx$catalog_path)

  expect_error(
    review_data_update(
      study_config(fx$root),
      release_id = "surgery_cohort-20260921-r1"
    ),
    "dimensions.*999"
  )
})

test_that("review omits cohort comparison when the contract has none", {
  fx <- make_release_aware_study(withr::local_tempdir(), named = TRUE)
  study_path <- file.path(fx$root, "_study.yml")
  study <- yaml::read_yaml(study_path)
  study$additional_datasets$named_data$cohort <- NULL
  yaml::write_yaml(study, study_path)

  review <- review_data_update(
    study_config(fx$root),
    dataset = "named_data",
    release_id = "surgery_cohort-20260921-r1"
  )

  expect_null(review$cohort_old)
  expect_null(review$cohort_new)
})

test_that("review fails when candidate cohort columns are absent", {
  fx <- make_release_aware_study(withr::local_tempdir())
  candidate_path <- file.path(fx$data_dir, "cohort_20260921.csv")
  candidate <- read.csv(candidate_path)
  candidate$dead <- NULL
  write.csv(candidate, candidate_path, row.names = FALSE)
  catalog <- yaml::read_yaml(fx$catalog_path)
  release <- catalog$datasets$surgery_cohort$releases[[2L]]
  release$sha256 <- digest::digest(candidate_path, algo = "sha256", file = TRUE)
  release$n_cols <- ncol(candidate)
  catalog$datasets$surgery_cohort$releases[[2L]] <- release
  yaml::write_yaml(catalog, fx$catalog_path)

  expect_error(
    review_data_update(
      study_config(fx$root),
      release_id = "surgery_cohort-20260921-r1"
    ),
    "no column named dead"
  )
})
