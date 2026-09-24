# Fixtures for the checkpoint tests. Every git-using test calls
# skip_if_no_git() and local_git_env(): the second points git at an empty
# global config so a developer's signing, hooks or default branch cannot
# change the result, and supplies an author identity.

skip_if_no_git <- function() {
  testthat::skip_if_not(nzchar(Sys.which("git")), "git is not available")
}

local_git_env <- function(.env = parent.frame()) {
  cfg <- withr::local_tempfile(.local_envir = .env)
  file.create(cfg)
  withr::local_envvar(
    c(GIT_CONFIG_GLOBAL = cfg,
      GIT_CONFIG_NOSYSTEM = "1",
      GIT_AUTHOR_NAME = "Test Analyst",
      GIT_AUTHOR_EMAIL = "analyst@example.org",
      GIT_COMMITTER_NAME = "Test Analyst",
      GIT_COMMITTER_EMAIL = "analyst@example.org"),
    .local_envir = .env
  )
}

plant_files <- function(root, paths, text = "x") {
  for (p in paths) {
    dest <- file.path(root, p)
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    writeLines(text, dest)
  }
  invisible(paths)
}

set_study_keys <- function(root, ...) {
  path <- file.path(root, "_study.yml")
  cfg <- yaml::read_yaml(path)
  keys <- list(...)
  for (k in names(keys)) cfg[[k]] <- keys[[k]]
  yaml::write_yaml(cfg, path)
  invisible(cfg)
}

make_checkpoint_study <- function(dir) {
  root <- file.path(dir, "study")
  study_setup(root, "Checkpoint fixture", 1267L)
  plant_files(root, c("30_analyses/fit.R", "renv.lock"))
  root
}

make_bare_remote <- function(dir, name = "remote.git") {
  bare <- file.path(dir, name)
  system2("git", shQuote(c("init", "--bare", "-q", bare)))
  bare
}

git_out <- function(repo, args) {
  suppressWarnings(system2("git", shQuote(c("-C", repo, args)),
                           stdout = TRUE, stderr = TRUE))
}

# The divergence fixture: a local-only checkpoint, then another copy pushes
# its own main and data_request_submitted-1 to the remote first.
diverge_study <- function(dir) {
  root <- make_checkpoint_study(dir)
  bare <- make_bare_remote(dir)
  local_cp <- study_checkpoint("data_request_submitted", root = root)
  other <- file.path(dir, "other")
  git_out(dir, c("clone", "-q", bare, other))
  git_out(other, c("checkout", "-q", "-b", "main"))
  plant_files(other, "other.R")
  git_out(other, c("add", "-A"))
  git_out(other, c("commit", "-q", "-m", "other copy"))
  git_out(other, c("tag", "-a", "data_request_submitted-1", "-m", "other"))
  git_out(other, c("push", "-q", "origin", "main",
                   "refs/tags/data_request_submitted-1"))
  list(root = root, bare = bare, local_cp = local_cp)
}

# A pre-receive hook on a bare remote that refuses the first push carrying a
# tag update and accepts every later one. POSIX shell, so not for Windows.
reject_tag_push_once <- function(bare, marker) {
  hook <- file.path(bare, "hooks", "pre-receive")
  writeLines(c(
    "#!/bin/sh",
    paste0("marker='", marker, "'"),
    "while read old new ref; do",
    "  case \"$ref\" in refs/tags/*)",
    "    if [ ! -f \"$marker\" ]; then",
    "      touch \"$marker\"; echo 'tag update refused once' >&2; exit 1",
    "    fi;;",
    "  esac",
    "done",
    "exit 0"
  ), hook)
  Sys.chmod(hook, "755")
  invisible(hook)
}
