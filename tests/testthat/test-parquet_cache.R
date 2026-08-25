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

test_that("a promoted entry is served from parquet when the source is gone", {
  # role: primary means the source was retired. If read_built() cannot serve
  # this, promotion is unreachable and the role field does nothing.
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir, n = 20L)
  cfg <- study_config(dir)
  read_built(cfg)                                  # populate the cache

  mp <- file.path(dir, "manifest.yaml")
  m <- yaml::read_yaml(mp)
  m$datasets[[1]]$role <- "primary"
  yaml::write_yaml(m, mp)
  file.remove(file.path(dir, "datasets", "built_test.sas7bdat"))

  d <- read_built(cfg)
  expect_equal(nrow(d), 20L)
})

test_that("refresh = TRUE re-reads the source even when the cache looks valid", {
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir, n = 20L)
  cfg <- study_config(dir)
  read_built(cfg)

  # Rewrite the source and restore the ORIGINAL mtime, so size+mtime cannot
  # detect the change. Only refresh can.
  src <- file.path(dir, "datasets", "built_test.sas7bdat")
  stamp <- file.info(src)$mtime
  replacement <- data.frame(id = 1:5, x = as.numeric(1:5),
                            dead = c(1L, 1L, 0L, 0L, 0L),
                            iv_dead = as.numeric(1:5))
  suppressWarnings(haven::write_sas(replacement, src))
  Sys.setFileTime(src, stamp)

  expect_equal(nrow(read_built(cfg, refresh = TRUE)), 5L)
})

test_that("refresh = TRUE on a promoted entry with no source errors clearly", {
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir, n = 20L)
  cfg <- study_config(dir)
  read_built(cfg)

  mp <- file.path(dir, "manifest.yaml")
  m <- yaml::read_yaml(mp)
  m$datasets[[1]]$role <- "primary"
  yaml::write_yaml(m, mp)
  file.remove(file.path(dir, "datasets", "built_test.sas7bdat"))

  expect_error(read_built(cfg, refresh = TRUE), "primary")
})

test_that("a same-size source inside the mtime ambiguity window is verified by sha256, not trusted", {
  # Ambiguity is constructed two ways at once, both required by the design:
  #   - same size: the replacement keeps the same shape (20 rows, same
  #     columns/types) as the original, so haven writes an identical
  #     page-aligned 16384-byte file -- size alone cannot see the change.
  #   - near-but-not-exact mtime: the rewritten source's mtime is set to the
  #     recorded stamp + 0.3s. That is above the sub-millisecond round-trip
  #     noise the manifest's string(de)serialization of mtime introduces
  #     (verified empirically at ~1e-6s), so it is NOT treated as an exact,
  #     trusted match -- but it is well inside the 1-second ambiguity window
  #     (assumed SMB mtime granularity), so it is NOT trusted as a confident
  #     "different file" signal either. Only the recorded sha256 can settle
  #     it, and it must not match the rewritten content.
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir, n = 20L)
  cfg <- study_config(dir)
  read_built(cfg)                                   # populate the cache

  src <- file.path(dir, "datasets", "built_test.sas7bdat")
  size_before <- file.info(src)$size

  mp <- file.path(dir, "manifest.yaml")
  m  <- yaml::read_yaml(mp)
  stamp <- as.POSIXct(m$datasets[[1]]$source_mtime, tz = "UTC")

  replacement <- data.frame(
    id      = 1:20,
    x       = as.numeric(1:20),
    dead    = c(rep(1L, 8), rep(0L, 12)),
    iv_dead = as.numeric(c(20:2, 999))              # same shape, changed value
  )
  suppressWarnings(haven::write_sas(replacement, src))
  Sys.setFileTime(src, stamp + 0.3)

  expect_equal(file.info(src)$size, size_before)     # confirms size is a dead end

  d <- read_built(cfg)
  expect_equal(nrow(d), 20L)
  expect_equal(d$iv_dead[20], 999)
})

test_that("an unchanged source inside the ambiguity window is trusted via sha256, not reconverted", {
  # The companion case to the test above, and the one that actually pins down
  # "verify sha256" rather than "always distrust an inexact mtime match": the
  # source's content is untouched, only its mtime is nudged by 0.3s (inside
  # the ambiguity window, e.g. clock skew or a benign re-stat that doesn't
  # rewrite the file). A correct sha256 fallback recomputes the hash, finds
  # it matches the recorded one, and serves the existing parquet unchanged.
  # An implementation that instead treats "not an exact mtime match" as
  # automatically invalid would reconvert here even though nothing changed,
  # which is the "sha256 is not the fast path" regression the design warns
  # against -- caught by checking the parquet was NOT rewritten.
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir, n = 20L)
  cfg <- study_config(dir)
  read_built(cfg)                                    # populate the cache

  parquet <- file.path(dir, "datasets", "built_test.parquet")
  parquet_mtime_before <- file.info(parquet)$mtime

  src <- file.path(dir, "datasets", "built_test.sas7bdat")
  Sys.setFileTime(src, file.info(src)$mtime + 0.3)    # touch only, no rewrite

  d <- read_built(cfg)
  expect_equal(nrow(d), 20L)
  # expect_equal()/waldo compares POSIXct as numeric epoch seconds with a
  # RELATIVE tolerance, and an epoch value is large enough (~1.8e9) that a
  # tolerance meant for fractions of a unit swallows a whole reconversion's
  # worth of elapsed wall-clock time -- so this must be an exact check, not
  # expect_equal(), or a reconversion that changes the parquet's mtime by
  # under ~25 seconds would go undetected.
  expect_true(identical(file.info(parquet)$mtime, parquet_mtime_before))
})

test_that("an exact mtime tie whose stamp sits inside the risky window does not serve a stale parquet", {
  # This is the scenario Change 0 exists for: a same-tick rewrite is
  # invisible to mtime, and treating an exact tie as proof of no change would
  # serve stale data forever. The fix requires the rewrite be caught via
  # sha256 whenever the recorded stamp itself was taken close to the source's
  # mtime -- the "risky" tick.
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir, n = 20L)
  cfg <- study_config(dir)
  read_built(cfg)                                    # populate the cache

  src <- file.path(dir, "datasets", "built_test.sas7bdat")
  mp  <- file.path(dir, "manifest.yaml")
  m   <- yaml::read_yaml(mp)
  original_mtime <- m$datasets[[1]]$source_mtime

  # Force the entry's stamp squarely inside the risky window -- taken at the
  # same instant as the source's own mtime -- regardless of how fast this
  # test happens to execute.
  m$datasets[[1]]$stamp_time <- original_mtime
  yaml::write_yaml(m, mp)

  # Same shape (20 rows, same columns) as the original fixture, so the
  # rewritten file is exactly as many bytes as the original -- size alone
  # cannot see this change either.
  replacement <- data.frame(
    id      = 1:20,
    x       = as.numeric(1:20),
    dead    = c(rep(1L, 8), rep(0L, 12)),
    iv_dead = as.numeric(c(20:2, 999))                # distinguishing value
  )
  suppressWarnings(haven::write_sas(replacement, src))
  Sys.setFileTime(src, as.POSIXct(original_mtime, tz = "UTC"))  # exact tie

  d <- read_built(cfg)
  expect_equal(d$iv_dead[20], 999)                    # NOT the stale value
})

test_that("a stamp comfortably after mtime is trusted without hashing", {
  # The companion case: once the stamp is safely outside the risky window,
  # the fast path must not pay for a hash at all -- proved by corrupting the
  # recorded sha256 and confirming the cache is still served, untouched.
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir, n = 20L)
  cfg <- study_config(dir)
  read_built(cfg)

  mp <- file.path(dir, "manifest.yaml")
  m  <- yaml::read_yaml(mp)
  stamp <- as.numeric(as.POSIXct(m$datasets[[1]]$source_mtime, tz = "UTC"))
  m$datasets[[1]]$stamp_time <- format(
    as.POSIXct(stamp + 5, origin = "1970-01-01", tz = "UTC"),
    "%Y-%m-%d %H:%M:%OS6", tz = "UTC")
  m$datasets[[1]]$sha256 <- strrep("0", 64)           # deliberately wrong
  yaml::write_yaml(m, mp)

  parquet <- file.path(dir, "datasets", "built_test.parquet")
  parquet_mtime_before <- file.info(parquet)$mtime

  d <- read_built(cfg)
  expect_equal(nrow(d), 20L)
  expect_true(identical(file.info(parquet)$mtime, parquet_mtime_before))
})
