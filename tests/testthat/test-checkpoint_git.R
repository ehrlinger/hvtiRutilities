test_that(".cp_git reports success without raising", {
  skip_if_no_git()
  local_git_env()
  repo <- withr::local_tempdir()
  res <- .cp_git(repo, c("init", "-q"))
  expect_true(res$ok)
  expect_true(dir.exists(file.path(repo, ".git")))
})

test_that(".cp_git reports failure without raising", {
  skip_if_no_git()
  local_git_env()
  repo <- withr::local_tempdir()
  .cp_git(repo, c("init", "-q"))
  res <- .cp_git(repo, c("rev-parse", "--verify", "HEAD"))
  expect_false(res$ok)
})

test_that(".cp_git_do raises with the command and git's output", {
  skip_if_no_git()
  local_git_env()
  repo <- withr::local_tempdir()
  .cp_git(repo, c("init", "-q"))
  expect_error(.cp_git_do(repo, c("rev-parse", "--verify", "HEAD")),
               "git rev-parse --verify HEAD failed")
})

test_that(".cp_or returns the fallback only for NULL", {
  expect_equal(.cp_or(NULL, 2), 2)
  expect_equal(.cp_or(1, 2), 1)
  expect_false(.cp_or(FALSE, TRUE))
})

test_that("the repo initialises on main under .checkpoint/repo", {
  skip_if_no_git()
  local_git_env()
  root <- withr::local_tempdir()
  repo <- .cp_repo_init(root)
  expect_equal(repo, file.path(root, ".checkpoint", "repo"))
  expect_equal(git_out(repo, c("symbolic-ref", "HEAD")), "refs/heads/main")
  expect_true(is.na(.cp_head(repo)))
})

test_that("commit, tag and sequencing work and stale files are removed", {
  skip_if_no_git()
  local_git_env()
  root <- withr::local_tempdir()
  plant_files(root, c("a.R", "b.R"))
  repo <- .cp_repo_init(root)
  expect_equal(.cp_next_tag(repo, "manuscript_submitted"),
               "manuscript_submitted-1")
  .cp_sync_tree(repo, root, c("a.R", "b.R"))
  sha <- .cp_commit_tag(repo, "manuscript_submitted-1", c("subject", "", "body"))
  expect_equal(sha, .cp_head(repo))
  expect_equal(.cp_next_tag(repo, "manuscript_submitted"),
               "manuscript_submitted-2")
  .cp_sync_tree(repo, root, "a.R")
  .cp_commit_tag(repo, "manuscript_submitted-2", "second")
  expect_equal(git_out(repo, c("ls-tree", "-r", "--name-only",
                               "manuscript_submitted-2")), "a.R")
})

test_that("rollback removes the tag and restores the previous head", {
  skip_if_no_git()
  local_git_env()
  root <- withr::local_tempdir()
  plant_files(root, "a.R")
  repo <- .cp_repo_init(root)
  .cp_sync_tree(repo, root, "a.R")
  first <- .cp_commit_tag(repo, "x-1", "first")
  .cp_commit_tag(repo, "x-2", "second")
  .cp_rollback(repo, first, "x-2")
  expect_equal(.cp_head(repo), first)
  expect_equal(git_out(repo, c("tag", "-l")), "x-1")
  .cp_rollback(repo, NA_character_, "x-1")
  expect_true(is.na(.cp_head(repo)))
})

test_that("init continues from an existing remote's history and tags", {
  skip_if_no_git()
  local_git_env()
  dir <- withr::local_tempdir()
  bare <- make_bare_remote(dir)
  src <- file.path(dir, "src")
  plant_files(src, "a.R")
  repo1 <- .cp_repo_init(src, bare)
  .cp_sync_tree(repo1, src, "a.R")
  .cp_commit_tag(repo1, "k-1", "one")
  git_out(repo1, c("push", "-q", "origin", "main", "refs/tags/k-1"))
  other <- file.path(dir, "other")
  dir.create(other)
  repo2 <- .cp_repo_init(other, bare)
  expect_equal(.cp_next_tag(repo2, "k"), "k-2")
  expect_true(file.exists(file.path(repo2, "a.R")))
})

test_that("a failed reset warns and suggests .git/index.lock", {
  skip_if_no_git()
  local_git_env()
  root <- withr::local_tempdir()
  plant_files(root, "a.R")
  repo <- .cp_repo_init(root)
  .cp_sync_tree(repo, root, "a.R")
  first <- .cp_commit_tag(repo, "x-1", "first")
  .cp_commit_tag(repo, "x-2", "second")
  # Lock the index to force reset to fail
  lock_file <- file.path(repo, ".git", "index.lock")
  writeLines("", lock_file)
  expect_warning(.cp_rollback(repo, first, "x-2"),
                 "rollback did not complete")
  # Clean up the lock file
  unlink(lock_file)
})

test_that("rolling back a tag that was never created does not warn", {
  skip_if_no_git()
  local_git_env()
  root <- withr::local_tempdir()
  plant_files(root, "a.R")
  repo <- .cp_repo_init(root)
  .cp_sync_tree(repo, root, "a.R")
  head_before <- .cp_head(repo)
  expect_no_warning(.cp_rollback(repo, head_before, "never-made"))
})
