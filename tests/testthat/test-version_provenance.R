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
