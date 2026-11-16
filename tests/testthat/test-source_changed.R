test_that("source_changed() is FALSE for a registered source that has not moved", {
  root <- versioned_study()
  expect_false(source_changed(study_config(root)))
  expect_false(source_changed(study_config(root), dataset = "built"))
})

test_that("source_changed() is TRUE once the source is rebuilt, and FALSE again after update_manifest()", {
  root <- versioned_study()
  rebuild_source(root)
  expect_true(source_changed(study_config(root)))
  withr::with_dir(root, suppressMessages(update_manifest()))
  expect_false(source_changed(study_config(root)))
})

test_that("source_changed() ignores a touch that changed no bytes", {
  root <- versioned_study()
  Sys.setFileTime(built_path(study_config(root)), as.POSIXct("2026-11-01 12:00:00", tz = "UTC"))
  expect_false(source_changed(study_config(root)))
})

test_that("source_changed() is FALSE without a dated version, or when the source is gone", {
  expect_false(source_changed(study_config(promoted_study())))
  root <- versioned_study()
  unlink(built_path(study_config(root)))
  expect_false(source_changed(study_config(root)))
})

test_that("source_changed() catches a same-size replacement that kept the recorded mtime", {
  # A copy or restore that preserves dates passes the stat read_built() trusts; the hash does not.
  root <- versioned_study(data = data.frame(id = 1:3, DEAD = c(1L, 0L, 0L)))
  src <- built_path(study_config(root))
  stamp <- as.POSIXct("2026-09-15 12:00:00.25", tz = "UTC")
  Sys.setFileTime(src, stamp)
  withr::with_dir(root, suppressMessages(update_manifest()))
  before <- file.info(src)
  utils::write.csv(data.frame(id = 1:3, DEAD = c(0L, 1L, 0L)), src, row.names = FALSE)
  Sys.setFileTime(src, stamp)
  expect_identical(file.info(src)$size, before$size)
  expect_identical(as.numeric(file.info(src)$mtime), as.numeric(before$mtime))
  expect_true(source_changed(study_config(root)))
})
