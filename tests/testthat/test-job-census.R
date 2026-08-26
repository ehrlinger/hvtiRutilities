library(testthat)
library(hvtiRutilities)

test_that("job_census() counts jobs by distinct stem and files by row", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  out <- job_census(d)
  expect_s3_class(out, "hvti_job_census")
  expect_true(all(c("study", "prefix", "folder", "is_template",
                    "n_jobs", "n_files") %in% names(out)))

  hz <- out[out$study %in% "alpha" & out$prefix %in% "hz" &
              out$folder %in% "distributions" & !out$is_template, ]
  expect_equal(hz$n_jobs, 1L)    # hz.dead
  expect_equal(hz$n_files, 4L)   # lst sas log sas~
})

test_that("templates are counted separately from jobs, never dropped", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)
  out <- job_census(d)

  tpl <- out[out$is_template, ]
  expect_equal(nrow(tpl), 1L)
  expect_equal(tpl$prefix, "hz")
  expect_equal(tpl$n_jobs, 1L)
})

test_that("job_census() accepts a job_files() frame without re-walking", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  expect_equal(job_census(job_files(d)), job_census(d))
})

test_that("the source rows are retained so accounting stays reachable", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  out <- job_census(d)
  expect_equal(nrow(attr(out, "files")), 12L)
})

test_that("unplaced files do not silently vanish from the roll-up", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  out <- job_census(d)
  files <- attr(out, "files")
  expect_true("unplaced" %in% files$status)
})

test_that("a second study is what makes a prefix templatable", {
  # The gate the roadmap needs: distinct studies per prefix, jobs only. This
  # is the shape of the 2026-08-26 hand-count -- hm/hs/bh sat at one study
  # each and therefore could not be templated.
  d <- withr::local_tempdir()
  make_corpus_fixture(d)
  out <- job_census(d)

  distinct_studies <- function(p) {
    length(unique(out$study[!out$is_template & out$prefix %in% p]))
  }

  expect_equal(distinct_studies("hz"), 1L)   # alpha only -- blocked
  expect_equal(distinct_studies("ac"), 2L)   # beta and gamma/sub -- unblocked
})
