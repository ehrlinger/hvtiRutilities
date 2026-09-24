test_that("an absent log reads as empty", {
  root <- withr::local_tempdir()
  expect_identical(.cp_log_read(root), list())
})

test_that("entries append in order and round-trip, NULLs included", {
  root <- withr::local_tempdir()
  .cp_log_append(root, list(type = "checkpoint", checkpoint_id = "a",
                            note = NULL, delivery = list(git = "pending")))
  .cp_log_append(root, list(type = "closure", closure_id = "b",
                            delivery = list(git = "pending")))
  log <- .cp_log_read(root)
  expect_length(log, 2L)
  expect_equal(vapply(log, .cp_entry_id, character(1)), c("a", "b"))
  expect_true("note" %in% names(log[[1]]))
  expect_equal(log[[1]]$delivery$git, "pending")
})

test_that(".cp_date formats dates and date strings", {
  expect_equal(.cp_date(as.Date("2026-09-24")), "2026-09-24")
  expect_equal(.cp_date("2026-10-02"), "2026-10-02")
})
