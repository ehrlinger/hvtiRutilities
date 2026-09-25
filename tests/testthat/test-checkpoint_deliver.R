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

test_that("a rejected tag push after a replay keeps the log in step", {
  skip_if_no_git()
  # The hook is a shell script; the delivery logic under test is platform-independent.
  skip_on_os("windows")
  local_git_env()
  dir <- withr::local_tempdir()
  fx <- diverge_study(dir)
  reject_tag_push_once(fx$bare, file.path(dir, "rejected-once"))
  set_study_keys(fx$root, checkpoint = list(remote = fx$bare))
  repo <- .cp_repo_path(fx$root)

  expect_warning(study_checkpoint_push(fx$root),
                 "data_request_submitted-2.*tag push rejected")
  e <- .cp_log_read(fx$root)[[1]]
  expect_equal(e$delivery$git, "pending")
  expect_equal(e$tag, "data_request_submitted-2")
  expect_equal(e$replayed_from, fx$local_cp$commit)
  expect_equal(e$git_commit, git_out(repo, c("rev-parse", "main")))
  expect_equal(git_out(repo, c("rev-parse", paste0(e$tag, "^{commit}"))),
               e$git_commit)

  study_checkpoint_push(fx$root)
  e <- .cp_log_read(fx$root)[[1]]
  expect_equal(e$delivery$git, "delivered")
  expect_equal(e$tag, "data_request_submitted-2")
  tags <- git_out(fx$bare, c("tag", "-l"))
  expect_setequal(tags, c("data_request_submitted-1", "data_request_submitted-2"))
  for (t in tags) {
    commit <- git_out(fx$bare, c("rev-parse", paste0(t, "^{commit}")))
    expect_false(identical(commit, fx$local_cp$commit))
    res <- system2("git", shQuote(c("-C", fx$bare, "merge-base",
                                    "--is-ancestor", commit, "main")))
    expect_equal(res, 0L, info = t)
  }
  expect_equal(git_out(fx$bare, c("rev-parse", paste0(e$tag, "^{commit}"))),
               e$git_commit)
})

test_that("a renumbered tag carries a message with its new name", {
  skip_if_no_git()
  local_git_env()
  dir <- withr::local_tempdir()
  fx <- diverge_study(dir)
  set_study_keys(fx$root, checkpoint = list(remote = fx$bare))
  study_checkpoint_push(fx$root)
  msg <- git_out(fx$bare, c("tag", "-l", "--format=%(contents:subject)",
                            "data_request_submitted-2"))
  expect_match(msg, "data_request_submitted-2", fixed = TRUE)
})

test_that("a failed fetch after the probe leaves the entry pending", {
  skip_if_no_git()
  local_git_env()
  dir <- withr::local_tempdir()
  fx <- diverge_study(dir)
  set_study_keys(fx$root, checkpoint = list(remote = fx$bare))
  testthat::local_mocked_bindings(.cp_git_do = function(repo, args) {
    if (identical(args[1], "fetch")) stop("git fetch failed: simulated")
    res <- .cp_git(repo, args)
    if (!res$ok) stop("git failed")
    res$out
  })
  expect_warning(study_checkpoint_push(fx$root),
                 "data_request_submitted-1.*git fetch failed")
  e <- .cp_log_read(fx$root)[[1]]
  expect_equal(e$delivery$git, "pending")
  expect_match(e$delivery$reason, "git fetch failed")
})

test_that("a log lost before its write never lets a retry push an orphan", {
  skip_if_no_git()
  # The hook is a shell script; the delivery logic under test is platform-independent.
  skip_on_os("windows")
  local_git_env()
  dir <- withr::local_tempdir()
  fx <- diverge_study(dir)
  reject_tag_push_once(fx$bare, file.path(dir, "rejected-once"))
  set_study_keys(fx$root, checkpoint = list(remote = fx$bare))
  log_path <- .cp_log_path(fx$root)
  before <- readLines(log_path)
  expect_warning(study_checkpoint_push(fx$root), "tag push rejected")
  writeLines(before, log_path)  # an interrupt before any log write

  w <- expect_warning(study_checkpoint_push(fx$root), "not on main")
  expect_match(conditionMessage(w), paste0(
    "data_request_submitted-[0-9]+ needs manual repair of ",
    "[.]checkpoint/log[.]yml"
  ))
  expect_no_match(conditionMessage(w), "retry")
  e <- .cp_log_read(fx$root)[[1]]
  expect_equal(e$delivery$git, "pending")
  expect_equal(e$git_commit, fx$local_cp$commit)
  for (t in git_out(fx$bare, c("tag", "-l"))) {
    commit <- git_out(fx$bare, c("rev-parse", paste0(t, "^{commit}")))
    expect_false(identical(commit, fx$local_cp$commit), info = t)
    res <- system2("git", shQuote(c("-C", fx$bare, "merge-base",
                                    "--is-ancestor", commit, "main")))
    expect_equal(res, 0L, info = t)
  }
})

test_that("retargeted entries reach the log before the network push", {
  skip_if_no_git()
  local_git_env()
  dir <- withr::local_tempdir()
  fx <- diverge_study(dir)
  set_study_keys(fx$root, checkpoint = list(remote = fx$bare))
  seen <- new.env()
  testthat::local_mocked_bindings(.cp_push_refs = function(repo, entries) {
    seen$entry <- .cp_log_read(fx$root)[[1]]
    "simulated interrupt"
  })
  expect_warning(study_checkpoint_push(fx$root), "simulated interrupt")
  expect_equal(seen$entry$tag, "data_request_submitted-2")
  expect_equal(seen$entry$replayed_from, fx$local_cp$commit)
  expect_equal(seen$entry$git_commit,
               git_out(.cp_repo_path(fx$root), c("rev-parse", "main")))
})

test_that("a replayed closure and its reopening move together to the remote", {
  skip_if_no_git()
  local_git_env()
  dir <- withr::local_tempdir()
  fx <- diverge_study(dir)
  cl <- study_close("abandoned", root = fx$root)
  ro <- suppressMessages(study_reopen("new PI", root = fx$root))
  expect_equal(ro$commit, cl$commit)
  set_study_keys(fx$root, checkpoint = list(remote = fx$bare))
  study_checkpoint_push(fx$root)

  log <- .cp_log_read(fx$root)
  expect_equal(vapply(log, function(e) e$delivery$git, character(1)),
               rep("delivered", 3L))
  closure <- log[[2]]
  reopening <- log[[3]]
  expect_equal(closure$replayed_from, cl$commit)
  expect_equal(reopening$replayed_from, cl$commit)
  expect_equal(reopening$git_commit, closure$git_commit)
  expect_false(identical(closure$git_commit, cl$commit))
  for (t in c("closed-abandoned-1", "reopened-1")) {
    expect_equal(git_out(fx$bare, c("rev-parse", paste0(t, "^{commit}"))),
                 closure$git_commit, info = t)
  }
  expect_equal(git_out(fx$bare, c("rev-parse", "main")), closure$git_commit)
})
