test_that("a render commit lands on renders and leaves main, tags and the tree alone", {
  skip_if_no_git()
  local_git_env()
  dir <- withr::local_tempdir()
  root <- make_checkpoint_study(dir)
  plant_files(root, c("00_datasets/built.sas7bdat", "30_analyses/fig.pdf"))
  cp <- study_checkpoint("manuscript_submitted", root = root)
  repo <- .cp_repo_path(root)
  work_tree <- function() {
    files <- list.files(repo, recursive = TRUE, all.files = TRUE)
    sort(files[!startsWith(files, ".git/")])
  }
  tree_before <- work_tree()
  tags_before <- git_out(repo, c("tag", "-l"))

  sha <- study_render_commit("30_analyses/fit.R", root = root)

  expect_match(sha, "^[0-9a-f]{40}$")
  expect_identical(git_out(repo, c("rev-parse", "renders"))[1], sha)
  expect_identical(git_out(repo, c("rev-parse", "main"))[1], cp$commit)
  expect_identical(git_out(repo, c("tag", "-l")), tags_before)
  expect_identical(work_tree(), tree_before)
  files <- git_out(repo, c("ls-tree", "-r", "--name-only", sha))
  expect_true(all(c("_study.yml", "30_analyses/fit.R") %in% files))
  expect_false(any(grepl("datasets|\\.pdf$", files)))
  expect_match(git_out(repo, c("log", "-1", "--format=%s", sha)),
               "30_analyses/fit.R", fixed = TRUE, all = FALSE)
})

test_that("an unchanged study reuses the last render commit", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  first <- study_render_commit(root = root)
  expect_identical(study_render_commit(root = root), first)
  expect_length(git_out(.cp_repo_path(root), c("rev-list", "renders")), 1L)
})

test_that("a changed job adds a commit whose parent is the last render", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  first <- study_render_commit(root = root)
  writeLines("fit <- 2", file.path(root, "30_analyses", "fit.R"))
  second <- study_render_commit(root = root)
  repo <- .cp_repo_path(root)
  expect_false(identical(second, first))
  expect_identical(git_out(repo, c("rev-parse", paste0(second, "^")))[1], first)
  expect_identical(git_out(repo, c("show", paste0(second, ":30_analyses/fit.R"))),
                   "fit <- 2")
})

test_that("a render commit works before any checkpoint and creates no main", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  study_render_commit(root = root)
  repo <- .cp_repo_path(root)
  main <- suppressWarnings(git_out(repo, c("rev-parse", "-q", "--verify", "main")))
  expect_length(main, 0L)
})

test_that("a held checkpoint lock stops the render commit", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  held <- .cp_lock(root, "test")
  on.exit(.cp_unlock(held), add = TRUE)
  expect_error(study_render_commit(root = root), "checkpoint lock")
})
