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
  expect_null(entry$delivery$reason)

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
