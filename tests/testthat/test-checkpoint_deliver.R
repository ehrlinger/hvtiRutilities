test_that("a checkpoint is pushed to the remote with its tag", {
  skip_if_no_git()
  local_git_env()
  dir <- withr::local_tempdir()
  root <- make_checkpoint_study(dir)
  bare <- make_bare_remote(dir)
  set_study_keys(root, checkpoint = list(remote = bare))
  cp <- study_checkpoint("abstract_submitted", root = root)
  expect_equal(cp$delivery$git, "delivered")
  expect_equal(git_out(bare, c("tag", "-l")), "abstract_submitted-1")
  expect_true("CHECKPOINT.yml" %in%
                git_out(bare, c("ls-tree", "--name-only", "main")))
})

test_that("an unreachable remote keeps the checkpoint and retries later", {
  skip_if_no_git()
  local_git_env()
  dir <- withr::local_tempdir()
  root <- make_checkpoint_study(dir)
  missing <- file.path(dir, "later.git")
  set_study_keys(root, checkpoint = list(remote = missing))
  expect_warning(cp <- study_checkpoint("abstract_submitted", root = root),
                 "not pushed")
  expect_equal(.cp_log_read(root)[[1]]$delivery$git, "pending")
  make_bare_remote(dir, "later.git")
  res <- study_checkpoint_push(root)
  expect_equal(res$git, "delivered")
  expect_equal(git_out(missing, c("tag", "-l")), "abstract_submitted-1")
  expect_silent(study_checkpoint_push(root))
})

test_that("no remote leaves delivery pending without a warning", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  expect_silent(study_checkpoint("abstract_submitted", root = root))
  e <- .cp_log_read(root)[[1]]
  expect_equal(e$delivery$git, "pending")
  expect_equal(e$delivery$reason, "no remote configured")
})

test_that("an unverified identity is committed but never pushed", {
  skip_if_no_git()
  local_git_env()
  dir <- withr::local_tempdir()
  root <- make_checkpoint_study(dir)
  bare <- make_bare_remote(dir)
  set_study_keys(root, identity_verified = FALSE,
                 checkpoint = list(remote = bare))
  expect_message(study_checkpoint("abstract_submitted", root = root),
                 "identity unverified")
  expect_length(git_out(bare, c("tag", "-l")), 0L)
  expect_equal(.cp_log_read(root)[[1]]$delivery$reason, "identity unverified")
  set_study_keys(root, identity_verified = TRUE)
  study_checkpoint_push(root)
  expect_equal(git_out(bare, c("tag", "-l")), "abstract_submitted-1")
})

test_that("push reconciles first and never delivers an abandoned entry", {
  skip_if_no_git()
  local_git_env()
  dir <- withr::local_tempdir()
  root <- make_checkpoint_study(dir)
  bare <- make_bare_remote(dir)
  set_study_keys(root, checkpoint = list(remote = bare))
  .cp_log_append(root, list(
    type = "checkpoint", checkpoint_id = "lost-1", st_id = 1267L,
    kind = "abstract_submitted", git_commit = NULL,
    tag = "abstract_submitted-1", state = "committing",
    delivery = list(git = "pending", st = "pending")
  ))
  res <- study_checkpoint_push(root)
  expect_equal(res$state, "abandoned")
  expect_equal(res$git, "pending")
  expect_length(git_out(bare, c("tag", "-l")), 0L)
})

test_that("divergence replays, renumbers and never force-pushes", {
  skip_if_no_git()
  local_git_env()
  dir <- withr::local_tempdir()
  root <- make_checkpoint_study(dir)
  bare <- make_bare_remote(dir)
  local_cp <- study_checkpoint("data_request_submitted", root = root)  # local only
  other <- file.path(dir, "other")
  git_out(dir, c("clone", "-q", bare, other))
  git_out(other, c("checkout", "-q", "-b", "main"))
  plant_files(other, "other.R")
  git_out(other, c("add", "-A"))
  git_out(other, c("commit", "-q", "-m", "other copy"))
  git_out(other, c("tag", "-a", "data_request_submitted-1", "-m", "other"))
  git_out(other, c("push", "-q", "origin", "main",
                   "refs/tags/data_request_submitted-1"))
  remote_head <- git_out(bare, c("rev-parse", "main"))
  set_study_keys(root, checkpoint = list(remote = bare))
  study_checkpoint_push(root)
  e <- .cp_log_read(root)[[1]]
  expect_equal(e$delivery$git, "delivered")
  expect_equal(e$tag, "data_request_submitted-2")
  expect_equal(e$renumbered_from, "data_request_submitted-1")
  expect_false(is.null(e$replayed_from))
  expect_equal(e$replayed_from, local_cp$commit)
  expect_false(identical(e$git_commit, local_cp$commit))
  expect_setequal(git_out(bare, c("tag", "-l")),
                  c("data_request_submitted-1", "data_request_submitted-2"))
  expect_length(git_out(bare, c("rev-list", "main")), 2L)
  expect_equal(git_out(bare, c("rev-parse", "main~1")), remote_head)
  expect_equal(git_out(bare, c("rev-parse", "data_request_submitted-2^{commit}")),
               e$git_commit)
  expect_true("30_analyses/fit.R" %in%
                git_out(bare, c("ls-tree", "-r", "--name-only",
                                "data_request_submitted-2")))
})

test_that("a re-cloned .checkpoint continues the sequence", {
  skip_if_no_git()
  local_git_env()
  dir <- withr::local_tempdir()
  root <- make_checkpoint_study(dir)
  bare <- make_bare_remote(dir)
  set_study_keys(root, checkpoint = list(remote = bare))
  study_checkpoint("abstract_submitted", root = root)
  study_checkpoint("abstract_submitted", root = root)
  unlink(file.path(root, ".checkpoint"), recursive = TRUE)
  expect_equal(study_checkpoint("abstract_submitted", root = root)$tag,
               "abstract_submitted-3")
})
