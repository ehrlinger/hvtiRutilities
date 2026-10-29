# Render commits: the same allow-listed snapshot a checkpoint takes, committed
# to the branch `renders` of .checkpoint/repo before a job runs, so a figure
# can name the commit of the code that drew it. Built with plumbing in a
# private index: main, the tags and the checkpoint's working tree, which
# closure state and delivery read, are never touched.

# Write `files` (relative to `root`) as blobs and return their tree.
.cp_render_tree <- function(repo, root, files) {
  index <- tempfile("cp-index-")
  on.exit(unlink(index), add = TRUE)
  withr::local_envvar(GIT_INDEX_FILE = index)
  paths <- tempfile("cp-paths-")
  on.exit(unlink(paths), add = TRUE)
  writeLines(file.path(root, files), paths, useBytes = TRUE)
  blobs <- .cp_git_stdin(repo, c("hash-object", "-w", "--stdin-paths"), paths)
  info <- tempfile("cp-info-")
  on.exit(unlink(info), add = TRUE)
  writeLines(paste0("100644 ", blobs, "\t", files), info, useBytes = TRUE)
  .cp_git_stdin(repo, c("update-index", "--add", "--index-info"), info)
  .cp_git_do(repo, "write-tree")[1]
}

# .cp_git_do() with `input` (a file) on stdin.
.cp_git_stdin <- function(repo, args, input) {
  out <- suppressWarnings(system2(
    "git", shQuote(c("-C", repo, args)), stdout = TRUE, stderr = TRUE,
    stdin = input
  ))
  status <- attr(out, "status")
  if (!is.null(status) && !identical(as.integer(status), 0L)) {
    stop("git ", paste(args, collapse = " "), " failed:\n",
         paste(out, collapse = "\n"), call. = FALSE)
  }
  as.character(out)
}

#' Commit the study's code before a render
#'
#' Commits the same allow-listed snapshot \code{\link{study_checkpoint}} takes
#' (code, identity and reproducibility files; never data or outputs) to the
#' branch \code{renders} of the private repository in
#' \code{.checkpoint/repo/}, and returns the commit. A render calls it before
#' the job runs, so each figure can print the commit of the code that drew it
#' and the job can later be shown as it ran.
#'
#' @details
#' A study whose snapshot is unchanged since the last render commit gets that
#' commit back, so re-rendering adds no history. The commit is local: it is not
#' tagged and not pushed, and \code{main}, its tags and the checkpoint working
#' tree are left as they were. It takes the checkpoint lock, so it stops when a
#' checkpoint or another render holds it; the caller decides whether the render
#' goes on without a commit.
#'
#' @param job Character(1) or \code{NULL}. The job being rendered, relative to
#'   the study root; it names the commit. Default \code{NULL}.
#' @param root Character(1). The study root. Default \code{study_root()}.
#'
#' @return Invisibly, the 40-character commit ID.
#'
#' @seealso \code{\link{study_checkpoint}}
#'
#' @examples
#' \donttest{
#' if (nzchar(Sys.which("git"))) {
#'   root <- file.path(tempdir(), "render-commit-example")
#'   study_setup(root, "Render commit example", 1L, renv = FALSE)
#'   writeLines("fit <- 1", file.path(root, "30_analyses", "fit.R"))
#'   # A commit needs an author; a real study uses the analyst's git config.
#'   withr::with_envvar(c(
#'     GIT_AUTHOR_NAME = "Example", GIT_AUTHOR_EMAIL = "example@example.org",
#'     GIT_COMMITTER_NAME = "Example", GIT_COMMITTER_EMAIL = "example@example.org"
#'   ), {
#'     sha <- study_render_commit("30_analyses/fit.R", root = root)
#'     print(substr(sha, 1, 7))
#'   })
#'   unlink(root, recursive = TRUE)
#' }
#' }
#' @export
study_render_commit <- function(job = NULL, root = study_root()) {
  .cp_require_git("study_render_commit")
  if (!is.null(job)) .cp_check_string(job, "study_render_commit", "job")
  root <- normalizePath(root, mustWork = TRUE)
  held <- .cp_lock(root, "study_render_commit")
  on.exit(.cp_unlock(held), add = TRUE)
  study <- .cp_study(root, "study_render_commit")
  repo <- .cp_repo_init(root, study$remote)
  sel <- .cp_select(root, study$include)
  if (nrow(sel$skipped)) {
    warning("study_render_commit(): skipped over the 50 MB cap: ",
            paste(sel$skipped$path, collapse = ", "), call. = FALSE)
  }
  tree <- .cp_render_tree(repo, root, sel$files)
  parent <- .cp_commit_of(repo, "refs/heads/renders")
  if (!is.na(parent) &&
        identical(.cp_git_do(repo, c("rev-parse", paste0(parent, "^{tree}")))[1],
                  tree)) {
    return(invisible(parent))
  }
  msg <- .cp_message_file(paste("render", .cp_or(job, "(study)")))
  on.exit(unlink(msg), add = TRUE)
  sha <- .cp_git_do(repo, c("commit-tree", tree,
                            if (!is.na(parent)) c("-p", parent),
                            "-F", msg))[1]
  # Compare-and-swap: a ref another process moved since `parent` was read
  # fails here rather than being overwritten.
  .cp_git_do(repo, c("update-ref", "refs/heads/renders", sha,
                     if (is.na(parent)) strrep("0", 40) else parent))
  invisible(sha)
}
