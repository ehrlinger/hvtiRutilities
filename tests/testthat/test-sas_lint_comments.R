library(testthat)
library(hvtiRutilities)

# ---------------------------------------------------------------------------
# Block comments spanning lines
#
# .strip_comments() applied gsub("/\\*.*?\\*/") to each line independently, so
# a /* ... */ block spanning lines survived. Prose inside it -- "Pearson's
# Chi-square" -- was then counted as an unbalanced quote and the file dropped.
# ---------------------------------------------------------------------------

test_that(".strip_comments removes a block comment spanning several lines", {
  lines <- c(
    "/* Purpose : Give N (%) for variable=1, Pearson's Chi-square",
    "   Author  : someone",
    "   Note    : Fisher's Exact test is used here */",
    "%macro keepme(a=1);",
    "%mend keepme;"
  )
  out <- hvtiRutilities:::.strip_comments(lines)
  expect_false(any(grepl("Pearson", out)))
  expect_false(any(grepl("Fisher", out)))
  expect_true(any(grepl("%macro keepme", out)))
})

test_that(".strip_comments still removes a single-line block comment", {
  out <- hvtiRutilities:::.strip_comments("data x; /* inline 'note' */ run;")
  expect_false(grepl("note", out))
  expect_true(grepl("data x;", out))
})

test_that(".strip_comments leaves code outside a closed block intact", {
  lines <- c("/* a 'comment' */", "if x = 'y' then z = 1;")
  out <- hvtiRutilities:::.strip_comments(lines)
  expect_true(any(grepl("if x =", out)))
})

test_that(".sas_lint does not flag apostrophes inside a block comment", {
  f <- withr::local_tempfile(fileext = ".sas")
  writeLines(c(
    "/* Purpose : Pearson's Chi-square test",
    "   Note    : Fisher's Exact test */",
    "%macro ok(a=1);",
    "  data x; y = 1; run;",
    "%mend ok;"
  ), f)
  res <- hvtiRutilities:::.sas_lint(f)
  expect_true(res$valid)
})

# ---------------------------------------------------------------------------
# do/end balance
#
# Textual do/end balance is not a validity property of SAS macro source. The
# count is confounded by the `end=` data set option, PROC SQL CASE...END,
# DATA step SELECT...END, and blocks emitted conditionally at macro time.
# ---------------------------------------------------------------------------

test_that(".sas_lint accepts the end= data set option", {
  f <- withr::local_tempfile(fileext = ".sas")
  writeLines(c(
    "%macro lastobs(dsn=);",
    "  data out; set &dsn end=last; if last; run;",
    "%mend lastobs;"
  ), f)
  expect_true(hvtiRutilities:::.sas_lint(f)$valid)
})

test_that(".sas_lint accepts PROC SQL CASE ... END", {
  f <- withr::local_tempfile(fileext = ".sas")
  writeLines(c(
    "%macro attrs(dsn=);",
    "  proc sql;",
    "    select case informat when ' ' then '0' else informat end as informat",
    "    from dictionary.columns;",
    "  quit;",
    "%mend attrs;"
  ), f)
  expect_true(hvtiRutilities:::.sas_lint(f)$valid)
})

test_that(".sas_lint reports no do/end failure at all", {
  f <- withr::local_tempfile(fileext = ".sas")
  writeLines(c(
    "%macro lopsided(a=1);",
    "  data x; do i = 1 to 10; y = i; run;",
    "%mend lopsided;"
  ), f)
  res <- hvtiRutilities:::.sas_lint(f)
  expect_false(any(grepl("do/end", res$failures)))
})

# ---------------------------------------------------------------------------
# Checks that must survive
# ---------------------------------------------------------------------------

test_that(".sas_lint still catches a genuinely unbalanced quote in code", {
  f <- withr::local_tempfile(fileext = ".sas")
  writeLines(c(
    "%macro broken(a=1);",
    "  define dev1/display 'Number*events of*interest;",
    "%mend broken;"
  ), f)
  res <- hvtiRutilities:::.sas_lint(f)
  expect_false(res$valid)
  expect_true(any(grepl("unbalanced quote", res$failures)))
})

test_that(".sas_lint still catches %macro/%mend imbalance", {
  f <- withr::local_tempfile(fileext = ".sas")
  writeLines(c("%macro truncated(a=1);", "  data x; run;"), f)
  res <- hvtiRutilities:::.sas_lint(f)
  expect_false(res$valid)
  expect_true(any(grepl("%macro/%mend", res$failures)))
})

test_that(".sas_lint still catches a file with no macro definition", {
  f <- withr::local_tempfile(fileext = ".sas")
  writeLines(c("NOTE: The SAS System stopped.", "ERROR: nothing here."), f)
  res <- hvtiRutilities:::.sas_lint(f)
  expect_false(res$valid)
  expect_true(any(grepl("no %macro definition", res$failures)))
})
