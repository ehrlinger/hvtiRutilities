# Render commits: the same allow-listed snapshot a checkpoint takes, committed
# before a job runs so a figure can name the commit of the code that drew it,
# and render records, which tie each published output's hash to that commit.
# Both live on one ref per copy of the study, refs/renders/<copy id>, outside
# refs/heads/ so nothing checks it out. They are built with plumbing in a
# private index and the ref moves last, in one compare-and-swap: main, its
# tags, HEAD and the checkpoint's working tree, which closure state and
# delivery read, are never touched, and an interrupted call leaves only
# unreferenced objects. Design: dev/specs/2026-10-29-figure-provenance-design.md
# in the hvtiR repository, sections 1 and R1 to R3.

# The records' folder inside each render tree. Every render commit carries the
# records of the ones before it, so the tip alone answers a lookup.
.cp_records_dir <- function() ".hvti-renders"

# This copy's render ref. A re-clone is a new copy and gets a new id, so two
# copies never push to the same ref and no render commit is ever rewritten.
.cp_render_ref <- function(repo) {
  res <- .cp_git(repo, c("config", "--get", "hvti.renderref"))
  if (res$ok && nzchar(res$out[1])) return(res$out[1])
  ref <- paste0("refs/renders/", uuid::UUIDgenerate())
  .cp_git_do(repo, c("config", "hvti.renderref", ref))
  ref
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

# Write `files` (absolute paths) as blobs at `paths` in the tree, on top of
# the records folder of `parent`, and return the tree.
.cp_render_tree <- function(repo, files, paths, parent) {
  index <- tempfile("cp-index-")
  on.exit(unlink(index), add = TRUE)
  withr::local_envvar(GIT_INDEX_FILE = index)
  records <- if (!is.na(parent)) {
    .cp_git(repo, c("rev-parse", "-q", "--verify",
                    paste0(parent, ":", .cp_records_dir())))
  }
  if (isTRUE(records$ok)) {
    .cp_git_do(repo, c("read-tree", paste0("--prefix=", .cp_records_dir(), "/"),
                       records$out[1]))
  }
  if (length(files)) {
    list_file <- tempfile("cp-paths-")
    on.exit(unlink(list_file), add = TRUE)
    writeLines(files, list_file, useBytes = TRUE)
    blobs <- .cp_git_stdin(repo, c("hash-object", "-w", "--stdin-paths"),
                           list_file)
    info <- tempfile("cp-info-")
    on.exit(unlink(info), add = TRUE)
    writeLines(paste0("100644 ", blobs, "\t", paths), info, useBytes = TRUE)
    .cp_git_stdin(repo, c("update-index", "--add", "--index-info"), info)
  }
  .cp_git_do(repo, "write-tree")[1]
}

# Commit `tree` on `ref` unless it is the tip's tree already, and return the
# commit. update-ref names the old value, so a ref another process moved
# since `parent` was read fails here rather than being overwritten.
.cp_render_advance <- function(repo, ref, parent, tree, subject) {
  if (!is.na(parent) &&
        identical(.cp_git_do(repo, c("rev-parse", paste0(parent, "^{tree}")))[1],
                  tree)) {
    return(parent)
  }
  msg <- .cp_message_file(subject)
  on.exit(unlink(msg), add = TRUE)
  sha <- .cp_git_do(repo, c("commit-tree", tree,
                            if (!is.na(parent)) c("-p", parent),
                            "-F", msg))[1]
  .cp_git_do(repo, c("update-ref", ref, sha,
                     if (is.na(parent)) strrep("0", 40) else parent))
  sha
}

# The blob `path` names in `commit`, or NA when the commit lacks it.
.cp_blob_at <- function(repo, commit, path) {
  res <- .cp_git(repo, c("rev-parse", "-q", "--verify",
                         paste0(commit, ":", path)))
  if (res$ok) res$out[1] else NA_character_
}

# Open the study's repository under the lock, for the render functions.
.cp_render_open <- function(root, caller) {
  .cp_require_git(caller)
  root <- normalizePath(root, mustWork = TRUE)
  held <- .cp_lock(root, caller)
  study <- .cp_study(root, caller)
  repo <- .cp_repo_init(root, study$remote)
  list(root = root, held = held, study = study, repo = repo,
       ref = .cp_render_ref(repo))
}

#' Commit the study's code before a render
#'
#' Commits the same allow-listed snapshot \code{\link{study_checkpoint}} takes
#' (code, identity and reproducibility files; never data or outputs) to this
#' copy's render ref in the private repository \code{.checkpoint/repo/}, and
#' returns the commit. A render calls it before the job runs, so each figure
#' can print the commit of the code that drew it.
#'
#' @details
#' The job must be in the commit, as the bytes on disk: a job the allow-list
#' leaves out (a symbolic link, a file under a data or estimates folder or one
#' over 50 MB) stops the call rather than returning a commit from which the
#' job cannot be recovered.
#'
#' A study whose snapshot is unchanged since the last render commit gets that
#' commit back, so re-rendering adds no history. The ref is
#' \code{refs/renders/<id>}, one per copy of the study and outside
#' \code{refs/heads/}; it is not tagged or pushed, and \code{main}, its tags,
#' \code{HEAD} and the checkpoint working tree are never touched. The call
#' takes the checkpoint lock, so it stops while a checkpoint or another render
#' holds it.
#'
#' The commit only proves what the job was when the render began. A render
#' that publishes outputs must also show that the code it executed matches
#' the commit, and record what it published with
#' \code{\link{study_render_record}}.
#'
#' @param job Character(1). The job being rendered, relative to the study
#'   root.
#' @param root Character(1). The study root. Default \code{study_root()}.
#'
#' @return Invisibly, the 40-character commit ID.
#'
#' @seealso \code{\link{study_render_record}}, \code{\link{study_checkpoint}}
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
study_render_commit <- function(job, root = study_root()) {
  .cp_check_string(job, "study_render_commit", "job")
  rc <- .cp_render_open(root, "study_render_commit")
  on.exit(.cp_unlock(rc$held), add = TRUE)
  sel <- .cp_select(rc$root, rc$study$include)
  if (nrow(sel$skipped)) {
    warning("study_render_commit(): skipped over the 50 MB cap: ",
            paste(sel$skipped$path, collapse = ", "), call. = FALSE)
  }
  if (!job %in% sel$files) {
    stop("study_render_commit(): ", job, " is not in the study's snapshot ",
         "(missing, a symbolic link, under a data or estimates folder, or ",
         "over 50 MB), so no commit could recover it", call. = FALSE)
  }
  parent <- .cp_commit_of(rc$repo, rc$ref)
  tree <- .cp_render_tree(rc$repo, file.path(rc$root, sel$files), sel$files,
                          parent)
  sha <- .cp_render_advance(rc$repo, rc$ref, parent, tree,
                            paste("render", job))
  on_disk <- .cp_git_do(rc$repo, c("hash-object", file.path(rc$root, job)))[1]
  if (!identical(.cp_blob_at(rc$repo, sha, job), on_disk)) {
    stop("study_render_commit(): ", job, " changed while it was being ",
         "committed; render again", call. = FALSE)
  }
  invisible(sha)
}

#' Record what a render published
#'
#' Adds a render record to this copy's render ref, tying every output a
#' render published to the commit its figures print. Records accumulate, so a
#' figure copied into a manuscript can be traced after its job is rendered
#' again.
#'
#' @details
#' The record is written as \code{.hvti-renders/<render_id>.json} in a new
#' commit on the render ref, and every later render commit carries it, so
#' the ref's tip holds every record. It names \code{commit}, \code{job}, the
#' time, \code{extra} (typically the render's provenance) and, for each file
#' in \code{outputs}, its path relative to the study root and its sha256. A
#' render that fails should publish nothing and record nothing.
#'
#' @param render_id Character(1). The render's identifier; names the record.
#' @param commit Character(1). The commit from
#'   \code{\link{study_render_commit}} that the outputs print.
#' @param job Character(1). The job rendered, relative to the study root.
#' @param outputs Character. Paths of the published files, absolute or
#'   relative to the study root; each must exist.
#' @param extra List. Further fields for the record. Default \code{list()}.
#' @param root Character(1). The study root. Default \code{study_root()}.
#'
#' @return Invisibly, the record as a list.
#'
#' @seealso \code{\link{study_render_commit}}
#'
#' @examples
#' \donttest{
#' if (nzchar(Sys.which("git"))) {
#'   root <- file.path(tempdir(), "render-record-example")
#'   study_setup(root, "Render record example", 1L, renv = FALSE)
#'   writeLines("fit <- 1", file.path(root, "30_analyses", "fit.R"))
#'   writeLines("figure", file.path(root, "30_analyses", "fit.png"))
#'   withr::with_envvar(c(
#'     GIT_AUTHOR_NAME = "Example", GIT_AUTHOR_EMAIL = "example@example.org",
#'     GIT_COMMITTER_NAME = "Example", GIT_COMMITTER_EMAIL = "example@example.org"
#'   ), {
#'     sha <- study_render_commit("30_analyses/fit.R", root = root)
#'     rec <- study_render_record("r1", sha, "30_analyses/fit.R",
#'                                "30_analyses/fit.png", root = root)
#'     print(rec$outputs)
#'   })
#'   unlink(root, recursive = TRUE)
#' }
#' }
#' @export
study_render_record <- function(render_id, commit, job, outputs,
                                extra = list(), root = study_root()) {
  .cp_check_string(render_id, "study_render_record", "render_id")
  .cp_check_string(commit, "study_render_record", "commit")
  .cp_check_string(job, "study_render_record", "job")
  if (!grepl("^[A-Za-z0-9._-]+$", render_id)) {
    stop("study_render_record(): render_id may hold only letters, digits, ",
         "'.', '_' and '-'", call. = FALSE)
  }
  if (!is.character(outputs) || anyNA(outputs)) {
    stop("study_render_record(): outputs must be file paths", call. = FALSE)
  }
  if (!is.list(extra)) {
    stop("study_render_record(): extra must be a list", call. = FALSE)
  }
  rc <- .cp_render_open(root, "study_render_record")
  on.exit(.cp_unlock(rc$held), add = TRUE)
  if (!.cp_git(rc$repo, c("merge-base", "--is-ancestor", commit, rc$ref))$ok) {
    stop("study_render_record(): ", commit, " is not a render commit of ",
         "this study", call. = FALSE)
  }
  abs <- ifelse(grepl("^(/|[A-Za-z]:[/\\\\])", outputs), outputs,
                file.path(rc$root, outputs))
  missing <- outputs[!file.exists(abs)]
  if (length(missing)) {
    stop("study_render_record(): no such output: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  abs <- normalizePath(abs, winslash = "/")
  prefix <- paste0(normalizePath(rc$root, winslash = "/"), "/")
  rel <- ifelse(startsWith(abs, prefix), substring(abs, nchar(prefix) + 1L),
                abs)
  record <- list(
    render_id = render_id, commit = commit, job = job,
    recorded_at = .cp_utc(Sys.time()),
    outputs = lapply(seq_along(abs), function(i) {
      list(path = rel[[i]], sha256 = .cp_sha(abs[[i]]))
    }),
    extra = extra
  )
  json <- tempfile("cp-record-", fileext = ".json")
  on.exit(unlink(json), add = TRUE)
  writeLines(jsonlite::toJSON(record, auto_unbox = TRUE, null = "null",
                              digits = NA, pretty = TRUE), json)
  parent <- .cp_commit_of(rc$repo, rc$ref)
  tree <- .cp_render_tree(rc$repo, json,
                          paste0(.cp_records_dir(), "/", render_id, ".json"),
                          NA_character_)
  # The records-only tree above is merged onto the tip's full tree.
  tree <- .cp_render_overlay(rc$repo, parent, tree)
  .cp_render_advance(rc$repo, rc$ref, parent, tree,
                     paste("record", render_id, "for", job))
  invisible(record)
}

# The tip's tree with the entries of `overlay` added or replaced.
.cp_render_overlay <- function(repo, parent, overlay) {
  index <- tempfile("cp-index-")
  on.exit(unlink(index), add = TRUE)
  withr::local_envvar(GIT_INDEX_FILE = index)
  .cp_git_do(repo, c("read-tree", parent))
  entries <- .cp_git_do(repo, c("ls-tree", "-r", overlay))
  info <- tempfile("cp-info-")
  on.exit(unlink(info), add = TRUE)
  writeLines(sub("^(\\S+) blob ", "\\1 ", entries), info, useBytes = TRUE)
  .cp_git_stdin(repo, c("update-index", "--add", "--index-info"), info)
  .cp_git_do(repo, "write-tree")[1]
}
