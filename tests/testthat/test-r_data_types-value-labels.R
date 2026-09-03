# Value-label handling in r_data_types(). See
# dev/specs/2026-09-02-label-length-and-fallback-design.md sections 2.2 and 7.3.

test_that("a two-valued haven_labelled column converts instead of erroring", {
  # as.logical() has no vctrs cast from haven_labelled, so the binary branch
  # used to abort. Dropping the value labels first makes the default path a
  # conversion rather than a crash.
  b <- haven::labelled(c(0, 1, 1, 0), labels = c(No = 0, Yes = 1),
                       label = "Prior stroke")

  out <- r_data_types(data.frame(flag = b), use_value_labels = FALSE)

  expect_type(out$flag, "logical")
  expect_equal(as.vector(out$flag), c(FALSE, TRUE, TRUE, FALSE))
  expect_equal(attr(out$flag, "label"), "Prior stroke")
})

test_that("a multi-level haven_labelled column keeps the codes as levels", {
  # The status quo of section 2.2, pinned deliberately: with use_value_labels
  # off, the level text is discarded and the numeric codes become the levels.
  x <- haven::labelled(c(1, 2, 1, 3), labels = c(Home = 1, Rehab = 2, SNF = 3),
                       label = "Discharge disposition")

  out <- r_data_types(data.frame(disp = x), use_value_labels = FALSE)

  expect_s3_class(out$disp, "factor")
  expect_equal(levels(out$disp), c("1", "2", "3"))
  expect_equal(attr(out$disp, "label"), "Discharge disposition")
})
