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
