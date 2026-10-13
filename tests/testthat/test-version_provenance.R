test_that("a version with no provenance row reads as legacy", {
  m <- list(datasets = list())
  expect_identical(.version_provenance(m, "built_20260915.parquet"), list(origin = "legacy"))
  m$provenance <- list(built_20260915.parquet = list(origin = "bd", build = list(job = "00_datasets/bd.qmd")))
  expect_identical(.version_provenance(m, "built_20260915.parquet")$origin, "bd")
})

test_that("setting a row keeps the others", {
  m <- .set_version_provenance(list(), "a_20260101.parquet", .legacy_row())
  m <- .set_version_provenance(m, "a_20260102.parquet", list(origin = "bd"))
  expect_identical(names(m$provenance), c("a_20260101.parquet", "a_20260102.parquet"))
})

test_that("registration and update write a legacy row for every new version", {
  root <- versioned_study()
  m <- .read_manifest(file.path(root, "manifest.yaml"))
  expect_identical(m$provenance$built_20260915.parquet, list(origin = "legacy"))

  path <- file.path(study_dir("datasets", root), "built.csv")
  utils::write.csv(data.frame(id = 1:4, DEAD = c(1L, 0L, 0L, 1L)), path, row.names = FALSE)
  withr::with_dir(root, suppressMessages(update_manifest(extract_date = "2026-10-01")))
  m <- .read_manifest(file.path(root, "manifest.yaml"))
  expect_identical(m$provenance$built_20261001.parquet, list(origin = "legacy"))
  expect_identical(m$provenance$built_20260915.parquet, list(origin = "legacy"))
})

test_that("an older reader's rewrite keeps the map and adds no row", {
  # 1.5.2 reads the whole manifest, replaces $datasets and writes it back.
  root <- versioned_study()
  mp <- file.path(root, "manifest.yaml")
  m <- .read_manifest(mp)
  m$provenance$built_20260915.parquet <- list(origin = "bd", build = list(job = "00_datasets/bd.qmd"))
  .write_manifest(m, mp)
  old_style <- yaml::read_yaml(mp)
  old_style$datasets <- Filter(Negate(is.character), old_style$datasets)
  old_style$datasets[[1]]$parquet <- "built_20261001.parquet"
  yaml::write_yaml(old_style, mp)
  m <- .read_manifest(mp)
  expect_identical(.version_provenance(m, "built_20260915.parquet")$origin, "bd")
  expect_identical(.version_provenance(m, "built_20261001.parquet")$origin, "legacy")
})

test_that("a matching sidecar makes a bd version and moves beside its parquet", {
  s <- unregistered_study()
  write_build_sidecar(s$src)
  suppressMessages(register_data(s$root, "built.csv"))
  dir <- dirname(s$src)
  expect_false(file.exists(.build_sidecar_path(s$src)))
  expect_true(file.exists(file.path(dir, "built_20260915.build.yml")))
  row <- .version_provenance(.read_manifest(file.path(s$root, "manifest.yaml")), "built_20260915.parquet")
  expect_identical(row$origin, "bd")
  expect_identical(row$build$record, "built_20260915.build.yml")
  expect_identical(row$build$record_sha256,
                   digest::digest(file.path(dir, "built_20260915.build.yml"), algo = "sha256", file = TRUE))
  expect_identical(row$build$view, "cardiac_master_v")
  expect_null(row$build$attrition)
})

test_that("no sidecar gives legacy", {
  s <- unregistered_study()
  suppressMessages(register_data(s$root, "built.csv"))
  row <- .version_provenance(.read_manifest(file.path(s$root, "manifest.yaml")), "built_20260915.parquet")
  expect_identical(row, list(origin = "legacy"))
})

test_that("a sidecar for other bytes gives legacy, says so, and stays put", {
  s <- unregistered_study()
  side <- write_build_sidecar(s$src, built_sha256 = strrep("0", 64))
  expect_message(register_data(s$root, "built.csv"), "describes a different built.csv")
  expect_true(file.exists(side))
  row <- .version_provenance(.read_manifest(file.path(s$root, "manifest.yaml")), "built_20260915.parquet")
  expect_identical(row$origin, "legacy")
})

test_that("an invalid or underived matching record stops and writes nothing", {
  s <- unregistered_study()
  dir <- dirname(s$src)
  before <- sort(list.files(dir))
  side <- write_build_sidecar(s$src, view = NULL)
  expect_error(register_data(s$root, "built.csv"), "missing view")
  expect_identical(sort(list.files(dir)), before |> c(basename(side)) |> sort())
  expect_false(file.exists(file.path(s$root, "manifest.yaml")))

  write_build_sidecar(s$src, derived_after_overlay = FALSE)
  expect_error(register_data(s$root, "built.csv"), "derivations were not recomputed")
  expect_identical(sort(list.files(dir)), before |> c(basename(side)) |> sort())
})

test_that("update_manifest claims a sidecar for a rebuild and keeps it on failure", {
  root <- versioned_study()
  src <- file.path(study_dir("datasets", root), "built.csv")
  utils::write.csv(data.frame(id = 1:4, DEAD = c(1L, 0L, 0L, 1L)), src, row.names = FALSE)
  write_build_sidecar(src)
  withr::with_dir(root, suppressMessages(update_manifest(extract_date = "2026-10-01")))
  m <- .read_manifest(file.path(root, "manifest.yaml"))
  expect_identical(.version_provenance(m, "built_20261001.parquet")$origin, "bd")
  expect_identical(.version_provenance(m, "built_20260915.parquet")$origin, "legacy")
})

test_that("a failed manifest write renames the record back to its sidecar", {
  root <- versioned_study()
  src <- file.path(study_dir("datasets", root), "built.csv")
  utils::write.csv(data.frame(id = 1:4, DEAD = c(1L, 0L, 0L, 1L)), src, row.names = FALSE)
  side <- write_build_sidecar(src)
  local_mocked_bindings(.write_manifest = function(manifest, path) stop("disk full"))
  expect_error(withr::with_dir(root, update_manifest(extract_date = "2026-10-01")), "disk full")
  expect_true(file.exists(side))
  expect_false(file.exists(file.path(dirname(src), "built_20261001.build.yml")))
  expect_false(file.exists(file.path(dirname(src), "built_20261001.parquet")))
})

test_that("a record with no built_sha256 is malformed, not stale", {
  s <- unregistered_study()
  write_build_sidecar(s$src, built_sha256 = NULL)
  expect_error(register_data(s$root, "built.csv"), "built_sha256 must be a SHA-256")
  expect_false(file.exists(file.path(s$root, "manifest.yaml")))
})

test_that("as_of must be a whole, real timestamp", {
  expect_true(.is_iso_timestamp("2026-10-01T00:00:00Z"))
  expect_true(.is_iso_timestamp("2026-10-01T08:30:00.5-04:00"))
  for (bad in c("2026-99-99Tgarbage", "2026-02-30T00:00:00Z", "2026-10-01T25:00:00Z", "2026-10-01", NA)) {
    expect_false(.is_iso_timestamp(bad), info = bad)
  }
})

test_that("a sidecar rewritten during registration is put back and nothing is registered", {
  s <- unregistered_study()
  side <- write_build_sidecar(s$src)
  local_mocked_bindings(.registration_rename = function(from, to) {
    ok <- file.rename(from, to)
    if (identical(basename(from), "built.build.yml")) cat("view: other\n", file = to, append = TRUE)
    ok
  })
  expect_error(register_data(s$root, "built.csv"), "changed while it was being registered")
  expect_true(file.exists(side))
  expect_false(file.exists(file.path(s$root, "manifest.yaml")))
})

test_that("a new version never takes a recorded record's name", {
  expect_true("x_20260915.build.yml" %in% .recorded_version_names(list(list(file = "x.csv", parquet = "x_20260915.parquet"))))
})

test_that("migration claims a sidecar for the new version and leaves the recovered one legacy", {
  root <- legacy_with_cache()
  rebuild_source(root, data.frame(id = 1:5, dead = c(1L, 0L, 0L, 0L, 1L), iv_dead = 1:5))
  src <- file.path(study_dir("datasets", root), "built.csv")
  write_build_sidecar(src)
  withr::local_dir(root)
  suppressMessages(update_manifest())
  m <- .read_manifest(file.path(root, "manifest.yaml"))
  e <- manifest_entry_for(root)
  expect_identical(.version_provenance(m, e$parquet)$origin, "bd")
  expect_identical(.version_provenance(m, e$history[[1L]]$parquet)$origin, "legacy")
  expect_false(file.exists(.build_sidecar_path(src)))
  expect_true(file.exists(file.path(dirname(src), .version_record_name(e$parquet))))
})

test_that("a migration whose manifest write fails restores the cache and the sidecar", {
  root <- legacy_with_cache()
  data_dir <- study_dir("datasets", root)
  cache <- file.path(data_dir, c("built.parquet", "built.schema.csv"))
  rebuild_source(root, data.frame(id = 1:5, dead = c(1L, 0L, 0L, 0L, 1L), iv_dead = 1:5))
  side <- write_build_sidecar(file.path(data_dir, "built.csv"))
  withr::local_dir(root)
  local_mocked_bindings(.write_manifest = function(manifest, path) stop("disk full"))
  expect_error(suppressMessages(update_manifest()), "disk full")
  expect_true(all(file.exists(cache)))
  expect_true(file.exists(side))
  expect_identical(list.files(data_dir, pattern = "_2026"), character())
})

test_that("register_data puts the sidecar back when a later step fails", {
  s <- unregistered_study()
  side <- write_build_sidecar(s$src)
  local_mocked_bindings(.replace_study_pair = function(...) stop("rename failed"))
  expect_error(suppressMessages(register_data(s$root, "built.csv")), "rename failed")
  expect_true(file.exists(side))
  expect_identical(list.files(dirname(s$src), pattern = "^built_"), character())
})
