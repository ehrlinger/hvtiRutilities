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
  refused <- "pass `time_cols? =` and `event_col =` by name"
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
      expect_identical(followup_check(b, time_cols = "tt", "ev")$cohort$event, 2L)
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
  new <- followup_check(d, time_cols = "iv_dead", event_col = "dead")
  local_fresh_notice("followup_check_args")
  expect_warning(old <- followup_check(d, event = "dead", followup = "iv_dead"), class = "hvtiRutilities_deprecated")
  expect_equal(old$cohort, new$cohort)
  expect_no_warning(followup_check(d, event = "dead", time = "iv_dead", identifier = "dead"))
  expect_identical(names(followup_check(d, time_cols = "iv_dead", event_col = "dead", id_col = "dead",
                                        max_rows = 1L)$review),
                   names(suppressWarnings(followup_check(d, event = "dead", followup = "iv_dead",
                                                         identifier = "dead", max_rows = 1L))$review))
  # Errors name each argument as the caller wrote it while the shim lives.
  expect_error(followup_check(d, event = "dead", followup = character()), "`followup` must name")
  expect_error(followup_check(d, event = "dead", time = character()), "`time` must name")
  expect_error(followup_check(d, time_cols = character(), event_col = "dead"), "`time_cols` must name")
  expect_error(followup_check(d, event = c("dead", "iv_dead"), followup = "iv_dead"), "`event` must name one column")
  expect_error(followup_check(d, event_col = c("dead", "iv_dead"), time_cols = "iv_dead"), "`event_col` must name one column")
  expect_error(followup_check(d, event = "dead", followup = "iv_dead", identifier = c("a", "b")), "`identifier`")
})

test_that("key_cols and order_by_cols: duplicate_keys(), declare_data() and register_data(); the old names warn once", {
  ops <- data.frame(id = c(1, 1, 2), dt = c(1, 1, 2), t = c(2, 1, 1))
  new <- duplicate_keys(ops, key_cols = c("id", "dt"), order_by_cols = "t")
  local_fresh_notice("duplicate_keys_args")
  expect_warning(old <- duplicate_keys(ops, key = c("id", "dt"), order_by = "t"), "`key_cols =` and `order_by_cols =`")
  expect_identical(old, new)
  expect_identical(duplicate_keys(ops, c("id", "dt"), "t"), new)
  expect_no_warning(duplicate_keys(ops, key = c("id", "dt"), order_by = "t"))
  expect_error(duplicate_keys(ops, key_cols = character()), "`key_cols` must name")

  skip_if_not_installed("arrow")
  root <- file.path(withr::local_tempdir(), "k")
  suppressMessages(study_setup(root, "Key cols", 9L, renv = FALSE))
  utils::write.csv(data.frame(ccfid = 1:3), file.path(study_dir("datasets", root), "built.csv"), row.names = FALSE)
  local_fresh_notice("declare_data_key")
  expect_warning(expect_true(declare_data("built.csv", key = "ccfid", root = root)), "`key =` is now `key_cols =`")
  expect_identical(study_config(root, require_data = FALSE)$key, "ccfid")
  root <- file.path(withr::local_tempdir(), "k2")
  suppressMessages(study_setup(root, "Key cols 2", 10L, renv = FALSE))
  utils::write.csv(data.frame(ccfid = 1:3), file.path(study_dir("datasets", root), "built.csv"), row.names = FALSE)
  local_fresh_notice("register_data_key")
  expect_warning(suppressMessages(register_data("built.csv", key = "ccfid", root = root)), "`key =` is now `key_cols =`")
})

test_that("proc_means(), proc_freq() and proc_univariate() take weight_col; weights = warns once", {
  w <- data.frame(x = c(1, 2, 3, 4), g = c("a", "a", "b", "b"), wt = c(1, 2, 1, 4))
  cases <- list(
    proc_means = function(...) proc_means(w, var_cols = "x", stats = c("n", "mean"), ...),
    proc_freq = function(...) proc_freq(w, "g", ...),
    proc_univariate = function(...) proc_univariate(w, var_cols = "x", stats = c("n", "mean"), ...)
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
  expect_false(declare_data("built.csv", key_cols = "ccfid", root = root))
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
  expect_true(declare_data(next_file(), key_cols = "ccfid", root = roots[[1]]))
  expect_identical(calls$n, 1L)
})

test_that("multi-column arguments take *_cols; the old names warn once and give the same result", {
  w <- data.frame(x = c(1, 2, 3, 4), g = c("a", "a", "b", "b"), f = factor(c("1", "2", "1", "2")),
                  s = c("u", "v", "u", "v"))
  # Each case: the call with the new name, the same call with the old name, and the notice key.
  cases <- list(
    covariate_audit = list(function() covariate_audit(w, var_cols = "f"),
                           function() covariate_audit(w, vars = "f"), "covariate_audit_vars"),
    covariates_to_numeric = list(function() covariates_to_numeric(w, var_cols = "f"),
                                 function() covariates_to_numeric(w, vars = "f"), "covariates_to_numeric_vars"),
    level_map = list(function() level_map(w, var_cols = "f"),
                     function() level_map(w, vars = "f"), "level_map_vars"),
    proc_means = list(function() proc_means(w, var_cols = "x", class_cols = "g", stats = c("n", "mean")),
                      function() proc_means(w, vars = "x", class = "g", stats = c("n", "mean")), "proc_means_cols"),
    proc_univariate = list(function() proc_univariate(w, var_cols = "x", class_cols = "g", stats = c("n", "mean")),
                           function() proc_univariate(w, vars = "x", class = "g", stats = c("n", "mean")),
                           "proc_univariate_cols"),
    proc_freq = list(function() proc_freq(w, table_cols = c("g", "s")),
                     function() proc_freq(w, tables = c("g", "s")), "proc_freq_tables"),
    proc_print = list(function() proc_print(w, x > 2 ~ "big", var_cols = "x", console = FALSE),
                      function() proc_print(w, x > 2 ~ "big", var = "x", console = FALSE), "proc_print_var"),
    r_data_types = list(function() r_data_types(w, skip_cols = "s", use_value_labels = FALSE),
                        function() r_data_types(w, skip_vars = "s", use_value_labels = FALSE), "r_data_types_skip_vars")
  )
  for (fn in names(cases)) {
    new <- cases[[fn]][[1L]]()
    local_fresh_notice(cases[[fn]][[3L]])
    expect_warning(old <- cases[[fn]][[2L]](), "_cols =`", class = "hvtiRutilities_deprecated", info = fn)
    expect_identical(old, new, info = fn)
    expect_no_warning(cases[[fn]][[2L]]())
  }
})

test_that("only class = in proc_means() is enough to warn, and positional calls bind as before", {
  w <- data.frame(x = c(1, 2, 3, 4), g = c("a", "a", "b", "b"))
  local_fresh_notice("proc_means_cols")
  expect_warning(proc_means(w, "x", class = "g", stats = "n"), "`class =`", class = "hvtiRutilities_deprecated")
  # The second and third positional arguments are still the analysis and class columns.
  expect_identical(proc_means(w, "x", "g", stats = "n"), proc_means(w, var_cols = "x", class_cols = "g", stats = "n"))
  expect_identical(proc_freq(w, "g"), proc_freq(w, table_cols = "g"))
  expect_identical(level_map(data.frame(f = factor("a")), "f"), level_map(data.frame(f = factor("a")), var_cols = "f"))
  expect_identical(r_data_types(w, 10, "g", use_value_labels = FALSE),
                   r_data_types(w, skip_cols = "g", use_value_labels = FALSE))
})

test_that("r_data_types() takes both old names at once: dataset = and skip_vars =", {
  w <- data.frame(x = c(1, 2, 3, 4), s = c("u", "v", "u", "v"))
  local_fresh_notice("r_data_types_dataset")
  local_fresh_notice("r_data_types_skip_vars")
  expect_warning(expect_warning(old <- r_data_types(dataset = w, skip_vars = "s", use_value_labels = FALSE),
                                "`dataset =`"), "`skip_vars =`")
  expect_identical(old, r_data_types(w, skip_cols = "s", use_value_labels = FALSE))
})

test_that("update_manifest() takes sort_key_cols and still records the field as sort_key", {
  dir <- withr::local_tempdir()
  csv <- file.path(dir, "d.csv")
  utils::write.csv(data.frame(id = 1:3), csv, row.names = FALSE)
  mpath <- file.path(dir, "manifest.yaml")
  update_manifest(csv, manifest_path = mpath, sort_key_cols = "id")
  expect_identical(yaml::read_yaml(mpath)$datasets[[1L]]$sort_key, "id")
  local_fresh_notice("update_manifest_sort_key")
  expect_warning(update_manifest(csv, manifest_path = mpath, sort_key = c("id", "x")), "`sort_key =` is now `sort_key_cols =`",
                 class = "hvtiRutilities_deprecated")
  expect_identical(yaml::read_yaml(mpath)$datasets[[1L]]$sort_key, c("id", "x"))
  # The no-file form still refuses a single-file argument under its new name.
  expect_error(update_manifest(sort_key_cols = "id"), "sort_key_cols")
})

test_that("a renamed argument given under both its old and its new name is an error, not a silent choice", {
  w <- data.frame(x = c(1, 2, 3, 4), g = c("a", "a", "b", "b"), wt = c(1, 2, 1, 4))
  expect_error(proc_means(w, var_cols = "x", weight_col = "wt", weights = NULL), "`weights =` and `weight_col =`")
  expect_error(proc_univariate(w, var_cols = "x", weight_col = "wt", weights = "wt"), "`weights =` and `weight_col =`")
  # The new name given by position counts as given.
  expect_error(proc_freq(w, "g", FALSE, FALSE, "wt", weights = NULL), "`weights =` and `weight_col =`")
  expect_error(followup_check(d, followup = "iv_dead", time_cols = "iv_dead", event_col = "dead"),
               "`followup =` and `time_cols =`")
  expect_error(followup_check(d, "dead", followup = "iv_dead", time = "iv_dead"), "`followup =` and `time_cols =`")
  expect_error(followup_check(d, time_cols = "iv_dead", event_col = "dead", id_col = "dead", identifier = "dead"),
               "`identifier =` and `id_col =`")
  expect_error(r_data_types(data = w, dataset = w, use_value_labels = FALSE), "`dataset =` and `data =`")
  expect_error(parity_headline(data = compare_parity("a", 1, 1), df = compare_parity("a", 1, 1)), "`df =` and `data =`")
})

test_that("only a call that opens with an unnamed directory is read in the old root-first order", {
  skip_if_not_installed("arrow")
  root <- file.path(withr::local_tempdir(), "s")
  suppressMessages(study_setup(root, "Root bind", 11L, renv = FALSE))
  utils::write.csv(data.frame(ccfid = 1:3), file.path(study_dir("datasets", root), "built.csv"), row.names = FALSE)
  # Run from the study, beside a directory named like the dataset and like the key.
  dir.create(file.path(root, "valve"))
  dir.create(file.path(root, "ccfid"))
  withr::local_dir(root)
  local_fresh_notice("declare_data_root")
  # `file` is named, so the unnamed "ccfid" is the key, never a root.
  expect_no_warning(declare_data(file = "built.csv", "ccfid"))
  expect_identical(study_config(root, require_data = FALSE)$key, "ccfid")
  local_fresh_notice("register_data_root")
  # Likewise the unnamed "valve" is the dataset.
  expect_no_warning(suppressMessages(register_data(file = "built.csv", "valve", role = "named")))
  expect_identical(yaml::read_yaml(file.path(root, "_study.yml"))$additional_datasets$valve$built, "built.csv")
})

test_that("capture_provenance() refuses a seed outside the integer range rather than recording none", {
  root <- file.path(withr::local_tempdir(), "p")
  suppressMessages(study_setup(root, "Seed range", 13L, renv = FALSE))
  expect_error(capture_provenance("job", data = list(), cfg = study_config(root, require_data = FALSE), seed = 3e9),
               "`seed`")
})

test_that("the *_cols renames refuse the old and the new name together", {
  w <- data.frame(x = c(1, 2, 3, 4), a = c("p", "q", "p", "q"), g = c("a", "a", "b", "b"),
                  f = factor(c("1", "2", "1", "2")))
  both <- function(old, new) paste0("`", old, " =` and `", new, " =`")
  expect_error(proc_means(w, var_cols = "x", vars = "x"), both("vars", "var_cols"))
  expect_error(proc_univariate(w, var_cols = "x", vars = "x"), both("vars", "var_cols"))
  expect_error(covariate_audit(w, var_cols = "f", vars = "f"), both("vars", "var_cols"))
  expect_error(covariates_to_numeric(w, var_cols = "f", vars = "f"), both("vars", "var_cols"))
  expect_error(level_map(w, var_cols = "f", vars = "f"), both("vars", "var_cols"))
  expect_error(proc_freq(w, table_cols = "g", tables = "a"), both("tables", "table_cols"))
  # The new name given by position counts as given, since it holds the old name's place.
  expect_error(proc_freq(w, "g", tables = "a"), both("tables", "table_cols"))
  expect_error(r_data_types(w, skip_cols = "a", skip_vars = "a", use_value_labels = FALSE), both("skip_vars", "skip_cols"))
  # An old name that partially matches the new one cannot be given with it: R refuses the call before
  # the function runs.
  expect_error(proc_means(w, "x", class_cols = "g", class = "g"), "unused argument (class", fixed = TRUE)
  expect_error(proc_print(w, x > 2 ~ "big", var_cols = "x", var = "x", console = FALSE), "unused argument (var", fixed = TRUE)
})

test_that("old and new column names together are refused for every alias family, with NULL or by position (#302 review)", {
  d <- data.frame(a = 1:3, b = 4:6, f = factor(c("1", "2", "1")), s = c("u", "v", "u"))
  both <- function(old, new) paste0("`", old, " =` and `", new, " =`")
  # The review's reproductions: before the fix each returned results for `b`.
  expect_error(proc_means(d, var_cols = "a", vars = "b", stats = "mean"), both("vars", "var_cols"))
  expect_error(proc_freq(d, table_cols = "a", tables = "b"), both("tables", "table_cols"))
  # An explicit NULL is still the new name given.
  expect_error(proc_means(d, var_cols = NULL, vars = "b"), both("vars", "var_cols"))
  expect_error(proc_univariate(d, var_cols = NULL, vars = "b"), both("vars", "var_cols"))
  expect_error(level_map(d, var_cols = NULL, vars = "f"), both("vars", "var_cols"))
  expect_error(r_data_types(d, skip_cols = NULL, skip_vars = "s", use_value_labels = FALSE), both("skip_vars", "skip_cols"))
  expect_error(proc_means(d, var_cols = "a", weight_col = NULL, weights = "b"), both("weights", "weight_col"))
  # The new name by position, in the place the old name held.
  expect_error(proc_means(d, "a", vars = "b"), both("vars", "var_cols"))
  expect_error(proc_univariate(d, "a", vars = "b"), both("vars", "var_cols"))
  expect_error(covariate_audit(d, "f", vars = "f"), both("vars", "var_cols"))
  expect_error(covariates_to_numeric(d, "f", vars = "f"), both("vars", "var_cols"))
  expect_error(level_map(d, "f", vars = "f"), both("vars", "var_cols"))
  expect_error(r_data_types(d, 10, "s", skip_vars = "a", use_value_labels = FALSE), both("skip_vars", "skip_cols"))
  # A skip_cols conflict must not convert a column the caller meant to keep.
  expect_error(r_data_types(d, skip_cols = "s", skip_vars = "a", use_value_labels = FALSE), both("skip_vars", "skip_cols"))
})
