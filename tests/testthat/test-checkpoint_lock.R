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

test_that("touching the lock refreshes its lease and leaves holder.yml alone", {
  root <- withr::local_tempdir()
  held <- .cp_lock(root, "test")
  lease <- .cp_lock_lease(held$lock, held$token)
  expect_true(file.exists(lease))
  Sys.setFileTime(lease, Sys.time() - 60 * 60)
  holder <- .cp_lock_holder(held$lock)
  expect_true(.cp_lock_touch(held))
  expect_lt(as.numeric(difftime(Sys.time(), file.mtime(lease), units = "mins")), 5)
  expect_equal(.cp_lock_holder(held$lock), holder)
  .cp_unlock(held)
})

test_that("a touch is one call: it fails on a missing lease and does not create it", {
  root <- withr::local_tempdir()
  held <- .cp_lock(root, "test")
  lease <- .cp_lock_lease(held$lock, held$token)
  unlink(lease)
  expect_error(.cp_lock_touch(held), "test\\(\\): the checkpoint lock was taken over",
               class = "hvti_cp_lock_lost")
  expect_false(file.exists(lease))
  .cp_unlock(held)
})

test_that("staleness is judged from the lease, not holder.yml's time", {
  root <- withr::local_tempdir()
  held <- .cp_lock(root, "test")
  Sys.setFileTime(.cp_lock_lease(held$lock, held$token),
                  Sys.time() - (6 * 60 + 1) * 60)
  expect_warning(theirs <- .cp_lock(root, "other"), "stale checkpoint lock")
  expect_error(.cp_lock_touch(held), class = "hvti_cp_lock_lost")
  .cp_unlock(theirs)

  held <- .cp_lock(root, "test")
  h <- .cp_lock_holder(held$lock)
  h$time <- "2020-01-01T00:00:00Z"
  yaml::write_yaml(h, file.path(held$lock, "holder.yml"))
  expect_error(.cp_lock(root, "other"), "another session holds the checkpoint lock")
  .cp_unlock(held)
})

test_that("a legacy lock with no lease file is judged by holder.yml's time", {
  root <- withr::local_tempdir()
  lock <- plant_lock(root, .cp_utc(Sys.time() - 60))
  expect_error(.cp_lock(root, "test"), "other_analyst, pid 4242.*retry")
  unlink(lock, recursive = TRUE)
  lock <- plant_lock(root, .cp_utc(Sys.time() - (6 * 60 + 1) * 60))
  expect_warning(held <- .cp_lock(root, "test"), "stale checkpoint lock")
  expect_equal(.cp_lock_holder(lock)$token, held$token)
  .cp_unlock(held)
})

test_that("a lost lock in a snapshot stops without rolling back the other session's work", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  n <- 0L
  rolled_back <- FALSE
  lost <- structure(class = c("hvti_cp_lock_lost", "error", "condition"),
                    list(message = "lock lost", call = NULL))
  testthat::local_mocked_bindings(
    .cp_lock_touch = function(held) {
      n <<- n + 1L
      if (n == 2L) stop(lost)
    },
    .cp_rollback = function(...) rolled_back <<- TRUE
  )
  expect_error(study_checkpoint("abstract_submitted", root = root), class = "hvti_cp_lock_lost")
  expect_false(rolled_back)
  expect_length(.cp_log_read(root), 0L)
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

# A competing session acts in the gap between this session judging the lock
# stale and taking it over: `compete` runs from the takeover warning.
lock_with_competitor <- function(root, compete) {
  done <- FALSE
  suppressWarnings(withCallingHandlers(
    .cp_lock(root, "test"),
    warning = function(w) {
      if (!done) {
        done <<- TRUE
        compete()
      }
    }
  ))
}

test_that("a second takeover of the same stale lock fails with the retry error", {
  root <- withr::local_tempdir()
  lock <- plant_lock(root, .cp_utc(Sys.time() - (6 * 60 + 1) * 60))
  theirs <- NULL
  expect_error(
    lock_with_competitor(root, function() theirs <<- suppressWarnings(.cp_lock(root, "other"))),
    "took the checkpoint lock first; retry"
  )
  expect_equal(.cp_lock_holder(lock)$token, theirs$token)
  expect_true(.cp_lock_touch(theirs))
  expect_equal(list.files(dirname(lock)), "lock")
  expect_equal(sort(list.files(lock)), sort(c("holder.yml", paste0("lease-", theirs$token))))
  .cp_unlock(theirs)
  expect_false(dir.exists(lock))
})

test_that("a stale lock that vanishes before the takeover fails with the retry error", {
  root <- withr::local_tempdir()
  lock <- plant_lock(root, .cp_utc(Sys.time() - (6 * 60 + 1) * 60))
  expect_error(
    lock_with_competitor(root, function() unlink(lock, recursive = TRUE)),
    "took the checkpoint lock first; retry"
  )
  expect_false(dir.exists(lock))
  expect_equal(list.files(dirname(lock)), character())
})

# Make a held lock look abandoned: its holder time and any lease file are
# set back past the stale age.
age_lock <- function(lock) {
  old <- Sys.time() - (6 * 60 + 1) * 60
  h <- .cp_lock_holder(lock)
  h$time <- .cp_utc(old)
  yaml::write_yaml(h, file.path(lock, "holder.yml"))
  leases <- list.files(lock, pattern = "^lease-", full.names = TRUE)
  if (length(leases)) Sys.setFileTime(leases, old)
}

test_that("a touch after another session took the lock over stops with the lost-lock error", {
  root <- withr::local_tempdir()
  a <- .cp_lock(root, "a")
  age_lock(a$lock)
  b <- suppressWarnings(.cp_lock(root, "b"))
  b_holder <- .cp_lock_holder(b$lock)
  b_files <- sort(list.files(b$lock))
  b_mtimes <- file.mtime(file.path(b$lock, b_files))
  expect_error(.cp_lock_touch(a), "taken over by another session.*retry", class = "hvti_cp_lock_lost")
  expect_equal(.cp_lock_holder(b$lock), b_holder)
  expect_equal(sort(list.files(b$lock)), b_files)
  expect_equal(file.mtime(file.path(b$lock, b_files)), b_mtimes)
  .cp_unlock(a)
  expect_true(dir.exists(b$lock))
  .cp_unlock(b)
})

test_that("a lease refreshed between the staleness check and the takeover puts the lock back", {
  root <- withr::local_tempdir()
  a <- .cp_lock(root, "a")
  age_lock(a$lock)
  a_holder <- .cp_lock_holder(a$lock)
  expect_error(
    lock_with_competitor(root, function() .cp_lock_touch(a)),
    "took the checkpoint lock first; retry"
  )
  expect_equal(.cp_lock_holder(a$lock), a_holder)
  expect_equal(sort(list.files(a$lock)), sort(c("holder.yml", paste0("lease-", a$token))))
  expect_equal(list.files(dirname(a$lock)), "lock")
  expect_true(.cp_lock_touch(a))
  .cp_unlock(a)
  expect_false(dir.exists(a$lock))
})

test_that("a stale takeover leaves only the new lock behind", {
  root <- withr::local_tempdir()
  lock <- plant_lock(root, .cp_utc(Sys.time() - (6 * 60 + 1) * 60))
  held <- suppressWarnings(.cp_lock(root, "test"))
  expect_equal(.cp_lock_holder(lock)$token, held$token)
  expect_equal(list.files(dirname(lock)), "lock")
  expect_equal(sort(list.files(lock)), sort(c("holder.yml", paste0("lease-", held$token))))
  .cp_unlock(held)
})

test_that("a put-back that cannot move the files keeps them and leaves no empty lock", {
  root <- withr::local_tempdir()
  a <- .cp_lock(root, "a")
  live <- sort(list.files(a$lock))
  testthat::local_mocked_bindings(.cp_lock_move = function(from, to) FALSE)
  expect_warning(
    expect_false(.cp_lock_take_stale(a$lock, list(holder = list(), leases = numeric()))),
    "files are kept in"
  )
  aside <- list.files(dirname(a$lock), pattern = "^lock[.]stale-", full.names = TRUE)
  expect_length(aside, 1L)
  expect_equal(sort(list.files(aside)), live)
  expect_false(dir.exists(a$lock))
  # Not refused for six hours: the next session takes the lock, and the
  # session whose lock was moved stops at its next refresh.
  b <- .cp_lock(root, "b")
  expect_error(.cp_lock_touch(a), class = "hvti_cp_lock_lost")
  .cp_unlock(b)
})

test_that("a put-back that moves only some files keeps the rest aside", {
  root <- withr::local_tempdir()
  a <- .cp_lock(root, "a")
  testthat::local_mocked_bindings(.cp_lock_move = function(from, to) {
    if (basename(from) == "holder.yml") file.rename(from, to) else FALSE
  })
  expect_warning(.cp_lock_take_stale(a$lock, list(holder = list(), leases = numeric())),
                 "files are kept in")
  aside <- list.files(dirname(a$lock), pattern = "^lock[.]stale-", full.names = TRUE)
  expect_equal(list.files(aside), paste0("lease-", a$token))
  expect_equal(list.files(a$lock), "holder.yml")
  # The holder stops at its next refresh, and its unlock clears the lock.
  expect_error(.cp_lock_touch(a), class = "hvti_cp_lock_lost")
  .cp_unlock(a)
  expect_false(dir.exists(a$lock))
})

test_that("a failed holder write leaves no lock behind", {
  root <- withr::local_tempdir()
  testthat::local_mocked_bindings(.cp_lock_write_holder = function(lock, h) stop("disk full"))
  expect_error(.cp_lock(root, "a"), "disk full")
  expect_false(dir.exists(file.path(root, ".checkpoint", "lock")))
  testthat::local_mocked_bindings(.cp_lock_write_holder = function(lock, h) {
    yaml::write_yaml(h, file.path(lock, "holder.yml"))
  })
  held <- .cp_lock(root, "a")
  expect_true(dir.exists(held$lock))
  .cp_unlock(held)
})
