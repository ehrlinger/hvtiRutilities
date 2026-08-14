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

# ===========================================================================
# Review of #41: the scanner was applied to the literal check only, so the
# %macro/%mend rules still counted definitions that the scan had already
# established were comments or string content.
# ===========================================================================

test_that("a %macro inside a block comment is not counted as a definition", {
  # Reported "imbalance: 2 open, 1 close" while the file is valid: the second
  # definition is commented out. This is the false-positive class the scanner
  # was written to remove, surviving in the rule the scanner had not reached.
  res <- lint_txt(c("%macro foo;", "  data x; run;", "%mend;",
                    "/*", "%macro dead;", "  data y; run;", "*/"))
  expect_true(res$valid)
})

test_that("a %mend inside a block comment is not counted", {
  res <- lint_txt(c("%macro foo;", "/*", "%mend;", "*/", "%mend;"))
  expect_true(res$valid)
})

test_that("a %macro inside a string literal is not counted", {
  res <- lint_txt(c("%macro foo;", "call execute('", "%macro inner;", "');",
                    "%mend;"))
  expect_true(res$valid)
})

test_that("a real %macro/%mend imbalance is still reported", {
  res <- lint_txt(c("%macro truncated(a=1);", "  data x; run;"))
  expect_false(res$valid)
  expect_true(any(grepl("%macro/%mend", res$failures)))
})

test_that("sas_macro_defs() does not inventory a commented-out macro", {
  f <- withr::local_tempfile(fileext = ".sas")
  writeLines(c("%macro live(a=1);", "  data x; run;", "%mend live;",
               "/*", "%macro dead(b=2);", "  data y; run;", "%mend dead;",
               "*/"), f)
  defs <- sas_macro_defs(f)
  expect_equal(nrow(defs), 1L)
  expect_equal(defs$macro, "live")
})

test_that("sas_macro_defs() keeps parameter names from the raw statement", {
  # Detection moved to the scanned source; extraction deliberately did not,
  # because the scanner strips the quoted default in `a='x'`.
  f <- withr::local_tempfile(fileext = ".sas")
  writeLines(c("%macro foo(a='x', b=2);", "  data d; run;", "%mend foo;"), f)
  expect_equal(sas_macro_defs(f)$params, "a,b")
})

# ===========================================================================
# An unterminated comment is a defect too, and the scanner already knew.
# ===========================================================================

test_that("a file ending inside a block comment is reported", {
  # More destructive than an unterminated literal: everything after the /* is
  # inert, so the file triages as usable source while most of it never runs.
  res <- lint_txt(c("%macro f;", "%mend;", "/* dangling"))
  expect_false(res$valid)
  expect_true(any(grepl("unterminated /\\* \\*/ comment opened at line 3",
                        res$failures)))
})

test_that("a file ending inside a star comment is reported", {
  res <- lint_txt(c("%macro f;", "%mend;", "* dangling"))
  expect_false(res$valid)
  expect_true(any(grepl("unterminated \\* \\.\\.\\. ; comment opened at line 3",
                        res$failures)))
})

test_that("a closed comment does not leave an open_line behind", {
  s <- hvtiRutilities:::.sas_scan(c("/* a */", "* b ;", "data x; run;"))
  expect_equal(s$open_state, "code")
  expect_true(is.na(s$open_line))
})

test_that("an unterminated star comment swallows the %macro that follows", {
  # bl_ord.norm.ci.sas in the macro library: a `* NOT COMPLETE` header with no
  # semicolon, then %MACRO BLORD on the next line. Counting raw lines saw
  # 4 open / 4 close and passed it; the definition is really inside the comment.
  res <- lint_txt(c("* NOT COMPLETE", "%macro blord(a=1);", "  data x; run;",
                    "%mend blord;"))
  expect_false(res$valid)
})
