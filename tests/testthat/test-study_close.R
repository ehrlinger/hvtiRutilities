pub <- list(title = "A paper", journal = "JTCVS", accepted_on = "2026-05-26",
            published_on = "2026-06-12", doi = "10.1016/j.jtcvs.2026.05.027")

test_that("close guards fail before anything is written", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  expect_error(study_close("published", publication = pub, root = root),
               "needs a manuscript_published checkpoint")
  suppressMessages(study_checkpoint("manuscript_published", root = root))
  expect_error(study_close("published", publication = pub[1:2], root = root),
               "accepted_on, published_on")
  expect_error(study_close("published",
                           publication = pub[c("title", "journal",
                                               "accepted_on", "published_on")],
                           root = root),
               "doi or pmid")
  expect_error(study_close("superseded", reason = "replaced", root = root),
               "superseded_by")
  expect_error(study_close("unrecorded", root = root), "legacy migration")
  expect_false(any(grepl("^closed-",
                         git_out(.cp_repo_path(root), c("tag", "-l")))))
  types <- vapply(.cp_log_read(root), function(e) e$type, character(1))
  expect_equal(types, "checkpoint")
})

test_that("close snapshots and tags; reopen tags without committing", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  expect_message(cl <- study_close("not_published", reason = "no journal fit",
                                   root = root),
                 "must not contain patient information")
  expect_equal(cl$tag, "closed-not_published-1")
  expect_equal(.cp_log_read(root)[[1]]$state, "committed")
  expect_true(.cp_is_closed(root))
  expect_error(study_close("abandoned", root = root), "already closed")
  repo <- .cp_repo_path(root)
  head <- .cp_head(repo)
  expect_message(ro <- study_reopen("new cohort", root = root),
                 "must not contain patient information")
  expect_equal(ro$tag, "reopened-1")
  expect_equal(ro$commit, head)
  expect_equal(.cp_head(repo), head)
  expect_false(.cp_is_closed(root))
  expect_error(study_reopen("again", root = root), "not closed")
  suppressMessages(study_checkpoint("manuscript_published", root = root))
  expect_equal(study_close("published", publication = pub, root = root)$tag,
               "closed-published-2")
  log <- .cp_log_read(root)
  expect_equal(vapply(log, function(e) e$type, character(1)),
               c("closure", "reopening", "checkpoint", "closure"))
  expect_equal(vapply(log, function(e) e$state, character(1)),
               rep("committed", 4L))
  expect_equal(log[[4]]$publication$doi, pub$doi)
})

test_that("a failed reopening leaves no tag and an abandoned entry", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  study_close("abandoned", root = root)
  local_mocked_bindings(.cp_tag_head = function(...) stop("tag failed"))
  expect_error(suppressMessages(study_reopen("new PI", root = root)),
               "tag failed")
  expect_true(.cp_is_closed(root))
  expect_false("reopened-1" %in% git_out(.cp_repo_path(root), c("tag", "-l")))
  log <- .cp_log_read(root)
  expect_equal(log[[2]]$type, "reopening")
  expect_equal(log[[2]]$state, "abandoned")
})

test_that("a reopening left committing is completed from its tag", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  study_close("abandoned", root = root)
  ro <- suppressMessages(study_reopen("new PI", root = root))
  log <- .cp_log_read(root)
  log[[2]]$state <- "committing"
  log[[2]]["git_commit"] <- list(NULL)
  .cp_log_write(root, log)
  study_close("abandoned", root = root)
  e <- .cp_log_read(root)[[2]]
  expect_equal(e$state, "committed")
  expect_equal(e$git_commit, ro$commit)
})

test_that("a checkpoint on a closed study succeeds and warns", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  study_close("abandoned", root = root)
  expect_warning(cp <- study_checkpoint("abstract_submitted", root = root),
                 "study is closed")
  expect_equal(cp$tag, "abstract_submitted-1")
})

test_that("manuscript_published hints at study_close", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  expect_message(study_checkpoint("manuscript_published", root = root),
                 "study_close\\(\"published\"")
})

test_that("guards on a study with no repository write nothing", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  expect_false(dir.exists(.cp_repo_path(root)))
  expect_error(study_close("published", publication = pub, root = root),
               "needs a manuscript_published checkpoint")
  expect_error(study_close("published", publication = pub[1:2], root = root),
               "accepted_on, published_on")
  expect_error(study_close("superseded", root = root), "superseded_by")
  expect_error(study_close("unrecorded", root = root), "legacy migration")
  expect_error(study_close("abandoned", reason = c("a", "b"), root = root),
               "reason")
  expect_error(study_reopen("new PI", root = root), "not closed")
  expect_error(study_reopen(c("a", "b"), root = root), "reason")
  expect_false(dir.exists(.cp_repo_path(root)))
  expect_length(.cp_log_read(root), 0L)
})

test_that("close and reopen validate their inputs", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  suppressMessages(study_checkpoint("manuscript_published", root = root))
  expect_error(study_close("superseded", superseded_by = 1.7, root = root),
               "superseded_by")
  expect_error(study_close("superseded", superseded_by = c(1L, 2L),
                           root = root),
               "superseded_by")
  no_id <- pub[c("title", "journal", "accepted_on", "published_on")]
  expect_error(study_close("published", publication = c(no_id, doi_url = "x"),
                           root = root),
               "doi or pmid")
  expect_error(study_close("published", publication = c(no_id, doi = ""),
                           root = root),
               "doi or pmid")
  expect_error(study_close("abandoned", reason = 1, root = root), "reason")
  expect_error(study_close("abandoned", reason = c("a", "b"), root = root),
               "reason")
  for (sb in list(1267L, 1267, "1267")) {
    cl <- study_close("superseded", superseded_by = sb, root = root)
    expect_identical(.cp_log_find(root, cl$entry$closure_id)$superseded_by, 1267L)
    expect_error(study_reopen("next", new_lead = c("a", "b"), root = root),
                 "new_lead")
    expect_error(study_reopen("next", new_lead = 1, root = root), "new_lead")
    suppressMessages(study_reopen("next", new_lead = "jdoe", root = root))
  }
})

test_that("a reopening after a numbering gap takes a fresh number", {
  skip_if_no_git()
  local_git_env()
  root <- gap_study(withr::local_tempdir())
  repo <- .cp_repo_path(root)
  before <- tag_commits(repo)
  ro <- suppressMessages(study_reopen("again", root = root))
  expect_equal(ro$tag, "reopened-3")
  after <- tag_commits(repo)
  expect_equal(after[names(before)], before)
  expect_false(.cp_is_closed(root))
})

test_that("a failed reopening never deletes a tag it did not create", {
  skip_if_no_git()
  local_git_env()
  root <- gap_study(withr::local_tempdir())
  repo <- .cp_repo_path(root)
  before <- tag_commits(repo)
  local_mocked_bindings(.cp_tag_head = function(...) stop("tag failed"))
  expect_error(suppressMessages(study_reopen("again", root = root)),
               "tag failed")
  expect_equal(tag_commits(repo), before)
})

test_that("closure numbers stay unique across outcomes on the remote", {
  skip_if_no_git()
  local_git_env()
  dir <- withr::local_tempdir()
  root <- make_checkpoint_study(dir)
  bare <- make_bare_remote(dir)
  study_close("abandoned", root = root)
  suppressMessages(study_reopen("new PI", root = root))
  expect_equal(study_close("abandoned", root = root)$tag,
               "closed-abandoned-2")
  other <- file.path(dir, "other")
  git_out(dir, c("clone", "-q", bare, other))
  git_out(other, c("checkout", "-q", "-b", "main"))
  plant_files(other, "other.R")
  git_out(other, c("add", "-A"))
  git_out(other, c("commit", "-q", "-m", "other copy"))
  git_out(other, c("tag", "-a", "closed-published-2", "-m", "other"))
  git_out(other, c("push", "-q", "origin", "main",
                   "refs/tags/closed-published-2"))
  set_study_keys(root, checkpoint = list(remote = bare))
  study_checkpoint_push(root)
  e <- .cp_log_read(root)[[3]]
  expect_equal(e$delivery$git, "delivered")
  expect_equal(e$tag, "closed-abandoned-3")
  expect_equal(e$renumbered_from, "closed-abandoned-2")
  closed <- grep("^closed-", git_out(bare, c("tag", "-l")), value = TRUE)
  expect_setequal(closed, c("closed-abandoned-1", "closed-published-2",
                            "closed-abandoned-3"))
  expect_false(anyDuplicated(.cp_seq_of(closed)) > 0L)
})
