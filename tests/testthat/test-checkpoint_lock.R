plant_lock <- function(root, time) {
  lock <- file.path(root, ".checkpoint", "lock")
  dir.create(lock, recursive = TRUE)
  yaml::write_yaml(list(user = "other_analyst", pid = 4242L, time = time,
                        token = "theirs"),
                   file.path(lock, "holder.yml"))
  lock
}

test_that("a fresh lock held by another session is an error that writes nothing", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  study_checkpoint("data_request_submitted", root = root)
  log_before <- .cp_log_read(root)
  tags_before <- git_out(.cp_repo_path(root), c("tag", "-l"))
  lock <- plant_lock(root, .cp_utc(Sys.time()))

  for (f in list(function() study_checkpoint("abstract_submitted", root = root),
                 function() study_checkpoint("data_received", root = root),
                 function() study_checkpoint_push(root = root),
                 function() study_close("abandoned", root = root))) {
    expect_error(f(), "other_analyst, pid 4242.*retry")
  }
  expect_error(study_reopen("new PI", root = root), "other_analyst")
  expect_equal(.cp_log_read(root), log_before)
  expect_equal(git_out(.cp_repo_path(root), c("tag", "-l")), tags_before)
  expect_equal(.cp_lock_holder(lock)$token, "theirs")
})

test_that("a lock under six hours old is not stale", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  lock <- plant_lock(root, .cp_utc(Sys.time() - 5 * 60 * 60))
  expect_error(study_checkpoint("abstract_submitted", root = root),
               "other_analyst, pid 4242.*retry")
  expect_equal(.cp_lock_holder(lock)$token, "theirs")
})

test_that("touching the lock refreshes its time only while the token matches", {
  root <- withr::local_tempdir()
  held <- .cp_lock(root, "test")
  h <- .cp_lock_holder(held$lock)
  h$time <- .cp_utc(Sys.time() - 60 * 60)
  yaml::write_yaml(h, file.path(held$lock, "holder.yml"))
  .cp_lock_touch(held)
  touched <- .cp_lock_holder(held$lock)
  expect_equal(touched$token, held$token)
  age <- difftime(Sys.time(), as.POSIXct(touched$time, format = "%Y-%m-%dT%H:%M:%SZ",
                                         tz = "UTC"), units = "mins")
  expect_lt(as.numeric(age), 5)

  theirs <- list(user = "other_analyst", pid = 4242L, time = "2020-01-01T00:00:00Z",
                 token = "theirs")
  yaml::write_yaml(theirs, file.path(held$lock, "holder.yml"))
  .cp_lock_touch(held)
  expect_equal(.cp_lock_holder(held$lock), theirs)
  .cp_unlock(held)
})

test_that("every entry point refreshes the lock between phases", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  n <- 0L
  testthat::local_mocked_bindings(.cp_lock_touch = function(held) {
    expect_true(dir.exists(held$lock))
    n <<- n + 1L
  })
  count <- function(expr) {
    n <<- 0L
    force(expr)
    n
  }
  # A snapshot: after selection, CHECKPOINT.yml, commit and tag, and before
  # delivery. A reopening only tags, so its tag and delivery share one touch.
  expect_equal(count(study_checkpoint("abstract_submitted", root = root)), 4L)
  expect_equal(count(study_checkpoint("data_received", root = root)), 1L)
  expect_equal(count(study_checkpoint_push(root = root)), 1L)
  expect_equal(count(study_close("abandoned", root = root)), 4L)
  expect_equal(count(suppressMessages(study_reopen("new PI", root = root))), 1L)
})

test_that("a stale lock is taken over with a warning", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  lock <- plant_lock(root, .cp_utc(Sys.time() - (6 * 60 + 1) * 60))
  expect_warning(cp <- study_checkpoint("abstract_submitted", root = root),
                 "stale checkpoint lock \\(other_analyst, pid 4242")
  expect_equal(cp$tag, "abstract_submitted-1")
  expect_false(dir.exists(lock))
})

test_that("the lock is released after success and after an error", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  lock <- file.path(root, ".checkpoint", "lock")
  study_checkpoint("abstract_submitted", root = root)
  expect_false(dir.exists(lock))
  study_checkpoint_push(root = root)
  expect_false(dir.exists(lock))
  expect_error(study_checkpoint("submitted", root = root), "unknown")
  expect_false(dir.exists(lock))
  study_close("abandoned", root = root)
  expect_false(dir.exists(lock))
  expect_error(study_close("abandoned", root = root), "already closed")
  expect_false(dir.exists(lock))
  suppressMessages(study_reopen("new PI", root = root))
  expect_false(dir.exists(lock))
  expect_error(study_reopen("again", root = root), "not closed")
  expect_false(dir.exists(lock))
})

test_that("a failed reopening abandons its entry before the lock is released", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  study_close("abandoned", root = root)
  seen <- NULL
  testthat::local_mocked_bindings(
    .cp_tag_head = function(...) stop("tag failed"),
    .cp_unlock = function(held) {
      seen <<- vapply(.cp_log_read(root), function(e) e$state, character(1))
      unlink(held$lock, recursive = TRUE)
    }
  )
  expect_error(suppressMessages(study_reopen("new PI", root = root)),
               "tag failed")
  expect_equal(seen, c("committed", "abandoned"))
})
