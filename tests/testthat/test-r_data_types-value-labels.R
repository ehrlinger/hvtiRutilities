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

test_that("use_value_labels = TRUE keeps the level text", {
  x <- haven::labelled(c(1, 2, 1, 3), labels = c(Home = 1, Rehab = 2, SNF = 3),
                       label = "Discharge disposition")

  out <- r_data_types(data.frame(disp = x), use_value_labels = TRUE)

  expect_s3_class(out$disp, "factor")
  expect_equal(levels(out$disp), c("Home", "Rehab", "SNF"))
  expect_equal(as.character(out$disp), c("Home", "Rehab", "Home", "SNF"))
  expect_equal(attr(out$disp, "label"), "Discharge disposition")
})

test_that("value labels beat the binary-to-logical branch", {
  # The binary branch runs first in the inference chain, so without this
  # precedence a labelled yes/no variable would come back logical with its
  # level text gone -- exactly the case the whole change is for.
  b <- haven::labelled(c(0, 1, 1, 0), labels = c(No = 0, Yes = 1),
                       label = "Prior stroke")

  out <- r_data_types(data.frame(flag = b), use_value_labels = TRUE)

  expect_s3_class(out$flag, "factor")
  expect_equal(levels(out$flag), c("No", "Yes"))
})

test_that("value labels beat factor_size", {
  # A declared type is not subject to a threshold on distinct values.
  codes <- c(1, 2, 3, 4, 5, 6)
  x <- haven::labelled(codes,
                       labels = c(a = 1, b = 2, c = 3, d = 4, e = 5, f = 6))

  out <- r_data_types(data.frame(v = x), factor_size = 3,
                      use_value_labels = TRUE)

  expect_s3_class(out$v, "factor")
  expect_equal(levels(out$v), c("a", "b", "c", "d", "e", "f"))
})

test_that("an unlabelled code keeps its code as the level text", {
  # labelled::to_factor(nolabel_to_na = FALSE) uses the label where there is
  # one and the value where there is not, so a code missing from the
  # catalogue is visible in the output rather than silently dropped to NA.
  p <- haven::labelled(c(1, 2, 9, 1), labels = c(Home = 1, Rehab = 2))

  out <- r_data_types(data.frame(v = p), use_value_labels = TRUE)

  expect_equal(levels(out$v), c("Home", "Rehab", "9"))
})

test_that("a haven_labelled column with no value labels falls through", {
  x <- haven::labelled(c(1, 2, 3, 1), label = "Just a label")

  out <- r_data_types(data.frame(v = x), use_value_labels = TRUE)
  rep <- type_conversion_report(out)

  expect_equal(rep$rule, "n_distinct_factor")
  expect_equal(rep$level_source, "inference")
})

test_that("the report names value labels as the level source", {
  x <- haven::labelled(c(1, 2, 1, 3), labels = c(Home = 1, Rehab = 2, SNF = 3))

  rep <- type_conversion_report(
    r_data_types(data.frame(disp = x), use_value_labels = TRUE)
  )

  expect_equal(rep$rule, "value_labels")
  expect_equal(rep$level_source, "value labels")
  expect_equal(rep$n_levels, 3L)
  expect_equal(rep$storage_in, "haven_labelled")
  expect_equal(rep$storage_out, "factor")
})

test_that("omitting use_value_labels warns once per session", {
  # The one-shot flag is session state; reset it so this test is
  # order-independent. `pkg:::name$field <- value` is not valid R -- the
  # replacement-function desugaring tries to reassign the bare symbol `pkg`,
  # which is never a bound variable. Use assign() against the
  # (reference-semantics) environment instead, and restore the prior value so
  # the reset doesn't leak into tests in other files.
  env <- hvtiRutilities:::.hvti_deprecated
  prior <- if (exists("use_value_labels", envir = env, inherits = FALSE)) {
    get("use_value_labels", envir = env, inherits = FALSE)
  } else {
    NULL
  }
  withr::defer(assign("use_value_labels", prior, envir = env))
  assign("use_value_labels", NULL, envir = env)

  dta <- data.frame(a = c(1, 2, 3, 1))

  expect_warning(r_data_types(dta), "use_value_labels")
  expect_silent(r_data_types(dta))
})

test_that("passing use_value_labels explicitly never warns", {
  env <- hvtiRutilities:::.hvti_deprecated
  prior <- if (exists("use_value_labels", envir = env, inherits = FALSE)) {
    get("use_value_labels", envir = env, inherits = FALSE)
  } else {
    NULL
  }
  withr::defer(assign("use_value_labels", prior, envir = env))
  assign("use_value_labels", NULL, envir = env)

  dta <- data.frame(a = c(1, 2, 3, 1))

  expect_silent(r_data_types(dta, use_value_labels = FALSE))
  expect_silent(r_data_types(dta, use_value_labels = TRUE))
})
