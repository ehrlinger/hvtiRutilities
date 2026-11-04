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

test_that("keys that print alike stay separate (#274 review)", {
  # 1e15 and 1e15 + 1 are distinct doubles that both format as "1e+15".
  d <- data.frame(id = rep(c(1e15, 1e15 + 1), each = 2), time = 1:4)
  expect_true(identical(as.character(d$id[1]), as.character(d$id[3])) &&
                d$id[1] != d$id[3])
  dk <- duplicate_keys(d, "id", order_by = "time")
  expect_equal(dk$summary$repeated_keys, 2L)
  expect_equal(dk$rows$.group, c(1L, 1L, 2L, 2L))
  expect_equal(dk$keep, c(TRUE, FALSE, TRUE, FALSE))
  expect_equal(nrow(d[dk$keep, ]), 2L)
})

test_that("composite keys whose pasted strings collide stay separate", {
  # Pasted with any one separator, ("a\037", "b") and ("a", "\037b") match.
  d <- data.frame(x = c("a\037", "a\037", "a", "a"),
                  y = c("b", "b", "\037b", "\037b"), time = 1:4)
  dk <- duplicate_keys(d, c("x", "y"), order_by = "time")
  expect_equal(dk$rows$.group, c(1L, 1L, 2L, 2L))
  expect_equal(dk$keep, c(TRUE, FALSE, TRUE, FALSE))
  # A missing key is not the same as the text "NA".
  d2 <- data.frame(id = c(NA, NA, "NA", "NA"), time = 1:4)
  expect_equal(duplicate_keys(d2, "id", order_by = "time")$rows$.group, c(1L, 1L, 2L, 2L))
})

test_that("order_by values that print alike are not a tie (#274 review)", {
  d <- data.frame(id = c(1, 1), t = c(1 + 1e-15, 1))
  expect_identical(as.character(d$t[1]), as.character(d$t[2]))
  dk <- duplicate_keys(d, "id", order_by = "t")
  expect_equal(dk$keep, c(FALSE, TRUE))
})
