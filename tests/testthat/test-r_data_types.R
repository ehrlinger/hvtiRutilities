testthat::test_that("multiplication works", {
  dta <- sample_data(n =100)
  udta <- r_data_types(dta)
  testthat::expect_type(udta$logical, type="logical")
  testthat::expect_type(udta$boolean, type="logical")
  testthat::expect_type(udta$float, type="double")
  testthat::expect_s3_class(udta$factor, "factor")
  testthat::expect_s3_class(udta$f_real, "factor")
})
