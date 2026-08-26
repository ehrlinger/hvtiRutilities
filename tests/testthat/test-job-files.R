library(testthat)
library(hvtiRutilities)

test_that("a file directly in a taxonomy folder is placed at depth 0", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  out <- hvtiRutilities:::.job_placement(
    file.path(d, "alpha/distributions/hz.dead.lst"), d
  )
  expect_equal(out$status, "placed")
  expect_equal(out$study, "alpha")
  expect_equal(out$folder, "distributions")
  expect_equal(out$depth, 0L)
})

test_that("a file nested below the folder keeps its study and records depth", {
  # graphs/Training/ is real in preserve_root. A naive "study is the file's
  # grandparent" rule credits these to a study named "graphs".
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  out <- hvtiRutilities:::.job_placement(
    file.path(d, "alpha/graphs/Training/hp.curve.pdf"), d
  )
  expect_equal(out$status, "nested")
  expect_equal(out$study, "alpha")
  expect_equal(out$folder, "graphs")
  expect_equal(out$depth, 1L)
})

test_that("a file with no taxonomy ancestor is unplaced, not dropped", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  out <- hvtiRutilities:::.job_placement(file.path(d, "alpha/README.md"), d)
  expect_equal(out$status, "unplaced")
  expect_true(is.na(out$study))
  expect_true(is.na(out$folder))
  expect_true(is.na(out$depth))
})

test_that("study is relative to the root, never absolute", {
  # The same study resolves to different absolute paths on the server and on
  # a Mac mount; an absolute study makes two runs of the same corpus incomparable.
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  out <- hvtiRutilities:::.job_placement(
    file.path(d, "beta/distributions/ac.dead.lst"), d
  )
  expect_equal(out$study, "beta")
  expect_false(grepl(d, out$study, fixed = TRUE))
})

test_that("a root holding regex metacharacters still strips correctly", {
  # The root is arbitrary input. An earlier draft anchored a regex on the
  # unescaped root, which passed every other test in this file because `.`
  # and `-` match themselves -- and produced a wrong study the moment a
  # directory name carried a metacharacter. Strip by position instead.
  d <- withr::local_tempdir()
  odd <- file.path(d, "study (copy) v1.2+")
  dir.create(file.path(odd, "epsilon", "distributions"), recursive = TRUE)
  file.create(file.path(odd, "epsilon", "distributions", "ac.dead.lst"))

  out <- hvtiRutilities:::.job_placement(
    file.path(odd, "epsilon/distributions/ac.dead.lst"), odd
  )
  expect_equal(out$study, "epsilon")
  expect_equal(out$status, "placed")
})

test_that("a multi-level study path is joined, not truncated", {
  # Real studies are cardiac/rhythm/maze/atricure/gender. Taking only the
  # taxonomy folder's immediate parent would collapse every study under maze
  # into one row named "gender".
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  out <- hvtiRutilities:::.job_placement(
    file.path(d, "gamma/sub/distributions/ac.dead.lst"), d
  )
  expect_equal(out$study, "gamma/sub")
  expect_equal(out$folder, "distributions")
  expect_equal(out$depth, 0L)
})

test_that("job_files() returns one row per file and drops nothing", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  out <- job_files(d)
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 12L)   # every file in the fixture
  expect_equal(
    names(out),
    c("path", "study", "folder", "status", "depth", "naming", "prefix",
      "is_template", "stem", "ext", "prefix_class", "folder_expected",
      "folder_ok")
  )
})

test_that("the stem drops only the final extension", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)
  out <- job_files(d)

  hz <- out[out$prefix %in% "hz" & !out$is_template, ]
  expect_true(all(hz$stem %in% c("hz.dead", "hz.misfiled")))
})

test_that("an editor backup shares its stem, so it inflates files not jobs", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)
  out <- job_files(d)

  dead <- out[out$stem %in% "hz.dead" & !out$is_template, ]
  expect_equal(nrow(dead), 4L)                      # lst sas log sas~
  expect_equal(length(unique(dead$stem)), 1L)
  expect_true("sas~" %in% dead$ext)
})

test_that("prefix_class is three-way, not two", {
  # hvti_non_prefixes() already distinguishes 'not a prefix' from 'a prefix
  # nobody documented'. Collapsing them reports pp -- 20 files in
  # preserve_root -- as a discovery.
  d <- withr::local_tempdir()
  make_corpus_fixture(d)
  out <- job_files(d)

  expect_equal(out$prefix_class[out$prefix %in% "hz"][1], "known")
  expect_equal(out$prefix_class[out$prefix %in% "pp"], "non_prefix")
  expect_equal(out$prefix_class[out$prefix %in% "zz"], "unknown")
})

test_that("folder_ok flags a prefix sitting outside its taxonomy folder", {
  # hz belongs in distributions. The corpus answer for hz was 'zero misfiled'
  # -- but that was verified, not assumed, and every prefix gets the check.
  d <- withr::local_tempdir()
  make_corpus_fixture(d)
  out <- job_files(d)

  mis <- out[out$stem %in% "hz.misfiled", ]
  expect_equal(mis$folder, "analyses")
  expect_equal(mis$folder_expected, "distributions")
  expect_false(mis$folder_ok)

  ok <- out[out$stem %in% "hz.dead" & out$ext %in% "lst" & !out$is_template, ]
  expect_true(ok$folder_ok)
})

test_that("a tp. file is a template and keeps its real prefix", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)
  out <- job_files(d)

  tpl <- out[out$is_template, ]
  expect_equal(nrow(tpl), 1L)
  expect_equal(tpl$prefix, "hz")
  expect_equal(tpl$stem, "tp.hz.dead")
})

test_that("there is no extension allowlist", {
  # A draft default of sas/lst/log/pdf/rtf, tuned on hz/ac/hp/bh, would have
  # dropped every R-side job in the corpus. .md is not a job extension and is
  # still present, because the filter does not exist.
  d <- withr::local_tempdir()
  make_corpus_fixture(d)
  out <- job_files(d)

  expect_true("md" %in% out$ext)
})

test_that("multiple roots are swept and the rows concatenate", {
  d1 <- withr::local_tempdir()
  d2 <- withr::local_tempdir()
  make_corpus_fixture(d1)
  make_corpus_fixture(d2)

  expect_equal(nrow(job_files(c(d1, d2))), 24L)
})
