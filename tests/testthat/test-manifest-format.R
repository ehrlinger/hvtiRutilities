# A manifest holding a dated version must make hvtiRutilities 1.4.x stop, not
# rewrite the entry. 1.4.x reads role: primary as "<stem>.parquet is the data",
# finds none, reconverts the rebuilt source and overwrites sha256 and n_rows.
# Every 1.4.x reader walks the datasets list with `e$file`, so a scalar item at
# its head stops each of them before anything is read or written. These tests
# stand in for 1.4.4, which a test cannot load beside this package: the walk is
# the one 1.4.4's .manifest_entry(), update_manifest() and verify_manifest() do.
old_reader_walk <- function(manifest_path) {
  for (e in yaml::read_yaml(manifest_path)$datasets) identical(e$file, "built.csv")
}

guard_study <- function(env = parent.frame()) {
  root <- make_legacy_registered_study(withr::local_tempdir(.local_envir = env))
  file.remove(file.path(root, "manifest.yaml"))
  raw <- yaml::read_yaml(file.path(root, "_study.yml"))
  raw$built <- NULL
  yaml::write_yaml(raw, file.path(root, "_study.yml"))
  suppressMessages(register_data(root, "built.csv"))
  root
}

test_that("a manifest with a registered version stops a reader older than 1.5.1", {
  skip_if_not_installed("arrow")
  root <- guard_study()
  mp <- file.path(root, "manifest.yaml")

  first <- yaml::read_yaml(mp)$datasets[[1L]]
  expect_true(is.character(first) && length(first) == 1L)
  expect_match(first, "hvtiRutilities 1.5.1 or later", fixed = TRUE)
  expect_error(old_reader_walk(mp), "\\$ operator is invalid for atomic vectors")
})

test_that("this version reads, verifies and updates a guarded manifest", {
  skip_if_not_installed("arrow")
  root <- guard_study()
  mp <- file.path(root, "manifest.yaml")

  expect_identical(nrow(read_built(study_config(root))), 3L)
  expect_true(all(verify_manifest(mp)$status == "OK"))
  expect_identical(.manifest_entry(mp, "built.csv")$parquet, "built_20260915.parquet")

  rebuild_src <- file.path(study_dir("datasets", root), "built.csv")
  utils::write.csv(data.frame(id = 1:4, dead = c(1L, 0L, 0L, 1L), iv_dead = 1:4), rebuild_src, row.names = FALSE)
  withr::with_dir(root, suppressMessages(update_manifest(extract_date = "2026-10-08")))
  expect_identical(.manifest_entry(mp, "built.csv")$parquet, "built_20261008.parquet")
  expect_error(old_reader_walk(mp), "\\$ operator is invalid for atomic vectors")
})

test_that("recording another file keeps the guard", {
  skip_if_not_installed("arrow")
  root <- guard_study()
  mp <- file.path(root, "manifest.yaml")
  other <- file.path(study_dir("datasets", root), "extra.csv")
  utils::write.csv(data.frame(a = 1:2), other, row.names = FALSE)

  update_manifest(other, manifest_path = mp)

  expect_error(old_reader_walk(mp), "\\$ operator is invalid for atomic vectors")
  expect_identical(vapply(Filter(is.list, yaml::read_yaml(mp)$datasets), `[[`, "", "file"),
                   c("built.csv", "extra.csv"))
})

test_that("a manifest written by 1.5.0 is read as it is and gains the guard on the next update", {
  skip_if_not_installed("arrow")
  root <- guard_study()
  mp <- file.path(root, "manifest.yaml")
  # 1.5.0 wrote the versioned entry with no guard ahead of it.
  m <- yaml::read_yaml(mp)
  m$datasets <- Filter(is.list, m$datasets)
  yaml::write_yaml(m, mp)
  expect_silent(old_reader_walk(mp))

  expect_identical(nrow(read_built(study_config(root))), 3L)
  expect_true(all(verify_manifest(mp)$status == "OK"))
  expect_silent(old_reader_walk(mp))

  out <- withr::with_dir(root, suppressMessages(update_manifest()))
  expect_identical(out$action, "unchanged")
  expect_error(old_reader_walk(mp), "\\$ operator is invalid for atomic vectors")
  expect_identical(.manifest_entry(mp, "built.csv")$parquet, "built_20260915.parquet")
})

test_that("a manifest with no registered version carries no guard", {
  skip_if_not_installed("arrow")
  root <- make_legacy_registered_study(withr::local_tempdir())
  mp <- file.path(root, "manifest.yaml")
  read_built(study_config(root))
  other <- file.path(study_dir("datasets", root), "extra.csv")
  utils::write.csv(data.frame(a = 1:2), other, row.names = FALSE)
  update_manifest(other, manifest_path = mp)

  expect_silent(old_reader_walk(mp))
})
