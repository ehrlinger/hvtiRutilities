library(testthat)
library(hvtiRutilities)

## Write `txt` to a temporary .sas file and lint it.
lint_txt <- function(txt) {
  f <- withr::local_tempfile(fileext = ".sas", .local_envir = parent.frame())
  writeLines(txt, f)
  hvtiRutilities:::.sas_lint(f)
}

wrap <- function(...) c("%macro probe(a=1);", ..., "%mend probe;")

# ===========================================================================
# Blind spots the per-line quote counter could not see.
#
# Each case below is valid SAS that the previous implementation reported as an
# unbalanced quote, or invalid SAS it reported as clean.
# ===========================================================================

test_that("macro-quoted apostrophe %STR(%') is not a string delimiter", {
  # SAS/IML matrix transpose. The apostrophe is macro-quoted precisely because
  # it is deliberately unbalanced. 19 files in the library use this.
  res <- lint_txt(wrap("  &PRED_Y=_DESIGN_*(_BETA_%STR(%')) ;"))
  expect_true(res$valid)
})

test_that("macro-quoted apostrophe is recognised outside %STR too", {
  res <- lint_txt(wrap("  ALL_PARM=PARMS%STR(%');",
                       "  SE_Z=(D1CH(K,)*_COV_*(D1CH(K,))%STR(%'))##(0.5);"))
  expect_true(res$valid)
})

test_that("single quotes inside a double-quoted string are literal", {
  res <- lint_txt(wrap(
    '  put "WARN\'\'ING: you requested a plot but didn\'t say which";'
  ))
  expect_true(res$valid)
})

test_that("a string literal may span lines", {
  res <- lint_txt(wrap(
    "  title h=1.5 c=black f=swissl 'CIF for event &&interest by",
    "&&group' ;"
  ))
  expect_true(res$valid)
})

test_that("prose in a * ... ; comment spanning lines is not syntax", {
  # gmatch.sas opens `** GMATCH Macro ...` and runs to `**;` eight lines later.
  res <- lint_txt(c(
    " ** GMATCH Macro to match 1 or more controls for each of N cases",
    "    Changes:",
    "    --options to transform X's and to choose distance metric",
    " **;",
    "%macro gmatch(a=1);",
    "%mend gmatch;"
  ))
  expect_true(res$valid)
})

test_that("prose in a mid-line * ... ; comment is not syntax", {
  # Review feedback on #39: a comment statement need not start the line.
  res <- lint_txt(wrap("  data y; run; * transform X's here;"))
  expect_true(res$valid)
})

test_that("code following a leading * ... ; on the same line is still linted", {
  # Review feedback on #39, the false NEGATIVE: blanking the whole line hid a
  # genuine unbalanced quote sitting in real code after the comment.
  res <- lint_txt(wrap("* note; data x; z = 'unterminated; run;"))
  expect_false(res$valid)
  expect_true(any(grepl("unterminated string", res$failures)))
})

test_that("doubled '' inside a single-quoted string is an escaped quote", {
  res <- lint_txt(wrap("  x = 'it''s fine';"))
  expect_true(res$valid)
})

test_that("a block comment spanning lines is not syntax", {
  # Regression guard for the fix shipped in #39.
  res <- lint_txt(c(
    "/* Purpose : Pearson's Chi-square",
    "   Note    : Fisher's Exact test */",
    "%macro ok(a=1);",
    "%mend ok;"
  ))
  expect_true(res$valid)
})

test_that("a quote inside a block comment does not open a string", {
  res <- lint_txt(wrap("  /* don't */ x = 1;"))
  expect_true(res$valid)
})

# ===========================================================================
# Checks that must survive
# ===========================================================================

test_that("an unterminated string literal is reported, with its line", {
  res <- lint_txt(c(
    "%macro broken(a=1);",
    "  define dev1/display 'Number*events of*interest;",
    "%mend broken;"
  ))
  expect_false(res$valid)
  expect_true(any(grepl("unterminated string literal", res$failures)))
  expect_true(any(grepl("line 2", res$failures)))
})

test_that("%macro/%mend imbalance is still reported", {
  res <- lint_txt(c("%macro truncated(a=1);", "  data x; run;"))
  expect_false(res$valid)
  expect_true(any(grepl("%macro/%mend", res$failures)))
})

test_that("a file with no macro definition is still reported", {
  res <- lint_txt(c("NOTE: The SAS System stopped.", "ERROR: nothing here."))
  expect_false(res$valid)
  expect_true(any(grepl("no %macro definition", res$failures)))
})

test_that("no do/end failure is reported", {
  res <- lint_txt(wrap("  data x; do i = 1 to 10; y = i; run;"))
  expect_false(any(grepl("do/end", res$failures)))
})

# ===========================================================================
# Scanner behaviour directly
# ===========================================================================

test_that(".sas_scan preserves line count", {
  lines <- c("/* a", "   b */", "x = 1;", "* c;", "y = 2;")
  expect_equal(length(hvtiRutilities:::.sas_scan(lines)$code), length(lines))
})

test_that(".sas_scan keeps code and drops comment and string content", {
  s <- hvtiRutilities:::.sas_scan("if x = 'abc' then /* note */ z = 1;")
  expect_false(grepl("abc", s$code))
  expect_false(grepl("note", s$code))
  expect_true(grepl("if x =", s$code))
  expect_true(grepl("z = 1;", s$code))
})

test_that(".sas_scan does not treat multiplication as a comment", {
  s <- hvtiRutilities:::.sas_scan("area = width * height;")
  expect_true(grepl("height", s$code))
})

test_that(".sas_scan reports the line where an unclosed string opened", {
  s <- hvtiRutilities:::.sas_scan(c("x = 1;", "y = 'oops;", "z = 2;"))
  expect_equal(s$open_state, "squote")
  expect_equal(s$open_line, 2L)
})
