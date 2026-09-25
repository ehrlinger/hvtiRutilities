d <- data.frame(
  id      = c("a", "b", "c", "d", "e", "f"),
  dead    = c(1, 0, 0, NA, 1, 0),
  iv_dead = c(2.5, 4, 0, 1.2, NA, -1),
  iv_fup  = c(3, 4, 1, 2, 5, 6)
)

test_that("cohort counts the whole cohort, each subset and missing events", {
  fc <- followup_check(d, "dead", "iv_dead")
  expect_s3_class(fc, "followup_check")
  expect_identical(fc$cohort, data.frame(full = 6L, event = 2L, censored = 3L, missing_event = 1L))
})

test_that("intervals count missing, negative and zero values and summarise the rest", {
  fc <- followup_check(d, "dead", c("iv_dead", "iv_fup"))
  row <- fc$intervals[fc$intervals$interval == "iv_dead", ]
  observed <- c(2.5, 4, 0, 1.2, -1)
  expect_identical(c(row$missing, row$negative, row$zero), c(1L, 1L, 1L))
  expect_equal(c(row$min, row$median, row$max), c(-1, 1.2, 4))
  expect_equal(c(row$q1, row$q3), unname(stats::quantile(observed, c(.25, .75))))
  expect_equal(c(row$mean, row$sd), c(mean(observed), stats::sd(observed)))
  expect_identical(fc$intervals$interval, c("iv_dead", "iv_fup"))
})

test_that("an interval with no observed value summarises as NA, not an error", {
  fc <- followup_check(transform(d, iv_dead = NA_real_), "dead", "iv_dead")
  expect_true(all(is.na(fc$intervals[c("min", "q1", "median", "q3", "mean", "sd", "max")])))
  expect_identical(fc$intervals$missing, 6L)
})

test_that("means are proc_means over the full, event and censored subsets", {
  fc <- followup_check(d, "dead", "iv_dead")
  st <- c("n", "nmiss", "mean", "std", "min", "p25", "median", "p75", "max")
  expect_named(fc$means, c("full", "event", "censored"))
  expect_identical(fc$means$full, proc_means(d, vars = "iv_dead", stats = st))
  expect_identical(fc$means$event, proc_means(d[c(1, 5), ], vars = "iv_dead", stats = st))
  expect_identical(fc$means$censored, proc_means(d[c(2, 3, 6), ], vars = "iv_dead", stats = st))
})

test_that("review holds suspicious rows in data order, capped, identifiers only on request", {
  fc <- followup_check(d, "dead", "iv_dead")
  # c: zero interval; d: missing event; e: missing interval; f: negative.
  expect_identical(fc$review$dead, c(0, NA, 1, 0))
  expect_named(fc$review, c("dead", "iv_dead"))
  expect_identical(attr(fc, "n_suspicious"), 4L)
  fc <- followup_check(d, "dead", "iv_dead", identifier = "id", max_rows = 2)
  expect_identical(fc$review$id, c("c", "d"))
  expect_identical(attr(fc, "n_suspicious"), 4L)
})

test_that("a logical event is accepted", {
  fc <- followup_check(transform(d, dead = as.logical(dead)), "dead", "iv_dead")
  expect_identical(fc$cohort$event, 2L)
})

test_that("every missing column is named in one error", {
  expect_error(followup_check(d, "dead", c("iv_dead", "nope1"), identifier = "nope2"),
               "Unknown column\\(s\\): nope1, nope2")
})

test_that("arguments are validated before anything is computed", {
  expect_error(followup_check(as.list(d), "dead", "iv_dead"), "data frame")
  expect_error(followup_check(d, c("dead", "id"), "iv_dead"), "`event` must name one column")
  expect_error(followup_check(d, "dead", character()), "`followup`")
  expect_error(followup_check(d, "dead", c("iv_dead", "iv_dead")), "`followup`")
  expect_error(followup_check(d, "dead", "iv_dead", identifier = c("id", "dead")), "`identifier`")
  for (bad in list(0, 1.5, NA, Inf, c(1, 2), "3")) {
    expect_error(followup_check(d, "dead", "iv_dead", max_rows = bad), "`max_rows`")
  }
  expect_error(followup_check(transform(d, dead = c(0, 2, 0, 1, 0, 1)), "dead", "iv_dead"), "binary")
  expect_error(followup_check(transform(d, iv_fup = as.character(iv_fup)), "dead", c("iv_dead", "iv_fup")),
               "must be numeric: iv_fup")
})

test_that("print summarises the check", {
  expect_output(print(followup_check(d, "dead", "iv_dead")), "6 \\(2 event, 3 censored, 1 missing event\\)")
})
