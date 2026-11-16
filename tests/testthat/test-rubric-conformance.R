# The hvtiR API rubric (2026-11-16): renames ship as one-release deprecations,
# quiet mode, condition classes and the shared provenance record.

# Clear one deprecation flag for the duration of a test, so its once-per-session
# notice fires here whatever ran first.
local_fresh_notice <- function(key, env = parent.frame()) {
  flags <- hvtiRutilities:::.hvti_deprecated
  old <- flags[[key]]
  if (!is.null(old)) rm(list = key, envir = flags)
  withr::defer(if (is.null(old)) suppressWarnings(rm(list = key, envir = flags)) else assign(key, old, envir = flags),
               envir = env)
}

d <- data.frame(dead = c(1, 0, 0, 1), iv_dead = c(2, 3, 4, 5))
want <- list(n = 4L, n_events = 2L, n_censored = 2L)

test_that("cohort_counts() takes (data, time, event); old calls work once more, with one notice", {
  expect_identical(cohort_counts(d, time = "iv_dead", event = "dead"), want)
  expect_identical(cohort_counts(data = d, event = "dead", time = "iv_dead"), want)
  local_fresh_notice("cohort_counts_args")
  expect_warning(got <- cohort_counts(d, "dead", "iv_dead"), class = "hvtiRutilities_deprecated")
  expect_identical(got, want)
  expect_no_warning(expect_identical(cohort_counts(d = d, event = "dead", time = "iv_dead"), want))
})

test_that("assert_cohort() reads an all-positional old call in the old order", {
  expect_true(assert_cohort(d, want, time = "iv_dead", event = "dead"))
  local_fresh_notice("assert_cohort_args")
  expect_warning(expect_true(assert_cohort(d, want, "dead", "iv_dead")), "now \\(data, expected, time, event\\)")
})

test_that("followup_check() takes time = and maps followup = to it", {
  new <- followup_check(d, time = "iv_dead", event = "dead")
  local_fresh_notice("followup_check_args")
  expect_warning(old <- followup_check(d, event = "dead", followup = "iv_dead"), class = "deprecatedWarning")
  expect_equal(old$cohort, new$cohort)
  expect_equal(followup_check(d, "dead", "iv_dead")$intervals, new$intervals)
})

test_that("r_data_types() and parity_headline() take data =", {
  local_fresh_notice("r_data_types_dataset")
  expect_warning(old <- r_data_types(dataset = d, use_value_labels = FALSE), "`dataset =` is now `data =`")
  expect_identical(old, r_data_types(data = d, use_value_labels = FALSE))
  rows <- compare_parity("a", 1.0001, 1, class = "mle_printed")
  local_fresh_notice("parity_headline_df")
  expect_warning(h <- parity_headline(df = rows), "`df =` is now `data =`")
  expect_identical(h, parity_headline(rows))
})

test_that("register_data() and declare_data() take root last and still read a root-first call", {
  skip_if_not_installed("arrow")
  root <- file.path(withr::local_tempdir(), "s")
  suppressMessages(study_setup(root, "Root last", 7L, renv = FALSE))
  utils::write.csv(data.frame(ccfid = 1:3), file.path(study_dir("datasets", root), "built.csv"),
                   row.names = FALSE)
  local_fresh_notice("declare_data_root")
  expect_warning(expect_true(declare_data(root, file = "built.csv", key = "ccfid")),
                 "`root` is now the last argument")
  expect_false(declare_data("built.csv", key = "ccfid", root = root))
  root <- file.path(withr::local_tempdir(), "s2")
  suppressMessages(study_setup(root, "Root last 2", 8L, renv = FALSE))
  utils::write.csv(data.frame(ccfid = 1:3), file.path(study_dir("datasets", root), "built.csv"),
                   row.names = FALSE)
  local_fresh_notice("register_data_root")
  expect_warning(suppressMessages(register_data(root, "built.csv")), class = "hvtiRutilities_deprecated")
})

test_that("a lost checkpoint lock carries the package's class and the old one", {
  e <- structure(class = c("hvtiRutilities_cp_lock_lost", "hvti_cp_lock_lost", "error", "condition"),
                 list(message = "x", call = NULL))
  expect_true(inherits(e, "hvtiRutilities_cp_lock_lost") && inherits(e, "hvti_cp_lock_lost"))
  cond <- hvtiRutilities:::.hvti_deprecation("m")
  expect_s3_class(cond, c("hvtiRutilities_deprecated", "deprecatedWarning", "warning"))
})

test_that("options(hvti.quiet = TRUE) silences informational messages, never warnings", {
  expect_message(hvtiRutilities:::.hvti_inform("hello"), "hello")
  withr::local_options(hvti.quiet = TRUE)
  expect_no_message(hvtiRutilities:::.hvti_inform("hello"))
  dir <- withr::local_tempdir()
  cache_fit("s", sum(1:3), dir = dir)
  expect_no_message(cache_fit("s", sum(1:3), dir = dir))
})

test_that("the shared provenance record conforms: seven fields, stated types and lengths", {
  rec <- hvtiRutilities:::.hvti_provenance_core(method = "job-x")
  expect_true(hvtiRutilities:::.hvti_provenance_conforms(rec))
  expect_identical(names(rec)[1:7], c("package", "version", "sha", "method", "seed", "rng_kind", "time"))
  expect_identical(rec$package, "hvtiRutilities")
  expect_identical(rec$seed, NA_integer_)
  expect_length(rec$rng_kind, 3L)
  bad <- rec
  bad$seed <- 1.5
  expect_false(hvtiRutilities:::.hvti_provenance_conforms(bad))
  bad <- rec[-3]
  expect_false(hvtiRutilities:::.hvti_provenance_conforms(bad))
})
