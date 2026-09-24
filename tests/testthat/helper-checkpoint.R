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
