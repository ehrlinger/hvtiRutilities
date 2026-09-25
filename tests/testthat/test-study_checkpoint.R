test_that("no denied file reaches the committed tree (PHI boundary)", {
  skip_if_no_git()
  local_git_env()
  dir <- withr::local_tempdir()
  root <- make_checkpoint_study(dir)
  set_study_keys(root, checkpoint = list(include = list("**/*.csv", "**/.env")))
  in_docs <- c("50_documents/table.csv", "50_documents/cohort.sas7bdat",
               "50_documents/supplement.xlsx", "50_documents/manuscript.docx")
  elsewhere <- c("10_descriptive/d.log", "30_analyses/draft.docx",
                 "00_datasets/built.sas7bdat", "00_datasets/notes.R",
                 "90_estimates/fit.R", ".env")
  plant_files(root, c(in_docs, elsewhere, "50_documents/paper.qmd"))
  linked <- character(0)
  if (.Platform$OS.type != "windows") {
    outside <- file.path(dir, "outside.R")
    writeLines("secret <- 1", outside)
    file.symlink(outside, file.path(root, "30_analyses", "linked.R"))
    linked <- "30_analyses/linked.R"
  }
  cp <- study_checkpoint("manuscript_submitted", root = root)
  repo <- .cp_repo_path(root)
  tree <- git_out(repo, c("ls-tree", "-r", "--name-only", cp$tag))
  expect_false(any(c(in_docs, elsewhere, linked, ".Renviron") %in% tree))
  expect_false(any(grepl(paste0("datasets|estimates|\\.csv$|\\.log$|",
                                "\\.xlsx$|\\.sas7bdat$|\\.docx$|\\.env$"),
                         tree)))
  expect_true(all(c("_study.yml", ".renvignore", "30_analyses/fit.R",
                    "50_documents/paper.qmd", "CHECKPOINT.yml") %in% tree))
  shown <- git_out(repo, c("show", paste0(cp$tag, ":CHECKPOINT.yml")))
  meta <- yaml::yaml.load(paste(shown, collapse = "\n"))
  docs <- vapply(meta$documents, function(d) d$path, character(1))
  expect_setequal(docs, in_docs)
  docx <- meta$documents[[which(docs == "50_documents/manuscript.docx")]]
  expect_equal(docx$sha256,
               digest::digest(file.path(root, "50_documents/manuscript.docx"),
                              algo = "sha256", file = TRUE))
  expect_gt(meta$denied$credential, 0L)
})

test_that("tags are numbered per kind and workspace_created is not", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  expect_equal(study_checkpoint("workspace_created", root = root)$tag,
               "workspace_created")
  expect_error(study_checkpoint("workspace_created", root = root),
               "already recorded")
  expect_equal(study_checkpoint("abstract_submitted", root = root)$tag,
               "abstract_submitted-1")
  expect_equal(study_checkpoint("abstract_submitted", root = root)$tag,
               "abstract_submitted-2")
  expect_length(.cp_log_read(root), 3L)
})

test_that("the log entry has the API checkpoint shape", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  expect_message(
    cp <- study_checkpoint("manuscript_submitted", note = "JTCVS",
                           attributes = list(journal = "JTCVS"),
                           occurred_at = as.Date("2026-10-02"), root = root),
    "patient information"
  )
  e <- .cp_log_read(root)[[1]]
  expect_equal(e$type, "checkpoint")
  expect_match(e$checkpoint_id, "^[0-9a-f-]{36}$")
  expect_equal(e$st_id, 1267L)
  expect_equal(e$occurred_at, "2026-10-02")
  expect_equal(e$state, "committed")
  expect_equal(e$git_commit, cp$commit)
  expect_equal(e$tag, "manuscript_submitted-1")
  expect_equal(e$attributes$journal, "JTCVS")
  expect_equal(e$delivery$git, "pending")
  expect_equal(e$delivery$st, "pending")
  msg <- git_out(.cp_repo_path(root),
                 c("tag", "-l", "--format=%(contents)", cp$tag))
  expect_true(any(grepl(e$checkpoint_id, msg, fixed = TRUE)))
})

test_that("free text prompts a one-line patient-information reminder", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  expect_message(study_checkpoint("abstract_submitted", note = "ASAIO",
                                  root = root),
                 "must not contain patient information")
  expect_message(study_checkpoint("abstract_submitted",
                                  attributes = list(meeting = "AATS"),
                                  root = root),
                 "must not contain patient information")
  expect_silent(study_checkpoint("abstract_submitted", note = "", root = root))
})

test_that("an automatic kind logs an entry but makes no commit", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  cp <- study_checkpoint("data_received", root = root)
  expect_null(cp$commit)
  e <- .cp_log_read(root)[[1]]
  expect_null(e$git_commit)
  expect_equal(e$state, "recorded")
  expect_equal(e$delivery$git, "none")
  expect_false(dir.exists(file.path(.cp_repo_path(root), ".git")))
})

test_that("a failure before the log append leaves no tag and no log entry", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  local_mocked_bindings(.cp_write_meta = function(...) stop("boom"))
  expect_error(study_checkpoint("manuscript_submitted", root = root), "boom")
  expect_length(.cp_log_read(root), 0L)
  expect_length(git_out(.cp_repo_path(root), c("tag", "-l")), 0L)
  expect_true(is.na(.cp_head(.cp_repo_path(root))))
})

test_that("a failure after the log append rolls git back and abandons the entry", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  first <- study_checkpoint("abstract_submitted", root = root)
  local_mocked_bindings(.cp_commit_tag = function(...) stop("git exploded"))
  expect_error(study_checkpoint("abstract_submitted", root = root),
               "git exploded")
  repo <- .cp_repo_path(root)
  expect_equal(.cp_head(repo), first$commit)
  expect_equal(git_out(repo, c("tag", "-l")), "abstract_submitted-1")
  log <- .cp_log_read(root)
  expect_length(log, 2L)
  expect_equal(log[[1]]$state, "committed")
  expect_equal(log[[2]]$state, "abandoned")
  expect_null(log[[2]]$git_commit)
})

test_that("a committing entry with no tag is abandoned by the next call", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  .cp_log_append(root, list(
    type = "checkpoint", checkpoint_id = "lost-1", st_id = 1267L,
    kind = "abstract_submitted", git_commit = NULL,
    tag = "abstract_submitted-1", state = "committing",
    delivery = list(git = "pending", st = "pending")
  ))
  cp <- study_checkpoint("abstract_submitted", root = root)
  log <- .cp_log_read(root)
  expect_equal(log[[1]]$state, "abandoned")
  expect_equal(log[[2]]$state, "committed")
  expect_equal(cp$tag, "abstract_submitted-1")
})

test_that("a committing entry whose tag exists is completed from the tag", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  cp <- study_checkpoint("abstract_submitted", root = root)
  log <- .cp_log_read(root)
  log[[1]]$state <- "committing"
  log[[1]]["git_commit"] <- list(NULL)
  .cp_log_write(root, log)
  study_checkpoint("abstract_submitted", root = root)
  e <- .cp_log_read(root)[[1]]
  expect_equal(e$state, "committed")
  expect_equal(e$git_commit, cp$commit)
})

test_that("an unknown kind is rejected before anything is written", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  expect_error(study_checkpoint("submitted", root = root),
               "unknown checkpoint kind")
  expect_false(dir.exists(file.path(root, ".checkpoint")))
})

test_that(".cp_reconcile removes an orphan commit left by a crash", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  first <- study_checkpoint("abstract_submitted", root = root)
  repo <- .cp_repo_path(root)
  fake_id <- uuid::UUIDgenerate()
  writeLines("orphan", file.path(repo, "orphan.txt"))
  git_out(repo, c("add", "-A"))
  git_out(repo, c("commit", "-q", "-m", fake_id))
  orphan_commit <- .cp_head(repo)
  .cp_log_append(root, list(
    type = "checkpoint", checkpoint_id = fake_id, st_id = 1267L,
    kind = "abstract_submitted", git_commit = NULL,
    tag = "abstract_submitted-2", state = "committing",
    delivery = list(git = "pending", st = "pending")
  ))
  .cp_reconcile(root)
  log <- .cp_log_read(root)
  expect_equal(log[[length(log)]]$state, "abandoned")
  expect_equal(.cp_head(repo), first$commit)
  main_history <- git_out(repo, c("rev-list", "main"))
  expect_false(orphan_commit %in% main_history)
  expect_true(first$commit %in% main_history)
})

test_that(".cp_reconcile peels stacked orphan commits from the top", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  first <- study_checkpoint("abstract_submitted", root = root)
  repo <- .cp_repo_path(root)
  ids <- c(uuid::UUIDgenerate(), uuid::UUIDgenerate())
  for (i in seq_along(ids)) {
    writeLines(ids[i], file.path(repo, "orphan.txt"))
    git_out(repo, c("add", "-A"))
    git_out(repo, c("commit", "-q", "-m", ids[i]))
    .cp_log_append(root, list(
      type = "checkpoint", checkpoint_id = ids[i], st_id = 1267L,
      kind = "abstract_submitted", tag = paste0("abstract_submitted-", i + 1L),
      state = "committing", delivery = list(git = "pending", st = "pending")
    ))
  }
  .cp_reconcile(root)
  states <- vapply(.cp_log_read(root), function(e) e$state, character(1))
  expect_equal(states, c("committed", "abandoned", "abandoned"))
  expect_equal(.cp_head(repo), first$commit)
})

test_that("a tag succeeds but marking committed fails: rollback and abandon", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  first <- study_checkpoint("abstract_submitted", root = root)
  real <- .cp_log_update
  local_mocked_bindings(.cp_log_update = function(root, id, fields, ...) {
    if (identical(fields$state, "committed")) stop("log update exploded")
    real(root, id, fields, ...)
  })
  expect_error(study_checkpoint("abstract_submitted", root = root),
               "log update exploded")
  repo <- .cp_repo_path(root)
  expect_equal(.cp_head(repo), first$commit)
  expect_equal(git_out(repo, c("tag", "-l")), "abstract_submitted-1")
  log <- .cp_log_read(root)
  expect_length(log, 2L)
  expect_equal(log[[1]]$state, "committed")
  expect_equal(log[[2]]$state, "abandoned")
  expect_null(log[[2]]$git_commit)
})
