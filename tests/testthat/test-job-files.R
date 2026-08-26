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
