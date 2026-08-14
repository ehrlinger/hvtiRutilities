library(testthat)
library(hvtiRutilities)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

fx <- function(name) testthat::test_path("fixtures", name)

# Write a .sas file containing a byte that is valid Latin-1 but invalid UTF-8
# (0xB5, a lone continuation byte = "micro sign"). Committing such a file would
# be non-portable, so it is built at runtime. Mirrors the 7 Latin-1 files found
# in the real macro library.
#
# The header comment is terminated with `;`. It was not, originally, which made
# the fixture invalid SAS in a way nothing noticed: a `*` comment runs to the
# next semicolon, so the unterminated header swallowed the %macro statement on
# the following line and the file defined no macro at all. The per-line rules
# could not see that and counted the definition anyway; the scanner can, so the
# fixture now says what it always meant to say.
write_latin1_sas <- function() {
  path <- tempfile(fileext = ".sas")
  writeBin(
    c(charToRaw("* threshold "), as.raw(0xB5), charToRaw("g comment;\n"),
      charToRaw("%macro latin1(dsn);\n  data &dsn.; run;\n%mend latin1;\n")),
    path
  )
  path
}

# ---------------------------------------------------------------------------
# sas_macro_defs — extraction
# ---------------------------------------------------------------------------

test_that("sas_macro_defs reads a Latin-1 file without an encoding crash", {
  p <- write_latin1_sas()

  res <- sas_macro_defs(p)

  expect_equal(nrow(res), 1L)
  expect_equal(res$macro, "latin1")
  expect_true(nzchar(res$body_hash))
})

test_that(".sas_lint and sas_macro_signature survive Latin-1 bytes", {
  p <- write_latin1_sas()

  expect_true(hvtiRutilities:::.sas_lint(p)$valid)
  expect_silent(sas_macro_signature(p))
})

test_that("sas_macro_defs extracts a single definition", {
  res <- sas_macro_defs(fx("alpha.sas"))

  expect_s3_class(res, "data.frame")
  expect_equal(nrow(res), 1L)
  expect_equal(res$macro, "alpha")
  expect_equal(res$params, "dsn")
  expect_equal(res$line_start, 1L)
  expect_equal(res$line_end, 3L)
  expect_true(nzchar(res$body_hash))
})

test_that("sas_macro_defs extracts every definition in a multi-macro file", {
  res <- sas_macro_defs(fx("multi.sas"))

  expect_equal(nrow(res), 3L)
  expect_setequal(res$macro, c("helper_one", "helper_two", "multi"))
})

test_that("sas_macro_defs folds case: %MACRO UPPER is found", {
  res <- sas_macro_defs(fx("upper.sas"))

  expect_equal(nrow(res), 1L)
  expect_equal(res$macro, "upper")
  expect_equal(res$params, "in")
  expect_true(nzchar(res$body_hash))
})

test_that("sas_macro_defs errors on an unmatched %macro", {
  expect_error(
    sas_macro_defs(fx("nomend.sas")),
    "unmatched '%macro nomend'.*line 1",
    fixed = FALSE
  )
})

test_that("sas_macro_defs errors on a file with no macro definition", {
  tmp <- withr::local_tempfile(fileext = ".sas")
  writeLines("proc print data=x; run;", tmp)

  expect_error(sas_macro_defs(tmp), "no %macro definition")
})

# ---------------------------------------------------------------------------
# sas_macro_defs — body hashing
# ---------------------------------------------------------------------------

test_that("identical bodies hash identically across files", {
  a <- sas_macro_defs(fx("delta.sas"))
  b <- sas_macro_defs(fx("delta_dup.sas"))

  expect_equal(a$body_hash, b$body_hash)
})

test_that("divergent bodies hash differently (_freq_ vs freq)", {
  a <- sas_macro_defs(fx("zeta.sas"))
  b <- sas_macro_defs(fx("zeta_old.sas"))

  expect_equal(a$macro, b$macro)
  expect_false(identical(a$body_hash, b$body_hash))
})

test_that("body hash ignores case and whitespace, not content", {
  t1 <- withr::local_tempfile(fileext = ".sas")
  t2 <- withr::local_tempfile(fileext = ".sas")
  writeLines(c("%macro q;", "  proc print; run;", "%mend q;"), t1)
  writeLines(c("%MACRO Q;", "PROC PRINT;    RUN;", "%MEND Q;"), t2)

  expect_equal(sas_macro_defs(t1)$body_hash, sas_macro_defs(t2)$body_hash)
})
