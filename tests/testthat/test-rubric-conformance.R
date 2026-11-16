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

test_that("cohort_counts() takes (data, time_col, event_col); d, time and event work once more, with one notice", {
  expect_identical(cohort_counts(d, time_col = "iv_dead", event_col = "dead"), want)
  expect_identical(cohort_counts(data = d, event_col = "dead", time_col = "iv_dead"), want)
  local_fresh_notice("cohort_counts_args")
  expect_warning(got <- cohort_counts(d, time = "iv_dead", event = "dead"), class = "hvtiRutilities_deprecated")
  expect_identical(got, want)
  expect_no_warning(expect_identical(cohort_counts(d = d, event = "dead", time = "iv_dead"), want))
})

test_that("assert_cohort() takes (data, expected, time_col, event_col); the old names warn once", {
  expect_true(assert_cohort(d, want, time_col = "iv_dead", event_col = "dead"))
  local_fresh_notice("assert_cohort_args")
  expect_warning(expect_true(assert_cohort(d = d, want, event = "dead", time = "iv_dead")),
                 "now \\(data, expected, time_col, event_col\\)")
})

# Both columns binary, so a swapped time and event changes the count rather
# than failing validation: three events read the wrong way round, two right.
b <- data.frame(ev = c(1, 1, 0), tt = c(1, 1, 1))
b_want <- list(n = 3L, n_events = 2L, n_censored = 1L)

test_that("two unnamed survival arguments are refused on every call, in either order", {
  refused <- "pass `time_col =` and `event_col =` by name"
  for (attempt in 1:2) {
    expect_error(cohort_counts(b, "tt", "ev"), refused)
    expect_error(cohort_counts(b, "ev", "tt"), refused)
    expect_error(cohort_counts(data = b, "ev", "tt"), refused)
    expect_error(assert_cohort(b, b_want, "tt", "ev"), refused)
    expect_error(assert_cohort(data = b, expected = b_want, "ev", "tt"), refused)
    expect_error(followup_check(b, "tt", "ev"), refused)
    expect_error(followup_check(data = b, "ev", "tt"), refused)
  }
})

test_that("one unnamed survival argument binds the same under every name, and never swaps", {
  local_fresh_notice("cohort_counts_args")
  local_fresh_notice("assert_cohort_args")
  local_fresh_notice("followup_check_args")
  suppressWarnings({
    for (attempt in 1:2) {
      # New names.
      expect_identical(cohort_counts(b, "tt", event_col = "ev"), b_want)
      expect_identical(cohort_counts(b, event_col = "ev", "tt"), b_want)
      expect_identical(cohort_counts(data = b, time_col = "tt", "ev"), b_want)
      expect_true(assert_cohort(b, b_want, "tt", event_col = "ev"))
      expect_true(assert_cohort(b, b_want, time_col = "tt", "ev"))
      expect_identical(followup_check(b, event_col = "ev", "tt")$cohort$event, 2L)
      expect_identical(followup_check(data = b, "tt", event_col = "ev")$cohort$event, 2L)
      expect_identical(followup_check(b, time_col = "tt", "ev")$cohort$event, 2L)
      # Old names, as hvtiRdatabuild and hvtiRtemplates still write them.
      expect_identical(cohort_counts(b, event = "ev", time = "tt"), b_want)
      expect_identical(cohort_counts(b, "tt", event = "ev"), b_want)
      expect_identical(cohort_counts(d = b, "ev", time = "tt"), b_want)
      expect_true(assert_cohort(b, expected = b_want, event = "ev", time = "tt"))
      expect_true(assert_cohort(b, b_want, "ev", time = "tt"))
      expect_identical(followup_check(b, event = "ev", followup = "tt")$cohort$event, 2L)
      expect_identical(followup_check(b, "ev", followup = "tt")$cohort$event, 2L)
      expect_identical(followup_check(b, "ev", followup = "tt", identifier = "tt")$cohort$event, 2L)
      expect_identical(followup_check(b, time = "tt", "ev")$cohort$event, 2L)
    }
  })
})

test_that("followup_check() takes time_col, event_col and id_col; the old names warn once", {
  new <- followup_check(d, time_col = "iv_dead", event_col = "dead")
  local_fresh_notice("followup_check_args")
  expect_warning(old <- followup_check(d, event = "dead", followup = "iv_dead"), class = "hvtiRutilities_deprecated")
  expect_equal(old$cohort, new$cohort)
  expect_no_warning(followup_check(d, event = "dead", time = "iv_dead", identifier = "dead"))
  expect_identical(names(followup_check(d, time_col = "iv_dead", event_col = "dead", id_col = "dead",
                                        max_rows = 1L)$review),
                   names(suppressWarnings(followup_check(d, event = "dead", followup = "iv_dead",
                                                         identifier = "dead", max_rows = 1L))$review))
  # Errors name each argument as the caller wrote it while the shim lives.
  expect_error(followup_check(d, event = "dead", followup = character()), "`followup` must name")
  expect_error(followup_check(d, event = "dead", time = character()), "`time` must name")
  expect_error(followup_check(d, time_col = character(), event_col = "dead"), "`time_col` must name")
  expect_error(followup_check(d, event = c("dead", "iv_dead"), followup = "iv_dead"), "`event` must name one column")
  expect_error(followup_check(d, event_col = c("dead", "iv_dead"), time_col = "iv_dead"), "`event_col` must name one column")
  expect_error(followup_check(d, event = "dead", followup = "iv_dead", identifier = c("a", "b")), "`identifier`")
})

test_that("proc_means(), proc_freq() and proc_univariate() take weight_col; weights = warns once", {
  w <- data.frame(x = c(1, 2, 3, 4), g = c("a", "a", "b", "b"), wt = c(1, 2, 1, 4))
  cases <- list(
    proc_means = function(...) proc_means(w, vars = "x", stats = c("n", "mean"), ...),
    proc_freq = function(...) proc_freq(w, "g", ...),
    proc_univariate = function(...) proc_univariate(w, vars = "x", stats = c("n", "mean"), ...)
  )
  for (fn in names(cases)) {
    new <- cases[[fn]](weight_col = "wt")
    local_fresh_notice(paste0(fn, "_weights"))
    expect_warning(old <- cases[[fn]](weights = "wt"), "`weights =` is now `weight_col =`", info = fn)
    expect_identical(old, new, info = fn)
    expect_no_warning(cases[[fn]](weights = "wt"))
  }
  # The fifth positional argument of proc_freq() is still the weight column.
  expect_identical(proc_freq(w, "g", FALSE, FALSE, "wt"), proc_freq(w, "g", weight_col = "wt"))
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

test_that("an extra named like a common provenance field is refused, and an NA sha or seed is null in JSON", {
  expect_error(hvtiRutilities:::.provenance_validate_extra(list(seed = 1L)), "may not set `seed`")
  path <- withr::local_tempfile(fileext = ".json")
  record <- list(sha = "NA", seed = NA_integer_, time = as.POSIXct("2026-01-02 03:04:05", tz = "UTC"))
  hvtiRutilities:::.provenance_write_json(record, path)
  back <- jsonlite::read_json(path)
  expect_null(back$sha)
  expect_null(back$seed)
  expect_identical(back$time, "2026-01-02T03:04:05Z")
})

test_that("capture_provenance() records a seeded job's seed, and NA when it sets none", {
  root <- versioned_study()
  cfg <- study_config(root)
  expect_identical(capture_provenance("job-x", data = list(), cfg = cfg)$seed, NA_integer_)
  rec <- capture_provenance("job-x", data = list(), cfg = cfg, seed = 42)
  expect_identical(rec$seed, 42L)
  expect_true(hvtiRutilities:::.hvti_provenance_conforms(rec))
  for (bad in list(1.5, c(1, 2), "1", Inf, NULL)) {
    expect_error(capture_provenance("job-x", data = list(), cfg = cfg, seed = bad), "`seed` must be")
  }
})

test_that("a seeded cache_fit() inside a study records its seed in the sidecar", {
  root <- versioned_study()
  dir <- study_dir("estimates", root)
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  cache_fit("draw", stats::runif(3), seed = 7, dir = dir)
  expect_identical(jsonlite::read_json(provenance_path(file.path(dir, "draw.rds")))$seed, 7L)
  cache_fit("plain", sum(1:3), dir = dir)
  expect_null(jsonlite::read_json(provenance_path(file.path(dir, "plain.rds")))$seed)
})

test_that("a root-first call evaluates its root once and writes to that study only", {
  skip_if_not_installed("arrow")
  base <- withr::local_tempdir()
  make_roots <- function(tag) {
    roots <- file.path(base, paste0(tag, 1:2))
    for (i in 1:2) {
      suppressMessages(study_setup(roots[[i]], paste("Two roots", tag, i), 20L + i, renv = FALSE))
      utils::write.csv(data.frame(ccfid = 1:3), file.path(study_dir("datasets", roots[[i]]), "built.csv"),
                       row.names = FALSE)
    }
    roots
  }
  # A stateful resolver: the first study on its first call, the second after.
  resolver <- function(roots) {
    calls <- new.env()
    calls$n <- 0L
    list(calls = calls, next_root = function() {
      calls$n <- calls$n + 1L
      roots[[calls$n]]
    })
  }
  yml <- function(roots) unname(tools::md5sum(file.path(roots, "_study.yml")))

  roots <- make_roots("declare")
  r <- resolver(roots)
  before <- yml(roots)
  local_fresh_notice("declare_data_root")
  suppressWarnings(declare_data(r$next_root(), file = "built.csv", key = "ccfid"))
  expect_identical(r$calls$n, 1L)
  expect_true(yml(roots)[[1]] != before[[1]])
  expect_identical(yml(roots)[[2]], before[[2]])

  roots <- make_roots("register")
  r <- resolver(roots)
  before <- yml(roots)
  local_fresh_notice("register_data_root")
  suppressWarnings(suppressMessages(register_data(r$next_root(), "built.csv")))
  expect_identical(r$calls$n, 1L)
  expect_true(yml(roots)[[1]] != before[[1]])
  expect_identical(yml(roots)[[2]], before[[2]])

  # A new-order call evaluates its file argument once, too.
  roots <- make_roots("file")
  calls <- new.env()
  calls$n <- 0L
  next_file <- function() {
    calls$n <- calls$n + 1L
    "built.csv"
  }
  expect_true(declare_data(next_file(), key = "ccfid", root = roots[[1]]))
  expect_identical(calls$n, 1L)
})
