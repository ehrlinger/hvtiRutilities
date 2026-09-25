# Study checkpoints: an allow-listed snapshot of the study committed and
# tagged in .checkpoint/repo and recorded in the outbox, then delivered. The
# outbox entry is written (state: committing) before any git change and
# completed after it, so a tag never exists without an entry; delivery never
# undoes a local checkpoint.

.cp_tag_message <- function(entry) {
  body <- entry[setdiff(names(entry), c("delivery", "git_commit", "tag", "state"))]
  c(paste0(entry$type, " ", entry$tag, " (ST ", entry$st_id, ")"), "",
    strsplit(yaml::as.yaml(body), "\n", fixed = TRUE)[[1]])
}

.cp_commit_of <- function(repo, ref) {
  res <- .cp_git(repo, c("rev-parse", "-q", "--verify", paste0(ref, "^{commit}")))
  if (res$ok) res$out[1] else NA_character_
}

# Spec 5.1a: free text leaves the study folder, so say so whenever any is
# given. A message rather than a warning: study_reopen() always has a reason.
.cp_free_text_notice <- function(...) {
  given <- vapply(list(...), function(v) {
    vals <- unlist(v, use.names = FALSE)
    length(vals) > 0L && any(!is.na(vals) & nzchar(as.character(vals)))
  }, logical(1))
  if (any(given)) {
    message("note/reason/attributes leave the study folder (git and ST); ",
            "they must not contain patient information.")
  }
  invisible(any(given))
}

# A crash can land the commit on main before the crash prevents the tag from
# being written. The commit and tag share the same message file, so main's
# HEAD names the entry id when this happened; with no tag pointing at HEAD,
# that commit was never delivered and must not seed the next checkpoint or be
# reachable for a later push. Move main back to HEAD's parent, or drop the
# branch entirely when HEAD had none.
.cp_reconcile_orphan <- function(repo, id) {
  head <- .cp_head(repo)
  if (is.na(head)) return(invisible(FALSE))
  msg <- .cp_git(repo, c("log", "-1", "--format=%B", "HEAD"))
  if (!msg$ok || !any(grepl(id, msg$out, fixed = TRUE))) {
    return(invisible(FALSE))
  }
  at_head <- .cp_git(repo, c("tag", "--points-at", "HEAD"))
  if (at_head$ok && any(nzchar(at_head$out))) return(invisible(FALSE))
  parent <- .cp_git(repo, c("rev-parse", "-q", "--verify", "HEAD~1"))
  if (parent$ok) {
    .cp_git_do(repo, c("reset", "-q", "--hard", "HEAD~1"))
  } else {
    .cp_git_do(repo, c("update-ref", "-d", "refs/heads/main"))
  }
  invisible(TRUE)
}

# Repair entries a crash left in state "committing". The tag message carries
# the entry id, so a tag that names the id proves the commit and tag both
# happened: the entry is completed from it. Otherwise the entry is abandoned,
# never to be delivered; the commit may still have landed without its tag,
# which .cp_reconcile_orphan() removes from main. Entries are visited newest
# first, so orphans stacked by successive crashes peel from the top.
.cp_reconcile <- function(root) {
  log <- .cp_log_read(root)
  open <- which(vapply(log, function(e) identical(e$state, "committing"),
                       logical(1)))
  if (!length(open)) return(invisible(log))
  repo <- .cp_repo_path(root)
  has_repo <- .cp_has_repo(repo)
  for (i in rev(open)) {
    e <- log[[i]]
    sha <- NA_character_
    if (has_repo && !is.null(e$tag)) {
      msg <- .cp_git(repo, c("tag", "-l", "--format=%(contents)", e$tag))
      if (msg$ok && any(grepl(.cp_entry_id(e), msg$out, fixed = TRUE))) {
        sha <- .cp_commit_of(repo, e$tag)
      }
    }
    if (is.na(sha)) {
      log[[i]]$state <- "abandoned"
      if (has_repo) .cp_reconcile_orphan(repo, .cp_entry_id(e))
    } else {
      log[[i]]$state <- "committed"
      log[[i]]$git_commit <- sha
    }
  }
  .cp_log_write(root, log)
  invisible(log)
}

# Select, copy, describe, log, commit, tag and complete the log entry.
# `tag_fn(repo)` names the tag, so checkpoints, closures and the unnumbered
# workspace_created share one transaction. Any failure puts the repository
# back as it was and, once the entry exists, marks it abandoned.
.cp_snapshot <- function(root, study, tag_fn, entry, caller, held = NULL) {
  repo <- .cp_repo_init(root, study$remote)
  tag <- tag_fn(repo)
  sel <- .cp_select(root, study$include)
  .cp_lock_touch(held)
  if (nrow(sel$skipped)) {
    warning(caller, "(): skipped over the 50 MB cap: ",
            paste(sel$skipped$path, collapse = ", "), call. = FALSE)
  }
  id <- .cp_entry_id(entry)
  head_before <- .cp_head(repo)
  logged <- FALSE
  done <- FALSE
  undo <- function() {
    .cp_rollback(repo, head_before, tag)
    if (logged) {
      try(.cp_log_update(root, id, list(state = "abandoned")), silent = TRUE)
    }
  }
  on.exit(if (!done) undo(), add = TRUE)

  entry$tag <- tag
  .cp_sync_tree(repo, root, sel$files)
  .cp_write_meta(repo, root, entry, sel)
  .cp_lock_touch(held)
  entry$state <- "committing"
  entry$delivery$git <- "pending"
  .cp_log_append(root, entry)
  logged <- TRUE
  sha <- .cp_commit_tag(repo, tag, .cp_tag_message(entry))
  entry <- .cp_log_update(root, id, list(state = "committed", git_commit = sha))
  done <- TRUE
  .cp_lock_touch(held)
  list(entry = entry, selection = sel, repo = repo)
}

# attributes travel to CHECKPOINT.yml, the tag and the ST record as flat
# key: value pairs, so only a named list of single atomic values is taken.
.cp_check_attributes <- function(attributes, caller) {
  if (is.null(attributes)) return(invisible(NULL))
  nms <- names(attributes)
  ok <- is.list(attributes) && !is.object(attributes) &&
    (!length(attributes) ||
       (!is.null(nms) && all(!is.na(nms) & nzchar(nms)) &&
          all(vapply(attributes, function(v) is.atomic(v) && length(v) == 1L,
                     logical(1)))))
  if (!ok) {
    stop(caller, "(): attributes must be NULL or a named list of single ",
         "values, for example list(journal = \"JTCVS\")", call. = FALSE)
  }
  invisible(attributes)
}

.cp_log_find <- function(root, id) {
  for (e in .cp_log_read(root)) {
    if (identical(.cp_entry_id(e), id)) return(e)
  }
  NULL
}

.cp_result <- function(entry, snap) {
  structure(
    list(type = entry$type, tag = entry$tag, commit = entry$git_commit,
         files = if (is.null(snap)) 0L else length(snap$selection$files),
         skipped = if (is.null(snap)) NULL else snap$selection$skipped,
         delivery = entry$delivery, entry = entry),
    class = "study_checkpoint"
  )
}

#' Record a study checkpoint
#'
#' @description
#' Commits an allow-listed snapshot of the study (code, identity and
#' reproducibility files) to a private git repository in
#' \code{.checkpoint/repo/}, tags it with the checkpoint kind and a sequence
#' number, records it in the outbox \code{.checkpoint/log.yml}, and pushes it
#' when \code{_study.yml} names a remote. Known data formats, credentials and
#' symbolic links are never committed, even through \code{include:} patterns,
#' and neither is anything under \code{00_datasets/} or \code{90_estimates/}
#' or an output file type. Files in
#' \code{50_documents/} other than \code{.qmd} and \code{.bib} sources are not
#' committed; \code{CHECKPOINT.yml} records their size and checksum.
#'
#' @details
#' The kind comes from the StudyTracker checkpoint vocabulary, for example
#' \code{"abstract_submitted"} or \code{"manuscript_submitted"}. Automatic
#' kinds such as \code{"data_received"} are logged without a snapshot.
#' A checkpoint is committed locally before anything is pushed, so an
#' unreachable remote never loses one; \code{\link{study_checkpoint_push}}
#' retries later.
#'
#' One session at a time: this function, \code{\link{study_checkpoint_push}},
#' \code{\link{study_close}} and \code{study_reopen()} hold the lock
#' \code{.checkpoint/lock} while they run. A call that finds it held by
#' another session stops, naming the holder; retry once that session has
#' finished. The holder refreshes the lock between phases (selection, the
#' snapshot's \code{CHECKPOINT.yml}, the commit and tag, delivery), so a lock
#' not refreshed for 6 hours was left by a crashed session and is taken over
#' with a warning.
#'
#' \code{note} and \code{attributes} are written to the snapshot, the tag and
#' the outbox, so they leave the study folder. A message says so whenever
#' either is given: they must not contain patient information.
#'
#' @param kind Character(1). A checkpoint kind.
#' @param note Optional character(1), stored with the checkpoint.
#' @param attributes Optional named list of kind-specific details, each a
#'   single value, for example \code{list(journal = "JTCVS")}.
#' @param occurred_at Date the event happened. Defaults to today.
#' @param root Character. Study root. Defaults to \code{study_root()}.
#'
#' @return An object of class \code{"study_checkpoint"}, returned invisibly,
#'   with the tag, commit, file count, skipped files and delivery states.
#'
#' @seealso \code{\link{study_checkpoint_push}}, \code{\link{study_close}},
#'   \code{\link{study_status}}
#'
#' @export
#'
#' @examples
#' \donttest{
#' if (nzchar(Sys.which("git"))) {
#'   root <- file.path(tempdir(), "checkpoint-example")
#'   study_setup(root, "Checkpoint example", 1267L)
#'   writeLines("x <- 1", file.path(root, "30_analyses", "fit.R"))
#'   # A throwaway identity, so the example commits on a machine with no
#'   # git user configured.
#'   withr::with_envvar(c(GIT_AUTHOR_NAME = "Example",
#'                        GIT_AUTHOR_EMAIL = "example@example.org",
#'                        GIT_COMMITTER_NAME = "Example",
#'                        GIT_COMMITTER_EMAIL = "example@example.org"), {
#'     cp <- study_checkpoint("abstract_submitted", root = root)
#'     print(cp$tag)
#'   })
#'   unlink(root, recursive = TRUE)
#' }
#' }
study_checkpoint <- function(kind, note = NULL, attributes = NULL,
                             occurred_at = Sys.Date(), root = study_root()) {
  .cp_require_git("study_checkpoint")
  root <- normalizePath(root, mustWork = TRUE)
  held <- .cp_lock(root, "study_checkpoint")
  on.exit(.cp_unlock(held), add = TRUE)
  .cp_reconcile(root)
  study <- .cp_study(root, "study_checkpoint")
  row <- .cp_kind_check(.cp_kinds(root), kind, "study_checkpoint")
  if (!is.null(note)) .cp_check_string(note, "study_checkpoint", "note")
  .cp_check_attributes(attributes, "study_checkpoint")
  if (.cp_is_closed(root)) {
    warning("study_checkpoint(): the study is closed; recording the ",
            "checkpoint anyway", call. = FALSE)
  }
  .cp_free_text_notice(note, attributes)

  entry <- list(
    type = "checkpoint", checkpoint_id = uuid::UUIDgenerate(),
    st_id = study$st_id, workspace_id = study$workspace_id, kind = kind,
    occurred_at = .cp_date(occurred_at), trigger = row$trigger,
    artifact = NULL, git_commit = NULL, note = note, attributes = attributes,
    tag = NULL, state = NULL, delivery = list(git = "none", st = "pending")
  )

  if (!identical(row$trigger, "manual")) {
    entry$state <- "recorded"
    .cp_log_append(root, entry)
    # Spec 6.1: every call retries pending deliveries, snapshot or not.
    .cp_lock_touch(held)
    .cp_deliver(root, study)
    return(invisible(.cp_result(entry, NULL)))
  }

  tag_fn <- function(repo) {
    if (row$numbered) return(.cp_next_tag(repo, kind))
    if (length(.cp_tags(repo, paste0("^", kind, "$")))) {
      stop("study_checkpoint(): '", kind, "' is already recorded for this ",
           "study", call. = FALSE)
    }
    kind
  }
  snap <- .cp_snapshot(root, study, tag_fn, entry, "study_checkpoint", held)
  .cp_lock_touch(held)
  .cp_deliver(root, study)
  final <- .cp_or(.cp_log_find(root, entry$checkpoint_id), snap$entry)
  if (identical(kind, "manuscript_published")) {
    message("The study can now be closed as published: ",
            "study_close(\"published\", publication = list(...))")
  }
  invisible(.cp_result(final, snap))
}

#' @export
print.study_checkpoint <- function(x, ...) {
  cat(x$type, if (!is.null(x$tag)) paste0(" ", x$tag), "\n", sep = "")
  cat("  commit:   ", .cp_or(x$commit, "none (no snapshot)"), "\n", sep = "")
  cat("  files:    ", x$files, "\n", sep = "")
  cat("  git:      ", x$delivery$git,
      if (!is.null(x$delivery$reason)) paste0(" (", x$delivery$reason, ")"),
      "\n", sep = "")
  cat("  ST:       ", x$delivery$st, "\n", sep = "")
  invisible(x)
}

#' Push pending study checkpoints
#'
#' @description
#' Retries delivery of every checkpoint, closure and reopening in
#' \code{.checkpoint/log.yml} that has not reached the remote yet.
#' \code{\link{study_checkpoint}} does this on every call; use this function
#' after a network outage, or once \code{study-setup --verify} has verified a
#' manually entered identity.
#'
#' @details
#' An entry that a crash left half-written is settled first: completed when
#' its tag exists, otherwise marked \code{abandoned}. Abandoned entries are
#' never pushed.
#'
#' @param root Character. Study root. Defaults to \code{study_root()}.
#'
#' @return A data frame, returned invisibly, with one row per logged event and
#'   columns \code{type}, \code{tag}, \code{state}, \code{git}, \code{st} and
#'   \code{reason}.
#'
#' @section Repairing a stuck delivery:
#' Two failures leave an entry pending in a way that retrying
#' \code{study_checkpoint_push()} cannot fix by itself. Each is reported as a
#' warning that names the tag and points back here.
#'
#' \itemize{
#'   \item \strong{Not on main} (a log write was lost after a replay).
#'   Find the commit on \code{main} whose message carries the entry's id
#'   (\code{checkpoint_id} for a checkpoint, \code{closure_id} for a closure,
#'   \code{reopening_id} for a reopening):
#'   \code{git -C .checkpoint/repo log --fixed-strings --grep=<id>
#'   --format=\%H main}. If a commit is found, set the entry's
#'   \code{git_commit} in \code{.checkpoint/log.yml} to that commit, keep the
#'   old value as \code{replayed_from}, then run \code{study_checkpoint_push()}
#'   again. If no such commit exists, set the entry's \code{state} to
#'   \code{"abandoned"} instead; an abandoned entry is never delivered.
#'   \item \strong{Unnumbered tag clash} (two copies of the study each
#'   recorded the same unnumbered tag, for example \code{workspace_created}).
#'   The two copies have diverged. Keep one copy's \code{.checkpoint/}
#'   directory, normally the one whose history is already on the remote,
#'   move the other copy's \code{.checkpoint/} aside, and run
#'   \code{study_checkpoint_push()} again from the kept copy.
#' }
#'
#' @seealso \code{\link{study_checkpoint}}
#'
#' @export
study_checkpoint_push <- function(root = study_root()) {
  .cp_require_git("study_checkpoint_push")
  root <- normalizePath(root, mustWork = TRUE)
  held <- .cp_lock(root, "study_checkpoint_push")
  on.exit(.cp_unlock(held), add = TRUE)
  .cp_reconcile(root)
  study <- .cp_study(root, "study_checkpoint_push")
  .cp_lock_touch(held)
  invisible(.cp_log_frame(.cp_deliver(root, study)))
}
