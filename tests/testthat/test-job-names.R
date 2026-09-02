library(testthat)
library(hvtiRutilities)

test_that("the legacy SAS convention yields the leading dot-field", {
  out <- hvtiRutilities:::.job_name_fields("hz.dead.lst")
  expect_equal(out$naming, "legacy")
  expect_equal(out$prefix, "hz")
  expect_false(out$is_template)
})

test_that("a tp. marker is stripped first and recorded", {
  # Without stripping first, tp.hz.dead.lst classifies as prefix "tp", which
  # both loses that it is an hz template and collides with the exclusion rule.
  out <- hvtiRutilities:::.job_name_fields("tp.hz.dead.lst")
  expect_equal(out$prefix, "hz")
  expect_true(out$is_template)
})

test_that("prefixes are not assumed two characters wide", {
  # vars, rfsrc, rfc and rfs are all in hvti_taxonomy().
  out <- hvtiRutilities:::.job_name_fields(c("vars.temp.sas", "rfsrc.surv.R"))
  expect_equal(out$prefix, c("vars", "rfsrc"))
})

test_that("the set convention is parsed, parity variant included", {
  out <- hvtiRutilities:::.job_name_fields(
    c("dead_pa-hz-03.01-ac.qmd", "dead_pa-hz-03.01-ac-parity.qmd")
  )
  expect_equal(out$naming, c("set", "set"))
  expect_equal(out$prefix, c("ac", "ac"))
})

test_that("the template convention is parsed", {
  out <- hvtiRutilities:::.job_name_fields("03.01-ac.qmd")
  expect_equal(out$naming, "template")
  expect_equal(out$prefix, "ac")
})

test_that("preserve_root's transitional R jobs are parsed, parity included", {
  out <- hvtiRutilities:::.job_name_fields(
    c("02-hz-dead_pa.qmd", "01-ac-dead_pa-parity.qmd")
  )
  expect_equal(out$naming, c("r_transitional", "r_transitional"))
  expect_equal(out$prefix, c("hz", "ac"))
})

test_that("legacy runs LAST -- it would otherwise shadow the template form", {
  # This is the whole reason the order is fixed. The legacy pattern happily
  # reads 03.01-ac.qmd as prefix "03". If this test fails, the parser order
  # has been rearranged and every R job in the corpus is misclassified.
  out <- hvtiRutilities:::.job_name_fields("03.01-ac.qmd")
  expect_equal(out$prefix, "ac")
  expect_false(identical(out$prefix, "03"))
})

test_that("a name no parser claims survives as NA rather than erroring", {
  out <- hvtiRutilities:::.job_name_fields(c("shape-census.R", "Makefile"))
  expect_true(all(is.na(out$naming)))
  expect_true(all(is.na(out$prefix)))
  expect_false(any(out$is_template))
})

test_that("the parser is vectorised and order-preserving", {
  out <- hvtiRutilities:::.job_name_fields(
    c("hz.dead.lst", "Makefile", "03.01-ac.qmd")
  )
  expect_equal(nrow(out), 3L)
  expect_equal(out$naming, c("legacy", NA, "template"))
})

test_that("legacy qualifiers are the fields between prefix and extension", {
  out <- hvtiRutilities:::.job_name_fields("hz.dead.lst")
  expect_equal(out$qualifier1, "dead")
  expect_equal(out$qualifiers, "dead")
  expect_equal(out$n_qualifiers, 1L)
})

test_that("a two-field legacy name has NO qualifier", {
  # The extension separator and the field separator are the same character,
  # so a parser counting from the left alone reads "sas7bdat" as the thing
  # the job does. hzdead.sas7bdat is an estimates dataset with no qualifier
  # at all, and 426 corpus rows depend on the difference.
  out <- hvtiRutilities:::.job_name_fields("hzdead.sas7bdat")
  expect_true(is.na(out$qualifier1))
  expect_true(is.na(out$qualifiers))
  expect_equal(out$n_qualifiers, 0L)
})

test_that("qualifiers deeper than one level are kept, in order", {
  # tp.dp.spaghetti.echo is real and is three levels. A parser that stops at
  # the second field cannot tell it from tp.dp.spaghetti.
  out <- hvtiRutilities:::.job_name_fields("tp.dp.spaghetti.echo.sas")
  expect_equal(out$prefix, "dp")
  expect_equal(out$qualifier1, "spaghetti")
  expect_equal(out$qualifiers, "spaghetti.echo")
  expect_equal(out$n_qualifiers, 2L)
})

test_that("the tp. marker is stripped before qualifiers are read", {
  # Otherwise qualifier1 is the prefix of the template it marks.
  out <- hvtiRutilities:::.job_name_fields("tp.hm.dead.sas")
  expect_true(out$is_template)
  expect_equal(out$qualifier1, "dead")
})

test_that("only the legacy convention has a qualifier slot", {
  # set, template and r_transitional each account for every field in their
  # grammar, so a qualifier there would be invented rather than read.
  out <- hvtiRutilities:::.job_name_fields(
    c("03.01-ac.qmd", "dead_pa-hz-03.01-ac.qmd", "03-ac-dead.qmd", "README")
  )
  expect_true(all(is.na(out$qualifier1)))
  expect_equal(out$n_qualifiers, rep(0L, 4))
})
