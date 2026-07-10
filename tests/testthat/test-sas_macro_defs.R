library(testthat)
library(hvtiRutilities)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

fx <- function(name) testthat::test_path("fixtures", name)

# ---------------------------------------------------------------------------
# sas_macro_defs — extraction
# ---------------------------------------------------------------------------

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
