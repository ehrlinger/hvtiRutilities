test_that("tolerance classes are the ones the design names", {
  expect_equal(parity_tolerance("count"), list(rtol = 0, atol = 0))
  expect_equal(parity_tolerance("loglik"), list(rtol = 0, atol = 0.0005))
  expect_equal(parity_tolerance("mle_stored"), list(rtol = 1e-6, atol = 1e-9))
  expect_equal(parity_tolerance("vcov_stored"), list(rtol = 1e-4, atol = 1e-9))
  expect_error(parity_tolerance("invented"), "invented")
})

test_that("agreement inside tolerance is PASS", {
  out <- compare_parity("mue", r = 0.1022604, sas = 0.1022604,
                        class = "mle_printed")
  expect_equal(out$outcome, "PASS")
  expect_equal(out$abs_diff, 0)
})

test_that("disagreement beyond tolerance is DIFFERS", {
  out <- compare_parity("mue", r = 0.11, sas = 0.1022604, class = "mle_printed")
  expect_equal(out$outcome, "DIFFERS")
})

test_that("a log-likelihood higher than SAS beyond tolerance is R_BETTER", {
  out <- compare_parity("log_likelihood", r = -239.10, sas = -239.194,
                        class = "loglik")
  expect_equal(out$outcome, "R_BETTER")
})

test_that("a log-likelihood lower than SAS beyond tolerance is DIFFERS", {
  out <- compare_parity("log_likelihood", r = -239.30, sas = -239.194,
                        class = "loglik")
  expect_equal(out$outcome, "DIFFERS")
})

test_that("a missing value on either side errors and never returns a row", {
  expect_error(
    compare_parity("mue", r = NULL, sas = 0.1, class = "mle_printed"),
    "absent"
  )
  expect_error(
    compare_parity("mue", r = 0.1, sas = NA_real_, class = "mle_printed"),
    "absent"
  )
})

test_that("printed class derives its tolerance from the printed digits", {
  out <- compare_parity("surv_5yr", r = 0.75001, sas = 0.75, class = "printed",
                        digits = 2)
  expect_equal(out$atol, 0.005)
  expect_equal(out$outcome, "PASS")
})

test_that("parity_headline reports the largest relative discrepancy", {
  df <- rbind(
    compare_parity("a", 1.0000, 1.0, class = "mle_printed"),
    compare_parity("b", 1.0002, 1.0, class = "mle_printed")
  )
  expect_match(parity_headline(df), "2 compared quantities")
  expect_match(parity_headline(df), "2.00e-04")
})

test_that("parity_headline flags an all-zero discrepancy as suspicious", {
  df <- rbind(
    compare_parity("a", 1, 1, class = "mle_printed"),
    compare_parity("b", 2, 2, class = "mle_printed")
  )
  expect_match(parity_headline(df), "exactly zero", fixed = TRUE)
})
