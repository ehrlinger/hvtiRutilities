write_source_csv <- function(dir, data = data.frame(id = 1:3, x = c(1.5, 2.5, 3.5)), file = "built.csv") {
  path <- file.path(dir, file)
  utils::write.csv(data, path, row.names = FALSE)
  path
}

test_that("version names are dated and take the next free revision", {
  dir <- withr::local_tempdir()
  expect_identical(.version_filename("built", "2026-10-07", dir), "built_20261007.parquet")
  expect_identical(.version_filename("built", "2026-10-07", dir, taken = "built_20261007.parquet"),
                   "built_20261007_r2.parquet")
  file.create(file.path(dir, c("built_20261007.parquet", "built_20261007_r2.schema.csv")))
  expect_identical(.version_filename("built", "2026-10-07", dir), "built_20261007_r3.parquet")
  expect_identical(.version_schema_name("built_20261007_r3.parquet"), "built_20261007_r3.schema.csv")
})

test_that(".write_version converts once and records the version", {
  skip_if_not_installed("arrow")
  dir <- withr::local_tempdir()
  src <- write_source_csv(dir)

  v <- .write_version(src, dir, "2026-10-07")

  expect_identical(v$parquet, "built_20261007.parquet")
  expect_true(file.exists(file.path(dir, "built_20261007.parquet")))
  expect_true(file.exists(file.path(dir, "built_20261007.schema.csv")))
  expect_identical(v$extract_date, "2026-10-07")
  expect_identical(v$n_rows, 3L)
  expect_identical(v$n_cols, 2L)
  expect_identical(v$sha256, digest::digest(file.path(dir, v$parquet), algo = "sha256", file = TRUE))
  expect_identical(v$source_sha256, digest::digest(src, algo = "sha256", file = TRUE))
  expect_identical(v$schema_sha256,
                   digest::digest(file.path(dir, "built_20261007.schema.csv"), algo = "sha256", file = TRUE))
  expect_true(all(c("source_size", "source_mtime") %in% names(v)))

  v2 <- .write_version(src, dir, "2026-10-07", taken = v$parquet)
  expect_identical(v2$parquet, "built_20261007_r2.parquet")
})

test_that(".write_version stops before writing anything when arrow is absent", {
  dir <- withr::local_tempdir()
  src <- write_source_csv(dir)
  local_mocked_bindings(.arrow_available = function() FALSE)

  expect_error(.write_version(src, dir, "2026-10-07"), "install.packages(\"arrow\")", fixed = TRUE)
  expect_identical(list.files(dir), "built.csv")
})

test_that("the authoritative path follows the entry", {
  src <- file.path("study", "datasets", "built.sas7bdat")
  expect_identical(.authoritative_path(list(parquet = "built_20261007.parquet"), src),
                   file.path("study", "datasets", "built_20261007.parquet"))
  expect_identical(.authoritative_path(list(role = "primary"), src), file.path("study", "datasets", "built.parquet"))
  expect_identical(.authoritative_path(list(role = "source"), src), src)
})

test_that("a changed source is detected and an untouched one is not", {
  skip_if_not_installed("arrow")
  dir <- withr::local_tempdir()
  src <- write_source_csv(dir)
  entry <- .versioned_entry("built.csv", .write_version(src, dir, "2026-10-07"))

  expect_false(.source_changed(src, entry))
  write_source_csv(dir, data.frame(id = 1:4, x = c(1.5, 2.5, 3.5, 4.5)))
  expect_true(.source_changed(src, entry))
  unlink(src)
  expect_false(.source_changed(src, entry))
})

test_that("the source-changed condition names the fix and carries both classes", {
  cond <- .source_changed_condition(list(file = "built.sas7bdat", extract_date = "2026-10-07",
                                         parquet = "built_20261007.parquet"))
  expect_s3_class(cond, "hvtiRutilities_source_changed")
  expect_s3_class(cond, "hvtiRutilities_out_of_date")
  expect_match(conditionMessage(cond), "update_manifest()", fixed = TRUE)
  expect_match(conditionMessage(cond), "built_20261007.parquet", fixed = TRUE)
})

test_that("a versioned entry keeps extra fields and history, and history drops the stamp", {
  v <- list(parquet = "b_20261007.parquet", sha256 = "a", source_sha256 = "b", extract_date = "2026-10-07",
            n_rows = 1L, n_cols = 1L, schema_sha256 = "c", source_size = 1, source_mtime = "x")
  e <- .versioned_entry("b.csv", v, extra = list(sort_key = "id"), history = list(list(parquet = "b_20260915.parquet")))
  expect_identical(e$file, "b.csv")
  expect_identical(e$role, "primary")
  expect_identical(e$sort_key, "id")
  expect_length(e$history, 1L)
  expect_false(any(c("source_size", "source_mtime") %in% names(.history_record(e))))
})

# A registered study whose source was last modified on 2026-09-15.
versioned_study <- function(env = parent.frame(), data = data.frame(id = 1:3, DEAD = c(1L, 0L, 0L))) {
  testthat::skip_if_not_installed("arrow")
  root <- file.path(withr::local_tempdir(.local_envir = env), "study")
  suppressMessages(study_setup(root, "Versioned fixture", 42L))
  path <- file.path(study_dir("datasets", root), "built.csv")
  utils::write.csv(data, path, row.names = FALSE)
  Sys.setFileTime(path, as.POSIXct("2026-09-15 12:00:00", tz = "UTC"))
  suppressMessages(register_data(root, "built.csv"))
  root
}

manifest_entry_for <- function(root, file = "built.csv") {
  m <- yaml::read_yaml(file.path(root, "manifest.yaml"))
  Filter(function(e) identical(e$file, file), m$datasets)[[1L]]
}

test_that("register_data converts the dataset to a dated parquet", {
  root <- versioned_study()
  data_dir <- study_dir("datasets", root)
  e <- manifest_entry_for(root)

  expect_identical(e$role, "primary")
  expect_identical(e$parquet, "built_20260915.parquet")
  expect_identical(e$extract_date, "2026-09-15")
  expect_true(file.exists(file.path(data_dir, "built_20260915.parquet")))
  expect_true(file.exists(file.path(data_dir, "built_20260915.schema.csv")))
  expect_identical(e$sha256, digest::digest(file.path(data_dir, e$parquet), algo = "sha256", file = TRUE))
  expect_identical(e$source_sha256, digest::digest(file.path(data_dir, "built.csv"), algo = "sha256", file = TRUE))
  expect_identical(e$n_rows, 3L)
  expect_null(e$history)
})

test_that("a parquet source is registered the same way, and is never the copy jobs read", {
  skip_if_not_installed("arrow")
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Parquet source", 42L))
  data_dir <- study_dir("datasets", root)
  src <- file.path(data_dir, "built.parquet")
  arrow::write_parquet(data.frame(id = 1:3, dead = c(1L, 0L, 0L)), src)
  Sys.setFileTime(src, as.POSIXct("2026-09-15 12:00:00", tz = "UTC"))
  before <- digest::digest(src, algo = "sha256", file = TRUE)

  suppressMessages(register_data(root, "built.parquet"))

  e <- manifest_entry_for(root, "built.parquet")
  expect_identical(e$parquet, "built_20260915.parquet")
  expect_identical(e$source_sha256, before)
  expect_identical(digest::digest(src, algo = "sha256", file = TRUE), before)
  expect_true(file.exists(file.path(data_dir, "built_20260915.parquet")))
  expect_match(provenance_data(cfg = study_config(root))$path, "built_20260915[.]parquet$")
})

test_that("a source already named with a date gets its own version name and is never overwritten", {
  skip_if_not_installed("arrow")
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Dated source", 42L))
  src <- file.path(study_dir("datasets", root), "built_20261007.parquet")
  arrow::write_parquet(data.frame(id = 1:2), src)
  Sys.setFileTime(src, as.POSIXct("2026-10-07 12:00:00", tz = "UTC"))
  before <- digest::digest(src, algo = "sha256", file = TRUE)

  suppressMessages(register_data(root, "built_20261007.parquet"))

  e <- manifest_entry_for(root, "built_20261007.parquet")
  expect_false(identical(e$parquet, "built_20261007.parquet"))
  expect_identical(digest::digest(src, algo = "sha256", file = TRUE), before)
})

test_that("register_data without arrow stops and writes nothing", {
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "No arrow", 42L))
  path <- file.path(study_dir("datasets", root), "built.csv")
  utils::write.csv(data.frame(id = 1:2), path, row.names = FALSE)
  before <- yaml::read_yaml(file.path(root, "_study.yml"))
  local_mocked_bindings(.arrow_available = function() FALSE)

  expect_error(register_data(root, "built.csv"), "install.packages(\"arrow\")", fixed = TRUE)
  expect_identical(yaml::read_yaml(file.path(root, "_study.yml")), before)
  expect_identical(list.files(study_dir("datasets", root)), "built.csv")
})

test_that("a registration refused after conversion leaves no parquet behind", {
  root <- versioned_study()
  # Registering the same file again under another name passes the early checks,
  # converts it (to built_20260915_r2.parquet), then is refused because the file
  # is already listed in manifest.yaml. The conversion must be cleaned up.
  expect_error(register_data(root, "built.csv", dataset = "again", role = "named"), "already listed")
  expect_identical(list.files(study_dir("datasets", root), pattern = "[.]parquet$"), "built_20260915.parquet")
})

test_that("read_built reads the registered version and says when the source moved on", {
  root <- versioned_study()
  cfg <- study_config(root)

  expect_no_message(d <- read_built(cfg))
  expect_identical(names(d), c("id", "dead"))
  expect_identical(nrow(d), 3L)

  utils::write.csv(data.frame(id = 1:4, DEAD = c(1L, 1L, 0L, 0L)), built_path(cfg), row.names = FALSE)
  expect_message(d <- read_built(cfg), class = "hvtiRutilities_source_changed")
  expect_identical(nrow(d), 3L)
})

test_that("read_built stops on an edited or missing registered version", {
  root <- versioned_study()
  cfg <- study_config(root)
  parquet <- file.path(study_dir("datasets", root), "built_20260915.parquet")

  cat("tamper", file = parquet, append = TRUE)
  expect_error(read_built(cfg), "does not match its recorded checksum")
  unlink(parquet)
  expect_error(read_built(cfg), "Restore it from backup")
})

test_that("refresh does not apply to a registered version and names update_manifest()", {
  root <- versioned_study()
  expect_error(read_built(study_config(root), refresh = TRUE), "update_manifest()", fixed = TRUE)
})

test_that("provenance records the registered parquet, not the source", {
  root <- versioned_study()
  rec <- provenance_data(cfg = study_config(root))
  expect_match(rec$path, "built_20260915[.]parquet$")
})

test_that("verify_manifest checks the version and treats a rebuilt source as pending", {
  root <- versioned_study()
  cfg <- study_config(root)
  manifest <- file.path(root, "manifest.yaml")

  rep <- verify_manifest(manifest)
  expect_identical(rep$status, "OK")

  utils::write.csv(data.frame(id = 1:4, DEAD = c(1L, 1L, 0L, 0L)), built_path(cfg), row.names = FALSE)
  expect_no_error(rep <- verify_manifest(manifest))
  expect_identical(rep$status, c("OK", "PENDING"))
  expect_match(rep$message[[2L]], "update_manifest()", fixed = TRUE)
})

test_that("verify_manifest stops on an edited version with the restore message", {
  root <- versioned_study()
  cat("tamper", file = file.path(study_dir("datasets", root), "built_20260915.parquet"), append = TRUE)
  expect_error(verify_manifest(file.path(root, "manifest.yaml")), "restore it from backup")
})

test_that("verify_manifest finds the study's manifest from a subfolder", {
  root <- versioned_study()
  withr::local_dir(study_dir("datasets", root))
  expect_identical(verify_manifest()$status, "OK")
})

test_that("a legacy checksum mismatch names update_manifest()", {
  root <- make_legacy_registered_study(withr::local_tempdir())
  path <- file.path(study_dir("datasets", root), "built.csv")
  utils::write.csv(data.frame(id = 1:9), path, row.names = FALSE)
  expect_error(verify_manifest(file.path(root, "manifest.yaml")), "update_manifest()", fixed = TRUE)
})

test_that("study_status reports a rebuilt source as pending, not failed", {
  root <- versioned_study()
  utils::write.csv(data.frame(id = 1:4, DEAD = c(1L, 1L, 0L, 0L)), built_path(study_config(root)), row.names = FALSE)
  st <- study_status(root)
  row <- st$checks[st$checks$item == "manifest.yaml", , drop = FALSE]
  expect_identical(row$status, "PENDING")
  expect_match(row$detail, "update_manifest()", fixed = TRUE)
})

rebuild_source <- function(root, data = data.frame(id = 1:4, DEAD = c(1L, 1L, 0L, 0L)), when = "2026-10-07 12:00:00") {
  path <- built_path(study_config(root))
  utils::write.csv(data, path, row.names = FALSE)
  Sys.setFileTime(path, as.POSIXct(when, tz = "UTC"))
  path
}

test_that("update_manifest() outside a study says what it looked for", {
  withr::local_dir(withr::local_tempdir())
  expect_error(update_manifest(), "found none", fixed = TRUE)
  expect_error(update_manifest(), "update_manifest(\"path/to/file\")", fixed = TRUE)
})

test_that("update_manifest() with nothing changed writes nothing", {
  root <- versioned_study()
  before <- readLines(file.path(root, "manifest.yaml"))
  withr::local_dir(root)

  expect_message(out <- update_manifest(), "unchanged")
  expect_identical(out$action, "unchanged")
  expect_identical(readLines(file.path(root, "manifest.yaml")), before)
})

test_that("update_manifest() registers a rebuilt source and keeps the old version", {
  root <- versioned_study()
  rebuild_source(root)
  withr::local_dir(study_dir("datasets", root))

  expect_message(out <- update_manifest(), "previous version kept as built_20260915.parquet", fixed = TRUE)
  expect_identical(out$action, "registered")

  e <- manifest_entry_for(root)
  expect_identical(e$parquet, "built_20261007.parquet")
  expect_identical(e$history[[1L]]$parquet, "built_20260915.parquet")
  expect_true(file.exists(file.path(study_dir("datasets", root), "built_20260915.parquet")))
  expect_identical(verify_manifest()$status, c("OK", "OK"))
  expect_no_message(d <- read_built(study_config(root)))
  expect_identical(nrow(d), 4L)
})

test_that("a rebuilt parquet source is updated the same way", {
  skip_if_not_installed("arrow")
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Parquet update", 42L))
  src <- file.path(study_dir("datasets", root), "built.parquet")
  arrow::write_parquet(data.frame(id = 1:3), src)
  Sys.setFileTime(src, as.POSIXct("2026-09-15 12:00:00", tz = "UTC"))
  suppressMessages(register_data(root, "built.parquet"))
  arrow::write_parquet(data.frame(id = 1:4), src)
  Sys.setFileTime(src, as.POSIXct("2026-10-07 12:00:00", tz = "UTC"))
  withr::local_dir(root)

  suppressMessages(update_manifest())

  e <- manifest_entry_for(root, "built.parquet")
  expect_identical(e$parquet, "built_20261007.parquet")
  expect_identical(e$history[[1L]]$parquet, "built_20260915.parquet")
  expect_true(file.exists(src))
  expect_identical(nrow(read_built(study_config(root))), 4L)
})

test_that("a second update on the same date takes the next revision", {
  root <- versioned_study()
  withr::local_dir(root)
  rebuild_source(root)
  suppressMessages(update_manifest())
  rebuild_source(root, data.frame(id = 1:5, DEAD = c(1L, 1L, 0L, 0L, 0L)), when = "2026-10-07 15:00:00")
  suppressMessages(update_manifest())

  e <- manifest_entry_for(root)
  expect_identical(e$parquet, "built_20261007_r2.parquet")
  expect_identical(vapply(e$history, `[[`, "", "parquet"), c("built_20261007.parquet", "built_20260915.parquet"))
})

test_that("update_manifest() keeps fields registration recorded", {
  skip_if_not_installed("arrow")
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Source field", 42L))
  path <- file.path(study_dir("datasets", root), "built.csv")
  utils::write.csv(data.frame(id = 1:2), path, row.names = FALSE)
  suppressMessages(register_data(root, "built.csv", source = "Synthetic"))
  utils::write.csv(data.frame(id = 1:3), path, row.names = FALSE)
  withr::local_dir(root)
  suppressMessages(update_manifest())
  expect_identical(manifest_entry_for(root)$source, "Synthetic")
})

test_that("update_manifest() refuses a release-aware dataset by name", {
  fx <- make_release_aware_study(withr::local_tempdir())
  withr::local_dir(fx$root)
  expect_error(update_manifest(dataset = "study"), "review_data_update()", fixed = TRUE)
})

test_that("update_manifest(file, ...) keeps its single-file behaviour", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "x.csv")
  utils::write.csv(data.frame(a = 1:2), path, row.names = FALSE)
  m <- update_manifest(path, manifest_path = file.path(dir, "manifest.yaml"), extract_date = "2026-10-07")
  expect_identical(m$datasets[[1L]]$file, "x.csv")
  expect_identical(m$datasets[[1L]]$role, "source")
})

test_that("update_manifest() in a study with no registered dataset names register_data()", {
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Empty study", 42L))
  withr::local_dir(root)
  expect_error(update_manifest(), "register_data()", fixed = TRUE)
})


test_that("migration converts an untouched source and drops the old cache", {
  root <- legacy_with_cache()
  withr::local_dir(root)

  expect_message(out <- update_manifest(), "migrated|registered")
  expect_identical(out$action, "migrated")
  e <- manifest_entry_for(root)
  expect_identical(e$parquet, "built_20260915.parquet")
  expect_null(e$history)
  expect_false(file.exists(file.path(study_dir("datasets", root), "built.parquet")))
})

test_that("migration after an overwrite recovers the old version from the cache", {
  root <- legacy_with_cache()
  rebuild_source(root, data.frame(id = 1:5, dead = c(1L, 0L, 0L, 0L, 1L), iv_dead = 1:5))
  withr::local_dir(root)

  expect_message(out <- update_manifest(), "recovered from the read cache", fixed = TRUE)
  e <- manifest_entry_for(root)
  expect_identical(e$parquet, "built_20261007.parquet")
  expect_identical(e$history[[1L]]$parquet, "built_20260915.parquet")
  expect_identical(e$history[[1L]]$recovered_from, "cache")
  expect_identical(verify_manifest()$status, c("OK", "OK"))
})

test_that("migrating a study whose source is built.parquet never touches the source", {
  skip_if_not_installed("arrow")
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Legacy parquet", 42L))
  src <- file.path(study_dir("datasets", root), "built.parquet")
  arrow::write_parquet(data.frame(id = 1:3), src)
  raw <- yaml::read_yaml(file.path(root, "_study.yml"))
  raw$built <- "built.parquet"
  yaml::write_yaml(raw, file.path(root, "_study.yml"))
  entry <- .registration_manifest_entry(src, data.frame(id = 1:3), "2026-09-15", NULL)
  yaml::write_yaml(list(datasets = list(entry)), file.path(root, "manifest.yaml"))
  withr::local_dir(root)

  # Unchanged: converted, and the source is left in place.
  suppressMessages(update_manifest())
  expect_true(file.exists(src))
  expect_identical(manifest_entry_for(root, "built.parquet")$parquet, "built_20260915.parquet")
})

test_that("an overwritten parquet source is not mistaken for a cache", {
  skip_if_not_installed("arrow")
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Legacy parquet overwritten", 42L))
  src <- file.path(study_dir("datasets", root), "built.parquet")
  arrow::write_parquet(data.frame(id = 1:3), src)
  raw <- yaml::read_yaml(file.path(root, "_study.yml"))
  raw$built <- "built.parquet"
  yaml::write_yaml(raw, file.path(root, "_study.yml"))
  # Make the overwritten source look exactly like a usable read cache: same
  # row and column counts, and a schema sidecar the entry records. Only the
  # parquet-source rule stops migration from renaming the source away.
  schema <- file.path(study_dir("datasets", root), "built.schema.csv")
  utils::write.csv(dataset_schema(data.frame(id = 1:3)), schema, row.names = FALSE)
  entry <- .registration_manifest_entry(src, data.frame(id = 1:3), "2026-09-15", NULL)
  entry$schema_sha256 <- digest::digest(schema, algo = "sha256", file = TRUE)
  yaml::write_yaml(list(datasets = list(entry)), file.path(root, "manifest.yaml"))
  arrow::write_parquet(data.frame(id = 4:6), src)
  Sys.setFileTime(src, as.POSIXct("2026-10-07 12:00:00", tz = "UTC"))
  withr::local_dir(root)

  expect_message(update_manifest(), "cannot be recovered", fixed = TRUE)
  expect_true(file.exists(src))
  expect_identical(arrow::read_parquet(src)$id, 4:6)
  expect_null(manifest_entry_for(root, "built.parquet")$history)
})

test_that("migration after an overwrite with no usable cache says the old version is gone", {
  skip_if_not_installed("arrow")
  root <- make_legacy_registered_study(withr::local_tempdir())
  rebuild_source(root, data.frame(id = 1:5, dead = c(1L, 0L, 0L, 0L, 1L), iv_dead = 1:5))
  withr::local_dir(root)

  expect_message(update_manifest(), "cannot be recovered", fixed = TRUE)
  e <- manifest_entry_for(root)
  expect_identical(e$parquet, "built_20261007.parquet")
  expect_null(e$history)
})

test_that("a migration that fails after recovering the cache puts the cache back", {
  root <- legacy_with_cache()
  data_dir <- study_dir("datasets", root)
  cache <- file.path(data_dir, c("built.parquet", "built.schema.csv"))
  before <- unname(tools::md5sum(cache))
  manifest_before <- readLines(file.path(root, "manifest.yaml"))
  rebuild_source(root, data.frame(id = 1:5, dead = c(1L, 0L, 0L, 0L, 1L), iv_dead = 1:5))
  withr::local_dir(root)
  local_mocked_bindings(.write_version = function(...) stop("conversion failed"))

  expect_error(update_manifest(), "conversion failed")
  expect_identical(unname(tools::md5sum(cache)), before)
  expect_false(file.exists(file.path(data_dir, "built_20260915.parquet")))
  expect_identical(readLines(file.path(root, "manifest.yaml")), manifest_before)
})

test_that("a migration that fails keeps the legacy cache of an untouched source", {
  root <- legacy_with_cache()
  cache <- file.path(study_dir("datasets", root), c("built.parquet", "built.schema.csv"))
  withr::local_dir(root)
  # Fail only the manifest write, after the new version has been converted.
  real_atomic_write <- .atomic_write
  local_mocked_bindings(.atomic_write = function(target, write_fn) {
    if (identical(basename(target), "manifest.yaml")) stop("disk full")
    real_atomic_write(target, write_fn)
  })

  expect_error(suppressMessages(update_manifest()), "disk full")
  expect_true(all(file.exists(cache)))
  expect_false(file.exists(file.path(study_dir("datasets", root), "built_20260915.parquet")))
})

test_that("a migration whose manifest write fails puts a recovered cache back", {
  root <- legacy_with_cache()
  data_dir <- study_dir("datasets", root)
  cache <- file.path(data_dir, c("built.parquet", "built.schema.csv"))
  before <- unname(tools::md5sum(cache))
  rebuild_source(root, data.frame(id = 1:5, dead = c(1L, 0L, 0L, 0L, 1L), iv_dead = 1:5))
  withr::local_dir(root)
  real_atomic_write <- .atomic_write
  local_mocked_bindings(.atomic_write = function(target, write_fn) {
    if (identical(basename(target), "manifest.yaml")) stop("disk full")
    real_atomic_write(target, write_fn)
  })

  expect_error(suppressMessages(update_manifest()), "disk full")
  expect_identical(unname(tools::md5sum(cache)), before)
  expect_identical(list.files(data_dir, pattern = "_2026"), character())
})

test_that("update_manifest(file, ...) refuses to flatten a registered dataset", {
  root <- versioned_study()
  before <- readLines(file.path(root, "manifest.yaml"))
  expect_error(update_manifest(built_path(study_config(root)), manifest_path = file.path(root, "manifest.yaml")),
               "with no arguments", fixed = TRUE)
  expect_identical(readLines(file.path(root, "manifest.yaml")), before)
})

test_that("the version date is the source's local modification date", {
  skip_if_not_installed("arrow")
  withr::local_timezone("America/New_York")
  dir <- withr::local_tempdir()
  src <- write_source_csv(dir)
  # 01:30 UTC on 7 October is 21:30 on 6 October in New York.
  Sys.setFileTime(src, as.POSIXct("2026-10-07 01:30:00", tz = "UTC"))
  expect_identical(.mtime_date(src), "2026-10-06")
})
