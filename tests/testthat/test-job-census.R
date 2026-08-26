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

test_that("print leads with prefixes ranked by distinct studies", {
  # Purpose-built corpus, NOT the shared 12-file fixture. In that fixture
  # the only 2-study prefix is "ac", which also happens to sort first
  # alphabetically -- so asserting "ac before the 1-study prefixes" there
  # passes exactly as well under a regression that sorts purely
  # alphabetically (ignoring distinct_studies) as it does under the real
  # sort. It does not discriminate on the ordering criterion; it only
  # catches the ranked-table block being deleted outright.
  #
  # Here "hz" (late alphabetically) sits at 2 distinct studies and "ac"
  # (early alphabetically) sits at 1, so alphabetical order and
  # distinct-studies order disagree: correct output ranks hz ahead of ac,
  # while a regression to alphabetical-only ranking would put ac ahead of
  # hz. This still also fails if the ranked-table block stops printing
  # entirely, since both grep matches below come up empty.
  d <- withr::local_tempdir()
  dir.create(file.path(d, "s1", "distributions"), recursive = TRUE)
  dir.create(file.path(d, "s2", "distributions"), recursive = TRUE)
  dir.create(file.path(d, "s3", "distributions"), recursive = TRUE)
  file.create(file.path(d, "s1", "distributions", "hz.a.sas"))
  file.create(file.path(d, "s2", "distributions", "hz.b.sas"))
  file.create(file.path(d, "s3", "distributions", "ac.a.sas"))

  out <- capture.output(print(job_census(d)))

  # hz's row must show a distinct-studies count of 2 ...
  hz_row <- grep("^\\s*[0-9]+\\s+hz\\s+2\\b", out)
  expect_length(hz_row, 1L)

  # ... and ac's row a count of 1 ...
  ac_row <- grep("^\\s*[0-9]+\\s+ac\\s+1\\b", out)
  expect_length(ac_row, 1L)

  # ... with hz (the 2-study prefix) printed ahead of ac (the 1-study one).
  expect_true(hz_row < ac_row)
})

test_that("print reports every accounting bucket, including empty ones", {
  # An empty bucket that prints "0" is a claim. A bucket that prints nothing
  # is indistinguishable from a bucket nobody computed -- which is how the
  # hazard census under-reported twice.
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  out <- paste(capture.output(print(job_census(d))), collapse = "\n")
  expect_match(out, "unplaced")
  expect_match(out, "nested")
  expect_match(out, "[Uu]nknown prefix")
  expect_match(out, "[Mm]isfiled")
})

test_that("print names the unknown prefix and the misfiled job", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  out <- paste(capture.output(print(job_census(d))), collapse = "\n")
  expect_match(out, "zz")            # the unknown prefix
  expect_match(out, "hz.misfiled")   # the prefix outside its folder
})

test_that("print returns its argument invisibly", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)
  x <- job_census(d)

  expect_invisible(print(x))
})

test_that("print errors clearly when the \"files\" attribute is missing", {
  # A column subset (x[, c(...)]) or a hand-built object keeps the class but
  # drops the attribute. Without a guard, files$status == s on NULL gives
  # logical(0), sum() reports a confident 0 for every Placement bucket, and
  # the function only later aborts at nrow(unknown) with an opaque
  # "argument is of length zero" -- exactly the silent-narrowing failure
  # this print method exists to prevent.
  x <- data.frame(
    study = "alpha", prefix = "hz", folder = "distributions",
    is_template = FALSE, n_jobs = 1L, n_files = 1L,
    stringsAsFactors = FALSE
  )
  class(x) <- c("hvti_job_census", "data.frame")

  expect_error(print(x), regexp = "\"?files\"?.*job_census\\(\\)|job_census\\(\\).*\"?files\"?")
})

test_that("print prints 0 for a bucket that is genuinely empty", {
  # The standard fixture has at least one member in every bucket, so a
  # regression that wrapped a count line in `if (n) ...` would pass that
  # suite untouched. Build a corpus with no misfiled job and no unplaced
  # file, and assert the count lines still print "0".
  d <- withr::local_tempdir()
  dir.create(file.path(d, "alpha", "distributions"), recursive = TRUE)
  file.create(file.path(d, "alpha", "distributions", "hz.dead.lst"))

  out <- paste(capture.output(print(job_census(d))), collapse = "\n")
  expect_match(out, "unplaced: 0\\b")
  expect_match(out, "Misfiled[^:]*: 0\\b")
})
