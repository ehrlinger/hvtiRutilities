# study_verify() and study_recover() hand their work to the qhsprograms
# study-setup command. Every test replaces the process seam, so none starts
# a process or reads Study Tracker.

local_qhs <- function(status = 0L, tracker = TRUE, env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  paths <- list(python = file.path(dir, "python"),
                command = file.path(dir, "study-setup"),
                tracker_env = file.path(dir, "tracker.env"))
  file.create(c(paths$python, paths$command,
                if (tracker) paths$tracker_env))
  calls <- list()
  testthat::local_mocked_bindings(
    .qhs_paths = function() paths,
    .qhs_exec = function(command, args) {
      calls[[length(calls) + 1L]] <<- list(command = command, args = args)
      status
    },
    .env = env
  )
  list(paths = paths, calls = function() calls)
}

test_that("study_verify runs study-setup --verify with the credentials loaded", {
  qhs <- local_qhs()
  root <- withr::local_tempdir()

  expect_true(study_verify(root))

  calls <- qhs$calls()
  expect_length(calls, 1L)
  expect_equal(calls[[1]]$command, "/bin/sh")
  args <- calls[[1]]$args
  expect_true(shQuote(qhs$paths$tracker_env) %in% args)
  expect_true(shQuote(qhs$paths$command) %in% args)
  expect_true(shQuote("--verify") %in% args)
  expect_true(shQuote(normalizePath(root)) %in% args)
})

test_that("study_verify never passes --yes, which would refuse a mismatch", {
  qhs <- local_qhs()
  study_verify(withr::local_tempdir())
  expect_false(shQuote("--yes") %in% qhs$calls()[[1]]$args)
})

test_that("study_verify stops before running without a credentials file", {
  qhs <- local_qhs(tracker = FALSE)
  expect_error(study_verify(withr::local_tempdir()), "not available yet")
  expect_length(qhs$calls(), 0L)
})

test_that("study_verify stops off the LRI servers without running", {
  qhs <- local_qhs()
  unlink(qhs$paths$command)
  expect_error(study_verify(withr::local_tempdir()), "only on the LRI servers")
  expect_length(qhs$calls(), 0L)
})

test_that("a failed command is an error naming its exit status", {
  local_qhs(status = 1L)
  expect_error(study_verify(withr::local_tempdir()), "exit status 1")
})

test_that("study_recover dry-runs, then restores without the credentials", {
  qhs <- local_qhs()
  root <- withr::local_tempdir()

  expect_true(study_recover(42, root, yes = TRUE))

  calls <- qhs$calls()
  expect_length(calls, 2L)
  expect_equal(calls[[1]]$command, qhs$paths$python)
  expect_false(shQuote(qhs$paths$tracker_env) %in% calls[[1]]$args)
  expect_true(all(shQuote(c("--recover", "42", "--dry-run")) %in%
                    calls[[1]]$args))
  expect_true(all(shQuote(c("--recover", "42", "--yes")) %in%
                    calls[[2]]$args))
  expect_false(shQuote("--dry-run") %in% calls[[2]]$args)
})

test_that("study_recover writes nothing when the dry run fails", {
  qhs <- local_qhs(status = 1L)
  expect_error(study_recover(root = withr::local_tempdir()), "exit status 1")
  expect_length(qhs$calls(), 1L)
})

test_that("study_recover rejects a Study Tracker ID that is not whole", {
  qhs <- local_qhs()
  expect_error(study_recover(42.5, withr::local_tempdir()), "whole number")
  expect_length(qhs$calls(), 0L)
})

test_that("study_recover writes nothing without consent when not interactive", {
  qhs <- local_qhs()
  expect_error(study_recover(42, withr::local_tempdir()), "yes = TRUE")
  calls <- qhs$calls()
  expect_length(calls, 1L)
  expect_true(shQuote("--dry-run") %in% calls[[1]]$args)
})
