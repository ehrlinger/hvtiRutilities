test_that("study_promote makes a provisional study promoted", {
  root <- file.path(withr::local_tempdir(), "explore")
  study_setup(root, "S", derived_from = 12L, renv = FALSE)
  ws <- yaml::read_yaml(file.path(root, "_study.yml"))$workspace_id
  expect_identical(study_promote(345L, start = root), 0L)
  raw <- yaml::read_yaml(file.path(root, "_study.yml"))
  expect_identical(raw$study_tracker_id, 345L)
  expect_identical(raw$derived_from, 12L)
  expect_identical(raw$workspace_id, ws)
  expect_null(raw$provisional_id)
  expect_identical(.study_identity_state(raw), "promoted")
})

test_that("study_promote refuses a study that is not provisional", {
  root <- file.path(withr::local_tempdir(), "s")
  study_setup(root, "S", 7L, renv = FALSE)
  expect_error(study_promote(9L, start = root),
               "already has Study Tracker ID 7")
})

test_that("study_promote refuses a file that is not a provisional exploration", {
  root <- file.path(withr::local_tempdir(), "legacy")
  dir.create(root)
  yaml::write_yaml(list(study = "Old"), file.path(root, "_study.yml"))
  expect_error(study_promote(9L, start = root),
               "is not a provisional exploration")
})

test_that("study_promote keeps provisional_id when rerun after an interruption", {
  skip_if_no_git()
  local_git_env()
  root <- file.path(withr::local_tempdir(), "explore")
  study_setup(root, "S", derived_from = 12L, renv = FALSE)
  study_checkpoint("manuscript_submitted", root = root)
  log_path <- file.path(root, ".checkpoint", "log.yml")
  prov <- yaml::read_yaml(log_path)[[1]]$st_id
  expect_match(prov, "^x12-")

  # Interrupted after the log is rewritten, before _study.yml is written.
  local({
    testthat::local_mocked_bindings(
      .study_write_atomic = function(...) stop("interrupted")
    )
    expect_error(study_promote(345L, start = root), "interrupted")
  })
  expect_identical(yaml::read_yaml(log_path)[[1]]$st_id, 345L)

  # The study still reads as provisional, so the next checkpoint re-holds
  # every pending entry, the rewritten one included.
  study_checkpoint("manuscript_submitted", root = root)
  held <- yaml::read_yaml(log_path)
  expect_identical(held[[1]]$delivery$reason, "provisional")

  study_promote(345L, start = root)
  final <- yaml::read_yaml(log_path)
  for (e in final) expect_identical(e$st_id, 345L)
  expect_identical(final[[1]]$provisional_id, prov)
  expect_match(final[[2]]$provisional_id, "^x12-")
})

test_that("study_promote refuses a bad ID", {
  root <- file.path(withr::local_tempdir(), "explore")
  study_setup(root, "S", derived_from = 12L, renv = FALSE)
  # A canonical integer string is accepted by .study_check_id() (Task A1),
  # so the refusals are tried with values it rejects.
  for (bad in list("abc", 3.5, 0L, c(1L, 2L))) {
    expect_error(study_promote(bad, start = root),
                 "study_tracker_id must be one positive integer")
  }
})

test_that("promotion rewrites held entries so they deliver the issued ID", {
  skip_if_no_git()
  local_git_env()
  root <- file.path(withr::local_tempdir(), "explore")
  study_setup(root, "S", derived_from = 12L, renv = FALSE)
  study_checkpoint("manuscript_submitted", root = root)
  log_path <- file.path(root, ".checkpoint", "log.yml")
  old <- yaml::read_yaml(log_path)
  prov <- old[[length(old)]]$st_id
  expect_match(prov, "^x12-")

  expect_identical(study_promote(345L, start = root), 1L)
  entry <- yaml::read_yaml(log_path)[[length(old)]]
  expect_identical(entry$st_id, 345L)
  expect_identical(entry$provisional_id, prov)
  # No longer held as provisional: the study_promoted checkpoint's delivery
  # tried it and found no remote yet.
  expect_identical(entry$delivery$reason, "no remote configured")

  bare <- withr::local_tempdir()
  system2("git", c("init", "--bare", "-q", bare))
  set_study_keys(root, checkpoint = list(remote = bare))
  study_checkpoint_push(root)
  delivered <- yaml::read_yaml(log_path)[[length(old)]]
  expect_identical(delivered$delivery$git, "delivered")
  expect_identical(delivered$st_id, 345L)
})

test_that("promoting to the parent's own ID warns", {
  root <- file.path(withr::local_tempdir(), "explore")
  study_setup(root, "S", derived_from = 12L, renv = FALSE)
  expect_warning(study_promote(12L, start = root), "the parent's own ID")
})

test_that("study_promote rewrites automatic-kind entries that are not held", {
  skip_if_no_git()
  local_git_env()
  root <- file.path(withr::local_tempdir(), "explore")
  study_setup(root, "S", derived_from = 7L, renv = FALSE)
  suppressMessages(study_checkpoint("analysis_started", root = root))
  suppressMessages(study_checkpoint("data_received", root = root))
  log_path <- file.path(root, ".checkpoint", "log.yml")
  for (e in yaml::read_yaml(log_path)) expect_match(e$st_id, "^x7-")

  expect_identical(study_promote(9L, start = root), 2L)
  final <- yaml::read_yaml(log_path)
  expect_length(final, 2L)
  for (e in final) {
    expect_identical(e$st_id, 9L)
    expect_match(e$provisional_id, "^x7-")
  }
})

test_that("study_promote refuses when the checkpoint repo is not on main", {
  skip_if_no_git()
  local_git_env()
  root <- file.path(withr::local_tempdir(), "explore")
  study_setup(root, "S", derived_from = 12L, renv = FALSE)
  study_checkpoint("manuscript_submitted", root = root)
  repo <- file.path(root, ".checkpoint", "repo")
  git_out(repo, c("checkout", "-q", "-b", "side"))
  before <- yaml::read_yaml(file.path(root, ".checkpoint", "log.yml"))
  expect_error(study_promote(345L, start = root), "not on main")
  expect_identical(yaml::read_yaml(file.path(root, ".checkpoint", "log.yml")),
                   before)
  expect_null(yaml::read_yaml(file.path(root, "_study.yml"))$study_tracker_id)
})

test_that("a retry with a different ID rewrites every entry to it", {
  skip_if_no_git()
  local_git_env()
  root <- file.path(withr::local_tempdir(), "explore")
  study_setup(root, "S", derived_from = 12L, renv = FALSE)
  study_checkpoint("manuscript_submitted", root = root)
  suppressMessages(study_checkpoint("analysis_started", root = root))
  log_path <- file.path(root, ".checkpoint", "log.yml")
  prov <- vapply(yaml::read_yaml(log_path), function(e) e$st_id, "")
  local({
    testthat::local_mocked_bindings(
      .study_write_atomic = function(...) stop("interrupted")
    )
    expect_error(study_promote(345L, start = root), "interrupted")
  })
  study_promote(400L, start = root)
  final <- yaml::read_yaml(log_path)
  # The rewritten entries, then the study_promoted checkpoint.
  expect_length(final, 3L)
  expect_identical(final[[3]]$kind, "study_promoted")
  expect_identical(final[[3]]$st_id, 400L)
  final <- final[1:2]
  for (i in seq_along(final)) {
    expect_identical(final[[i]]$st_id, 400L)
    expect_identical(final[[i]]$provisional_id, prov[[i]])
  }
})

test_that("study_promote refuses a manifest with a legacy st_id key", {
  skip_if_no_git()
  local_git_env()
  root <- file.path(withr::local_tempdir(), "explore")
  study_setup(root, "S", derived_from = 12L, renv = FALSE)
  suppressMessages(study_checkpoint("analysis_started", root = root))
  set_study_keys(root, st_id = 5L)
  log_path <- file.path(root, ".checkpoint", "log.yml")
  log_before <- yaml::read_yaml(log_path)
  yml_before <- readLines(file.path(root, "_study.yml"))
  expect_error(study_promote(345L, start = root), "legacy st_id key")
  expect_identical(yaml::read_yaml(log_path), log_before)
  expect_identical(readLines(file.path(root, "_study.yml")), yml_before)
})

test_that("promote then push publishes the promoted _study.yml", {
  skip_if_no_git()
  local_git_env()
  dir <- withr::local_tempdir()
  root <- file.path(dir, "explore")
  study_setup(root, "S", derived_from = 12L, renv = FALSE)
  bare <- make_bare_remote(dir)
  set_study_keys(root, checkpoint = list(remote = bare))
  held <- study_checkpoint("manuscript_submitted", root = root)
  expect_identical(held$delivery$reason, "provisional")

  suppressMessages(study_promote(345L, start = root))
  suppressMessages(study_checkpoint_push(root))

  shown <- git_out(bare, c("show", "main:_study.yml"))
  remote_yml <- yaml::yaml.load(paste(shown, collapse = "\n"))
  expect_identical(remote_yml$study_tracker_id, 345L)
  expect_null(remote_yml$provisional_id)
  expect_identical(remote_yml$derived_from, 12L)

  log <- yaml::read_yaml(file.path(root, ".checkpoint", "log.yml"))
  promoted <- Filter(function(e) identical(e$kind, "study_promoted"), log)
  expect_length(promoted, 1L)
  expect_identical(promoted[[1]]$st_id, 345L)
  expect_identical(promoted[[1]]$tag, "study_promoted")
  expect_identical(promoted[[1]]$delivery$git, "delivered")

  tags <- git_out(bare, c("tag", "-l"))
  expect_true(all(c(held$tag, "study_promoted") %in% tags))

  clone <- file.path(dir, "second")
  system2("git", shQuote(c("clone", "-q", "-b", "main", bare, clone)))
  cloned <- yaml::read_yaml(file.path(clone, "_study.yml"))
  expect_identical(.study_identity_state(cloned), "promoted")
  expect_identical(cloned$study_tracker_id, 345L)
})

test_that("a retired study_promoted kind stops promotion before any write", {
  skip_if_no_git()
  local_git_env()
  root <- file.path(withr::local_tempdir(), "explore")
  study_setup(root, "S", derived_from = 12L, renv = FALSE)
  study_checkpoint("manuscript_submitted", root = root)
  yaml::write_yaml(list(list(kind = "study_promoted", retired = TRUE)),
                   file.path(root, ".checkpoint", "kinds.yml"))
  log_path <- file.path(root, ".checkpoint", "log.yml")
  log_before <- yaml::read_yaml(log_path)
  yml_before <- readLines(file.path(root, "_study.yml"))
  expect_error(study_promote(345L, start = root), "is retired")
  expect_identical(yaml::read_yaml(log_path), log_before)
  expect_identical(readLines(file.path(root, "_study.yml")), yml_before)
})
