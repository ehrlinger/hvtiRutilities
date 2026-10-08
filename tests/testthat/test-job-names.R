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

test_that("set, template and r_transitional have no qualifier slot", {
  # set, template and r_transitional each account for every field in their
  # grammar, so a qualifier there would be invented rather than read.
  out <- hvtiRutilities:::.job_name_fields(
    c("03.01-ac.qmd", "dead_pa-hz-03.01-ac.qmd", "03-ac-dead.qmd", "README")
  )
  expect_true(all(is.na(out$qualifier1)))
  expect_equal(out$n_qualifiers, rep(0L, 4))
})

test_that("the scaffolded convention is parsed, qualifier carried", {
  # hvtiRtemplates::add_job() writes <subject>-<type>-<prefix>[-<qualifier>].qmd.
  out <- hvtiRutilities:::.job_name_fields(
    c("dead-hz-bc.qmd", "lvef-boost-nb-boostmtree.qmd")
  )
  expect_equal(out$naming, c("scaffolded", "scaffolded"))
  expect_equal(out$prefix, c("bc", "nb"))
  expect_equal(out$qualifier1, c(NA, "boostmtree"))
  expect_equal(out$qualifiers, c(NA, "boostmtree"))
  expect_equal(out$n_qualifiers, c(0L, 1L))
})

test_that("a scaffolded job's runner is parsed as that job, not a qualifier", {
  # add_job() writes <stem>-runner.R beside the bl, br, bc and bh reports.
  # "runner" read as a qualifier would make the runner a second, distinct job.
  out <- hvtiRutilities:::.job_name_fields(
    c("dead-hz-bc-runner.R", "lvef-boost-nb-boostmtree-runner.R")
  )
  expect_equal(out$naming, c("scaffolded", "scaffolded"))
  expect_equal(out$prefix, c("bc", "nb"))
  expect_equal(out$qualifier1, c(NA, "boostmtree"))
})

test_that("r_transitional keeps a two-digit name whose third field is an endpoint", {
  # 03-bc-dead.qmd fits both grammars. "dead" is not a taxonomy prefix, so it
  # is an endpoint and the name stays r_transitional; -parity is its suffix,
  # not a qualifier.
  out <- hvtiRutilities:::.job_name_fields(
    c("03-bc-dead.qmd", "01-ac-dead_pa-parity.qmd")
  )
  expect_equal(out$naming, c("r_transitional", "r_transitional"))
  expect_equal(out$prefix, c("bc", "ac"))
})

test_that("a dashed name of the wrong shape is not scaffolded", {
  # Two fields, five fields, and an .R that is not a runner.
  out <- hvtiRutilities:::.job_name_fields(
    c("dead-hz.qmd", "a-b-c-d-e.qmd", "dead-hz-bc.R")
  )
  expect_true(all(is.na(out$naming)))
})

test_that("a two-digit subject still parses as scaffolded, runner included", {
  # add_job(prefix = "bc", subject = "03", type = "hz") writes 03-hz-bc.qmd
  # and 03-hz-bc-runner.R. Read as r_transitional, the report became a false
  # hz job and the runner an orphan bc job.
  out <- hvtiRutilities:::.job_name_fields(
    c("03-hz-bc.qmd", "03-hz-bc-runner.R", "03-hz-nb-boostmtree.qmd")
  )
  expect_equal(out$naming, rep("scaffolded", 3))
  expect_equal(out$prefix, c("bc", "bc", "nb"))
  expect_equal(out$qualifier1, c(NA, NA, "boostmtree"))
})

test_that("the template-first form is parsed as scaffolded, before the legacy parser", {
  # hvtiRtemplates::add_job() writes <prefix>[.<qualifier>].<subject>.<type>.qmd
  # since 2026-10. The legacy parser would read any dotted name as <prefix>.<anything>
  # and call it a SAS-era job.
  out <- hvtiRutilities:::.job_name_fields(
    c("ac.death.hz.qmd", "dp.trends.cohort.eda.qmd", "bl.death.boot.runner.R")
  )
  expect_equal(out$naming, rep("scaffolded", 3))
  expect_equal(out$prefix, c("ac", "dp", "bl"))
  expect_equal(out$qualifier1, c(NA, "trends", NA))
  expect_equal(out$n_qualifiers, c(0L, 1L, 0L))
})

test_that("SAS-era dotted names stay legacy", {
  out <- hvtiRutilities:::.job_name_fields(c("hm.dead.sas", "dp.trends.sas", "ac.death.hz.lst", "zz.death.hz.qmd"))
  expect_equal(out$naming, rep("legacy", 4))
})

test_that("a template-first runner takes its report's stem in job_files()", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "alpha", "analyses"), recursive = TRUE)
  file.create(file.path(root, "alpha", "analyses", c("bl.death.boot.qmd", "bl.death.boot.runner.R")))
  files <- job_files(root)
  expect_identical(unique(files$stem[files$naming %in% "scaffolded"]), "bl.death.boot")
})

test_that("old dotted names of the template-first shape are now read as scaffolded (accepted tradeoff)", {
  # dp.spaghetti.echo.qmd was a legacy name with qualifiers (spaghetti, echo). A known prefix
  # plus three or four dot-fields is now claimed as scaffolded, so the legacy
  # qualifier fields are gone. The maintainer accepted this on 2026-10.
  out <- hvtiRutilities:::.job_name_fields(c("dp.spaghetti.echo.qmd", "bd.death.hz.qmd"))
  expect_equal(out$naming, rep("scaffolded", 2))
  expect_equal(out$qualifier1, c(NA_character_, NA_character_))
  expect_equal(out$qualifiers, c(NA_character_, NA_character_))
  expect_equal(out$n_qualifiers, c(0L, 0L))
})

test_that("the boundaries of the template-first form hold", {
  out <- hvtiRutilities:::.job_name_fields(c("ac.a.b.c.d.qmd", "ac.death.runner.R"))
  expect_equal(out$naming, rep("legacy", 2))

  hy <- hvtiRutilities:::.job_name_fields("dead_pa-hz-ac.qmd")
  expect_equal(hy$naming, "scaffolded")
  expect_equal(hy$prefix, "ac")
  expect_true(is.na(hy$qualifier1))
  expect_equal(hy$n_qualifiers, 0L)
})
