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

test_that("variable labels survive, including after rows are dropped", {
  d <- data.frame(dead = c(1, 0, NA))
  labelled::var_label(d$dead) <- "Death indicator"
  res <- proc_freq(d, "dead")
  expect_equal(labelled::var_label(res$dead), "Death indicator")
})

test_that("variable labels survive weighting", {
  d <- data.frame(g = c("a", "b"), wt = c(1, NA))
  labelled::var_label(d$g) <- "Group"
  res <- proc_freq(d, "g", weights = "wt")
  expect_equal(labelled::var_label(res$g), "Group")
})

test_that("value-labelled variables gain a label column beside them", {
  d <- data.frame(status = haven::labelled(c(2, 1, 3, 2),
                                           labels = c(Alive = 1, Dead = 2)),
                  arm = c("a", "a", "b", "b"))
  res <- proc_freq(d, c("status", "arm"), list = TRUE)
  expect_named(res, c("status", "status_label", "arm", "Frequency",
                      "Percent", "Cum_Frequency", "Cum_Percent"))
  expect_false(inherits(res$status, "haven_labelled"))
  expect_equal(res$status, c(1, 2, 2, 3))
  expect_equal(res$status_label, c("Alive", "Dead", "Dead", NA))
})

test_that("a missing value-labelled value has an NA label", {
  d <- data.frame(status = haven::labelled(c(1, NA), labels = c(Alive = 1)))
  res <- proc_freq(d, "status", missing = TRUE)
  expect_equal(res$status_label, c(NA, "Alive"))
})

test_that("variables without value labels get no label column", {
  res <- proc_freq(data.frame(g = c("a", "b")), "g")
  expect_false("g_label" %in% names(res))
})

test_that("codes sharing a value label form one row at the smallest code", {
  d <- data.frame(v = haven::labelled(c(9, 99, 1, 99),
                                      labels = c(Yes = 1, Unknown = 9,
                                                 Unknown = 99)))
  res <- proc_freq(d, "v")
  expect_equal(nrow(res), 2L)
  expect_equal(res$v, c(1, 9))
  expect_equal(res$v_label, c("Yes", "Unknown"))
  expect_equal(res$Frequency, c(1L, 3L))
  expect_equal(res$Percent, c(25, 75))
})

test_that("a labelled variable's value without a label stays its own row", {
  d <- data.frame(v = haven::labelled(c(1, 2, 3), labels = c(A = 1, A = 2)))
  res <- proc_freq(d, "v")
  expect_equal(res$v, c(1, 3))
  expect_equal(res$v_label, c("A", NA))
  expect_equal(res$Frequency, c(2L, 1L))
})

test_that("a crosstab keeps variable labels beside value-label columns", {
  d <- data.frame(status = haven::labelled(c(2, 1, 1, 2),
                                           labels = c(Alive = 1, Dead = 2)),
                  arm = c("a", "a", "b", "b"))
  labelled::var_label(d$status) <- "Vital status"
  res <- proc_freq(d, c("status", "arm"))
  expect_equal(labelled::var_label(res$status), "Vital status")
  expect_named(res, c("status", "status_label", "arm", "Frequency",
                      "Percent", "Row_Percent", "Col_Percent"))
})

test_that("a labelled character groups shared labels and a blank value", {
  v <- haven::labelled(c("b", "c", "", "b", "  "),
                       labels = c(Bad = "b", Bad = "c"))
  res <- proc_freq(data.frame(v = v), "v")
  expect_equal(nrow(res), 1L)
  expect_equal(res$v, "b")
  expect_equal(res$v_label, "Bad")
  expect_equal(res$Frequency, 3L)
  expect_identical(attr(res, "frequency_missing"), 2L)
})

test_that("a representative code absent from the data is its own row", {
  v <- haven::labelled(c(99, 99, 1),
                       labels = c(Yes = 1, Unknown = 9, Unknown = 99))
  res <- proc_freq(data.frame(v = v), "v")
  expect_equal(res$v, c(1, 9))
  expect_equal(res$v_label, c("Yes", "Unknown"))
  expect_equal(res$Frequency, c(1L, 2L))
})
