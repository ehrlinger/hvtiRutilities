# #271: find rows that repeat a key, and choose which to keep the way the SAS
# jobs do (first operation kept, the second treated as a complication).

dk_ops <- function() {
  data.frame(
    id = c(1, 2, 2, 3, 3, 4),
    dt_surg = as.Date(c("2010-01-05", "2012-03-01", "2012-03-01",
                        "2011-06-01", "2015-02-10", "2013-09-09")),
    op_time = c(8, 14, 9, 10, 11, 7),
    proc = c("avr", "mvr", "cabg", "avr", "redo", "tvr")
  )
}

test_that("a clean key reports zero repeats and still counts the rows", {
  d <- dk_ops()[c(1, 2, 4, 6), ]
  dk <- duplicate_keys(d, "id", order_by = "op_time")
  expect_s3_class(dk, "duplicate_keys")
  expect_identical(dk$summary$rows, 4L)
  expect_identical(dk$summary$keys, 4L)
  expect_identical(dk$summary$repeated_keys, 0L)
  expect_identical(dk$summary$rows_in_repeats, 0L)
  expect_identical(nrow(dk$rows), 0L)
  expect_identical(dk$keep, rep(TRUE, 4L))
})

test_that("a same-day pair repeats the patient-and-date key; different days do not", {
  d <- dk_ops()
  dk <- duplicate_keys(d, c("id", "dt_surg"))
  expect_identical(dk$summary$repeated_keys, 1L)
  expect_identical(dk$rows$row, c(2L, 3L))
  expect_identical(dk$rows$.group, c(1L, 1L))

  by_id <- duplicate_keys(d, "id")
  expect_identical(by_id$summary$repeated_keys, 2L)
  expect_identical(by_id$summary$rows_in_repeats, 4L)
  expect_identical(by_id$rows$row, c(2L, 3L, 4L, 5L))
})

test_that("order_by keeps the first row of each key and marks the rest", {
  d <- dk_ops()
  dk <- duplicate_keys(d, c("id", "dt_surg"), order_by = "op_time")
  # Patient 2 had two operations on 2012-03-01: 09:00 cabg is first.
  expect_identical(dk$keep, c(TRUE, FALSE, TRUE, TRUE, TRUE, TRUE))
  expect_identical(d[!dk$keep, "proc"], "mvr")
  expect_identical(dk$rows$.rank, c(2L, 1L))
  expect_identical(anyDuplicated(d[dk$keep, c("id", "dt_surg")]), 0L)

  by_id <- duplicate_keys(d, "id", order_by = c("dt_surg", "op_time"))
  expect_identical(d[by_id$keep, "proc"], c("avr", "cabg", "avr", "tvr"))
})

test_that("without order_by nothing is chosen", {
  expect_null(duplicate_keys(dk_ops(), "id")$keep)
})

test_that("a tie or a missing order_by value in a repeated key stops", {
  d <- dk_ops()
  d$op_time[3] <- 14
  expect_error(duplicate_keys(d, c("id", "dt_surg"), order_by = "op_time"),
               "1 repeated key")
  d <- dk_ops()
  d$op_time[3] <- NA
  expect_error(duplicate_keys(d, c("id", "dt_surg"), order_by = "op_time"),
               "missing")
  # A missing order_by value outside any repeated key is not a choice to make.
  d <- dk_ops()
  d$op_time[1] <- NA
  expect_identical(sum(!duplicate_keys(d, c("id", "dt_surg"), order_by = "op_time")$keep), 1L)
})

test_that("key values are shown only when asked", {
  d <- dk_ops()
  expect_false(any(c("id", "dt_surg") %in% names(duplicate_keys(d, c("id", "dt_surg"))$rows)))
  shown <- duplicate_keys(d, c("id", "dt_surg"), show_key = TRUE)$rows
  expect_identical(shown$id, c(2, 2))
  expect_output(print(duplicate_keys(d, "id")), "2 keys repeat")
})

test_that("missing key values are counted, and unknown columns are named at once", {
  d <- dk_ops()
  d$id[6] <- NA
  expect_identical(duplicate_keys(d, "id")$summary$missing_keys, 1L)
  expect_error(duplicate_keys(d, c("idd", "dt_surg"), order_by = "op_tim"),
               "idd.*op_tim")
  expect_error(duplicate_keys(d, character()), "key")
})
