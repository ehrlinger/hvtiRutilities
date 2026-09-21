release_contract_bytes <- function(root) {
  paths <- file.path(root, c("_study.yml", "manifest.yaml"))
  lapply(paths, function(path) {
    readBin(path, "raw", n = file.info(path)$size)
  })
}

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

test_that("release notices carry the complete update report", {
  withr::local_options(hvtiRutilities.disable_parquet_cache = TRUE)
  fx <- make_release_aware_study(withr::local_tempdir())
  cfg <- study_config(fx$root)
  .reset_update_notices()
  notice <- NULL

  withCallingHandlers(
    read_built(cfg),
    hvtiRutilities_update_available = function(cnd) {
      notice <<- cnd
      invokeRestart("muffleMessage")
    }
  )

  expect_s3_class(notice$report, "data_update_report")
  expect_true(any(notice$report$status == "UPDATE AVAILABLE"))
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

test_that("pinned integrity is enforced when the catalog is unavailable", {
  skip_if_not_installed("arrow")
  cases <- c("missing", "malformed")
  for (case in cases) {
    fx <- make_release_aware_study(withr::local_tempdir())
    cfg <- study_config(fx$root)
    .reset_update_notices()
    suppressMessages(read_built(cfg))
    manifest_path <- file.path(fx$root, "manifest.yaml")
    before <- readBin(manifest_path, "raw", n = file.info(manifest_path)$size)
    writeLines("changed in place", file.path(fx$data_dir, "cohort_20260920.csv"))
    if (identical(case, "missing")) {
      unlink(fx$catalog_path)
    } else {
      catalog <- yaml::read_yaml(fx$catalog_path)
      catalog$format_version <- 2L
      yaml::write_yaml(catalog, fx$catalog_path)
    }

    expect_error(
      read_built(cfg),
      class = "hvtiRutilities_release_integrity",
      info = case
    )
    after <- readBin(manifest_path, "raw", n = file.info(manifest_path)$size)
    expect_identical(after, before, info = case)
  }
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
    "exact release ID"
  )
  expect_error(
    review_data_update(
      cfg,
      release_id = "surgery_cohort-20260920-r1"
    ),
    "newer"
  )
})

test_that("review rejects a catalog release literally named latest", {
  fx <- make_release_aware_study(withr::local_tempdir())
  catalog <- yaml::read_yaml(fx$catalog_path)
  catalog$datasets$surgery_cohort$releases[[2L]]$release_id <- "latest"
  yaml::write_yaml(catalog, fx$catalog_path)

  expect_error(
    review_data_update(study_config(fx$root), release_id = "latest"),
    "exact release ID"
  )
})

test_that("review and adoption reconcile the pin with the manifest", {
  fx <- make_release_aware_study(withr::local_tempdir())
  pinned_path <- file.path(fx$data_dir, "cohort_20260920.csv")
  changed <- data.frame(id = 1:5, dead = c(1L, 1L, 0L, 0L, 0L), iv_dead = 1:5)
  write.csv(changed, pinned_path, row.names = FALSE)
  catalog <- yaml::read_yaml(fx$catalog_path)
  pinned <- catalog$datasets$surgery_cohort$releases[[1L]]
  pinned$sha256 <- digest::digest(pinned_path, algo = "sha256", file = TRUE)
  pinned$n_rows <- nrow(changed)
  pinned$n_cols <- ncol(changed)
  catalog$datasets$surgery_cohort$releases[[1L]] <- pinned
  yaml::write_yaml(catalog, fx$catalog_path)
  before <- release_contract_bytes(fx$root)

  expect_error(
    review_data_update(
      study_config(fx$root),
      release_id = "surgery_cohort-20260921-r1"
    ),
    class = "hvtiRutilities_release_integrity"
  )
  expect_error(
    adopt_data_update(
      study_config(fx$root),
      release_id = "surgery_cohort-20260921-r1"
    ),
    class = "hvtiRutilities_release_integrity"
  )
  expect_identical(release_contract_bytes(fx$root), before)
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

test_that("adoption advances the default contract and manifest entry", {
  fx <- make_release_aware_study(withr::local_tempdir(), pinned_sequence = 1L)

  status <- adopt_data_update(
    study_config(fx$root),
    release_id = "surgery_cohort-20260921-r1"
  )

  expect_s3_class(status, "study_status")
  cfg <- study_config(fx$root)
  expect_identical(cfg$built, "cohort_20260921.csv")
  expect_identical(cfg$release$release_id,
                   "surgery_cohort-20260921-r1")
  expect_identical(cfg$cohort$n, 4L)
  manifest <- yaml::read_yaml(file.path(fx$root, "manifest.yaml"))
  files <- vapply(manifest$datasets, function(x) x$file, character(1))
  expect_false("cohort_20260920.csv" %in% files)
  expect_true("cohort_20260921.csv" %in% files)
  expect_true(file.exists(file.path(fx$data_dir, "cohort_20260920.csv")))
  update <- status$checks[status$checks$item == "update:study", , drop = FALSE]
  expect_identical(update$status, "CURRENT")
})

test_that("adoption advances only the selected named contract", {
  fx <- make_release_aware_study(
    withr::local_tempdir(),
    pinned_sequence = 1L,
    named = TRUE
  )
  before <- yaml::read_yaml(file.path(fx$root, "_study.yml"))

  status <- adopt_data_update(
    study_config(fx$root),
    dataset = "named_data",
    release_id = "surgery_cohort-20260921-r1"
  )

  after <- yaml::read_yaml(file.path(fx$root, "_study.yml"))
  expect_identical(after$built, before$built)
  expect_identical(after$cohort, before$cohort)
  expect_identical(after$release, before$release)
  expect_identical(
    after$additional_datasets$named_data$built,
    "cohort_20260921.csv"
  )
  expect_identical(
    after$additional_datasets$named_data$release$release_id,
    "surgery_cohort-20260921-r1"
  )
  expect_identical(after$additional_datasets$named_data$cohort$n, 4L)
  update <- status$checks[
    status$checks$item == "update:named_data",
    ,
    drop = FALSE
  ]
  expect_identical(update$status, "CURRENT")
})

test_that("a named release can be adopted before the default is registered", {
  root <- file.path(withr::local_tempdir(), "study")
  study_setup(root, "Named release fixture", 42L)
  fx <- write_release_fixture(root)
  register_data(
    root,
    "cohort_20260920.csv",
    "dead",
    "iv_dead",
    dataset = "named_data",
    role = "named",
    catalog_dataset = "surgery_cohort",
    release_id = "surgery_cohort-20260920-r1"
  )

  adopt_data_update(
    study_config(root, require_data = FALSE),
    dataset = "named_data",
    release_id = "surgery_cohort-20260921-r1"
  )

  cfg <- study_config(root, require_data = FALSE)
  expect_null(cfg$built)
  expect_identical(
    cfg$additional_datasets$named_data$release$release_id,
    "surgery_cohort-20260921-r1"
  )
  expect_true(file.exists(fx$catalog_path))
})

test_that("adoption retains additive release metadata", {
  for (named in c(FALSE, TRUE)) {
    fx <- make_release_aware_study(withr::local_tempdir(), named = named)
    path <- file.path(fx$root, "_study.yml")
    raw <- yaml::read_yaml(path)
    if (named) {
      raw$additional_datasets$named_data$release$future_field <- "keep me"
    } else {
      raw$release$future_field <- "keep me"
    }
    yaml::write_yaml(raw, path)

    adopt_data_update(
      study_config(fx$root),
      dataset = if (named) "named_data" else "study",
      release_id = "surgery_cohort-20260921-r1"
    )

    after <- yaml::read_yaml(path)
    release <- if (named) {
      after$additional_datasets$named_data$release
    } else {
      after$release
    }
    expect_identical(release$future_field, "keep me", info = as.character(named))
  }
})

test_that("adoption revalidates bytes changed after review", {
  fx <- make_release_aware_study(withr::local_tempdir(), pinned_sequence = 1L)
  cfg <- study_config(fx$root)
  review_data_update(
    cfg,
    release_id = "surgery_cohort-20260921-r1"
  )
  before <- release_contract_bytes(fx$root)
  writeLines(
    "changed after review",
    file.path(fx$data_dir, "cohort_20260921.csv")
  )

  expect_error(
    adopt_data_update(
      cfg,
      release_id = "surgery_cohort-20260921-r1"
    ),
    class = "hvtiRutilities_release_integrity"
  )
  expect_identical(release_contract_bytes(fx$root), before)
})

test_that("adoption rolls back both contracts when pair replacement fails", {
  fx <- make_release_aware_study(withr::local_tempdir(), pinned_sequence = 1L)
  before <- release_contract_bytes(fx$root)
  local_mocked_bindings(
    .registration_rename = function(from, to) {
      if (grepl("^[.]manifest-", basename(from))) return(FALSE)
      file.rename(from, to)
    }
  )

  expect_error(
    adopt_data_update(
      study_config(fx$root),
      release_id = "surgery_cohort-20260921-r1"
    ),
    "prepared manifest"
  )
  expect_identical(release_contract_bytes(fx$root), before)
})

test_that("adoption requires exactly one old manifest entry", {
  missing <- make_release_aware_study(withr::local_tempdir())
  missing_path <- file.path(missing$root, "manifest.yaml")
  manifest <- yaml::read_yaml(missing_path)
  manifest$datasets[[1L]]$file <- "other.csv"
  yaml::write_yaml(manifest, missing_path)
  before <- release_contract_bytes(missing$root)
  expect_error(
    adopt_data_update(
      study_config(missing$root),
      release_id = "surgery_cohort-20260921-r1"
    ),
    "exactly one manifest entry"
  )
  expect_identical(release_contract_bytes(missing$root), before)

  duplicate <- make_release_aware_study(withr::local_tempdir())
  duplicate_path <- file.path(duplicate$root, "manifest.yaml")
  manifest <- yaml::read_yaml(duplicate_path)
  manifest$datasets <- c(manifest$datasets, manifest$datasets)
  yaml::write_yaml(manifest, duplicate_path)
  before <- release_contract_bytes(duplicate$root)
  expect_error(
    adopt_data_update(
      study_config(duplicate$root),
      release_id = "surgery_cohort-20260921-r1"
    ),
    "exactly one manifest entry"
  )
  expect_identical(release_contract_bytes(duplicate$root), before)
})

test_that("adoption rejects a candidate stem collision", {
  fx <- make_release_aware_study(withr::local_tempdir())
  manifest_path <- file.path(fx$root, "manifest.yaml")
  manifest <- yaml::read_yaml(manifest_path)
  conflict <- manifest$datasets[[1L]]
  conflict$file <- "cohort_20260921.rds"
  manifest$datasets <- c(manifest$datasets, list(conflict))
  yaml::write_yaml(manifest, manifest_path)
  before <- release_contract_bytes(fx$root)

  expect_error(
    adopt_data_update(
      study_config(fx$root),
      release_id = "surgery_cohort-20260921-r1"
    ),
    "derived path stem"
  )
  expect_identical(release_contract_bytes(fx$root), before)
})

test_that("adoption rejects withdrawn and non-newer candidates", {
  withdrawn <- make_release_aware_study(withr::local_tempdir())
  withdraw_fixture_release(
    withdrawn,
    "surgery_cohort-20260921-r1",
    "Candidate withdrawn"
  )
  expect_error(
    adopt_data_update(
      study_config(withdrawn$root),
      release_id = "surgery_cohort-20260921-r1"
    ),
    "published"
  )

  old <- make_release_aware_study(withr::local_tempdir())
  expect_error(
    adopt_data_update(
      study_config(old$root),
      release_id = "surgery_cohort-20260920-r1"
    ),
    "newer"
  )
})
