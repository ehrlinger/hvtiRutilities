skip_if_no_arrow <- function() skip_if_not_installed("arrow")

test_that("first read writes a parquet and a sidecar; second read uses them", {
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir)
  cfg <- study_config(dir)

  d1 <- read_built(cfg)
  expect_true(file.exists(file.path(dir, "datasets", "built_test.parquet")))
  expect_true(file.exists(file.path(dir, "datasets", "built_test.schema.csv")))

  d2 <- read_built(cfg)
  expect_equal(d1, d2)
})

test_that("changing the source invalidates the cache", {
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir, n = 20L)
  cfg <- study_config(dir)

  expect_equal(nrow(read_built(cfg)), 20L)

  # Rewrite the source with a different row count. Asserting on the returned
  # data rather than on the parquet's mtime is deliberate: an mtime comparison
  # passes whether or not the cache was rebuilt, so it tests nothing. A stale
  # cache returns 20 rows here.
  replacement <- data.frame(
    id      = 1:5,
    x       = as.numeric(1:5),
    dead    = c(1L, 1L, 0L, 0L, 0L),
    iv_dead = as.numeric(1:5)
  )
  suppressWarnings(haven::write_sas(
    replacement, file.path(dir, "datasets", "built_test.sas7bdat")))

  expect_equal(nrow(read_built(cfg)), 5L)
})

test_that("a parquet round trip preserves haven metadata", {
  skip_if_no_arrow()
  tmp <- withr::local_tempfile(fileext = ".parquet")
  d <- data.frame(x = 1:3)
  d$grp <- haven::labelled(c(1, 2, 1), labels = c(No = 1, Yes = 2), label = "Group")
  d$when <- as.POSIXct("2020-01-01", tz = "UTC")
  attr(d$x, "format.sas") <- "BEST12"

  arrow::write_parquet(d, tmp)
  b <- as.data.frame(arrow::read_parquet(tmp))

  expect_s3_class(b$grp, "haven_labelled")
  expect_equal(attr(b$grp, "labels"), c(No = 1, Yes = 2))
  expect_equal(attr(b$grp, "label"), "Group")
  expect_equal(attr(b$x, "format.sas"), "BEST12")
  expect_equal(format(b$when[1], tz = "UTC", usetz = TRUE),
               "2020-01-01 UTC")
})

test_that("the sidecar of a promoted entry is never regenerated", {
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir)
  cfg <- study_config(dir)
  read_built(cfg)

  side <- file.path(dir, "datasets", "built_test.schema.csv")
  writeLines("do not overwrite", side)

  # manifest.yaml lives at the study root (study_init() writes it there),
  # not beside the datasets it describes.
  mp <- file.path(dir, "manifest.yaml")
  m <- yaml::read_yaml(mp)
  m$datasets[[1]]$role <- "primary"
  yaml::write_yaml(m, mp)

  src <- file.path(dir, "datasets", "built_test.sas7bdat")
  Sys.setFileTime(src, Sys.time() + 5)
  suppressWarnings(try(read_built(cfg), silent = TRUE))

  expect_equal(readLines(side), "do not overwrite")
})

test_that("a failed conversion leaves no partial parquet", {
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "datasets"))
  target <- file.path(dir, "datasets", "x.parquet")

  # A list column holding an environment has no Arrow type arrow can infer,
  # so write_parquet() errors. (A plain list column of atomic values, as an
  # earlier draft of this test used, round-trips fine under arrow and would
  # not exercise the cleanup path at all.)
  expect_error(
    hvtiRutilities:::.write_parquet_atomic(
      data.frame(a = I(list(1, environment()))), target),
    NULL
  )
  expect_false(file.exists(target))
})

test_that("reads still work when arrow is unavailable", {
  dir <- withr::local_tempdir()
  make_study_fixture(dir)
  withr::local_options(hvtiRutilities.disable_parquet_cache = TRUE)

  d <- read_built(study_config(dir))

  expect_s3_class(d, "data.frame")
  expect_false(file.exists(file.path(dir, "datasets", "built_test.parquet")))
})
