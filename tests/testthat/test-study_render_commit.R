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
  tip <- render_ref(root, "records")
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

test_that("a record needs a source commit that holds its job (review 1)", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  fig <- file.path(root, "30_analyses", "fit.png")
  writeLines("figure", fig)
  first <- study_render_commit("30_analyses/fit.R", root = root)
  writeLines("other <- 1", file.path(root, "30_analyses", "other.R"))
  second <- study_render_commit("30_analyses/other.R", root = root)

  expect_error(study_render_record("r1", first, "30_analyses/other.R", fig,
                                   root = root),
               "not a render job")
  expect_error(study_render_record("r1", second, "30_analyses/none.R", fig,
                                   root = root),
               "not a render job")
  study_render_record("r1", second, "30_analyses/other.R", fig, root = root)
  study_render_record("r2", first, "30_analyses/fit.R", fig, root = root)
  forged <- git_out(.cp_repo_path(root),
                    c("rev-parse", render_ref(root, "records")))[1]
  expect_error(study_render_record("r3", forged, "30_analyses/fit.R", fig,
                                   root = root),
               "not a render commit")
  expect_error(study_render_record("r3", substr(second, 1, 7),
                                   "30_analyses/fit.R", fig, root = root),
               "40-character")
})

test_that("recorded renders of unchanged code print one commit (review 2)", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  fig <- file.path(root, "30_analyses", "fit.png")
  writeLines("figure", fig)
  shas <- vapply(1:3, function(i) {
    sha <- study_render_commit("30_analyses/fit.R", root = root)
    if (i < 3) {
      study_render_record(paste0("r", i), sha, "30_analyses/fit.R", fig,
                          root = root)
    }
    sha
  }, character(1))
  expect_length(unique(shas), 1L)
  repo <- .cp_repo_path(root)
  expect_length(git_out(repo, c("rev-list", render_ref(root))), 1L)
  expect_length(git_out(repo, c("rev-list", render_ref(root, "records"))), 2L)
})

test_that("a job changed mid-snapshot leaves the source ref unchanged (review 3)", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  first <- study_render_commit("30_analyses/fit.R", root = root)
  writeLines("fit <- 2", file.path(root, "30_analyses", "fit.R"))
  real <- .cp_tree_with
  local_mocked_bindings(.cp_tree_with = function(...) {
    tree <- real(...)
    writeLines("fit <- 3", file.path(root, "30_analyses", "fit.R"))
    tree
  })
  expect_error(study_render_commit("30_analyses/fit.R", root = root),
               "changed while it was being committed")
  expect_identical(git_out(.cp_repo_path(root),
                           c("rev-parse", render_ref(root)))[1], first)
})

test_that("files are committed byte for byte under core.autocrlf (review 4)", {
  skip_if_no_git()
  local_git_env()
  system2("git", shQuote(c("config", "--file", Sys.getenv("GIT_CONFIG_GLOBAL"),
                           "core.autocrlf", "true")))
  root <- make_checkpoint_study(withr::local_tempdir())
  job <- file.path(root, "30_analyses", "fit.R")
  fig <- file.path(root, "30_analyses", "fit.png")
  writeLines("figure", fig)
  # An LF file, about which git warns on stderr while it succeeds.
  writeBin(charToRaw("fit <- 1\n"), job)
  first <- study_render_commit("30_analyses/fit.R", root = root)
  expect_match(first, "^[0-9a-f]{40}$")
  study_render_record("r1", first, "30_analyses/fit.R", fig, root = root)
  # A CRLF file, which the clean conversion would store as LF.
  writeBin(charToRaw("fit <- 2\r\n"), job)
  second <- study_render_commit("30_analyses/fit.R", root = root)
  repo <- .cp_repo_path(root)
  raw <- git_out(repo, c("hash-object", "--no-filters", job))[1]
  expect_false(identical(git_out(repo, c("hash-object", job))[1], raw))
  expect_identical(git_out(repo, c("rev-parse",
                                   paste0(second, ":30_analyses/fit.R")))[1],
                   raw)
})

test_that("an executable script stays executable on recovery (review 5)", {
  skip_if_no_git()
  skip_on_os("windows")
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  worker <- file.path(root, "30_analyses", "worker.sh")
  writeLines(c("#!/bin/sh", "echo recovered"), worker)
  Sys.chmod(worker, "755")
  sha <- study_render_commit("30_analyses/fit.R", root = root)
  repo <- .cp_repo_path(root)
  modes <- git_out(repo, c("ls-tree", "-r", sha))
  expect_match(modes, "^100755 .*\t30_analyses/worker.sh$", all = FALSE)
  expect_match(modes, "^100644 .*\t30_analyses/fit.R$", all = FALSE)

  out <- withr::local_tempdir()
  withr::local_envvar(GIT_INDEX_FILE = withr::local_tempfile())
  git_out(repo, c("--work-tree", out, "read-tree", sha))
  git_out(repo, c("--work-tree", out, "checkout-index", "-a"))
  expect_identical(system2(file.path(out, "30_analyses", "worker.sh"),
                           stdout = TRUE),
                   "recovered")
})

test_that("outputs outside the study stop the record before it is written (review 6)", {
  skip_if_no_git()
  local_git_env()
  dir <- withr::local_tempdir()
  root <- make_checkpoint_study(dir)
  sha <- study_render_commit("30_analyses/fit.R", root = root)
  outside <- file.path(dir, "outside.png")
  writeLines("outside", outside)
  expect_error(study_render_record("r1", sha, "30_analyses/fit.R", outside,
                                   root = root),
               "outside the study root")
  expect_error(study_render_record("r1", sha, "30_analyses/fit.R",
                                   "../outside.png", root = root),
               "outside the study root")
  if (.Platform$OS.type != "windows") {
    link <- file.path(root, "30_analyses", "link.png")
    file.symlink(outside, link)
    expect_error(study_render_record("r1", sha, "30_analyses/fit.R",
                                     "30_analyses/link.png", root = root),
                 "outside the study root")
  }
  expect_true(is.na(.cp_commit_of(.cp_repo_path(root),
                                  render_ref(root, "records"))))
})

test_that("a copied study gets its own render refs and keeps the old (review 7)", {
  skip_if_no_git()
  local_git_env()
  dir <- withr::local_tempdir()
  root <- make_checkpoint_study(dir)
  original <- study_render_commit("30_analyses/fit.R", root = root)
  study_checkpoint("manuscript_submitted", root = root)
  ref <- render_ref(root)

  copy_dir <- withr::local_tempdir()
  expect_true(file.copy(root, copy_dir, recursive = TRUE))
  copy <- file.path(copy_dir, "study")
  writeLines("fit <- 2", file.path(copy, "30_analyses", "fit.R"))
  copied <- study_render_commit("30_analyses/fit.R", root = copy)
  expect_false(identical(render_ref(copy), ref))
  repo <- .cp_repo_path(copy)
  expect_identical(git_out(repo, c("rev-parse", ref))[1], original)
  expect_identical(git_out(repo, c("rev-parse", render_ref(copy)))[1], copied)
  # The original keeps its ID.
  expect_identical(study_render_commit("30_analyses/fit.R", root = root),
                   original)
  expect_identical(render_ref(root), ref)

  clone_dir <- withr::local_tempdir()
  expect_true(file.copy(root, clone_dir, recursive = TRUE))
  clone <- file.path(clone_dir, "study")
  unlink(.cp_repo_path(clone), recursive = TRUE)
  git_out(dir, c("clone", "-q", .cp_repo_path(root), .cp_repo_path(clone)))
  study_render_commit("30_analyses/fit.R", root = clone)
  expect_false(render_ref(clone) %in% c(ref, render_ref(copy)))
})

test_that("an output that vanishes or changes while hashed is not recorded (review 8)", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  fig <- file.path(root, "30_analyses", "fit.png")
  writeLines("figure", fig)
  sha <- study_render_commit("30_analyses/fit.R", root = root)
  repo <- .cp_repo_path(root)
  records <- function() .cp_commit_of(repo, render_ref(root, "records"))

  real_digest <- digest::digest
  local_mocked_bindings(digest = function(...) {
    unlink(fig)
    real_digest(...)
  }, .package = "digest")
  expect_error(study_render_record("r1", sha, "30_analyses/fit.R", fig,
                                   root = root),
               "could not hash")
  expect_true(is.na(records()))

  writeLines("figure", fig)
  local_mocked_bindings(digest = function(...) {
    hash <- real_digest(...)
    cat("more\n", file = fig, append = TRUE)
    hash
  }, .package = "digest")
  expect_error(study_render_record("r1", sha, "30_analyses/fit.R", fig,
                                   root = root),
               "changed while it was being recorded")
  expect_true(is.na(records()))
})

test_that("a render_id is recorded once and never replaced (Copilot)", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  fig <- file.path(root, "30_analyses", "fit.png")
  writeLines("figure one", fig)
  sha <- study_render_commit("30_analyses/fit.R", root = root)
  study_render_record("r1", sha, "30_analyses/fit.R", fig, root = root)
  repo <- .cp_repo_path(root)
  tip <- git_out(repo, c("rev-parse", render_ref(root, "records")))[1]
  writeLines("figure two", fig)
  expect_error(study_render_record("r1", sha, "30_analyses/fit.R", fig,
                                   root = root),
               "already recorded")
  expect_identical(git_out(repo, c("rev-parse", render_ref(root, "records")))[1],
                   tip)
})

test_that("a failed setup releases the lock (Copilot)", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  yml <- file.path(root, "_study.yml")
  saved <- readLines(yml)
  unlink(yml)
  expect_error(study_render_commit("30_analyses/fit.R", root = root),
               "no _study.yml")
  expect_error(study_render_record("r1", strrep("a", 40), "30_analyses/fit.R",
                                   character(0), root = root),
               "no _study.yml")
  writeLines(saved, yml)
  expect_match(study_render_commit("30_analyses/fit.R", root = root),
               "^[0-9a-f]{40}$")
})

test_that("checkpoint, close and reopen stop off main before writing (Copilot)", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  study_close("abandoned", root = root)
  repo <- .cp_repo_path(root)
  git_out(repo, c("checkout", "-q", "-b", "elsewhere"))
  tags <- git_out(repo, c("tag", "-l"))
  head <- git_out(repo, c("rev-parse", "HEAD"))[1]
  local_mocked_bindings(.cp_reconcile = function(...) stop("reconciled"),
                        .cp_sync = function(...) stop("synced"))
  expect_error(study_checkpoint("manuscript_submitted", root = root),
               "not on main")
  expect_error(study_close("abandoned", root = root), "not on main")
  expect_error(study_reopen("new PI", root = root), "not on main")
  expect_identical(git_out(repo, c("tag", "-l")), tags)
  expect_identical(git_out(repo, c("rev-parse", "HEAD"))[1], head)
})

test_that("a file swapped for a symbolic link while hashed is not committed (review 2.1)", {
  skip_if_no_git()
  skip_on_os("windows")
  local_git_env()
  dir <- withr::local_tempdir()
  root <- make_checkpoint_study(dir)
  writeLines("helper <- 1", file.path(root, "30_analyses", "helper.R"))
  first <- study_render_commit("30_analyses/fit.R", root = root)
  outside <- file.path(dir, "outside.R")
  writeLines("outside <- 'protected'", outside)
  repo <- .cp_repo_path(root)
  real <- .cp_hash_files
  for (swapped in c("30_analyses/fit.R", "30_analyses/helper.R")) {
    writeLines(paste("# edit", swapped), file.path(root, "30_analyses", "fit.R"),
               sep = "\n")
    target <- file.path(root, swapped)
    saved <- readLines(target)
    local_mocked_bindings(.cp_hash_files = function(repo, files) {
      if (length(files) > 1L) {
        unlink(target)
        file.symlink(outside, target)
      }
      real(repo, files)
    })
    expect_error(study_render_commit("30_analyses/fit.R", root = root),
                 "replaced by a symbolic link")
    expect_identical(git_out(repo, c("rev-parse", render_ref(root)))[1], first)
    unlink(target)
    writeLines(saved, target)
  }
})

test_that("a record's job must be a code file in its commit (review 2.2)", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  fig <- file.path(root, "30_analyses", "fit.png")
  writeLines("figure", fig)
  sha <- study_render_commit("30_analyses/fit.R", root = root)
  for (job in c("30_analyses", "_study.yml", "30_analyses/")) {
    expect_error(study_render_record("r1", sha, job, fig, root = root),
                 "not a render job")
  }
  expect_error(study_render_commit("_study.yml", root = root),
               "not a code file")
  expect_true(is.na(.cp_commit_of(.cp_repo_path(root),
                                  render_ref(root, "records"))))
})

test_that("a named pipe output stops the record without hashing (review 2.3)", {
  skip_if_no_git()
  skip_on_os("windows")
  skip_if_not(nzchar(Sys.which("mkfifo")), "mkfifo is not available")
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  sha <- study_render_commit("30_analyses/fit.R", root = root)
  pipe <- file.path(root, "30_analyses", "fit.png")
  system2("mkfifo", shQuote(pipe))
  expect_error(study_render_record("r1", sha, "30_analyses/fit.R",
                                   "30_analyses/fit.png", root = root),
               "regular file")
})

test_that("a render that straddles a move of the study still records (review 2.4)", {
  skip_if_no_git()
  local_git_env()
  dir <- withr::local_tempdir()
  root <- make_checkpoint_study(dir)
  writeLines("figure", file.path(root, "30_analyses", "fit.png"))
  sha <- study_render_commit("30_analyses/fit.R", root = root)
  old_ref <- render_ref(root)
  moved <- file.path(dir, "moved")
  expect_true(file.rename(root, moved))
  rec <- study_render_record("r1", sha, "30_analyses/fit.R",
                             "30_analyses/fit.png", root = moved)
  expect_identical(rec$commit, sha)
  expect_false(identical(render_ref(moved), old_ref))
  repo <- .cp_repo_path(moved)
  shown <- git_out(repo, c("show", paste0(render_ref(moved, "records"),
                                          ":.hvti-renders/r1.json")))
  expect_identical(jsonlite::fromJSON(paste(shown, collapse = "\n"))$commit,
                   sha)
})
