skip_if_no_arrow <- function() skip_if_not_installed("arrow")

test_that("first read writes a parquet and a sidecar; second read leaves them untouched", {
  # `expect_equal(d1, d2)` alone proves nothing about whether the parquet was
  # actually consulted -- it holds identically whether the second call served
  # the cache or reconverted from the source. Pinning cache use here means
  # asserting the parquet and sidecar are NOT rewritten by the second read: a
  # reconversion would rewrite both via .write_parquet_atomic()/.atomic_write(),
  # changing their mtimes, so an unchanged mtime is direct evidence the cache
  # was hit rather than regenerated. (The parquet-mtime-identity tests further
  # down cover the size/mtime/sha256 validity RULES that decide a hit; this
  # test only pins that the ordinary, unperturbed second call is one.)
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir)
  cfg <- study_config(dir)

  d1 <- read_built(cfg)
  parquet <- file.path(dir, "datasets", "built_test.parquet")
  side    <- file.path(dir, "datasets", "built_test.schema.csv")
  expect_true(file.exists(parquet))
  expect_true(file.exists(side))
  parquet_mtime_before <- file.info(parquet)$mtime
  side_mtime_before    <- file.info(side)$mtime

  d2 <- read_built(cfg)
  expect_equal(d1, d2)
  expect_true(identical(file.info(parquet)$mtime, parquet_mtime_before))
  expect_true(identical(file.info(side)$mtime, side_mtime_before))
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
  # No try()/suppressWarnings() wrapper: a version that regressed and errored
  # here (e.g. before reaching the sidecar branch) must fail this test, not
  # pass it vacuously.
  d <- read_built(cfg)

  expect_s3_class(d, "data.frame")
  expect_equal(readLines(side), "do not overwrite")
})

test_that("a failed conversion leaves no partial parquet", {
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "datasets"))
  target <- file.path(dir, "datasets", "x.parquet")

  # A list column holding an environment has no Arrow type arrow can infer,
  # so write_parquet() errors before it ever opens the sink -- no temp file
  # is created, so this only proves the target was never written, not that
  # any cleanup ran. The companion test below forces the failure AFTER a
  # successful write, which is the case that actually exercises cleanup.
  expect_error(
    hvtiRutilities:::.write_parquet_atomic(
      data.frame(a = I(list(1, environment()))), target),
    NULL
  )
  expect_false(file.exists(target))
})

test_that("a rename failure after a successful write leaves no target and no tmp residue", {
  # testthat's local_mocked_bindings() cannot stub file.rename(): it is
  # called unqualified from base, not as an explicit package import, so
  # there is no binding for the mock to find. The rename is instead made to
  # fail the same way the OS itself reports a failure: renaming a file onto
  # an existing directory returns FALSE (with a warning) rather than
  # erroring, so the write below succeeds and the failure comes only from
  # the rename step -- the case the old test above cannot reach.
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  target <- file.path(dir, "x.parquet")
  dir.create(target)

  suppressWarnings(
    expect_error(
      hvtiRutilities:::.write_parquet_atomic(data.frame(a = 1:3), target),
      "move"
    )
  )
  expect_true(dir.exists(target))          # untouched -- still a directory
  tmp_residue <- list.files(dir, pattern = "\\.tmp$", full.names = TRUE)
  expect_length(tmp_residue, 0)
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

  # Task 5c, item 4: `file` names the dataset, not the file currently
  # storing it, and must never change on promotion -- every read-path lookup
  # keys on the source's basename, so a renamed entry would be invisible to
  # read_built() even though it just successfully served this one.
  m2 <- yaml::read_yaml(mp)
  expect_equal(m2$datasets[[1]]$file, "built_test.sas7bdat")
})

test_that("a cache miss on a promoted entry reconverts without rewriting its provenance", {
  # Task 5c, item 6: if a promoted entry's parquet is lost while its retired
  # source happens to still be present, the ordinary miss path would replace
  # the whole entry via update_manifest() -- recording the SOURCE's hash as
  # sha256 (wrong: role: "primary" means sha256 describes the parquet) and
  # dropping promoted_date/source_sha256, permanently breaking
  # verify_manifest() on a study whose data is intact. The parquet should be
  # reconverted, but every promotion field must survive untouched and the
  # recorded sha256 must describe the new parquet.
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir, n = 20L)
  cfg <- study_config(dir)
  read_built(cfg)                                  # populate the cache

  mp <- file.path(dir, "manifest.yaml")
  m <- yaml::read_yaml(mp)
  m$datasets[[1]]$role          <- "primary"
  m$datasets[[1]]$promoted_date <- "2026-08-01"
  m$datasets[[1]]$source_sha256 <- m$datasets[[1]]$sha256
  yaml::write_yaml(m, mp)

  parquet <- file.path(dir, "datasets", "built_test.parquet")
  unlink(parquet)                                  # lost, source still present

  d <- read_built(cfg)
  expect_equal(nrow(d), 20L)
  expect_true(file.exists(parquet))

  m3 <- yaml::read_yaml(mp)
  expect_equal(m3$datasets[[1]]$role, "primary")
  expect_equal(m3$datasets[[1]]$promoted_date, "2026-08-01")
  expect_equal(m3$datasets[[1]]$source_sha256, m$datasets[[1]]$source_sha256)
  expect_equal(m3$datasets[[1]]$sha256,
              digest::digest(parquet, algo = "sha256", file = TRUE))
})

test_that("refresh = TRUE on a promoted entry errors clearly even when the cache is disabled", {
  # Task 5c, item 7: the role: "primary" guard must fire before the
  # .cache_enabled() early return, or with arrow absent (or the cache
  # disabled) the call falls through to reader(path) on a retired,
  # possibly-missing source and dies inside haven instead of naming the
  # actual reason.
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir, n = 20L)
  cfg <- study_config(dir)
  read_built(cfg)                                  # populate the cache (needs arrow)

  mp <- file.path(dir, "manifest.yaml")
  m <- yaml::read_yaml(mp)
  m$datasets[[1]]$role <- "primary"
  yaml::write_yaml(m, mp)
  file.remove(file.path(dir, "datasets", "built_test.sas7bdat"))

  withr::local_options(hvtiRutilities.disable_parquet_cache = TRUE)
  expect_error(read_built(cfg, refresh = TRUE), "primary")
})

test_that("a promoted entry with no parquet names the parquet as the missing copy, not the retired source", {
  # Task 5c, item 7: the source was retired on purpose -- naming it as
  # "missing" in the error is misleading. For a promoted entry whose parquet
  # is also gone, the parquet is the copy that's actually missing.
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
  file.remove(file.path(dir, "datasets", "built_test.parquet"))

  expect_error(read_built(cfg), "built_test\\.parquet")
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

test_that("a whole-second source mtime is verified by sha256, not trusted directly", {
  # Whether an unchanged mtime alone proves an unchanged file is a property
  # of the filesystem, measured rather than assumed: a whole-second mtime
  # means the filesystem cannot see inside that second, so an exact tie
  # could also be a same-tick rewrite -- exactly what is constructed here.
  # Same size (the replacement keeps the same shape, so haven writes an
  # identical page-aligned 16384-byte file) means only the recorded sha256
  # can catch the rewrite, and it must not match the new content.
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir, n = 20L)
  cfg <- study_config(dir)
  read_built(cfg)                                    # populate the cache

  src <- file.path(dir, "datasets", "built_test.sas7bdat")
  size_before <- file.info(src)$size

  # Force the recorded stamp to a whole second, so the fast path cannot
  # apply and the sha256 fallback is exercised deterministically regardless
  # of this filesystem's native mtime resolution.
  whole_second <- as.POSIXct(floor(as.numeric(Sys.time())),
                              origin = "1970-01-01", tz = "UTC")
  Sys.setFileTime(src, whole_second)
  mp <- file.path(dir, "manifest.yaml")
  m  <- yaml::read_yaml(mp)
  m$datasets[[1]]$source_mtime <- format(whole_second, "%Y-%m-%d %H:%M:%OS6",
                                         tz = "UTC")
  yaml::write_yaml(m, mp)

  replacement <- data.frame(
    id      = 1:20,
    x       = as.numeric(1:20),
    dead    = c(rep(1L, 8), rep(0L, 12)),
    iv_dead = as.numeric(c(20:2, 999))              # same shape, changed value
  )
  suppressWarnings(haven::write_sas(replacement, src))
  Sys.setFileTime(src, whole_second)                  # exact, whole-second tie

  expect_equal(file.info(src)$size, size_before)      # confirms size is a dead end

  d <- read_built(cfg)
  expect_equal(d$iv_dead[20], 999)                    # NOT the stale value
})

test_that("an unchanged source with a whole-second mtime is trusted via sha256, not reconverted", {
  # The companion case: content genuinely unchanged, mtime an exact
  # whole-second tie. The sha256 fallback must recompute, find a match, and
  # serve the existing parquet rather than reconverting.
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir, n = 20L)
  cfg <- study_config(dir)
  read_built(cfg)                                     # populate the cache

  src <- file.path(dir, "datasets", "built_test.sas7bdat")
  whole_second <- as.POSIXct(floor(as.numeric(Sys.time())),
                              origin = "1970-01-01", tz = "UTC")
  Sys.setFileTime(src, whole_second)
  mp <- file.path(dir, "manifest.yaml")
  m  <- yaml::read_yaml(mp)
  m$datasets[[1]]$source_mtime <- format(whole_second, "%Y-%m-%d %H:%M:%OS6",
                                         tz = "UTC")
  m$datasets[[1]]$sha256 <- digest::digest(src, algo = "sha256", file = TRUE)
  yaml::write_yaml(m, mp)

  parquet <- file.path(dir, "datasets", "built_test.parquet")
  parquet_mtime_before <- file.info(parquet)$mtime

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

test_that("a fractional (sub-second) source mtime is trusted directly, without hashing", {
  # The companion to both tests above: when the filesystem's own mtime
  # carries a fractional part, that tick is microseconds wide and mtime
  # alone is trusted -- proved by corrupting the recorded sha256 and
  # confirming the cache is still served, untouched.
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir, n = 20L)
  cfg <- study_config(dir)
  read_built(cfg)

  src <- file.path(dir, "datasets", "built_test.sas7bdat")
  fractional <- as.POSIXct(as.numeric(Sys.time()) + 5.123456,
                            origin = "1970-01-01", tz = "UTC")
  Sys.setFileTime(src, fractional)
  mp <- file.path(dir, "manifest.yaml")
  m  <- yaml::read_yaml(mp)
  m$datasets[[1]]$source_mtime <- format(fractional, "%Y-%m-%d %H:%M:%OS6",
                                         tz = "UTC")
  m$datasets[[1]]$sha256 <- strrep("0", 64)           # deliberately wrong
  yaml::write_yaml(m, mp)

  parquet <- file.path(dir, "datasets", "built_test.parquet")
  parquet_mtime_before <- file.info(parquet)$mtime

  d <- read_built(cfg)
  expect_equal(nrow(d), 20L)
  expect_true(identical(file.info(parquet)$mtime, parquet_mtime_before))
})

# ---------------------------------------------------------------------------
# Task 5c, item 3: a torn read is caught and discarded, not cached.
# ---------------------------------------------------------------------------

test_that("a source that changes mid-read is discarded and errors, writing nothing", {
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir, n = 20L)
  src <- file.path(dir, "datasets", "built_test.sas7bdat")
  manifest_path <- file.path(dir, "manifest.yaml")

  # A reader that simulates a rewrite landing while the read is in flight:
  # the source's mtime differs by the time this "read" returns its frame,
  # even though the frame itself was already captured.
  reader <- function(f) {
    Sys.setFileTime(f, file.info(f)$mtime + 100)
    data.frame(id = 1:20)
  }

  expect_error(
    hvtiRutilities:::.cache_read(src, reader, manifest_path),
    "changed"
  )
  expect_false(file.exists(file.path(dir, "datasets", "built_test.parquet")))
  expect_false(file.exists(file.path(dir, "datasets", "built_test.schema.csv")))
  expect_false(file.exists(manifest_path))
})

# ---------------------------------------------------------------------------
# Change 1: the conversion round trip is verified, not just written.
# ---------------------------------------------------------------------------

test_that(".verify_parquet_roundtrip is silent when the parquet matches the frame it came from", {
  skip_if_no_arrow()
  target <- withr::local_tempfile(fileext = ".parquet")
  original <- data.frame(id = 1:3, x = c(1.5, 2.5, 3.5))
  arrow::write_parquet(original, target)

  expect_true(hvtiRutilities:::.verify_parquet_roundtrip(original, target))
  expect_true(file.exists(target))
})

test_that(".verify_parquet_roundtrip errors naming the first differing column and removes the parquet", {
  skip_if_no_arrow()
  target <- withr::local_tempfile(fileext = ".parquet")
  original <- data.frame(id = 1:3, x = c(1.5, 2.5, 3.5), y = c("a", "b", "c"))

  # Simulate a bad conversion: what's on disk disagrees with what haven
  # returned, in the second column ('x'), even though the first ('id')
  # matches -- proving the error names 'x', not just "something differs".
  corrupted <- original
  corrupted$x[2] <- 999
  arrow::write_parquet(corrupted, target)

  expect_error(
    hvtiRutilities:::.verify_parquet_roundtrip(original, target),
    "x"
  )
  expect_false(file.exists(target))
})

# ---------------------------------------------------------------------------
# Change 2: an unreadable parquet must not be fatal (except for role: primary).
# ---------------------------------------------------------------------------

test_that("an unreadable parquet warns and falls back to regenerating a role: source entry", {
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir, n = 20L)
  cfg <- study_config(dir)
  read_built(cfg)                                    # populate the cache

  parquet <- file.path(dir, "datasets", "built_test.parquet")
  writeLines("not a parquet file", parquet)           # truncate/corrupt

  expect_warning(d <- read_built(cfg), "regenerat")
  expect_equal(nrow(d), 20L)
  # The fallback actually rewrote a valid parquet, not just returned data.
  expect_equal(nrow(as.data.frame(arrow::read_parquet(parquet))), 20L)
})

test_that("an unreadable parquet errors plainly for a role: primary entry, naming it the only copy", {
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir, n = 20L)
  cfg <- study_config(dir)
  read_built(cfg)

  mp <- file.path(dir, "manifest.yaml")
  m  <- yaml::read_yaml(mp)
  m$datasets[[1]]$role <- "primary"
  yaml::write_yaml(m, mp)

  parquet <- file.path(dir, "datasets", "built_test.parquet")
  writeLines("not a parquet file", parquet)

  expect_error(read_built(cfg), "only copy")
})

# ---------------------------------------------------------------------------
# Change 3: a half-written stamp must not crash the validity check.
# ---------------------------------------------------------------------------

test_that("a half-written stamp (source_size present, source_mtime absent) is treated as invalid, not an error", {
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir, n = 20L)
  cfg <- study_config(dir)
  read_built(cfg)

  mp <- file.path(dir, "manifest.yaml")
  m  <- yaml::read_yaml(mp)
  m$datasets[[1]]$source_mtime <- NULL     # simulate a hand edit / interrupted write
  yaml::write_yaml(m, mp)

  expect_no_error(d <- read_built(cfg))
  expect_equal(nrow(d), 20L)
})

# ---------------------------------------------------------------------------
# Change 7: cache-hit fidelity, and the writer/reader agreeing end to end.
# ---------------------------------------------------------------------------

test_that("a cache hit still carries haven_labelled value labels, format.sas, and POSIXct", {
  # The existing round-trip test (above) writes and reads a synthetic frame
  # directly with arrow, never through the cache. This exercises the actual
  # cache-hit path -- .cache_read()'s second call, served from
  # arrow::read_parquet() -- which is exactly where a conversion defect
  # would show up and previously went untested. A stub reader is used
  # because haven::write_sas() cannot itself write value-labelled columns
  # into a real .sas7bdat (verified separately); the cache mechanism is
  # what's under test here, not haven's SAS writer.
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir)
  src <- file.path(dir, "datasets", "built_test.sas7bdat")
  manifest_path <- file.path(dir, "manifest.yaml")

  rich <- data.frame(id = 1:5, x = as.numeric(1:5))
  rich$grp <- haven::labelled(c(1, 2, 1, 2, 1), labels = c(No = 1, Yes = 2),
                              label = "Group")
  attr(rich$x, "format.sas") <- "BEST12"
  rich$dt <- as.POSIXct("2020-01-01", tz = "UTC") + (0:4) * 3600

  reader <- function(f) rich

  hvtiRutilities:::.cache_read(src, reader, manifest_path)          # miss
  d2 <- hvtiRutilities:::.cache_read(src, reader, manifest_path)    # hit

  expect_s3_class(d2$grp, "haven_labelled")
  expect_equal(attr(d2$grp, "labels"), c(No = 1, Yes = 2))
  expect_equal(attr(d2$grp, "label"), "Group")
  expect_equal(attr(d2$x, "format.sas"), "BEST12")
  expect_equal(format(d2$dt[1], tz = "UTC", usetz = TRUE), "2020-01-01 UTC")
})

test_that("read_built() records haven's version as the manifest entry's reader", {
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir)
  cfg <- study_config(dir)
  read_built(cfg)

  m <- yaml::read_yaml(file.path(dir, "manifest.yaml"))
  expect_equal(m$datasets[[1]]$reader,
               paste("haven", as.character(utils::packageVersion("haven"))))
})

test_that("verify_manifest() passes against a manifest the cache itself wrote", {
  # The only end-to-end proof that the cache's writer (.derived_paths()) and
  # verify_manifest()'s reader agree on the sidecar naming rule.
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir)
  cfg <- study_config(dir)
  read_built(cfg)

  report <- verify_manifest(file.path(dir, "manifest.yaml"))
  expect_true(all(report$status == "OK"))
})

# ---------------------------------------------------------------------------
# Task: three untested behaviours -- the 1e-4 tolerance branch, refresh with
# the cache disabled, and a legacy manifest (the latter lives in
# test-manifest.R, next to the other verify_manifest() coverage).
# ---------------------------------------------------------------------------

test_that(".cache_valid()'s mtime round-trip tolerance holds just under 1e-4s and not just over", {
  # The 1e-4s constant itself, and where it's assigned in the function body,
  # are out of scope here (triaged as acceptable to defer) -- this only pins
  # the behaviour at each side of it: a gap comfortably under the tolerance
  # is noise absorbed as an exact tie (and, since the mtime is fractional,
  # trusted directly); a gap comfortably over it is treated as a real
  # difference and invalidates the entry, with no sha256 fallback reached in
  # either case.
  dir <- withr::local_tempdir()
  src <- file.path(dir, "src.sas7bdat")
  writeLines("x", src)
  derived <- hvtiRutilities:::.derived_paths(src)
  writeLines("placeholder", derived$parquet)   # .cache_valid() only checks existence

  # A fractional mtime with margin either side of the tolerance for the
  # offset itself, so the comparison isn't sensitive to filesystem rounding.
  base_time <- as.POSIXct(as.numeric(Sys.time()), origin = "1970-01-01",
                          tz = "UTC") + 10.500000
  Sys.setFileTime(src, base_time)
  size <- as.numeric(file.info(src)$size)

  under <- base_time - 5e-5   # half the tolerance: within it
  entry_under <- list(source_size = size,
                      source_mtime = format(under, "%Y-%m-%d %H:%M:%OS6",
                                            tz = "UTC"))
  expect_true(hvtiRutilities:::.cache_valid(src, derived, entry_under))

  over <- base_time - 5e-4    # five times the tolerance: outside it
  entry_over <- list(source_size = size,
                     source_mtime = format(over, "%Y-%m-%d %H:%M:%OS6",
                                           tz = "UTC"))
  expect_false(hvtiRutilities:::.cache_valid(src, derived, entry_over))
})

test_that("refresh = TRUE with the cache disabled on a role: source entry just reads the source", {
  # refresh = TRUE only has cache machinery to override when the cache is
  # enabled. With it disabled, .cache_read() returns reader(path) directly
  # (the same path as an ordinary disabled-cache read) rather than erroring
  # or trying to honor refresh some other way.
  dir <- withr::local_tempdir()
  make_study_fixture(dir, n = 20L)
  cfg <- study_config(dir)
  withr::local_options(hvtiRutilities.disable_parquet_cache = TRUE)

  d <- read_built(cfg, refresh = TRUE)

  expect_equal(nrow(d), 20L)
  expect_false(file.exists(file.path(dir, "datasets", "built_test.parquet")))
})
