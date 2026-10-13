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

test_that("verify_manifest checks build records and stops on a changed or missing one", {
  s <- unregistered_study()
  write_build_sidecar(s$src)
  suppressMessages(register_data(s$root, "built.csv"))
  mp <- file.path(s$root, "manifest.yaml")
  rec <- file.path(dirname(s$src), "built_20260915.build.yml")

  rep <- verify_manifest(mp, stop_on_error = FALSE)
  expect_true(any(rep$file == "built.csv (built_20260915.build.yml)" & rep$status == "OK"))

  cat("# edited\n", file = rec, append = TRUE)
  expect_error(verify_manifest(mp), "provenance of a registered version")
  unlink(rec)
  expect_warning(rep <- verify_manifest(mp, stop_on_error = FALSE), "provenance of a registered version")
  expect_identical(rep$status[rep$file == "built.csv (built_20260915.build.yml)"], "FAIL")
})

test_that("a provenance row for no recorded version fails", {
  root <- versioned_study()
  mp <- file.path(root, "manifest.yaml")
  m <- .set_version_provenance(.read_manifest(mp), "ghost_20200101.parquet", list(origin = "legacy"))
  .write_manifest(m, mp)
  expect_warning(rep <- verify_manifest(mp, stop_on_error = FALSE), "which no dataset records")
  expect_identical(rep$status[rep$file == "ghost_20200101.parquet (provenance)"], "FAIL")
})

test_that("a build record neither inflates study_status's entry count nor hides its FAIL", {
  s <- unregistered_study()
  suppressMessages(register_data(s$root, "built.csv"))
  count <- function() {
    d <- study_status(s$root)$checks
    d$detail[d$item == "manifest.yaml"]
  }
  before <- sub(" verified.*", "", count())

  unlink(s$root, recursive = TRUE)
  s <- unregistered_study()
  write_build_sidecar(s$src)
  suppressMessages(register_data(s$root, "built.csv"))
  expect_identical(sub(" verified.*", "", count()), before)

  cat("# edited\n", file = file.path(dirname(s$src), "built_20260915.build.yml"), append = TRUE)
  d <- study_status(s$root)$checks
  row <- d[d$item == "manifest.yaml", ]
  expect_identical(row$status, "FAIL")
  expect_match(row$detail, "built.csv", fixed = TRUE)
  expect_no_match(row$detail, "built_20260915", fixed = TRUE)
})

test_that("a provenance row keyed by a sidecar name is an orphan, not a pass or a crash", {
  root <- versioned_study()
  mp <- file.path(root, "manifest.yaml")
  m <- .read_manifest(mp)
  schema <- .version_schema_name(m$datasets[[1]]$parquet)
  m <- .set_version_provenance(m, schema, list(origin = "legacy"))
  .write_manifest(m, mp)
  expect_warning(rep <- verify_manifest(mp, stop_on_error = FALSE), "which no dataset records")
  expect_identical(rep$status[rep$file == paste0(schema, " (provenance)")], "FAIL")
})

test_that("an invalid build record in a hand-edited manifest fails under the entry's label", {
  s <- unregistered_study()
  write_build_sidecar(s$src)
  suppressMessages(register_data(s$root, "built.csv"))
  mp <- file.path(s$root, "manifest.yaml")
  for (bad in list(list(record = "", record_sha256 = strrep("a", 64)),
                   list(record = "built_20260915.build.yml", record_sha256 = "nothex"),
                   list(record = c("a", "b"), record_sha256 = strrep("a", 64)))) {
    m <- .read_manifest(mp)
    m$provenance[["built_20260915.parquet"]]$build <- bad
    .write_manifest(m, mp)
    expect_warning(rep <- verify_manifest(mp, stop_on_error = FALSE), "invalid build record")
    expect_identical(rep$status[rep$file == "built.csv (built_20260915.parquet build record)"], "FAIL")
  }
})

test_that("a promoted entry with a retired source migrates from its parquet and lifts the gate", {
  root <- promoted_study()
  dir <- study_dir("datasets", root)
  before <- digest::digest(file.path(dir, "built.parquet"), algo = "sha256", file = TRUE)
  local_mocked_bindings(.is_interactive = function() FALSE,
                        .job_file = function() file.path(study_dir("analyses", root), "km", "km.qmd"))
  expect_error(read_built(study_config(root)), "jobs read registered data only")

  out <- withr::with_dir(root, suppressMessages(update_manifest()))
  expect_identical(out$action, "migrated")
  e <- .read_manifest(file.path(root, "manifest.yaml"))$datasets[[1]]
  expect_identical(e$parquet, "built_20260915.parquet")
  expect_identical(e$recovered_from, "promoted")
  expect_identical(e$sha256, before)
  expect_identical(e$promoted_date, "2026-09-20")
  expect_false(file.exists(file.path(dir, "built.parquet")))
  expect_identical(nrow(read_built(study_config(root))), 3L)
})

test_that("a promoted parquet that does not match its hash is not migrated", {
  root <- promoted_study()
  cat("x", file = file.path(study_dir("datasets", root), "built.parquet"), append = TRUE)
  out <- withr::with_dir(root, suppressMessages(update_manifest()))
  expect_identical(out$action, "missing")
  expect_match(out$detail, "does not match its recorded checksum")
  expect_match(out$detail, "read_built() stops for it", fixed = TRUE)
  expect_false(file.exists(file.path(study_dir("datasets", root), "built_20260915.parquet")))
})

test_that("a promoted entry whose parquet is gone says read_built() stops", {
  root <- promoted_study()
  unlink(file.path(study_dir("datasets", root), "built.parquet"))
  out <- withr::with_dir(root, suppressMessages(update_manifest()))
  expect_identical(out$action, "missing")
  expect_match(out$detail, "is not on disk")
  expect_match(out$detail, "read_built() stops for it", fixed = TRUE)
})

test_that("each retired function and argument warns, naming its replacement", {
  expect_warning(.deprecated_arg("register_data", "release_id", "a build record sidecar"),
                 class = "deprecatedWarning")
  expect_warning(.deprecated_arg("register_data", "release_id", "a build record sidecar"),
                 "release_id.*a build record sidecar")
})

test_that("a scalar provenance row fails the manifest instead of crashing it", {
  root <- versioned_study()
  mp <- file.path(root, "manifest.yaml")
  m <- .read_manifest(mp)
  m$provenance <- list(built_20260915.parquet = "legacy")
  .write_manifest(m, mp)
  expect_warning(rep <- verify_manifest(mp, stop_on_error = FALSE), "manifest.yaml")
  expect_identical(rep$status[rep$file == "built_20260915.parquet (provenance)"], "FAIL")
  expect_match(rep$message[rep$file == "built_20260915.parquet (provenance)"], "version control", fixed = TRUE)
  d <- study_status(root)$checks
  expect_identical(d$status[d$item == "manifest.yaml"], "FAIL")
})

test_that("a provenance field that is not a mapping is one failing row", {
  root <- versioned_study()
  mp <- file.path(root, "manifest.yaml")
  for (bad in list("legacy", list("a", "b"))) {
    m <- .read_manifest(mp)
    m$provenance <- bad
    .write_manifest(m, mp)
    expect_warning(rep <- verify_manifest(mp, stop_on_error = FALSE), "manifest.yaml")
    expect_identical(rep$status[rep$file == "manifest.yaml (provenance)"], "FAIL")
  }
})

test_that("two invalid build records of one entry get distinct labels", {
  s <- unregistered_study()
  write_build_sidecar(s$src)
  suppressMessages(register_data(s$root, "built.csv"))
  path <- rebuild_source(s$root)
  write_build_sidecar(path)
  withr::with_dir(s$root, suppressMessages(update_manifest()))
  mp <- file.path(s$root, "manifest.yaml")
  m <- .read_manifest(mp)
  parquets <- names(m$provenance)
  expect_length(parquets, 2L)
  for (p in parquets) m$provenance[[p]]$build$record_sha256 <- "nothex"
  .write_manifest(m, mp)
  suppressWarnings(rep <- verify_manifest(mp, stop_on_error = FALSE))
  bad <- rep$file[grepl("build record", rep$file)]
  expect_length(unique(bad), 2L)
})

test_that("study_status does not count a build record as an earlier version", {
  s <- unregistered_study()
  write_build_sidecar(s$src)
  suppressMessages(register_data(s$root, "built.csv"))
  d <- study_status(s$root)$checks
  expect_no_match(d$detail[d$item == "manifest.yaml"], "earlier versions", fixed = TRUE)
})

test_that("a failed manifest write puts a promoted migration back", {
  root <- promoted_study()
  dir <- study_dir("datasets", root)
  mp <- file.path(root, "manifest.yaml")
  before <- readLines(mp)
  local_mocked_bindings(.write_manifest = function(...) stop("disk full"))
  expect_error(withr::with_dir(root, suppressMessages(update_manifest())), "disk full")
  expect_true(file.exists(file.path(dir, "built.parquet")))
  expect_true(file.exists(file.path(dir, "built.schema.csv")))
  expect_false(file.exists(file.path(dir, "built_20260915.parquet")))
  expect_false(file.exists(file.path(dir, "built_20260915.schema.csv")))
  expect_identical(readLines(mp), before)
})

test_that("a provenance row with an origin this version does not know fails", {
  root <- versioned_study()
  mp <- file.path(root, "manifest.yaml")
  m <- .read_manifest(mp)
  m$provenance[["built_20260915.parquet"]] <- list(origin = "future")
  .write_manifest(m, mp)
  expect_warning(rep <- verify_manifest(mp, stop_on_error = FALSE), "does not know")
  row <- rep[rep$file == "built_20260915.parquet (provenance)", ]
  expect_identical(row$status, "FAIL")
  expect_match(row$message, "future", fixed = TRUE)
  expect_match(row$message, "pdate hvtiRutilities or restore manifest.yaml from version control", fixed = TRUE)
})

test_that("a bd provenance row without its build record fails, a legacy row without one stays silent", {
  root <- versioned_study()
  mp <- file.path(root, "manifest.yaml")
  m <- .read_manifest(mp)
  m$provenance[["built_20260915.parquet"]] <- list(origin = "bd")
  .write_manifest(m, mp)
  expect_warning(rep <- verify_manifest(mp, stop_on_error = FALSE), "without its build record")
  expect_identical(rep$status[rep$file == "built.csv (built_20260915.parquet build record)"], "FAIL")

  m$provenance[["built_20260915.parquet"]] <- list(origin = "legacy")
  .write_manifest(m, mp)
  rep <- verify_manifest(mp, stop_on_error = FALSE)
  expect_false(any(rep$status == "FAIL"))
  expect_false(any(grepl("provenance|build record", rep$file)))
})

test_that("provenance in a manifest with no datasets still fails", {
  root <- versioned_study()
  mp <- file.path(root, "manifest.yaml")
  yaml::write_yaml(list(datasets = list(), provenance = list(ghost_20200101.parquet = list(origin = "legacy"))), mp)
  expect_warning(rep <- verify_manifest(mp, stop_on_error = FALSE), "which no dataset records")
  expect_identical(rep$status[rep$file == "ghost_20200101.parquet (provenance)"], "FAIL")
  expect_error(verify_manifest(mp), "which no dataset records")

  yaml::write_yaml(list(datasets = list()), mp)
  rep <- verify_manifest(mp, verbose = FALSE)
  expect_identical(nrow(rep), 0L)
})

test_that("an NA build record checksum fails instead of crashing", {
  s <- unregistered_study()
  write_build_sidecar(s$src)
  suppressMessages(register_data(s$root, "built.csv"))
  mp <- file.path(s$root, "manifest.yaml")
  m <- .read_manifest(mp)
  m$provenance[["built_20260915.parquet"]]$build$record_sha256 <- NA_character_
  yaml::write_yaml(m, mp)
  expect_warning(rep <- verify_manifest(mp, stop_on_error = FALSE), "invalid build record")
  expect_identical(rep$status[rep$file == "built.csv (built_20260915.parquet build record)"], "FAIL")
})

test_that("as_of offsets are bounded", {
  for (ok in c("2026-10-01T08:30:00-04:00", "2026-10-01T08:30:00+0530", "2026-10-01T08:30:00+14:00")) {
    expect_true(.is_iso_timestamp(ok), info = ok)
  }
  for (bad in c("2026-10-01T08:30:00+99:99", "2026-10-01T08:30:00+24:00", "2026-10-01T08:30:00+05:60",
                "2026-10-01T08:30:00+1500")) {
    expect_false(.is_iso_timestamp(bad), info = bad)
  }
})

test_that("register_data keeps a sidecar written after the claim and files the claimed one beside it", {
  s <- unregistered_study()
  side <- write_build_sidecar(s$src, view = "older_v")
  local_mocked_bindings(.replace_study_pair = function(...) {
    write_build_sidecar(s$src, view = "newer_v")
    stop("rename failed")
  })
  expect_warning(expect_error(suppressMessages(register_data(s$root, "built.csv")), "rename failed"), "restored-")
  expect_identical(yaml::read_yaml(side)$view, "newer_v")
  kept <- list.files(dirname(s$src), pattern = "^built[.]build[.]yml[.]restored-", full.names = TRUE)
  expect_length(kept, 1L)
  expect_identical(yaml::read_yaml(kept)$view, "older_v")
})

test_that("update_manifest keeps a sidecar written after the claim and files the claimed one beside it", {
  root <- legacy_with_cache()
  data_dir <- study_dir("datasets", root)
  rebuild_source(root, data.frame(id = 1:5, dead = c(1L, 0L, 0L, 0L, 1L), iv_dead = 1:5))
  src <- file.path(data_dir, "built.csv")
  side <- write_build_sidecar(src, view = "older_v")
  withr::local_dir(root)
  local_mocked_bindings(.write_manifest = function(manifest, path) {
    write_build_sidecar(src, view = "newer_v")
    stop("disk full")
  })
  expect_warning(expect_error(suppressMessages(update_manifest()), "disk full"), "restored-")
  expect_identical(yaml::read_yaml(side)$view, "newer_v")
  kept <- list.files(data_dir, pattern = "^built[.]build[.]yml[.]restored-", full.names = TRUE)
  expect_length(kept, 1L)
  expect_identical(yaml::read_yaml(kept)$view, "older_v")
})

test_that("a promoted entry whose schema was edited is not migrated", {
  root <- promoted_study()
  dir <- study_dir("datasets", root)
  schema <- file.path(dir, "built.schema.csv")
  mp <- file.path(root, "manifest.yaml")
  m <- .read_manifest(mp)
  m$datasets[[1]]$schema_sha256 <- digest::digest(schema, algo = "sha256", file = TRUE)
  yaml::write_yaml(m, mp)
  cat("x\n", file = schema, append = TRUE)
  out <- withr::with_dir(root, suppressMessages(update_manifest()))
  expect_identical(out$action, "missing")
  expect_match(out$detail, "built.schema.csv", fixed = TRUE)
  expect_match(out$detail, "checksum", fixed = TRUE)
  expect_false(file.exists(file.path(dir, "built_20260915.parquet")))
  expect_true(file.exists(schema))
})

test_that("a record without schema 1 is foreign: left in place, the version is legacy, and it says so", {
  s <- unregistered_study()
  side <- write_foreign_build_record(s$src)
  before <- readBin(side, "raw", file.size(side))
  expect_message(register_data(s$root, "built.csv"), "not a build record this version reads (no schema: 1)", fixed = TRUE)
  expect_identical(readBin(side, "raw", file.size(side)), before)
  row <- .version_provenance(.read_manifest(file.path(s$root, "manifest.yaml")), "built_20260915.parquet")
  expect_identical(row$origin, "legacy")
})

test_that("a record with another schema number is foreign too", {
  s <- unregistered_study()
  side <- write_build_sidecar(s$src, schema = 2L)
  expect_message(register_data(s$root, "built.csv"), "no schema: 1", fixed = TRUE)
  expect_true(file.exists(side))
})

test_that("update_manifest() registers a rebuild beside a foreign record", {
  root <- versioned_study()
  src <- file.path(study_dir("datasets", root), "built.csv")
  utils::write.csv(data.frame(id = 1:4, DEAD = c(1L, 0L, 0L, 1L)), src, row.names = FALSE)
  side <- write_foreign_build_record(src)
  out <- withr::with_dir(root, suppressMessages(update_manifest(extract_date = "2026-10-01")))
  expect_identical(out$action, "registered")
  expect_true(file.exists(side))
  expect_match(out$detail, "no schema: 1", fixed = TRUE)
})

test_that("a release-aware study leaves the release path and registers beside bd's record", {
  fx <- make_release_aware_study(withr::local_tempdir())
  cfg <- study_config(fx$root)
  data <- file.path(study_dir("datasets", fx$root), cfg$built)
  expect_true(file.exists(data))
  write_foreign_build_record(data)
  yml <- file.path(fx$root, "_study.yml")
  y <- yaml::read_yaml(yml)
  y$release <- NULL
  y$data$release <- NULL
  yaml::write_yaml(y, yml)
  out <- withr::with_dir(fx$root, suppressMessages(update_manifest()))
  expect_false(any(out$action == "skipped"))
  m <- .read_manifest(file.path(fx$root, "manifest.yaml"))
  expect_identical(.version_provenance(m, manifest_entry_for(fx$root, cfg$built)$parquet)$origin, "legacy")
  expect_match(paste(out$detail, collapse = " "), "no schema: 1", fixed = TRUE)
})
