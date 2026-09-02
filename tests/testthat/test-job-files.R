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
  expect_equal(nrow(out), 16L)   # every file in the fixture
  expect_equal(
    names(out),
    c("path", "study", "folder", "status", "depth", "naming", "prefix",
      "is_template", "qualifier1", "qualifiers", "n_qualifiers", "stem",
      "ext", "prefix_class", "folder_expected",
      "folder_ok")
  )
})

test_that("the stem drops only the final extension", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)
  out <- job_files(d)

  hz <- out[out$prefix %in% "hz" & !out$is_template, ]
  expect_setequal(unique(hz$stem),
                  c("hz.dead", "hz.misfiled", "02-hz-dead_pa"))
  # hz.dead.sas~ keeps hz.dead: the backup shares the stem it backs up.
  expect_equal(sum(hz$stem == "hz.dead"), 4L)
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
  # dropped every R-side job in the corpus. The canary must therefore be the
  # R-side extensions themselves -- .md would survive a filter that removed
  # exactly qmd/R/rda, which is the regression this test exists to catch.
  d <- withr::local_tempdir()
  make_corpus_fixture(d)
  out <- job_files(d)

  expect_true("qmd" %in% out$ext)
  expect_true("rda" %in% out$ext)
  expect_true("md" %in% out$ext)
})

test_that("multiple roots are swept and the rows concatenate", {
  d1 <- withr::local_tempdir()
  d2 <- withr::local_tempdir()
  make_corpus_fixture(d1)
  make_corpus_fixture(d2)

  expect_equal(nrow(job_files(c(d1, d2))), 32L)
})

test_that("an unparsed prefix does not fall into the taxonomy's NA-prefix row", {
  # hvti_taxonomy()$prefix has one genuine NA (the "estimates" row, an
  # artifact kind rather than an analysis type). match() pairs NA with NA by
  # default, so a file whose prefix does not parse -- also NA -- would match
  # that row unless match() is called with incomparables = NA_character_.
  # Every basename in the shared fixture contains a dot and parses to a real
  # prefix, so none of them exercise this path; a name with no dot at all is
  # needed to produce an unparsed (NA) prefix.
  d <- withr::local_tempdir()
  dir.create(file.path(d, "alpha", "distributions"), recursive = TRUE)
  file.create(file.path(d, "alpha", "distributions", "Makefile"))

  out <- job_files(d)
  expect_true(is.na(out$prefix))
  expect_true(is.na(out$folder_expected))
  expect_false(identical(out$folder_expected, "estimates"))
})

test_that("a leading-dot filename keeps its whole name as the stem", {
  # .DS_Store has one dot, at position 1. Splitting on the final dot the same
  # way an extensioned name is split leaves stem = "" and ext = "DS_Store" --
  # wrong on its face, and macOS writes these throughout any mounted share
  # this corpus is swept from. A name whose only dot is leading should be
  # treated like a name with no dot at all: whole name as stem, ext NA.
  d <- withr::local_tempdir()
  dir.create(file.path(d, "alpha", "distributions"), recursive = TRUE)
  file.create(file.path(d, "alpha", "distributions", ".DS_Store"))

  out <- job_files(d)
  expect_equal(out$stem, ".DS_Store")
  expect_true(is.na(out$ext))
})

test_that("a root with no files returns a 0-row frame with the full column set", {
  d <- withr::local_tempdir()

  out <- job_files(d)
  expect_equal(nrow(out), 0L)
  expect_equal(
    names(out),
    c("path", "study", "folder", "status", "depth", "naming", "prefix",
      "is_template", "qualifier1", "qualifiers", "n_qualifiers", "stem",
      "ext", "prefix_class", "folder_expected",
      "folder_ok")
  )
})

test_that("a backslash-separated path splits into components, not one blob", {
  # On Windows normalizePath() defaults to winslash = "\\", so the
  # root-relative path arrives as alpha\\distributions\\hz.dead.lst. Splitting
  # that on "/" alone yields ONE component, head(p, -1L) is character(0), and
  # every file in the corpus classifies "unplaced" -- a zero-row census on a
  # platform R-CMD-check.yaml actually runs.
  #
  # This asserts on the separator-handling directly rather than through
  # normalizePath(), so it is a real assertion on macOS and Linux too.
  out <- hvtiRutilities:::.job_placement_rel(
    "C:\\corpus\\alpha\\distributions\\hz.dead.lst", "C:\\corpus"
  )
  expect_equal(out$status, "placed")
  expect_equal(out$study, "alpha")
  expect_equal(out$folder, "distributions")
  expect_equal(out$depth, 0L)
})

test_that("forward-slash paths still split the same way", {
  out <- hvtiRutilities:::.job_placement_rel(
    "/corpus/alpha/graphs/Training/hp.curve.pdf", "/corpus"
  )
  expect_equal(out$status, "nested")
  expect_equal(out$study, "alpha")
  expect_equal(out$depth, 1L)
})

test_that("the same root passed twice is swept once", {
  # Otherwise every file is emitted twice and n_files doubles silently.
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  expect_equal(nrow(job_files(c(d, d))), nrow(job_files(d)))
})

test_that("a root nested inside another root warns and is dropped", {
  # job_files(c("/studies", "/studies/cardiac/aorta")) emits the same physical
  # file twice under two different study labels, so a prefix present in ONE
  # study reads as two distinct studies and the template gate falsely
  # unblocks. That is the exact decision this sweep exists to make.
  d <- withr::local_tempdir()
  make_corpus_fixture(d)
  inner <- file.path(d, "alpha")

  expect_warning(out <- job_files(c(d, inner)), "counted twice")
  expect_equal(nrow(out), nrow(job_files(d)))
})

test_that("overlapping roots do not inflate a prefix's distinct-study count", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  expect_warning(cen <- job_census(c(d, file.path(d, "alpha"))),
                 "counted twice")
  hz <- cen[!cen$is_template & cen$prefix %in% "hz", , drop = FALSE]
  expect_equal(length(unique(hz$study)), 1L)
})

test_that("a root that IS a study warns -- a root must sit above studies", {
  # Passing two study directories is the natural way to compare two studies,
  # and it is exactly wrong: the taxonomy folder is then the first path
  # component, both studies label as ".", they merge, and every prefix reports
  # 1 distinct study -- the template gate falsely BLOCKED.
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  expect_warning(job_files(file.path(d, "alpha")), "must sit ABOVE")
})

test_that("job_files() errors when a root does not exist", {
  # A share that failed to mount is an empty directory that looks exactly
  # like a corpus with no jobs in it. A confident zero-row answer there is
  # the failure this sweep exists to make impossible.
  missing <- file.path(tempdir(), "no-such-corpus-4b1f")
  expect_error(job_files(missing), "no-such-corpus-4b1f")
})

test_that("job_files() errors on an NA root rather than sweeping nothing", {
  expect_error(job_files(NA_character_), "NA")
})

test_that("job_files() errors when a root is a file, not a directory", {
  d <- withr::local_tempdir()
  f <- file.path(d, "notes.txt")
  file.create(f)

  expect_error(job_files(f), "not a directory")
})

test_that("job_files() errors on a non-character roots argument, naming what was passed", {
  expect_error(job_files(1L), "`roots` must be a character vector")
  expect_error(job_files(1L), "integer")
})

test_that("job_files() errors on a zero-length roots argument, naming what was expected", {
  expect_error(job_files(character(0)), "at least one")
  expect_error(job_files(character(0)), "zero-length")
})

test_that("folder_ok is NA when either side is unknown, never FALSE", {
  # folder_ok is defined as folder == folder_expected, which is NA when
  # either side is NA. Shipping it as FALSE makes !folder_ok select unplaced
  # files and unparsed names alongside genuinely misfiled jobs -- README.md
  # and Makefile come back as "misfiled", which they are not.
  d <- withr::local_tempdir()
  make_corpus_fixture(d)
  out <- job_files(d)

  unplaced <- out[out$status %in% "unplaced", , drop = FALSE]
  expect_true(nrow(unplaced) >= 1L)
  expect_true(all(is.na(unplaced$folder_ok)))

  d2 <- withr::local_tempdir()
  dir.create(file.path(d2, "alpha", "distributions"), recursive = TRUE)
  file.create(file.path(d2, "alpha", "distributions", "Makefile"))
  out2 <- job_files(d2)
  expect_true(is.na(out2$prefix))
  expect_true(is.na(out2$folder_ok))
})

test_that("the fixture exercises every naming convention and prefix class", {
  # The fixture is the thing that decides what the rest of this suite can
  # catch. It shipped holding twelve SAS-shaped files and not one R-side
  # file, so an extension filter dropping exactly R/qmd/rda -- the regression
  # the design spec section 4.4 exists to prevent -- passed the whole suite.
  # Assert the coverage here, so the fixture cannot quietly narrow the way
  # the hazard census's printed summary once did.
  d <- withr::local_tempdir()
  make_corpus_fixture(d)
  out <- job_files(d)

  expect_setequal(
    unique(stats::na.omit(out$naming)),
    c("legacy", "template", "set", "r_transitional")
  )
  expect_setequal(
    unique(stats::na.omit(out$prefix_class)),
    c("known", "non_prefix", "unknown")
  )
  expect_setequal(unique(out$status), c("placed", "nested", "unplaced"))
  expect_true(any(out$is_template))
})

test_that("a file under a symlinked subdir keeps the study it was walked into", {
  # normalizePath() resolves symlinks. When a subdirectory inside the corpus
  # points somewhere outside the root, the resolved path no longer carries
  # the root prefix, so stripping by position slices at the wrong offset and
  # produces a mangled `study` -- silently, with no error. The walked path is
  # the right answer: a file found under a study belongs to that study.
  skip_on_os("windows")

  d <- withr::local_tempdir()
  outside <- withr::local_tempdir()
  dir.create(file.path(outside, "distributions"), recursive = TRUE)
  file.create(file.path(outside, "distributions", "hz.dead.lst"))

  dir.create(file.path(d, "alpha"), recursive = TRUE)
  file.symlink(outside, file.path(d, "alpha", "linked"))
  skip_if_not(file.exists(file.path(d, "alpha", "linked", "distributions",
                                    "hz.dead.lst")))

  out <- job_files(d)
  row <- out[out$stem %in% "hz.dead", ]

  expect_equal(nrow(row), 1L)
  expect_equal(row$study, "alpha/linked")
  expect_equal(row$folder, "distributions")
  expect_equal(row$status, "placed")
})

test_that("a directory is never returned as a file row", {
  # The per-file dir.exists() filter was removed as redundant. This pins the
  # property it was guarding, so the removal cannot regress silently.
  d <- withr::local_tempdir()
  dir.create(file.path(d, "alpha", "distributions", "nested.dir"),
             recursive = TRUE)
  file.create(file.path(d, "alpha", "distributions", "hz.dead.lst"))

  out <- job_files(d)
  expect_false(any(dir.exists(out$path)))
  expect_equal(nrow(out), 1L)
})

test_that("a filename invalid in the session encoding is escaped, not fatal", {
  # This cannot be an end-to-end test: APFS refuses to create a file whose
  # name is not valid UTF-8 ("Illegal byte sequence"), so the corpus case is
  # unreproducible on macOS and on the macOS CI runner. The sanitiser is
  # therefore tested directly, on the byte sequence that actually broke a
  # corpus sweep -- a Latin-1 e-acute (0xe9) in a job filename.
  bad <- rawToChar(as.raw(c(0x68, 0x7a, 0x2e, 0xe9, 0x74, 0x75, 0x2e,
                            0x6c, 0x73, 0x74)))
  out <- hvtiRutilities:::.sanitize_paths(bad)

  expect_false(is.na(iconv(out, "UTF-8", "UTF-8")))
  expect_match(out, "<e9>", fixed = TRUE)
})

test_that("the sanitiser leaves valid paths untouched", {
  valid <- c("/a/b/hz.dead.lst", "/a/b/étude.sas")
  expect_identical(hvtiRutilities:::.sanitize_paths(valid), valid)
})

test_that("an escaped name still parses to its prefix, stem and extension", {
  # The escape must not cost the classification: an unreadable byte in the
  # middle of a name should still leave a usable prefix, since that is what
  # the census counts.
  bad <- rawToChar(as.raw(c(0x68, 0x7a, 0x2e, 0xe9, 0x74, 0x75, 0x2e,
                            0x6c, 0x73, 0x74)))
  san <- hvtiRutilities:::.sanitize_paths(bad)
  f <- hvtiRutilities:::.job_name_fields(san)

  expect_equal(f$naming, "legacy")
  expect_equal(f$prefix, "hz")
})

test_that("the sanitiser stays non-fatal when warnings are errors", {
  # Not because iconv() warns -- it does not; it returns NA silently, which is
  # what the probe relies on. This pins that property. If a future change
  # swapped the probe for something that warns (validUTF8(), a regex, an
  # encoding conversion with a different `sub`), the sweep would abort again
  # under strict warning handling, and the failure would look like the very
  # bug this function was written to fix.
  withr::local_options(warn = 2)

  bad <- rawToChar(as.raw(c(0x68, 0x7a, 0x2e, 0xe9, 0x74, 0x75, 0x2e,
                            0x6c, 0x73, 0x74)))
  expect_no_error(out <- hvtiRutilities:::.sanitize_paths(bad))
  expect_match(out, "<e9>", fixed = TRUE)

  # And the whole sweep, not just the helper.
  d <- withr::local_tempdir()
  dir.create(file.path(d, "alpha", "distributions"), recursive = TRUE)
  file.create(file.path(d, "alpha", "distributions", "hz.dead.lst"))
  expect_no_error(res <- job_files(d))
  expect_equal(nrow(res), 1L)
})
