test_that("a render commit lands on the render ref and leaves main, tags and the tree alone", {
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
  head_before <- git_out(repo, c("symbolic-ref", "HEAD"))

  sha <- study_render_commit("30_analyses/fit.R", root = root)

  expect_match(sha, "^[0-9a-f]{40}$")
  expect_match(render_ref(root), "^refs/renders/")
  expect_identical(git_out(repo, c("rev-parse", render_ref(root)))[1], sha)
  expect_identical(git_out(repo, c("rev-parse", "main"))[1], cp$commit)
  expect_identical(git_out(repo, c("tag", "-l")), tags_before)
  expect_identical(git_out(repo, c("symbolic-ref", "HEAD")), head_before)
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
  first <- study_render_commit("30_analyses/fit.R", root = root)
  expect_identical(study_render_commit("30_analyses/fit.R", root = root), first)
  expect_length(git_out(.cp_repo_path(root), c("rev-list", render_ref(root))),
                1L)
})

test_that("a changed job adds a commit whose parent is the last render", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  first <- study_render_commit("30_analyses/fit.R", root = root)
  writeLines("fit <- 2", file.path(root, "30_analyses", "fit.R"))
  second <- study_render_commit("30_analyses/fit.R", root = root)
  repo <- .cp_repo_path(root)
  expect_false(identical(second, first))
  expect_identical(git_out(repo, c("rev-parse", paste0(second, "^")))[1], first)
  expect_identical(git_out(repo, c("show", paste0(second, ":30_analyses/fit.R"))),
                   "fit <- 2")
})

test_that("a job the snapshot leaves out stops the commit", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  plant_files(root, "00_datasets/build.R")
  expect_error(study_render_commit("00_datasets/build.R", root = root),
               "not in the study's snapshot")
  expect_error(study_render_commit("30_analyses/none.R", root = root),
               "not in the study's snapshot")
})

test_that("a held checkpoint lock stops the render commit", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  held <- .cp_lock(root, "test")
  on.exit(.cp_unlock(held), add = TRUE)
  expect_error(study_render_commit("30_analyses/fit.R", root = root),
               "checkpoint lock")
})

test_that("a milestone after a render commit is tagged on main (R3)", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  # An unborn main with render commits present.
  sha <- study_render_commit("30_analyses/fit.R", root = root)
  cp <- study_checkpoint("manuscript_submitted", root = root)
  repo <- .cp_repo_path(root)
  expect_identical(git_out(repo, c("rev-parse", "main"))[1], cp$commit)
  expect_identical(git_out(repo, c("rev-parse", paste0(cp$tag, "^{commit}")))[1],
                   cp$commit)
  expect_identical(git_out(repo, c("rev-parse", render_ref(root)))[1], sha)
})

test_that("an interrupted render commit leaves the ref and main usable (R3)", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  first <- study_render_commit("30_analyses/fit.R", root = root)
  writeLines("fit <- 2", file.path(root, "30_analyses", "fit.R"))
  real <- .cp_git_do
  local_mocked_bindings(.cp_git_do = function(repo, args) {
    if (identical(args[1], "update-ref")) stop("interrupted")
    real(repo, args)
  })
  expect_error(study_render_commit("30_analyses/fit.R", root = root),
               "interrupted")
  local_mocked_bindings(.cp_git_do = real)
  repo <- .cp_repo_path(root)
  expect_identical(git_out(repo, c("rev-parse", render_ref(root)))[1], first)
  cp <- study_checkpoint("manuscript_submitted", root = root)
  expect_identical(git_out(repo, c("rev-parse", "main"))[1], cp$commit)
  expect_false(identical(study_render_commit("30_analyses/fit.R", root = root),
                         first))
})

test_that("a checkpoint stops when HEAD is not main (R3)", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  study_checkpoint("manuscript_submitted", root = root)
  repo <- .cp_repo_path(root)
  git_out(repo, c("checkout", "-q", "-b", "elsewhere"))
  expect_error(study_checkpoint("manuscript_submitted", root = root),
               "not on main")
  expect_length(git_out(repo, c("tag", "--points-at", "elsewhere")), 1L)
})

test_that("records accumulate, so a superseded figure still traces (R2)", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  fig <- file.path(root, "30_analyses", "fit.png")
  writeLines("figure one", fig)
  first <- study_render_commit("30_analyses/fit.R", root = root)
  study_render_record("r1", first, "30_analyses/fit.R", fig, root = root)
  copied <- file.path(withr::local_tempdir(), "manuscript-fig1.png")
  file.copy(fig, copied)

  writeLines("fit <- 2", file.path(root, "30_analyses", "fit.R"))
  writeLines("figure two", fig)
  second <- study_render_commit("30_analyses/fit.R", root = root)
  study_render_record("r2", second, "30_analyses/fit.R", fig, root = root)

  repo <- .cp_repo_path(root)
  tip <- render_ref(root)
  records <- git_out(repo, c("ls-tree", "--name-only",
                             paste0(tip, ":.hvti-renders")))
  expect_setequal(records, c("r1.json", "r2.json"))
  shown <- git_out(repo, c("show", paste0(tip, ":.hvti-renders/r1.json")))
  r1 <- jsonlite::fromJSON(paste(shown, collapse = "\n"))
  expect_identical(r1$commit, first)
  expect_identical(r1$outputs$path, "30_analyses/fit.png")
  expect_identical(r1$outputs$sha256,
                   digest::digest(copied, algo = "sha256", file = TRUE))
  # The record commits do not change what the next render commit holds.
  expect_identical(git_out(repo, c("show", paste0(second, ":30_analyses/fit.R"))),
                   "fit <- 2")
})

test_that("a record must name a render commit of this study", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  study_render_commit("30_analyses/fit.R", root = root)
  fig <- file.path(root, "30_analyses", "fit.png")
  writeLines("figure", fig)
  expect_error(study_render_record("r1", strrep("a", 40), "30_analyses/fit.R",
                                   fig, root = root),
               "not a render commit")
  expect_error(study_render_record("r 1", strrep("a", 40), "30_analyses/fit.R",
                                   fig, root = root),
               "render_id")
})
