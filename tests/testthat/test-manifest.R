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

test_that("update_manifest [SAS] creates entry with correct row count", {
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
