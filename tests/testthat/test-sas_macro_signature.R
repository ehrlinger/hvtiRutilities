library(testthat)
library(hvtiRutilities)

fx <- function(name) testthat::test_path("fixtures", name)

test_that("sas_macro_signature parses the header block", {
  res <- sas_macro_signature(fx("documented.sas"))

  expect_equal(res$macro_name, "docmacro")
  expect_equal(res$short_desc, "Does a documented thing")
  expect_equal(res$created_on, "2019/04/05")
  expect_equal(res$modified_on, "2019/04/09")
  expect_equal(res$documented_call, "%DocMacro(DSN, NBINS)")
})

test_that("sas_macro_signature returns NA fields for an undocumented file", {
  res <- sas_macro_signature(fx("alpha.sas"))

  expect_equal(res$file, "alpha.sas")
  expect_true(is.na(res$macro_name))
  expect_true(is.na(res$modified_on))
})

test_that("sas_macro_signature takes the LAST MODIFIED BY date", {
  tmp <- withr::local_tempfile(fileext = ".sas")
  writeLines(
    c("* MODIFIED BY:  A                         2015/01/01",
      "* MODIFIED BY:  B                         2018/06/30",
      "%macro m; %put x; %mend m;"),
    tmp
  )

  expect_equal(sas_macro_signature(tmp)$modified_on, "2018/06/30")
})
