# The per-column conversion report. See
# dev/specs/2026-09-02-label-length-and-fallback-design.md section 7.3.

test_that("the report has one row per column, in column order", {
  dta <- data.frame(
    num  = c(1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5, 8.5, 9.5, 10.5, 11.5, 12.5),
    flag = c(0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1),
    chr  = letters[1:12],
    few  = c(1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3),
    stringsAsFactors = FALSE
  )

  rep <- type_conversion_report(r_data_types(dta, use_value_labels = FALSE))

  expect_s3_class(rep, "data.frame")
  expect_equal(rep$variable, c("num", "flag", "chr", "few"))
  expect_equal(names(rep), c("variable", "storage_in", "rule", "level_source",
                             "n_levels", "storage_out"))
})

test_that("each inference rule is named, and named as inference", {
  dta <- data.frame(
    num  = c(1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5, 8.5, 9.5, 10.5, 11.5, 12.5),
    flag = c(0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1),
    chr  = letters[1:12],
    few  = c(1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3),
    stringsAsFactors = FALSE
  )

  rep <- type_conversion_report(r_data_types(dta, use_value_labels = FALSE))

  expect_equal(rep$rule, c("unchanged", "binary_logical", "character_factor",
                           "n_distinct_factor"))
  expect_equal(rep$level_source,
               c(NA, NA, "inference", "inference"))
  expect_equal(rep$n_levels, c(NA_integer_, NA_integer_, 12L, 3L))
  expect_equal(rep$storage_out,
               c("numeric", "logical", "factor", "factor"))
  expect_equal(rep$storage_in,
               c("numeric", "numeric", "character", "numeric"))
})

test_that("a skipped column is reported as skipped, not as unchanged", {
  # The two are different claims. "unchanged" means every rule was tested and
  # none fired; "skipped" means no rule was tested. Collapsing them would make
  # skip_vars invisible in the record of what happened.
  dta <- data.frame(a = c(1, 2, 3, 1), b = c(0, 1, 0, 1))

  rep <- type_conversion_report(
    r_data_types(dta, skip_vars = "b", use_value_labels = FALSE)
  )

  expect_equal(rep$rule, c("n_distinct_factor", "skipped"))
  expect_equal(rep$storage_in, c("numeric", "numeric"))
  expect_equal(rep$storage_out, c("factor", "numeric"))
  expect_true(is.na(rep$level_source[2]))
})

test_that("the report is attached whether or not value labels are used", {
  dta <- data.frame(a = c(1, 2, 3, 1))

  expect_s3_class(type_conversion_report(
    r_data_types(dta, use_value_labels = FALSE)), "data.frame")
  expect_s3_class(type_conversion_report(
    r_data_types(dta, use_value_labels = TRUE)), "data.frame")
})

test_that("a zero-column frame yields a zero-row report with the same columns", {
  rep <- type_conversion_report(
    r_data_types(data.frame(), use_value_labels = FALSE)
  )

  expect_equal(nrow(rep), 0)
  expect_equal(names(rep), c("variable", "storage_in", "rule", "level_source",
                             "n_levels", "storage_out"))
})

test_that("the accessor says what went wrong rather than returning NULL", {
  expect_error(type_conversion_report(mtcars),
               "did not come from r_data_types")
})
