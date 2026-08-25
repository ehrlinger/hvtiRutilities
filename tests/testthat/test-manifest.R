library(testthat)
library(hvtiRutilities)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

make_df <- function(n) data.frame(id = seq_len(n), x = seq_len(n) * 0.1)

write_temp_csv <- function(n = 10, name = NULL, dir = tempdir()) {
  name <- name %||% paste0("cohort_", format(Sys.Date(), "%Y%m%d"), ".csv")
  path <- file.path(dir, name)
  write.csv(make_df(n), path, row.names = FALSE)
  path
}

write_temp_sas <- function(n = 10, name = "cohort_20240115.sas7bdat",
                           dir = tempdir()) {
  skip_if_not_installed("haven")
  path <- file.path(dir, name)
  suppressWarnings(haven::write_sas(make_df(n), path))
  path
}

write_temp_excel <- function(n = 10, name = "cohort_20240115.xlsx",
                             dir = tempdir()) {
  skip_if_not_installed("writexl")
  path <- file.path(dir, name)
  writexl::write_xlsx(make_df(n), path)
  path
}

# ---------------------------------------------------------------------------
# update_manifest — CSV
# ---------------------------------------------------------------------------

test_that("update_manifest [CSV] creates entry with correct fields", {
  tmp <- tempdir()
  csv <- write_temp_csv(n = 10, dir = tmp)
  mpath <- file.path(tmp, "manifest_csv.yaml")

  update_manifest(
    file          = csv,
    manifest_path = mpath,
    extract_date  = "2024-01-15",
    source        = "Epic EMR, query v4.2",
    sort_key      = "id"
  )

  m <- yaml::read_yaml(mpath)
  entry <- m$datasets[[1]]
  expect_equal(entry$file, basename(csv))
  expect_equal(entry$extract_date, "2024-01-15")
  expect_equal(entry$n_rows, 10L)
  expect_match(entry$sha256, "^[a-f0-9]{64}$")
  expect_equal(entry$source, "Epic EMR, query v4.2")
  expect_equal(entry$sort_key, "id")
})

test_that("update_manifest [CSV] updates existing entry in place", {
  tmp <- tempdir()
  csv <- write_temp_csv(n = 5, name = "cohort_upd.csv", dir = tmp)
  mpath <- file.path(tmp, "manifest_csv_upd.yaml")

  update_manifest(file = csv, manifest_path = mpath, extract_date = "2024-01-01")
  update_manifest(file = csv, manifest_path = mpath, extract_date = "2024-06-01",
                  source = "Updated source")

  m <- yaml::read_yaml(mpath)
  expect_length(m$datasets, 1L)
  expect_equal(m$datasets[[1]]$extract_date, "2024-06-01")
  expect_equal(m$datasets[[1]]$source, "Updated source")
})

test_that("update_manifest [CSV] appends a second distinct file", {
  tmp <- tempdir()
  csv1 <- write_temp_csv(n = 5, name = "cohort_a.csv", dir = tmp)
  csv2 <- write_temp_csv(n = 3, name = "labs_20240115.csv", dir = tmp)
  mpath <- file.path(tmp, "manifest_csv_two.yaml")

  update_manifest(file = csv1, manifest_path = mpath, extract_date = "2024-01-15")
  update_manifest(file = csv2, manifest_path = mpath, extract_date = "2024-01-15")

  expect_length(yaml::read_yaml(mpath)$datasets, 2L)
})

# ---------------------------------------------------------------------------
# update_manifest — SAS
# ---------------------------------------------------------------------------

test_that("update_manifest [SAS] errors without allow_heavy_rowcount option", {
  tmp <- tempdir()
  sas <- write_temp_sas(n = 5, name = "cohort_guard.sas7bdat", dir = tmp)
  expect_error(
    update_manifest(file = sas, manifest_path = file.path(tmp, "m_guard.yaml")),
    "allow_heavy_rowcount"
  )
})

test_that("update_manifest [Excel] errors without allow_heavy_rowcount option", {
  tmp <- tempdir()
  xlsx <- write_temp_excel(n = 5, name = "cohort_guard.xlsx", dir = tmp)
  expect_error(
    update_manifest(file = xlsx, manifest_path = file.path(tmp, "m_guard_xl.yaml")),
    "allow_heavy_rowcount"
  )
})

test_that("update_manifest [SAS] creates entry with correct row count", {
  withr::local_options(manifest.allow_heavy_rowcount = TRUE)
  tmp <- tempdir()
  sas <- write_temp_sas(n = 12, dir = tmp)
  mpath <- file.path(tmp, "manifest_sas.yaml")

  update_manifest(
    file          = sas,
    manifest_path = mpath,
    extract_date  = "2024-01-15",
    source        = "SAS CORR registry, labs module v2.1",
    sort_key      = "pat_id"
  )

  m <- yaml::read_yaml(mpath)
  entry <- m$datasets[[1]]
  expect_equal(entry$file, basename(sas))
  expect_equal(entry$n_rows, 12L)
  expect_match(entry$sha256, "^[a-f0-9]{64}$")
  expect_equal(entry$source, "SAS CORR registry, labs module v2.1")
})

# ---------------------------------------------------------------------------
# update_manifest — Excel
# ---------------------------------------------------------------------------

test_that("update_manifest [Excel] creates entry with correct row count", {
  withr::local_options(manifest.allow_heavy_rowcount = TRUE)
  tmp <- tempdir()
  xlsx <- write_temp_excel(n = 7, dir = tmp)
  mpath <- file.path(tmp, "manifest_xlsx.yaml")

  update_manifest(
    file          = xlsx,
    manifest_path = mpath,
    extract_date  = "2024-01-15",
    source        = "Clinical events committee adjudication log"
  )

  m <- yaml::read_yaml(mpath)
  entry <- m$datasets[[1]]
  expect_equal(entry$file, basename(xlsx))
  expect_equal(entry$n_rows, 7L)
  expect_match(entry$sha256, "^[a-f0-9]{64}$")
})

# ---------------------------------------------------------------------------
# update_manifest — RDS (explicit n_rows required)
# ---------------------------------------------------------------------------

test_that("update_manifest [RDS] errors without explicit n_rows", {
  tmp <- tempdir()
  rds <- file.path(tmp, "cohort.rds")
  saveRDS(make_df(5), rds)
  expect_error(
    update_manifest(file = rds, manifest_path = file.path(tmp, "m_rds.yaml")),
    "n_rows"
  )
})

test_that("update_manifest [RDS] succeeds with explicit n_rows", {
  tmp <- tempdir()
  rds <- file.path(tmp, "cohort2.rds")
  saveRDS(make_df(5), rds)
  mpath <- file.path(tmp, "manifest_rds.yaml")

  expect_no_error(
    update_manifest(file = rds, manifest_path = mpath, n_rows = 5L)
  )
  expect_equal(yaml::read_yaml(mpath)$datasets[[1]]$n_rows, 5L)
})

# ---------------------------------------------------------------------------
# update_manifest — edge cases
# ---------------------------------------------------------------------------

test_that("update_manifest errors on missing file", {
  expect_error(
    update_manifest(file = "/no/such/file.csv"),
    "Dataset file not found"
  )
})

# ---------------------------------------------------------------------------
# verify_manifest — CSV round-trip
# ---------------------------------------------------------------------------

test_that("verify_manifest [CSV] passes when file is unchanged", {
  tmp <- tempdir()
  csv <- write_temp_csv(n = 8, name = "cohort_verify.csv", dir = tmp)
  mpath <- file.path(tmp, "manifest_vcsv.yaml")
  update_manifest(file = csv, manifest_path = mpath)

  report <- verify_manifest(manifest_path = mpath, data_dir = tmp)
  expect_equal(report$status, "OK")
})

test_that("verify_manifest [CSV] detects SHA-256 mismatch", {
  tmp <- tempdir()
  csv <- file.path(tmp, "cohort_tampered.csv")
  write.csv(make_df(5), csv, row.names = FALSE)
  mpath <- file.path(tmp, "manifest_tamper.yaml")
  update_manifest(file = csv, manifest_path = mpath)

  write.csv(make_df(5)[c(2,1,3,4,5), ], csv, row.names = FALSE)  # different content → new hash

  expect_error(
    verify_manifest(manifest_path = mpath, data_dir = tmp),
    "SHA-256 mismatch"
  )
})

test_that("verify_manifest [CSV] detects missing file", {
  tmp <- tempdir()
  csv <- file.path(tmp, "cohort_gone.csv")
  write.csv(make_df(3), csv, row.names = FALSE)
  mpath <- file.path(tmp, "manifest_gone.yaml")
  update_manifest(file = csv, manifest_path = mpath)
  file.remove(csv)

  expect_error(
    verify_manifest(manifest_path = mpath, data_dir = tmp),
    "File not found"
  )
})

# ---------------------------------------------------------------------------
# verify_manifest — SAS round-trip
# ---------------------------------------------------------------------------

test_that("verify_manifest [SAS] passes when file is unchanged", {
  withr::local_options(manifest.allow_heavy_rowcount = TRUE)
  tmp <- tempdir()
  sas <- write_temp_sas(n = 6, name = "labs_verify.sas7bdat", dir = tmp)
  mpath <- file.path(tmp, "manifest_vsas.yaml")
  update_manifest(file = sas, manifest_path = mpath)

  report <- verify_manifest(manifest_path = mpath, data_dir = tmp)
  expect_equal(report$status, "OK")
})

# ---------------------------------------------------------------------------
# verify_manifest — Excel round-trip
# ---------------------------------------------------------------------------

test_that("verify_manifest [Excel] passes when file is unchanged", {
  withr::local_options(manifest.allow_heavy_rowcount = TRUE)
  tmp <- tempdir()
  xlsx <- write_temp_excel(n = 4, name = "adj_verify.xlsx", dir = tmp)
  mpath <- file.path(tmp, "manifest_vxlsx.yaml")
  update_manifest(file = xlsx, manifest_path = mpath)

  report <- verify_manifest(manifest_path = mpath, data_dir = tmp)
  expect_equal(report$status, "OK")
})

# ---------------------------------------------------------------------------
# verify_manifest — multi-format manifest
# ---------------------------------------------------------------------------

test_that("verify_manifest handles CSV + SAS + Excel in one manifest", {
  withr::local_options(manifest.allow_heavy_rowcount = TRUE)
  tmp <- tempdir()
  csv  <- write_temp_csv(n = 5,  name = "multi_cohort.csv",   dir = tmp)
  sas  <- write_temp_sas(n = 8,  name = "multi_labs.sas7bdat",dir = tmp)
  xlsx <- write_temp_excel(n = 3, name = "multi_adj.xlsx",    dir = tmp)
  mpath <- file.path(tmp, "manifest_multi.yaml")

  update_manifest(file = csv,  manifest_path = mpath)
  update_manifest(file = sas,  manifest_path = mpath)
  update_manifest(file = xlsx, manifest_path = mpath)

  report <- verify_manifest(manifest_path = mpath, data_dir = tmp)
  expect_equal(nrow(report), 3L)
  expect_true(all(report$status == "OK"))
})

# ---------------------------------------------------------------------------
# verify_manifest — entries with no recorded row count
#
# A manifest written by hand, or by a version that could not count rows, has
# entries with no n_rows at all. There is nothing to compare against, so the
# entry passes on its checksum; the message must say that rather than printing
# an empty count field, which reads as though a count of nothing was verified.
# ---------------------------------------------------------------------------

# Writes a manifest entry directly, bypassing update_manifest(), which always
# records an n_rows. `...` adds fields to the entry.
write_bare_manifest <- function(path, file, sha256, ...) {
  yaml::write_yaml(
    list(datasets = list(c(list(file = file, sha256 = sha256), list(...)))),
    path
  )
  path
}

test_that("verify_manifest says so when no row count was recorded", {
  tmp <- withr::local_tempdir()
  csv <- write_temp_csv(n = 10, name = "norows.csv", dir = tmp)
  mpath <- write_bare_manifest(
    file.path(tmp, "manifest.yaml"), "norows.csv",
    digest::digest(csv, algo = "sha256", file = TRUE)
  )

  report <- verify_manifest(manifest_path = mpath, data_dir = tmp)
  expect_equal(report$status, "OK")
  expect_match(report$message, "no row count recorded", fixed = TRUE)
  expect_false(report$row_count_checked)
  # The empty count field is the defect: it reads as a verified count of
  # nothing rather than as an absent count.
  expect_false(grepl("(n = )", report$message, fixed = TRUE))
})

test_that("verify_manifest verbose output omits the empty count field", {
  tmp <- withr::local_tempdir()
  csv <- write_temp_csv(n = 10, name = "norows_v.csv", dir = tmp)
  mpath <- write_bare_manifest(
    file.path(tmp, "manifest.yaml"), "norows_v.csv",
    digest::digest(csv, algo = "sha256", file = TRUE)
  )

  expect_message(
    verify_manifest(manifest_path = mpath, data_dir = tmp, verbose = TRUE),
    "no row count recorded", fixed = TRUE
  )
})

test_that("verify_manifest still reports a recorded row count", {
  tmp <- withr::local_tempdir()
  csv <- write_temp_csv(n = 7, name = "withrows.csv", dir = tmp)
  mpath <- file.path(tmp, "manifest.yaml")
  update_manifest(file = csv, manifest_path = mpath)

  report <- verify_manifest(manifest_path = mpath, data_dir = tmp)
  expect_equal(report$message, "SHA-256 match (n = 7)")
  expect_true(report$row_count_checked)
})

# ---------------------------------------------------------------------------
# verify_manifest — entries with no SHA-256 to compare
#
# The checksum is the whole of what this function verifies, so an entry
# carrying none cannot be passed: that is the "gate that passes without
# verifying" shape. It must fail, but it must say why. Reporting a mismatch
# blames a comparison that never happened.
# ---------------------------------------------------------------------------

test_that("verify_manifest fails an entry with no recorded checksum, and says so", {
  tmp <- withr::local_tempdir()
  csv <- write_temp_csv(n = 10, name = "nosha.csv", dir = tmp)
  mpath <- file.path(tmp, "manifest.yaml")
  yaml::write_yaml(
    list(datasets = list(list(file = "nosha.csv", n_rows = 10L))), mpath
  )

  report <- suppressWarnings(
    verify_manifest(manifest_path = mpath, data_dir = tmp,
                    stop_on_error = FALSE)
  )
  expect_equal(report$status, "FAIL")
  expect_match(report$message, "No SHA-256 recorded", fixed = TRUE)
  expect_false(grepl("mismatch", report$message, fixed = TRUE))
})

test_that("verify_manifest names the algorithm a manifest recorded instead", {
  tmp <- withr::local_tempdir()
  csv <- write_temp_csv(n = 10, name = "md5only.csv", dir = tmp)
  mpath <- file.path(tmp, "manifest.yaml")
  # As a manifest written by an md5-based writer would look.
  yaml::write_yaml(
    list(datasets = list(list(
      file = "md5only.csv", n_rows = 10L,
      md5  = digest::digest(csv, algo = "md5", file = TRUE)
    ))), mpath
  )

  report <- suppressWarnings(
    verify_manifest(manifest_path = mpath, data_dir = tmp,
                    stop_on_error = FALSE)
  )
  expect_equal(report$status, "FAIL")
  expect_match(report$message, "md5", fixed = TRUE)
  expect_false(grepl("mismatch", report$message, fixed = TRUE))
})

test_that("verify_manifest still reports a genuine SHA-256 mismatch as a mismatch", {
  tmp <- withr::local_tempdir()
  csv <- write_temp_csv(n = 10, name = "realmismatch.csv", dir = tmp)
  mpath <- file.path(tmp, "manifest.yaml")
  update_manifest(file = csv, manifest_path = mpath)
  write.csv(make_df(11), csv, row.names = FALSE)

  report <- suppressWarnings(
    verify_manifest(manifest_path = mpath, data_dir = tmp,
                    stop_on_error = FALSE)
  )
  expect_equal(report$status, "FAIL")
  expect_match(report$message, "SHA-256 mismatch", fixed = TRUE)
})

# ---------------------------------------------------------------------------
# verify_manifest — heavy row counting disabled
#
# The default state for every real study: options(manifest.allow_heavy_rowcount)
# is unset, so the row count cannot be re-derived from a .sas7bdat or .xlsx
# without loading the whole file. A check that cannot run is skipped, not
# failed — but nothing else about the entry may be let through.
# ---------------------------------------------------------------------------

test_that("verify_manifest [SAS] passes with heavy row counting disabled", {
  withr::local_options(manifest.allow_heavy_rowcount = NULL)
  tmp <- withr::local_tempdir()
  sas <- write_temp_sas(n = 6, name = "labs_noheavy.sas7bdat", dir = tmp)
  mpath <- file.path(tmp, "manifest.yaml")
  update_manifest(file = sas, manifest_path = mpath, n_rows = 6L)

  report <- verify_manifest(manifest_path = mpath, data_dir = tmp)
  expect_equal(report$status, "OK")
  expect_match(report$message, "row count not re-derived")
})

test_that("verify_manifest [Excel] passes with heavy row counting disabled", {
  withr::local_options(manifest.allow_heavy_rowcount = NULL)
  tmp <- withr::local_tempdir()
  xlsx <- write_temp_excel(n = 4, name = "adj_noheavy.xlsx", dir = tmp)
  mpath <- file.path(tmp, "manifest.yaml")
  update_manifest(file = xlsx, manifest_path = mpath, n_rows = 4L)

  report <- verify_manifest(manifest_path = mpath, data_dir = tmp)
  expect_equal(report$status, "OK")
  expect_match(report$message, "row count not re-derived")
})

test_that("verify_manifest [SAS] still detects SHA-256 mismatch when heavy row counting is disabled", {
  withr::local_options(manifest.allow_heavy_rowcount = NULL)
  tmp <- withr::local_tempdir()
  sas <- write_temp_sas(n = 6, name = "labs_tamper.sas7bdat", dir = tmp)
  mpath <- file.path(tmp, "manifest.yaml")
  update_manifest(file = sas, manifest_path = mpath, n_rows = 6L)

  # Same row count, different bytes: only the checksum can catch this.
  suppressWarnings(haven::write_sas(make_df(6)[6:1, ], sas))

  report <- suppressWarnings(
    verify_manifest(manifest_path = mpath, data_dir = tmp,
                    stop_on_error = FALSE)
  )
  expect_equal(report$status, "FAIL")
  expect_match(report$message, "SHA-256 mismatch")
})

test_that("verify_manifest [SAS] still detects a row-count mismatch when heavy row counting is enabled", {
  withr::local_options(manifest.allow_heavy_rowcount = TRUE)
  tmp <- withr::local_tempdir()
  sas <- write_temp_sas(n = 6, name = "labs_rowdrift.sas7bdat", dir = tmp)
  mpath <- file.path(tmp, "manifest.yaml")
  # Record a row count the file does not have, then re-checksum so that only
  # the row-count check can fail.
  update_manifest(file = sas, manifest_path = mpath, n_rows = 99L)

  report <- suppressWarnings(
    verify_manifest(manifest_path = mpath, data_dir = tmp,
                    stop_on_error = FALSE)
  )
  expect_equal(report$status, "FAIL")
  expect_match(report$message, "Row count mismatch")
})

test_that("verify_manifest reports row_count_checked per entry", {
  withr::local_options(manifest.allow_heavy_rowcount = NULL)
  tmp <- withr::local_tempdir()
  csv <- write_temp_csv(n = 5, name = "rcc_cohort.csv", dir = tmp)
  sas <- write_temp_sas(n = 6, name = "rcc_labs.sas7bdat", dir = tmp)
  mpath <- file.path(tmp, "manifest.yaml")
  update_manifest(file = csv, manifest_path = mpath)
  update_manifest(file = sas, manifest_path = mpath, n_rows = 6L)

  report <- verify_manifest(manifest_path = mpath, data_dir = tmp)
  expect_true(all(report$status == "OK"))
  # The CSV count is cheap and was re-derived; the SAS count was not.
  expect_equal(report$row_count_checked,
               c(TRUE, FALSE))
})

test_that("verify_manifest marks a re-derived row-count mismatch as checked", {
  withr::local_options(manifest.allow_heavy_rowcount = TRUE)
  tmp <- withr::local_tempdir()
  sas <- write_temp_sas(n = 6, name = "rcc_drift.sas7bdat", dir = tmp)
  mpath <- file.path(tmp, "manifest.yaml")
  update_manifest(file = sas, manifest_path = mpath, n_rows = 99L)

  report <- suppressWarnings(
    verify_manifest(manifest_path = mpath, data_dir = tmp,
                    stop_on_error = FALSE)
  )
  expect_equal(report$status, "FAIL")
  expect_true(report$row_count_checked)
})

test_that("verify_manifest empty report carries the row_count_checked column", {
  tmp <- withr::local_tempdir()
  mpath <- file.path(tmp, "manifest.yaml")
  yaml::write_yaml(list(datasets = list()), mpath)

  report <- verify_manifest(manifest_path = mpath, data_dir = tmp)
  expect_equal(names(report),
               c("file", "status", "message", "row_count_checked"))
  expect_equal(nrow(report), 0L)
})

test_that("verify_manifest reports an unreadable file as FAIL, not a skipped check", {
  withr::local_options(manifest.allow_heavy_rowcount = TRUE)
  tmp <- withr::local_tempdir()
  sas <- file.path(tmp, "labs_corrupt.sas7bdat")
  writeBin(as.raw(rep(0L, 512)), sas)
  mpath <- file.path(tmp, "manifest.yaml")
  update_manifest(file = sas, manifest_path = mpath, n_rows = 6L)

  report <- suppressWarnings(
    verify_manifest(manifest_path = mpath, data_dir = tmp,
                    stop_on_error = FALSE)
  )
  expect_equal(report$status, "FAIL")
  expect_match(report$message, "Row count auto-detection failed")
})

# ---------------------------------------------------------------------------
# verify_manifest — control flow
# ---------------------------------------------------------------------------

test_that("verify_manifest with stop_on_error=FALSE warns instead of stopping", {
  tmp <- tempdir()
  csv <- file.path(tmp, "cohort_warn.csv")
  write.csv(make_df(3), csv, row.names = FALSE)
  mpath <- file.path(tmp, "manifest_warn.yaml")
  update_manifest(file = csv, manifest_path = mpath)
  file.remove(csv)

  expect_warning(
    report <- verify_manifest(manifest_path = mpath, data_dir = tmp,
                              stop_on_error = FALSE),
    "STOP: manifest verification failed"
  )
  expect_equal(report$status, "FAIL")
})

test_that("verify_manifest errors on missing manifest file", {
  expect_error(
    verify_manifest(manifest_path = "/no/such/manifest.yaml"),
    "Manifest file not found"
  )
})

test_that("verify_manifest returns empty data frame for empty manifest", {
  tmp <- tempdir()
  mpath <- file.path(tmp, "manifest_empty.yaml")
  yaml::write_yaml(list(datasets = list()), mpath)

  report <- verify_manifest(manifest_path = mpath, data_dir = tmp)
  expect_equal(nrow(report), 0L)
})

# ---------------------------------------------------------------------------
# verbose — console output is opt-in, silent by default
# ---------------------------------------------------------------------------

test_that("update_manifest is silent by default", {
  tmp <- tempdir()
  csv <- write_temp_csv(n = 4, name = "cohort_quiet.csv", dir = tmp)
  mpath <- file.path(tmp, "manifest_quiet.yaml")

  # First call appends a new entry, second updates it in place; both silent.
  expect_silent(update_manifest(file = csv, manifest_path = mpath))
  expect_silent(update_manifest(file = csv, manifest_path = mpath))
})

test_that("update_manifest reports add and update when verbose = TRUE", {
  tmp <- withr::local_tempdir()
  csv <- write_temp_csv(n = 4, name = "cohort_loud.csv", dir = tmp)
  mpath <- file.path(tmp, "manifest_loud.yaml")

  expect_message(
    update_manifest(file = csv, manifest_path = mpath, verbose = TRUE),
    "Manifest entry added: cohort_loud\\.csv"
  )
  expect_message(
    update_manifest(file = csv, manifest_path = mpath, verbose = TRUE),
    "Manifest updated: cohort_loud\\.csv"
  )
})

test_that("verify_manifest is silent by default on success", {
  tmp <- tempdir()
  csv <- write_temp_csv(n = 6, name = "cohort_vquiet.csv", dir = tmp)
  mpath <- file.path(tmp, "manifest_vquiet.yaml")
  update_manifest(file = csv, manifest_path = mpath)

  expect_silent(verify_manifest(manifest_path = mpath, data_dir = tmp))
})

test_that("verify_manifest reports each passing entry when verbose = TRUE", {
  tmp <- tempdir()
  csv <- write_temp_csv(n = 6, name = "cohort_vloud.csv", dir = tmp)
  mpath <- file.path(tmp, "manifest_vloud.yaml")
  update_manifest(file = csv, manifest_path = mpath)

  expect_message(
    verify_manifest(manifest_path = mpath, data_dir = tmp, verbose = TRUE),
    "cohort_vloud\\.csv .* SHA-256 match \\(n = 6\\)"
  )
})

test_that("verify_manifest empty-manifest notice respects verbose", {
  tmp <- tempdir()
  mpath <- file.path(tmp, "manifest_empty_verbose.yaml")
  yaml::write_yaml(list(datasets = list()), mpath)

  expect_silent(verify_manifest(manifest_path = mpath, data_dir = tmp))
  expect_message(
    verify_manifest(manifest_path = mpath, data_dir = tmp, verbose = TRUE),
    "no dataset entries"
  )
})

test_that("verbose = FALSE does not suppress failures", {
  tmp <- tempdir()
  csv <- file.path(tmp, "cohort_quiet_fail.csv")
  write.csv(make_df(5), csv, row.names = FALSE)
  mpath <- file.path(tmp, "manifest_quiet_fail.yaml")
  update_manifest(file = csv, manifest_path = mpath)

  write.csv(make_df(5)[c(2, 1, 3, 4, 5), ], csv, row.names = FALSE)

  # Default (silent) call must still raise on a real mismatch.
  expect_error(
    verify_manifest(manifest_path = mpath, data_dir = tmp),
    "SHA-256 mismatch"
  )
  expect_warning(
    verify_manifest(manifest_path = mpath, data_dir = tmp,
                    stop_on_error = FALSE),
    "SHA-256 mismatch"
  )
})

# ---------------------------------------------------------------------------
# verify_manifest(strict = TRUE)
# ---------------------------------------------------------------------------
# The default is deliberately permissive: a check that cannot run is skipped
# and the entry passes on its checksum, which is the stronger of the two.
# `strict` is for the caller who needs the opposite guarantee, that every
# applicable check actually ran. Under it, "not checked" is a distinct failure
# from "checked and wrong", and the message must say which.
#
# The default path must not move. Every test below that asserts a FAIL has a
# sibling asserting the same manifest still passes at strict = FALSE.

test_that("strict = TRUE fails an entry whose row count was never recorded", {
  tmp <- withr::local_tempdir()
  csv <- write_temp_csv(n = 10, name = "nrows_absent.csv", dir = tmp)
  mpath <- file.path(tmp, "manifest.yaml")
  update_manifest(file = csv, manifest_path = mpath, n_rows = 10L)

  # Remove the recorded count, leaving an otherwise intact entry.
  m <- yaml::read_yaml(mpath)
  m$datasets[[1]]$n_rows <- NULL
  yaml::write_yaml(m, mpath)

  lax <- verify_manifest(manifest_path = mpath, data_dir = tmp)
  expect_equal(lax$status, "OK")

  strict <- suppressWarnings(
    verify_manifest(manifest_path = mpath, data_dir = tmp,
                    strict = TRUE, stop_on_error = FALSE))
  expect_equal(strict$status, "FAIL")
  expect_false(strict$row_count_checked)
  expect_match(strict$message, "not recorded")
})

test_that("strict = TRUE fails a SAS entry whose count could not be re-derived", {
  # The default state for every real study, and the reason strict exists: the
  # entry is intact but one of its two checks did not run.
  withr::local_options(manifest.allow_heavy_rowcount = NULL)
  tmp <- withr::local_tempdir()
  sas <- write_temp_sas(n = 6, name = "strict_heavy.sas7bdat", dir = tmp)
  mpath <- file.path(tmp, "manifest.yaml")
  update_manifest(file = sas, manifest_path = mpath, n_rows = 6L)

  expect_equal(verify_manifest(manifest_path = mpath, data_dir = tmp)$status,
               "OK")

  strict <- suppressWarnings(
    verify_manifest(manifest_path = mpath, data_dir = tmp,
                    strict = TRUE, stop_on_error = FALSE))
  expect_equal(strict$status, "FAIL")
  expect_match(strict$message, "manifest.allow_heavy_rowcount")
})

test_that("strict = TRUE fails a file type whose rows cannot be counted", {
  tmp <- withr::local_tempdir()
  rds <- file.path(tmp, "obj.rds")
  saveRDS(make_df(5), rds)
  mpath <- file.path(tmp, "manifest.yaml")
  update_manifest(file = rds, manifest_path = mpath, n_rows = 5L)

  expect_equal(verify_manifest(manifest_path = mpath, data_dir = tmp)$status,
               "OK")

  strict <- suppressWarnings(
    verify_manifest(manifest_path = mpath, data_dir = tmp,
                    strict = TRUE, stop_on_error = FALSE))
  expect_equal(strict$status, "FAIL")
  expect_match(strict$message, "rds")
})

test_that("strict = TRUE passes when every check actually ran", {
  # Strict must be satisfiable, not merely strict.
  tmp <- withr::local_tempdir()
  csv <- write_temp_csv(n = 10, name = "strict_ok.csv", dir = tmp)
  mpath <- file.path(tmp, "manifest.yaml")
  update_manifest(file = csv, manifest_path = mpath, n_rows = 10L)

  report <- verify_manifest(manifest_path = mpath, data_dir = tmp,
                            strict = TRUE)
  expect_equal(report$status, "OK")
  expect_true(report$row_count_checked)
})

test_that("strict = TRUE passes a SAS entry once heavy counting is enabled", {
  withr::local_options(manifest.allow_heavy_rowcount = TRUE)
  tmp <- withr::local_tempdir()
  sas <- write_temp_sas(n = 6, name = "strict_heavy_on.sas7bdat", dir = tmp)
  mpath <- file.path(tmp, "manifest.yaml")
  update_manifest(file = sas, manifest_path = mpath, n_rows = 6L)

  report <- verify_manifest(manifest_path = mpath, data_dir = tmp,
                            strict = TRUE)
  expect_equal(report$status, "OK")
  expect_true(report$row_count_checked)
})

test_that("strict = TRUE still stops by default when an entry fails", {
  tmp <- withr::local_tempdir()
  csv <- write_temp_csv(n = 10, name = "strict_stops.csv", dir = tmp)
  mpath <- file.path(tmp, "manifest.yaml")
  update_manifest(file = csv, manifest_path = mpath, n_rows = 10L)
  m <- yaml::read_yaml(mpath)
  m$datasets[[1]]$n_rows <- NULL
  yaml::write_yaml(m, mpath)

  expect_error(verify_manifest(manifest_path = mpath, data_dir = tmp,
                               strict = TRUE),
               "not recorded")
})

test_that("update_manifest records n_cols, schema_sha256 and role", {
  dir <- withr::local_tempdir()
  f <- file.path(dir, "d.csv")
  write.csv(data.frame(a = 1:3, b = 4:6), f, row.names = FALSE)
  side <- file.path(dir, "d.schema.csv")
  write.csv(dataset_schema(data.frame(a = 1:3, b = 4:6)), side, row.names = FALSE)
  mp <- file.path(dir, "manifest.yaml")

  expected_schema_sha <- digest::digest(side, algo = "sha256", file = TRUE)
  update_manifest(f, manifest_path = mp, n_cols = 2L,
                  schema_sha256 = expected_schema_sha)

  m <- yaml::read_yaml(mp)
  expect_equal(m$datasets[[1]]$n_cols, 2L)
  expect_equal(m$datasets[[1]]$role, "source")
  expect_equal(m$datasets[[1]]$schema_sha256, expected_schema_sha)
})

test_that("update_manifest rejects role = \"primary\"", {
  # A promoted entry's sha256 must describe its parquet, not the source this
  # function hashes -- writing role = "primary" here would produce a
  # manifest entry that can never verify (verify_manifest() hashes the
  # parquet for a primary entry). No exported function performs promotion;
  # .update_promoted_entry() is what maintains a promoted entry once one
  # exists.
  dir <- withr::local_tempdir()
  f <- file.path(dir, "d.csv")
  write.csv(data.frame(a = 1:3), f, row.names = FALSE)
  mp <- file.path(dir, "manifest.yaml")

  expect_error(
    update_manifest(f, manifest_path = mp, role = "primary"),
    "primary"
  )
  expect_false(file.exists(mp))
})

test_that("update_manifest records reader when supplied", {
  dir <- withr::local_tempdir()
  f <- file.path(dir, "d.csv")
  write.csv(data.frame(a = 1:3), f, row.names = FALSE)
  mp <- file.path(dir, "manifest.yaml")

  update_manifest(f, manifest_path = mp, reader = "haven 2.5.5")

  m <- yaml::read_yaml(mp)
  expect_equal(m$datasets[[1]]$reader, "haven 2.5.5")
})

test_that("update_manifest omits reader when not supplied", {
  dir <- withr::local_tempdir()
  f <- file.path(dir, "d.csv")
  write.csv(data.frame(a = 1:3), f, row.names = FALSE)
  mp <- file.path(dir, "manifest.yaml")

  update_manifest(f, manifest_path = mp)

  m <- yaml::read_yaml(mp)
  expect_null(m$datasets[[1]]$reader)
})

test_that(".atomic_write() cleans up after a rename failure, for any writer, not just parquet", {
  # update_manifest()'s manifest write and the parquet cache's sidecar write
  # both go through this same helper (Change 4 generalises
  # .write_parquet_atomic()'s temp-and-rename discipline into it). This
  # proves the generalization directly, with a non-parquet payload.
  #
  # local_mocked_bindings() cannot stub file.rename(): it is called
  # unqualified from base, not as an explicit import, so there is no binding
  # for the mock to find. The rename is instead made to fail the way the OS
  # itself reports a failure: renaming a file onto an existing directory
  # returns FALSE (with a warning) rather than erroring.
  dir <- withr::local_tempdir()
  target <- file.path(dir, "manifest.yaml")
  dir.create(target)                       # occupies the rename target

  suppressWarnings(
    expect_error(
      hvtiRutilities:::.atomic_write(target,
                                     function(tmp) writeLines("a: 1", tmp)),
      "move"
    )
  )
  expect_true(dir.exists(target))          # untouched -- still a directory
  tmp_residue <- list.files(dir, pattern = "\\.tmp$", full.names = TRUE)
  expect_length(tmp_residue, 0)
})

test_that("update_manifest rejects an unknown role", {
  dir <- withr::local_tempdir()
  f <- file.path(dir, "d.csv")
  write.csv(data.frame(a = 1), f, row.names = FALSE)

  expect_error(
    update_manifest(f, manifest_path = file.path(dir, "manifest.yaml"),
                    role = "authoritative"),
    "should be one of"
  )
})

test_that("verify_manifest hashes the parquet, not the source, for a role: primary entry", {
  # Task 5c, item 5: `file` never changes on promotion, so which physical
  # file sha256 describes cannot be inferred from the name -- only from
  # `role`. A missing source is also expected once role is "primary": the
  # source was retired on purpose, so its absence must not fail here.
  skip_if_not_installed("arrow")
  dir <- withr::local_tempdir()
  f   <- file.path(dir, "d.sas7bdat")
  suppressWarnings(haven::write_sas(data.frame(a = 1:3), f))
  mp  <- file.path(dir, "manifest.yaml")
  update_manifest(f, manifest_path = mp, n_cols = 1L, n_rows = 3L)

  parquet <- file.path(dir, "d.parquet")
  arrow::write_parquet(data.frame(a = 1:3), parquet)
  parquet_sha <- digest::digest(parquet, algo = "sha256", file = TRUE)

  m <- yaml::read_yaml(mp)
  m$datasets[[1]]$role   <- "primary"
  m$datasets[[1]]$sha256 <- parquet_sha
  yaml::write_yaml(m, mp)

  file.remove(f)                                   # the retired source

  res <- verify_manifest(mp, stop_on_error = FALSE)
  expect_equal(res$status[1], "OK")
})

test_that("verify_manifest fails a role: primary entry when the parquet's hash doesn't match", {
  skip_if_not_installed("arrow")
  dir <- withr::local_tempdir()
  f   <- file.path(dir, "d.sas7bdat")
  suppressWarnings(haven::write_sas(data.frame(a = 1:3), f))
  mp  <- file.path(dir, "manifest.yaml")
  update_manifest(f, manifest_path = mp, n_cols = 1L, n_rows = 3L)

  parquet <- file.path(dir, "d.parquet")
  arrow::write_parquet(data.frame(a = 1:3), parquet)

  m <- yaml::read_yaml(mp)
  m$datasets[[1]]$role   <- "primary"
  m$datasets[[1]]$sha256 <- strrep("0", 64)         # deliberately wrong
  yaml::write_yaml(m, mp)

  res <- verify_manifest(mp, stop_on_error = FALSE)
  expect_equal(res$status[1], "FAIL")
  expect_match(res$message[1], "mismatch")
})

test_that("verify_manifest still fails a role: source entry with a missing file", {
  # The companion to the two tests above: a missing source is only expected
  # once the entry is promoted. A `role: "source"` entry (the default) with
  # no file on disk is still a genuine failure.
  dir <- withr::local_tempdir()
  f   <- file.path(dir, "d.csv")
  write.csv(data.frame(a = 1:3), f, row.names = FALSE)
  mp  <- file.path(dir, "manifest.yaml")
  update_manifest(f, manifest_path = mp, n_cols = 1L)
  file.remove(f)

  res <- verify_manifest(mp, stop_on_error = FALSE)
  expect_equal(res$status[1], "FAIL")
  expect_match(res$message[1], "not found")
})

test_that("verify_manifest fails when a role: primary entry's parquet is missing", {
  dir <- withr::local_tempdir()
  f   <- file.path(dir, "d.sas7bdat")
  suppressWarnings(haven::write_sas(data.frame(a = 1:3), f))
  mp  <- file.path(dir, "manifest.yaml")
  update_manifest(f, manifest_path = mp, n_cols = 1L, n_rows = 3L)

  m <- yaml::read_yaml(mp)
  m$datasets[[1]]$role <- "primary"
  yaml::write_yaml(m, mp)
  # no d.parquet ever written

  res <- verify_manifest(mp, stop_on_error = FALSE)
  expect_equal(res$status[1], "FAIL")
  expect_match(res$message[1], "d\\.parquet")
})

test_that("verify_manifest fails when the sidecar has been edited", {
  dir <- withr::local_tempdir()
  f <- file.path(dir, "d.csv")
  write.csv(data.frame(a = 1:3), f, row.names = FALSE)
  side <- file.path(dir, "d.schema.csv")
  write.csv(dataset_schema(data.frame(a = 1:3)), side, row.names = FALSE)
  mp <- file.path(dir, "manifest.yaml")
  update_manifest(f, manifest_path = mp, n_cols = 1L,
                  schema_sha256 = digest::digest(side, algo = "sha256", file = TRUE))

  cat("tampered\n", file = side, append = TRUE)

  res <- verify_manifest(mp, stop_on_error = FALSE)
  expect_true(any(res$status == "FAIL"))
  # "Schema" alone also matches the "sidecar not found" branch; an
  # implementation that only checked file.exists() and never hashed would
  # pass that weaker assertion. "mismatch" only appears once the sidecar's
  # hash was actually recomputed and compared.
  expect_match(paste(res$message, collapse = " "), "mismatch")
})

test_that("verify_manifest reports two entries claiming the same derived paths", {
  dir <- withr::local_tempdir()
  write.csv(data.frame(a = 1), file.path(dir, "built.csv"), row.names = FALSE)
  saveRDS(data.frame(a = 1), file.path(dir, "built.rds"))
  mp <- file.path(dir, "manifest.yaml")
  update_manifest(file.path(dir, "built.csv"), manifest_path = mp, n_cols = 1L)
  update_manifest(file.path(dir, "built.rds"), manifest_path = mp, n_cols = 1L,
                  n_rows = 1L)
  # The collision only fires once one of the two entries has actually
  # produced a derived artifact the other would overwrite; a plain
  # "same stem" pair with nothing derived yet must not fail (see the
  # "two entries sharing a stem with no derived artifact" test below).
  # An empty sidecar is enough to make the contention real.
  file.create(file.path(dir, "built.schema.csv"))

  res <- verify_manifest(mp, stop_on_error = FALSE)
  expect_match(paste(res$message, collapse = " "), "derived path")
  collisions <- res[grepl("derived path", res$message), , drop = FALSE]
  expect_equal(nrow(collisions), 1L)
  expect_equal(collisions$status, "FAIL")
})

test_that("verify_manifest finds datasets in datasets/ without an explicit data_dir", {
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "datasets"))
  f <- file.path(dir, "datasets", "d.csv")
  write.csv(data.frame(a = 1:3), f, row.names = FALSE)
  mp <- file.path(dir, "manifest.yaml")
  update_manifest(f, manifest_path = mp, n_cols = 1L)

  res <- verify_manifest(mp, stop_on_error = FALSE)

  expect_equal(res$status, "OK")
})

test_that("verify_manifest still resolves alongside the manifest when there is no datasets/", {
  dir <- withr::local_tempdir()
  f <- file.path(dir, "d.csv")
  write.csv(data.frame(a = 1:3), f, row.names = FALSE)
  mp <- file.path(dir, "manifest.yaml")
  update_manifest(f, manifest_path = mp, n_cols = 1L)

  res <- verify_manifest(mp, stop_on_error = FALSE)

  expect_equal(res$status, "OK")
})

# Regression: a flat-layout study whose manifest legitimately references files
# beside the manifest, but which also happens to have a datasets/ directory
# (here, empty), must still verify OK. Choosing data_dir on directory
# existence alone would send every lookup into the unrelated datasets/ and
# fail every entry even though the data is intact.
test_that("verify_manifest verifies OK for a flat layout that also has an empty datasets/", {
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "datasets"))
  f <- file.path(dir, "flat.csv")
  write.csv(data.frame(a = 1:3), f, row.names = FALSE)
  mp <- file.path(dir, "manifest.yaml")
  update_manifest(f, manifest_path = mp, n_cols = 1L)

  res <- verify_manifest(mp, stop_on_error = FALSE)

  expect_equal(res$status, "OK")
})

# Regression: a manifest listing both a source and an export of it sharing a
# stem (e.g. cohort.sas7bdat and cohort.csv) has always been legal. With no
# derived artifact (.parquet or .schema.csv) yet on disk, the two entries are
# not contending for anything, so verification must pass rather than abort at
# the default stop_on_error = TRUE.
test_that("verify_manifest passes two entries sharing a stem when no derived artifact exists", {
  dir <- withr::local_tempdir()
  write.csv(data.frame(a = 1), file.path(dir, "cohort.csv"), row.names = FALSE)
  saveRDS(data.frame(a = 1), file.path(dir, "cohort.rds"))
  mp <- file.path(dir, "manifest.yaml")
  update_manifest(file.path(dir, "cohort.csv"), manifest_path = mp, n_cols = 1L)
  update_manifest(file.path(dir, "cohort.rds"), manifest_path = mp, n_cols = 1L,
                  n_rows = 1L)

  res <- verify_manifest(mp, stop_on_error = FALSE)

  expect_true(all(res$status == "OK"))
})
