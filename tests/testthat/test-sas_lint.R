library(testthat)
library(hvtiRutilities)

fx <- function(name) testthat::test_path("fixtures", name)

test_that(".sas_lint passes a well-formed file", {
  res <- hvtiRutilities:::.sas_lint(fx("alpha.sas"))

  expect_true(res$valid)
  expect_length(res$failures, 0L)
})

test_that(".sas_lint catches an unbalanced single quote", {
  res <- hvtiRutilities:::.sas_lint(fx("gamma_broken.sas"))

  expect_false(res$valid)
  expect_match(paste(res$failures, collapse = " "), "unbalanced quote")
})

test_that(".sas_lint catches an unmatched %macro", {
  res <- hvtiRutilities:::.sas_lint(fx("nomend.sas"))

  expect_false(res$valid)
  expect_match(paste(res$failures, collapse = " "), "%macro/%mend")
})

test_that(".sas_lint catches a file with no macro definition", {
  tmp <- withr::local_tempfile(fileext = ".sas")
  writeLines("proc print data=x; run;", tmp)

  res <- hvtiRutilities:::.sas_lint(tmp)
  expect_false(res$valid)
  expect_match(paste(res$failures, collapse = " "), "no %macro definition")
})

test_that(".sas_lint folds case for %MACRO/%MEND", {
  res <- hvtiRutilities:::.sas_lint(fx("upper.sas"))

  expect_true(res$valid)
})

test_that(".sas_lint ignores quotes inside comment lines", {
  tmp <- withr::local_tempfile(fileext = ".sas")
  writeLines(
    c("* it's a comment with an apostrophe;",
      "%macro ok;",
      "  proc print; run;",
      "%mend ok;"),
    tmp
  )

  expect_true(hvtiRutilities:::.sas_lint(tmp)$valid)
})
