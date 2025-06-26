testthat::test_that("column types", {
  dta <- sample_data(n =100)
  testthat::expect_type(dta$logical, type="character")
  testthat::expect_type(dta$boolean, type="integer")
  testthat::expect_type(dta$float, type="double")
  testthat::expect_s3_class(dta$factor, "factor")
  testthat::expect_type(dta$f_real, type="double")
})
