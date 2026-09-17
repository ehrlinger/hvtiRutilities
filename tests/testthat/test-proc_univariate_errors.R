library(testthat)
library(hvtiRutilities)

dta <- data.frame(x = c(1, 2, 3, 4), w = c(1, 1, 2, 0.5))

test_that("proc_means() errors and messages carry over", {
  expect_error(proc_univariate(list(x = 1)), "'data' must be a data frame")
  expect_error(proc_univariate(dta, vars = "nope"), "not found in 'data'")
  expect_error(proc_univariate(data.frame(x = "a"), vars = "x"),
               "Non-numeric column")
  expect_error(proc_univariate(dta, weights = "nope"), "not found in 'data'")
  expect_error(proc_univariate(data.frame(x = 1, w = 0), vars = "x",
                               weights = "w"),
               "non-positive value")
  expect_error(proc_univariate(dta, vars = c("x", "w"), weights = "w"),
               "also named in 'vars' or 'class'")
})

test_that("an unknown keyword errors and lists the univariate keywords", {
  expect_error(proc_univariate(dta, stats = "bogus"),
               "Unrecognised statistic keyword\\(s\\): bogus")
  expect_error(proc_univariate(dta, stats = "bogus"), "signrank")
})

test_that("proc_means() does not gain the univariate keywords", {
  for (k in c("stdmean", "t", "probt", "msign", "probm", "signrank",
              "probs", "normal", "probn")) {
    expect_error(proc_means(dta, stats = k), "Unrecognised statistic")
  }
})

test_that("pctlpts is validated", {
  expect_error(proc_univariate(dta, pctlpts = "50"), "must be numeric")
  expect_error(proc_univariate(dta, pctlpts = c(50, NA)), "must not contain NA")
  expect_error(proc_univariate(dta, pctlpts = c(-1, 50)), "\\[0, 100\\]")
  expect_error(proc_univariate(dta, pctlpts = 100.5), "\\[0, 100\\]")
  expect_error(proc_univariate(dta, pctlpts = c(2.5, 2.5)), "duplicated")
})

test_that("pctlpre is validated", {
  expect_error(proc_univariate(dta, pctlpts = 50, pctlpre = ""),
               "single non-empty string")
  expect_error(proc_univariate(dta, pctlpts = 50, pctlpre = c("a", "b")),
               "single non-empty string")
  expect_error(proc_univariate(dta, pctlpts = 50, pctlpre = NA_character_),
               "single non-empty string")
  expect_error(proc_univariate(dta, pctlpts = 50, pctlpre = 1),
               "single non-empty string")
})

test_that("a percentile name that duplicates a stats column errors", {
  expect_error(proc_univariate(dta, stats = c("n", "p50"), pctlpts = 50),
               "duplicate another output column: p50")
})

test_that("a percentile name that duplicates a class column errors", {
  cls <- data.frame(x = c(1, 2, 3, 4), p50 = c("a", "a", "b", "b"))
  expect_error(proc_univariate(cls, vars = "x", class = "p50", pctlpts = 50),
               "duplicate another output column: p50")
})

test_that("mu0 must be a single finite number", {
  expect_error(proc_univariate(dta, mu0 = NA_real_), "single finite number")
  expect_error(proc_univariate(dta, mu0 = Inf), "single finite number")
  expect_error(proc_univariate(dta, mu0 = c(1, 2)), "single finite number")
  expect_error(proc_univariate(dta, mu0 = "1"), "single finite number")
})

test_that("vardef must be one of the four SAS values", {
  expect_error(proc_univariate(dta, vardef = "wgt"), "should be one of")
})

test_that("normality above 2000 observations is NA with one warning", {
  big <- data.frame(x = sin(seq_len(2001)), y = cos(seq_len(2001)))
  expect_warning(
    res <- proc_univariate(big, stats = c("n", "normal", "probn")),
    "Kolmogorov D"
  )
  expect_true(all(is.na(res$normal)))
  expect_true(all(is.na(res$probn)))
  warnings_seen <- 0L
  withCallingHandlers(
    proc_univariate(big, stats = c("normal", "probn")),
    warning = function(w) {
      warnings_seen <<- warnings_seen + 1L
      invokeRestart("muffleWarning")
    }
  )
  expect_equal(warnings_seen, 1L)
})

test_that("a constant column above 2000 observations also warns", {
  expect_warning(
    res <- proc_univariate(data.frame(x = rep(5, 2001)), stats = "normal"),
    "Kolmogorov D"
  )
  expect_true(is.na(res$normal))
})

test_that("no warning at 2000 observations or without a normality keyword", {
  expect_no_warning(
    proc_univariate(data.frame(x = sin(seq_len(2000))), stats = "normal")
  )
  expect_no_warning(
    proc_univariate(data.frame(x = sin(seq_len(2001))), stats = "n")
  )
})
