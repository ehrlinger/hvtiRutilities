test_that("preflight_report returns the documented shape", {
  out <- preflight_report()
  expect_s3_class(out, "data.frame")
  expect_named(out, c("component", "found", "version", "notes"))
  expect_type(out$found, "logical")
})

test_that("preflight_report always reports R itself and numDeriv", {
  out <- preflight_report()
  expect_true("R" %in% out$component)
  expect_true("numDeriv" %in% out$component)
})

test_that("numDeriv carries a note explaining why its absence matters", {
  out <- preflight_report()
  note <- out$notes[out$component == "numDeriv"]
  expect_match(note, "standard errors", fixed = TRUE)
})

test_that("extra packages are appended", {
  out <- preflight_report(extra = "utils")
  expect_true("utils" %in% out$component)
})

test_that("naming R in extra still yields exactly one R row, the real one", {
  out <- preflight_report(extra = "R")
  expect_equal(sum(out$component == "R"), 1L)
  expect_true(out$found[out$component == "R"])
})

test_that("a non-character extra errors rather than inventing a component", {
  expect_error(preflight_report(extra = 42), "character vector")
})

test_that("row names are cleared, not the ones rbind synthesizes", {
  out <- preflight_report(extra = "R")
  expect_identical(rownames(out), as.character(seq_len(nrow(out))))
})
