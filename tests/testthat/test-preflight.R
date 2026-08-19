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
