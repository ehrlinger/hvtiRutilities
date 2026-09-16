library(testthat)
library(hvtiRutilities)

test_that("columns lead with table variables in the order given", {
  d <- data.frame(b = c(1, 2), a = c("x", "y"))
  expect_named(proc_freq(d, c("a", "b")),
               c("a", "b", "Frequency", "Percent", "Row_Percent",
                 "Col_Percent"))
  expect_named(proc_freq(d, c("a", "b"), list = TRUE),
               c("a", "b", "Frequency", "Percent", "Cum_Frequency",
                 "Cum_Percent"))
})

test_that("the result is a plain data frame with sequential row names", {
  res <- proc_freq(data.frame(g = c("b", "a", "b")), "g")
  expect_s3_class(res, "data.frame")
  expect_false(inherits(res, "tbl_df"))
  expect_equal(rownames(res), c("1", "2"))
})
