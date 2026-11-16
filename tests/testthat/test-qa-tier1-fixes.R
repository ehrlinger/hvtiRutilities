# Regression tests for the 2026-11-16 family QA pass, one block per finding.

test_that("r_data_types() keeps n < factor_size as the numeric threshold", {
  d <- data.frame(n9 = c(1:9, 1:9, 1, 2), n10 = rep(1:10, 2))
  out <- r_data_types(d, factor_size = 10, use_value_labels = FALSE)
  expect_s3_class(out$n9, "factor")
  expect_type(out$n10, "integer")
})

test_that("r_data_types() warns on a character column with more than 50 levels", {
  d <- data.frame(id = sprintf("p%03d", 1:60), grp = rep(c("a", "b"), 30))
  expect_warning(out <- r_data_types(d, use_value_labels = FALSE),
                 "more than 50 levels: id\\.")
  expect_s3_class(out$id, "factor")
  expect_no_warning(r_data_types(d, skip_vars = "id", use_value_labels = FALSE))
  expect_no_warning(r_data_types(d[1:50, ], use_value_labels = FALSE))
})

test_that("r_data_types() errors carry no call and name the unknown skip_vars", {
  e <- expect_error(r_data_types(list(), use_value_labels = FALSE))
  expect_null(conditionCall(e))
  expect_error(r_data_types(mtcars, skip_vars = c("mpg", "nope"), use_value_labels = FALSE),
               "dataset: nope\\.")
})

test_that("read_clinical_data() refuses dots it cannot honour", {
  tmp <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(data.frame(a = 1:3), tmp, row.names = FALSE)
  expect_error(read_clinical_data(tmp, convert_types = FALSE, factor_size = 5),
               "does not run when `convert_types` is FALSE")
  expect_error(read_clinical_data(tmp, convert_types = TRUE, sheet = 2),
               "no argument `sheet`")
  expect_error(read_clinical_data(tmp, TRUE, 5), "must be named")
  out <- read_clinical_data(tmp, convert_types = TRUE, factor_size = 5,
                            use_value_labels = FALSE)
  expect_s3_class(out$a, "factor")
})

test_that("read_clinical_data() column types per format are as documented", {
  df <- data.frame(dt = as.Date("2020-01-02") + 0:1, ch = c("a", "b"))
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(df, csv, row.names = FALSE)
  expect_type(read_clinical_data(csv, convert_types = FALSE)$dt, "character")
  sas <- withr::local_tempfile(fileext = ".sas7bdat")
  suppressWarnings(haven::write_sas(df, sas))
  expect_s3_class(read_clinical_data(sas, convert_types = FALSE)$dt, "Date")
})

test_that("study_status() reports closure UNKNOWN when git errors", {
  root <- file.path(withr::local_tempdir(), "s")
  suppressMessages(study_setup(root, "Git error", 7L, renv = FALSE))
  .cp_log_append(root, list(type = "checkpoint", checkpoint_id = "c-1",
                            kind = "abstract_submitted", tag = "abstract_submitted-1",
                            state = "committed",
                            delivery = list(git = "done", st = "done")))
  local_mocked_bindings(.cp_is_closed = function(root) stop("git exploded"))
  checks <- study_status(root)$checks
  expect_equal(checks$status[checks$item == "closure"], "UNKNOWN")
})

test_that("compare_datasets() compares levels and says values were not compared", {
  old <- data.frame(g = factor(c("a", "b")), x = 1:2)
  new <- data.frame(g = factor(c("a", "c")), x = 3:4)
  res <- compare_datasets(old, new)
  expect_equal(res$level_changes$variable, "g")
  expect_equal(res$level_changes$n_added, 1L)
  expect_equal(res$level_changes$n_removed, 1L)
  res <- compare_datasets(old, new, show_levels = TRUE)
  expect_equal(res$level_changes$old_levels, "a, b")
  expect_equal(res$level_changes$new_levels, "a, c")
  out <- capture.output(print(compare_datasets(old[, "x", drop = FALSE],
                                               new[, "x", drop = FALSE])))
  expect_true(any(grepl("factor levels", out)))
  expect_true(any(grepl("Values were not compared", out)))
})

test_that(".default_manifest_path() passes on a malformed _study.yml", {
  root <- withr::local_tempdir()
  writeLines("study: [unclosed", file.path(root, "_study.yml"))
  withr::local_dir(root)
  expect_error(.default_manifest_path())
  outside <- withr::local_tempdir()
  withr::local_dir(outside)
  expect_identical(.default_manifest_path(), "manifest.yaml")
})

test_that("verify_manifest() missing-file error carries no call", {
  e <- expect_error(verify_manifest(file.path(tempdir(), "no-such.yaml")))
  expect_null(conditionCall(e))
})

test_that("add_labels() on a data frame warns about names it cannot apply", {
  d <- data.frame(age = 1:3)
  expect_warning(out <- add_labels(d, c(age = "Age", agee = "Typo")),
                 "not applied: agee")
  expect_identical(labelled::var_label(out$age), "Age")
  expect_no_warning(add_labels(d, c(age = "Age")))
})

test_that("an empty study root resolves to the numbered layout", {
  root <- withr::local_tempdir()
  expect_identical(study_dir("estimates", root), file.path(root, "90_estimates"))
})

test_that("cohort_counts() warns on zero or negative time but keeps the count", {
  d <- data.frame(dead = c(1, 0, 0), t = c(0, -1, 5))
  expect_warning(cc <- cohort_counts(d, event_col = "dead", time_col = "t"),
                 "1 negative and 1 zero")
  expect_equal(cc$n, 3L)
  expect_no_warning(cohort_counts(data.frame(dead = 1, t = 2), time_col = "t", event_col = "dead"))
})

test_that("covariates_to_numeric() warns about names not in the data", {
  d <- data.frame(x = factor(c("0", "1")))
  expect_warning(out <- covariates_to_numeric(d, c("x", "xx")), "not converted: xx")
  expect_type(out$x, "double")
})

test_that("apply_value_labels() leaves a factor column as read and says so", {
  d <- data.frame(s = factor(c("1", "2")), n = c(1, 2))
  yml <- withr::local_tempfile(fileext = ".yml")
  writeLines(c("s:", "  '1': Home", "n:", "  '1': Home", "  '2': Rehab"), yml)
  expect_warning(out <- apply_value_labels(d, yml), "already factors.*: s\\.")
  expect_identical(out$s, d$s)
  expect_length(labelled::val_labels(out$n), 2L)
})

# Second pass: checkpoint, git and setup internals.

test_that("checkpoint dates must be one Date or one YYYY-MM-DD string", {
  expect_identical(.cp_date(as.Date("2026-01-02")), "2026-01-02")
  expect_identical(.cp_date("2026-01-02"), "2026-01-02")
  expect_identical(.cp_date(as.POSIXct("2026-01-02 10:00:00", tz = "UTC")), "2026-01-02")
  for (bad in list("01/02/2026", 20260101, NA, c("2026-01-01", "2026-01-02"), "2026-02-30")) {
    expect_error(.cp_date(bad, "study_checkpoint(): `occurred_at`"),
                 "`occurred_at` must be one Date")
  }
})

test_that("an unknown trigger stops only the kind that carries it", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, ".checkpoint"))
  yaml::write_yaml(list(list(kind = "manuscript_submitted", trigger = "Manual"),
                        list(kind = "grant_submitted", trigger = c("manual", "auto"))),
                   file.path(root, ".checkpoint", "kinds.yml"))
  kinds <- .cp_kinds(root)
  expect_error(.cp_kind_check(kinds, "manuscript_submitted", "study_checkpoint"),
               "'manuscript_submitted' has trigger \"Manual\"")
  expect_error(.cp_kind_check(kinds, "grant_submitted", "study_checkpoint"),
               "trigger \"manual, auto\"")
  expect_identical(.cp_kind_check(kinds, "abstract_submitted", "study_checkpoint")$kind,
                   "abstract_submitted")
})

test_that("an empty or non-scalar checkpoint remote is a configuration error", {
  expect_null(.cp_check_remote(NULL, "f"))
  expect_identical(.cp_check_remote("git@host:x.git", "f"), "git@host:x.git")
  expect_error(.cp_check_remote("", "f"), "one non-empty URL")
  expect_error(.cp_check_remote(c("a", "b"), "f"), "one non-empty URL")
  expect_error(.cp_check_remote(list(a = 1), "f"), "one non-empty URL")
})

test_that("compare_datasets() never prints or returns level values unless asked", {
  # Synthetic identifier-like levels: a character ID read as a factor.
  old <- data.frame(mrn = factor(c("MRN-000101", "MRN-000102")))
  new <- data.frame(mrn = factor(c("MRN-000101", "MRN-000199")), order = 1:2)
  res <- compare_datasets(old, new)
  out <- capture.output(print(res))
  expect_false(any(grepl("MRN-", out)))
  expect_false(any(grepl("MRN-", unlist(lapply(unclass(res), function(x) unlist(x))))))
  expect_true(any(grepl("mrn: 2 -> 2 levels \\(1 added, 1 removed\\)", out)))
  # An order-only change is reported as such, still without values.
  reordered <- data.frame(mrn = factor(c("MRN-000101", "MRN-000102"), levels = c("MRN-000102", "MRN-000101")))
  out <- capture.output(print(compare_datasets(old, reordered)))
  expect_true(any(grepl("mrn: 2 -> 2 levels \\(order changed\\)", out)))
  expect_false(any(grepl("MRN-", out)))
  # The opt-in shows them, in the object and the print.
  out <- capture.output(print(compare_datasets(old, new, show_levels = TRUE)))
  expect_true(any(grepl("MRN-000199", out)))
  expect_error(compare_datasets(old, new, show_levels = NA), "show_levels")
})

test_that(".cp_date() refuses non-finite dates and date-times", {
  expect_error(.cp_date(structure(Inf, class = "Date")), "must be one")
  expect_error(.cp_date(structure(-Inf, class = "Date")), "must be one")
  expect_error(.cp_date(.POSIXct(Inf, tz = "UTC")), "must be one")
  expect_error(.cp_date(.POSIXct(NaN, tz = "UTC")), "must be one")
  expect_error(.cp_date(as.POSIXlt(.POSIXct(Inf, tz = "UTC"))), "must be one")
})
