# Render commits: the same allow-listed snapshot a checkpoint takes, committed
# before a job runs so a figure can name the commit of the code that drew it,
# and render records, which tie each published output's hash to that commit.
# Each copy of the study has two refs outside refs/heads/, so nothing checks
# them out: refs/renders/<copy id>/source holds only source snapshots, and
# refs/renders/<copy id>/records only the append-only record commits. They are
# built with plumbing in a private index, every check runs before the ref
# moves, and the ref moves last, in one compare-and-swap: main, its tags, HEAD
# and the checkpoint's working tree, which closure state and delivery read,
# are never touched, and a failed or interrupted call leaves only
# unreferenced objects. Design: dev/specs/2026-10-29-figure-provenance-design.md
# in the hvtiR repository, sections 1 and R1 to R3.

# The records' folder in each record commit. Every record commit carries the
# records of the ones before it, so the tip alone answers a lookup.
.cp_records_dir <- function() ".hvti-renders"

# This copy's render ID. It is kept in the repository's config with the
# repository's real path and the host, because copying or moving a study
# carries .checkpoint/repo and its config along: a copy at another path or on
# another host mints a new ID rather than committing under the original's
# refs, so no two copies ever share one. The refs it inherited stay, and their
# records stay readable. A re-clone has no such config and gets a new ID too.
.cp_render_id <- function(repo) {
  get <- function(key) {
    res <- .cp_git(repo, c("config", "--get", paste0("hvti.render", key)))
    if (res$ok) res$out[1] else NA_character_
  }
  path <- normalizePath(repo, winslash = "/", mustWork = TRUE)
  host <- unname(Sys.info()[["nodename"]])
  id <- get("id")
  if (!is.na(id) && identical(get("path"), path) &&
        identical(get("host"), host)) {
    return(id)
  }
  id <- uuid::UUIDgenerate()
  .cp_git_do(repo, c("config", "hvti.renderid", id))
  .cp_git_do(repo, c("config", "hvti.renderpath", path))
  .cp_git_do(repo, c("config", "hvti.renderhost", host))
  id
}

.cp_render_refs <- function(repo) {
  base <- paste0("refs/renders/", .cp_render_id(repo))
  list(source = paste0(base, "/source"), records = paste0(base, "/records"))
}

# .cp_git_do() with `input` (a file) on stdin. stderr is kept apart, so a
# warning git prints on success never reaches the output a caller parses.
.cp_git_stdin <- function(repo, args, input) {
  err <- tempfile("cp-stderr-")
  on.exit(unlink(err), add = TRUE)
  out <- suppressWarnings(system2(
    "git", shQuote(c("-C", repo, args)), stdout = TRUE, stderr = err,
    stdin = input
  ))
  status <- attr(out, "status")
  if (!is.null(status) && !identical(as.integer(status), 0L)) {
    stop("git ", paste(args, collapse = " "), " failed:\n",
         paste(c(out, readLines(err, warn = FALSE)), collapse = "\n"),
         call. = FALSE)
  }
  as.character(out)
}

# Write `files` (absolute paths) as blobs of their bytes on disk and return
# one blob ID per file. --no-filters skips autocrlf and clean filters, so the
# blob is the file, not git's conversion of it.
.cp_hash_files <- function(repo, files) {
  list_file <- tempfile("cp-paths-")
  on.exit(unlink(list_file), add = TRUE)
  writeLines(files, list_file, useBytes = TRUE)
  blobs <- .cp_git_stdin(repo, c("hash-object", "-w", "--no-filters",
                                 "--stdin-paths"), list_file)
  if (length(blobs) != length(files) || !all(grepl("^[0-9a-f]{40}$", blobs))) {
    stop("git hash-object did not return one object ID per file:\n",
         paste(blobs, collapse = "\n"), call. = FALSE)
  }
  blobs
}

# Git's mode for each file: 100755 when its owner may execute it, so a
# recovered study can still run a script its job invoked directly.
.cp_file_modes <- function(files) {
  exec <- .Platform$OS.type != "windows" &
    bitwAnd(as.integer(file.mode(files)), strtoi("100", 8L)) > 0L
  ifelse(exec, "100755", "100644")
}

# The tree of commit `base` (none when NA) with the given entries added or
# replaced, built in a private index.
.cp_tree_with <- function(repo, base, modes, blobs, paths) {
  index <- tempfile("cp-index-")
  on.exit(unlink(index), add = TRUE)
  withr::local_envvar(GIT_INDEX_FILE = index)
  if (!is.na(base)) .cp_git_do(repo, c("read-tree", base))
  info <- tempfile("cp-info-")
  on.exit(unlink(info), add = TRUE)
  writeLines(paste0(modes, " ", blobs, "\t", paths), info, useBytes = TRUE)
  .cp_git_stdin(repo, c("update-index", "--add", "--index-info"), info)
  .cp_git_do(repo, "write-tree")[1]
}

# Commit `tree` on `ref` and return the commit. update-ref names the old
# value, so a ref another process moved since `parent` was read fails here
# rather than being overwritten.
.cp_render_advance <- function(repo, ref, parent, tree, message) {
  msg <- .cp_message_file(message)
  on.exit(unlink(msg), add = TRUE)
  sha <- .cp_git_do(repo, c("commit-tree", tree,
                            if (!is.na(parent)) c("-p", parent),
                            "-F", msg))[1]
  .cp_git_do(repo, c("update-ref", ref, sha,
                     if (is.na(parent)) strrep("0", 40) else parent))
  sha
}

# The blob `path` names in the commit or tree `treeish`, or NA when it lacks
# it.
.cp_blob_at <- function(repo, treeish, path) {
  res <- .cp_git(repo, c("rev-parse", "-q", "--verify",
                         paste0(treeish, ":", path)))
  if (res$ok) res$out[1] else NA_character_
}

# Open the study's repository under the lock, for the render functions. The
# lock is released here if opening fails, and passes to the caller only once
# it succeeds.
.cp_render_open <- function(root, caller) {
  .cp_require_git(caller)
  root <- normalizePath(root, mustWork = TRUE)
  held <- .cp_lock(root, caller)
  opened <- FALSE
  on.exit(if (!opened) .cp_unlock(held), add = TRUE)
  study <- .cp_study(root, caller)
  repo <- .cp_repo_init(root, study$remote)
  refs <- .cp_render_refs(repo)
  opened <- TRUE
  list(root = root, held = held, study = study, repo = repo, refs = refs)
}

#' Commit the study's code before a render
#'
#' Commits the same allow-listed snapshot \code{\link{study_checkpoint}} takes
#' (code, identity and reproducibility files; never data or outputs) to this
#' copy's render source ref in the private repository \code{.checkpoint/repo/},
#' and returns the commit. A render calls it before the job runs, so each
#' figure can print the commit of the code that drew it.
#'
#' @details
#' The job must be in the commit, as the bytes on disk: a job the allow-list
#' leaves out (a symbolic link, a file under a data or estimates folder or one
#' over 50 MB) stops the call rather than returning a commit from which the
#' job cannot be recovered, and so does a job that changes while the snapshot
#' is taken. Files are committed byte for byte, without line-ending
#' conversion, and an executable file keeps its executable bit.
#'
#' A study whose snapshot is unchanged since the last render commit gets that
#' commit back, so re-rendering adds no history and an unchanged job always
#' prints the same commit. The ref is \code{refs/renders/<id>/source}, outside
#' \code{refs/heads/}; records go to a separate ref (see
#' \code{\link{study_render_record}}). The ID belongs to this copy of the study
#' at this path on this host: a study copied or moved elsewhere gets a new one,
#' and keeps the refs it brought with it. Nothing is tagged or pushed, and
#' \code{main}, its tags, \code{HEAD} and the checkpoint working tree are never
#' touched. The call takes the checkpoint lock, so it stops while a checkpoint
#' or another render holds it.
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
  files <- file.path(rc$root, sel$files)
  tree <- .cp_tree_with(rc$repo, NA_character_, .cp_file_modes(files),
                        .cp_hash_files(rc$repo, files), sel$files)
  # Checked before the ref moves, so a failed snapshot is never on it.
  on_disk <- .cp_hash_files(rc$repo, file.path(rc$root, job))
  if (!identical(.cp_blob_at(rc$repo, tree, job), on_disk)) {
    stop("study_render_commit(): ", job, " changed while it was being ",
         "committed; render again", call. = FALSE)
  }
  parent <- .cp_commit_of(rc$repo, rc$refs$source)
  if (!is.na(parent) &&
        identical(.cp_git_do(rc$repo, c("rev-parse",
                                        paste0(parent, "^{tree}")))[1],
                  tree)) {
    return(invisible(parent))
  }
  invisible(.cp_render_advance(rc$repo, rc$refs$source, parent, tree,
                               paste("render", job)))
}

#' Record what a render published
#'
#' Adds a render record to this copy's render records ref, tying every output
#' a render published to the commit its figures print. Records accumulate, so
#' a figure copied into a manuscript can be traced after its job is rendered
#' again.
#'
#' @details
#' The record is written as \code{.hvti-renders/<render_id>.json} in a new
#' commit on \code{refs/renders/<id>/records}, and every later record commit
#' carries it, so the ref's tip holds every record. A \code{render_id} already
#' recorded stops the call; a record is never replaced. The record names
#' \code{commit}, \code{job}, the time, \code{extra} (typically the render's
#' provenance) and, for each file in \code{outputs}, its path relative to the
#' study root and its sha256. A render that fails should publish nothing and
#' record nothing.
#'
#' Everything is checked before the ref moves. \code{commit} must be on this
#' copy's render source ref, which holds only source snapshots that passed
#' their checks, and \code{job} must be in it. Each output must be a regular
#' file inside the study: an absolute path elsewhere, a \code{..} escape or a
#' symbolic link that resolves outside the study stops the call. An output
#' that disappears or changes while it is hashed stops it too.
#'
#' @param render_id Character(1). The render's identifier; names the record.
#' @param commit Character(1). The 40-character commit from
#'   \code{\link{study_render_commit}} that the outputs print.
#' @param job Character(1). The job rendered, relative to the study root.
#' @param outputs Character. Paths of the published files inside the study,
#'   absolute or relative to the study root; each must exist.
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
  caller <- "study_render_record"
  .cp_check_string(render_id, caller, "render_id")
  .cp_check_string(commit, caller, "commit")
  .cp_check_string(job, caller, "job")
  if (!grepl("^[A-Za-z0-9._-]+$", render_id)) {
    stop("study_render_record(): render_id may hold only letters, digits, ",
         "'.', '_' and '-'", call. = FALSE)
  }
  if (!grepl("^[0-9a-f]{40}$", commit)) {
    stop("study_render_record(): commit must be the 40-character ID ",
         "study_render_commit() returned", call. = FALSE)
  }
  if (!is.character(outputs) || anyNA(outputs)) {
    stop("study_render_record(): outputs must be file paths", call. = FALSE)
  }
  if (!is.list(extra)) {
    stop("study_render_record(): extra must be a list", call. = FALSE)
  }
  rc <- .cp_render_open(root, caller)
  on.exit(.cp_unlock(rc$held), add = TRUE)
  source_tip <- .cp_commit_of(rc$repo, rc$refs$source)
  if (is.na(source_tip) ||
        !.cp_git(rc$repo, c("merge-base", "--is-ancestor", commit,
                            source_tip))$ok) {
    stop("study_render_record(): ", commit, " is not a render commit of ",
         "this copy of the study", call. = FALSE)
  }
  if (is.na(.cp_blob_at(rc$repo, commit, job))) {
    stop("study_render_record(): ", job, " is not in render commit ", commit,
         call. = FALSE)
  }
  cfg <- list(root = rc$root)
  paths <- lapply(outputs, .provenance_relative_path, cfg = cfg,
                  caller = caller)
  records_tip <- .cp_commit_of(rc$repo, rc$refs$records)
  record_path <- paste0(.cp_records_dir(), "/", render_id, ".json")
  if (!is.na(records_tip) &&
        !is.na(.cp_blob_at(rc$repo, records_tip, record_path))) {
    stop("study_render_record(): render_id ", render_id, " is already ",
         "recorded, and a record is never replaced", call. = FALSE)
  }
  snaps <- lapply(paths, function(p) {
    snap <- .provenance_file_snapshot(p$absolute, p$relative, caller)
    if (!.provenance_hash_valid(snap$sha256)) {
      stop("study_render_record(): could not hash ", p$relative,
           call. = FALSE)
    }
    list(path = snap$path, sha256 = snap$sha256)
  })
  record <- list(
    render_id = render_id, commit = commit, job = job,
    recorded_at = .cp_utc(Sys.time()), outputs = snaps, extra = extra
  )
  json <- tempfile("cp-record-", fileext = ".json")
  on.exit(unlink(json), add = TRUE)
  writeLines(jsonlite::toJSON(record, auto_unbox = TRUE, null = "null",
                              digits = NA, pretty = TRUE), json)
  tree <- .cp_tree_with(rc$repo, records_tip, "100644",
                        .cp_hash_files(rc$repo, json), record_path)
  .cp_render_advance(rc$repo, rc$refs$records, records_tip, tree,
                     c(paste("record", render_id, "for", job), "",
                       paste("source", commit)))
  invisible(record)
}
