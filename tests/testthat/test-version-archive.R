# Earlier registered versions move into <datasets>/_archive/ (1.5.12). The
# current version stays beside its source; manifest.yaml keeps bare names.

version_files <- function(stem) c(paste0(stem, ".parquet"), paste0(stem, ".schema.csv"))

test_that("a new version moves the previous parquet and schema into _archive/", {
  root <- versioned_study()
  dir <- study_dir("datasets", root)
  sha_before <- manifest_entry_for(root)$sha256
  rebuild_source(root)
  withr::with_dir(root, suppressMessages(update_manifest()))

  expect_setequal(list.files(dir, pattern = "[.](parquet|schema[.]csv)$"), version_files("built_20261007"))
  expect_setequal(list.files(file.path(dir, "_archive")), version_files("built_20260915"))
  e <- manifest_entry_for(root)
  expect_identical(e$parquet, "built_20261007.parquet")
  expect_identical(e$history[[1L]]$parquet, "built_20260915.parquet")
  expect_identical(digest::digest(file.path(dir, "_archive", "built_20260915.parquet"), algo = "sha256", file = TRUE),
                   sha_before)
  expect_identical(nrow(read_built(study_config(root))), 4L)

  # A third version archives the second; the first stays archived.
  rebuild_source(root, data.frame(id = 1:5, DEAD = c(1L, 1L, 0L, 0L, 0L)), when = "2026-10-20 12:00:00")
  withr::with_dir(root, suppressMessages(update_manifest()))
  expect_setequal(list.files(dir, pattern = "[.](parquet|schema[.]csv)$"), version_files("built_20261020"))
  expect_setequal(list.files(file.path(dir, "_archive")), c(version_files("built_20260915"), version_files("built_20261007")))
  expect_identical(nrow(read_built(study_config(root))), 5L)
})

test_that("verify_manifest() checks every archived version by sha256", {
  root <- versioned_study()
  dir <- study_dir("datasets", root)
  mp <- file.path(root, "manifest.yaml")
  rebuild_source(root)
  withr::with_dir(root, suppressMessages(update_manifest()))
  rebuild_source(root, data.frame(id = 1:5, DEAD = c(1L, 1L, 0L, 0L, 0L)), when = "2026-10-20 12:00:00")
  withr::with_dir(root, suppressMessages(update_manifest()))

  rep <- verify_manifest(mp)
  expect_identical(rep$file, c("built.csv", "built.csv (built_20261007.parquet)", "built.csv (built_20260915.parquet)"))
  expect_identical(rep$status, rep("OK", 3L))
  expect_true(all(rep$row_count_checked))

  # The archived copy is the one verified: editing it fails, removing it fails.
  archived <- file.path(dir, "_archive", "built_20260915.parquet")
  bytes <- readBin(archived, "raw", file.size(archived))
  writeBin(c(bytes, as.raw(0L)), archived)
  expect_warning(rep <- verify_manifest(mp, stop_on_error = FALSE), "registered data")
  expect_identical(rep$status[rep$file == "built.csv (built_20260915.parquet)"], "FAIL")
  expect_match(rep$message[rep$file == "built.csv (built_20260915.parquet)"], "does not match its recorded checksum")
  writeBin(bytes, archived)
  unlink(file.path(dir, "_archive", "built_20260915.schema.csv"))
  expect_warning(rep <- verify_manifest(mp, stop_on_error = FALSE), "registered data")
  expect_match(rep$message[rep$file == "built.csv (built_20260915.parquet)"], "schema.csv is missing")
})

test_that("a study registered before the archive keeps working, and its next version tidies it", {
  root <- versioned_study()
  dir <- study_dir("datasets", root)
  mp <- file.path(root, "manifest.yaml")
  rebuild_source(root)
  withr::with_dir(root, suppressMessages(update_manifest()))
  # Put the earlier version back beside the source, as 1.5.11 left it.
  for (f in version_files("built_20260915")) file.rename(file.path(dir, "_archive", f), file.path(dir, f))
  unlink(file.path(dir, "_archive"), recursive = TRUE)
  manifest_before <- readLines(mp)

  # Reads and verification need no migration, and write nothing.
  expect_identical(verify_manifest(mp)$status, c("OK", "OK"))
  expect_identical(nrow(read_built(study_config(root))), 4L)
  expect_message(out <- withr::with_dir(root, update_manifest()), "unchanged")
  expect_identical(out$action, "unchanged")
  expect_false(dir.exists(file.path(dir, "_archive")))
  expect_true(all(file.exists(file.path(dir, version_files("built_20260915")))))
  expect_identical(readLines(mp), manifest_before)

  # The next registration moves every earlier version, not only the one it supersedes.
  rebuild_source(root, data.frame(id = 1:5, DEAD = c(1L, 1L, 0L, 0L, 0L)), when = "2026-10-20 12:00:00")
  withr::with_dir(root, suppressMessages(update_manifest()))
  expect_setequal(list.files(dir, pattern = "[.](parquet|schema[.]csv)$"), version_files("built_20261020"))
  expect_setequal(list.files(file.path(dir, "_archive")), c(version_files("built_20260915"), version_files("built_20261007")))
  expect_identical(verify_manifest(mp)$status, rep("OK", 3L))
})

test_that("a version's build record moves with it and still verifies", {
  s <- unregistered_study()
  write_build_sidecar(s$src)
  suppressMessages(register_data(s$root, "built.csv"))
  dir <- dirname(s$src)
  mp <- file.path(s$root, "manifest.yaml")
  rebuild_source(s$root)
  write_build_sidecar(s$src)
  withr::with_dir(s$root, suppressMessages(update_manifest()))

  expect_true(file.exists(file.path(dir, "_archive", "built_20260915.build.yml")))
  expect_true(file.exists(file.path(dir, "built_20261007.build.yml")))
  rep <- verify_manifest(mp)
  expect_identical(rep$status[rep$file == "built.csv (built_20260915.build.yml)"], "OK")
  expect_true(all(rep$status == "OK"))
})

test_that("a new version never takes a name already in _archive/", {
  root <- versioned_study()
  dir <- study_dir("datasets", root)
  dir.create(file.path(dir, "_archive"))
  # An unrecorded file in the archive, as a hand-copied backup would be.
  writeLines("not a version", file.path(dir, "_archive", "built_20261007.parquet"))
  rebuild_source(root)
  withr::with_dir(root, suppressMessages(update_manifest()))
  expect_identical(manifest_entry_for(root)$parquet, "built_20261007_r2.parquet")
  expect_identical(readLines(file.path(dir, "_archive", "built_20261007.parquet")), "not a version")
})

test_that("a version that cannot be archived stays where verify_manifest() finds it", {
  root <- versioned_study()
  dir <- study_dir("datasets", root)
  # An archived file of the same name already exists, so the move is refused, never an overwrite.
  dir.create(file.path(dir, "_archive"))
  writeLines("someone else's copy", file.path(dir, "_archive", "built_20260915.schema.csv"))
  rebuild_source(root)
  expect_warning(withr::with_dir(root, suppressMessages(update_manifest())), "could not move built_20260915.schema.csv")
  expect_true(file.exists(file.path(dir, "_archive", "built_20260915.parquet")))
  expect_true(file.exists(file.path(dir, "built_20260915.schema.csv")))
  expect_identical(readLines(file.path(dir, "_archive", "built_20260915.schema.csv")), "someone else's copy")
  expect_identical(verify_manifest(file.path(root, "manifest.yaml"))$status, c("OK", "OK"))
})

test_that("only a registered version is looked for in _archive/, never a source", {
  root <- versioned_study()
  dir <- study_dir("datasets", root)
  dir.create(file.path(dir, "_archive"))
  file.copy(file.path(dir, "built.csv"), file.path(dir, "_archive", "built.csv"))
  rebuild_source(root)
  withr::with_dir(root, suppressMessages(update_manifest()))
  # The source is gone from beside the manifest; the stray archived copy must not stand in for it.
  unlink(file.path(dir, "built.csv"))
  expect_identical(.version_path(dir, "built.csv"), file.path(dir, "_archive", "built.csv"))
  rep <- verify_manifest(file.path(root, "manifest.yaml"))
  expect_false(any(grepl("(source)", rep$file, fixed = TRUE)))
})
