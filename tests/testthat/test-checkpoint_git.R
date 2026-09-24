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
