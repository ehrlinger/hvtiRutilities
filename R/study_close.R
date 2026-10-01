# Closing and reopening, following the StudyTracker Workspace API's Closure
# and Reopening rules. Closing always takes a final snapshot; reopening only
# tags. A study is closed when its latest closed-* tag has no reopened-* tag
# after it, where "latest" is position on main's first-parent history, never
# a tag timestamp (spec 2026-10-01). Both write their outbox entry before any
# git change and complete it after, as study_checkpoint() does.

.cp_outcomes <- function() c("published", "not_published", "superseded", "abandoned")

# Closed when the latest closure event on HEAD's first-parent history is a
# closed-* tag. Local and fetched remote tags both count, resolved to their
# commits and de-duplicated by (family, commit), so a commit known under two
# names is one event. On one commit a reopening follows its closure: a
# closure always makes a new commit, and a reopening only tags HEAD. A remote
# tag whose commit is not on that history only means this copy is behind, and
# is ignored. A LOCAL tag off that history (delivery interrupted between
# moving main and retagging) is an event that cannot be placed, so the state
# is unknown and the result is NA: ignoring it would allow a second close.
.cp_is_closed <- function(root) {
  repo <- .cp_repo_path(root)
  if (!.cp_has_repo(repo) || is.na(.cp_head(repo))) return(FALSE)
  refs <- .cp_git_do(repo, c("for-each-ref", "--format=%(refname)",
                             "refs/tags", "refs/remote-tags"))
  name <- sub("^refs/(remote-)?tags/", "", refs)
  family <- ifelse(grepl("^closed-[a-z_]+-[0-9]+$", name), "closed",
                   ifelse(grepl("^reopened-[0-9]+$", name), "reopened", NA))
  refs <- refs[!is.na(family)]
  family <- family[!is.na(family)]
  if (!length(refs)) return(FALSE)
  commits <- .cp_git_do(repo, c("rev-parse", paste0(refs, "^{commit}")))
  history <- .cp_git_do(repo, c("rev-list", "--first-parent", "HEAD"))
  # rev-list lists newest first, so the latest event has the smallest position.
  pos <- match(commits, history)
  if (any(startsWith(refs, "refs/tags/") & is.na(pos))) return(NA)
  if (all(is.na(pos))) return(FALSE)
  latest <- family[which(pos == min(pos, na.rm = TRUE))]
  !"reopened" %in% latest
}

# Bring HEAD up to the remote's main before a closure guard, so every pushed
# closed-* and reopened-* tag sits on its history. Pending entries go through
# .cp_deliver(), which fetches, replays and retargets them. With nothing
# pending, fetch and fast-forward only when HEAD is an ancestor of
# origin/main: there is no entry to retarget, so the log cannot be left
# naming a stale commit. Returns TRUE when the sync reached the remote; when
# it did not and a remote is configured, says that closure state reflects
# this copy only. Never stops.
.cp_sync <- function(root, study) {
  if (is.null(study$remote)) return(invisible(FALSE))
  repo <- .cp_repo_init(root, study$remote)
  ancestor <- function(a, b) .cp_git(repo, c("merge-base", "--is-ancestor", a, b))$ok
  has_origin <- function() !is.na(.cp_commit_of(repo, "refs/remotes/origin/main"))
  why <- NULL
  if (!study$verified) {
    why <- "an unverified study does not read the remote"
  } else {
    log <- .cp_log_read(root)
    pending <- which(vapply(log, function(e) {
      identical(e$state, "committed") && identical(e$delivery$git, "pending")
    }, logical(1)))
    if (length(pending)) {
      log <- .cp_deliver(root, study)
      reasons <- unlist(lapply(log[pending], function(e) e$delivery$reason))
      if (any(grepl("^(remote unreachable|git fetch)", reasons))) {
        why <- "the remote could not be reached"
      } else if (has_origin() && !ancestor("refs/remotes/origin/main", "HEAD")) {
        why <- "this copy could not be replayed onto the remote"
      }
    } else {
      why <- .cp_fast_forward(repo, ancestor, has_origin)
    }
  }
  if (!is.null(why)) {
    message("Closure state is from this copy's last fetch and may be out of ",
            "date: ", why, ".")
  }
  invisible(is.null(why))
}

# The nothing-pending half of .cp_sync(): fetch with .cp_push()'s refspecs
# and fast-forward. Returns NULL on success, otherwise why it stopped short.
.cp_fast_forward <- function(repo, ancestor, has_origin) {
  probe <- .cp_remote_probe(repo)
  if (!probe$reachable) return("the remote could not be reached")
  refspecs <- "+refs/tags/*:refs/remote-tags/*"
  if (probe$has_main) {
    refspecs <- c("+refs/heads/main:refs/remotes/origin/main", refspecs)
  }
  fetched <- .cp_git(repo, c("fetch", "-q", "--no-tags", "origin", refspecs))
  if (!fetched$ok) return("the remote could not be reached")
  if (!probe$has_main || !has_origin()) return(NULL)
  if (is.na(.cp_head(repo)) || ancestor("HEAD", "refs/remotes/origin/main")) {
    .cp_git_do(repo, c("reset", "-q", "--hard", "refs/remotes/origin/main"))
    return(NULL)
  }
  if (ancestor("refs/remotes/origin/main", "HEAD")) return(NULL)
  "this copy has diverged from the remote"
}

.cp_unknown_reason <- function() {
  paste0("closure state cannot be determined from this copy: a closed-* or ",
         "reopened-* tag is not on main")
}

.cp_stop_unknown <- function(caller) {
  stop(caller, "(): ", .cp_unknown_reason(), ". Run study_checkpoint_push() ",
       "while the remote is reachable; see ?study_checkpoint_push.",
       call. = FALSE)
}

# Field checks only, so they run before anything is written. doi and pmid are
# read with [[ ]] so a field such as doi_url cannot stand in for them.
.cp_check_publication <- function(publication) {
  given <- function(k) {
    v <- publication[[k]]
    !is.null(v) && length(v) == 1L && !is.na(v) && nzchar(as.character(v))
  }
  required <- c("title", "journal", "accepted_on", "published_on")
  missing <- required[!vapply(required, given, logical(1))]
  if (!given("doi") && !given("pmid")) missing <- c(missing, "doi or pmid")
  if (length(missing)) {
    stop("study_close(): outcome 'published' needs publication fields: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  lapply(publication, function(v) if (inherits(v, "Date")) .cp_date(v) else v)
}

# Reads the tags of an existing repository; a study with none has no
# manuscript_published checkpoint, so nothing needs creating to answer.
.cp_check_published_tag <- function(root) {
  repo <- .cp_repo_path(root)
  has <- .cp_has_repo(repo) &&
    length(.cp_tags(repo, "^manuscript_published-[0-9]+$")) > 0L
  if (!has) {
    stop("study_close(): outcome 'published' needs a manuscript_published ",
         "checkpoint first; run study_checkpoint(\"manuscript_published\")",
         call. = FALSE)
  }
}

# One whole positive number, given as an integer, a double or a string.
.cp_check_superseded_by <- function(superseded_by) {
  sb <- if (is.numeric(superseded_by) || is.character(superseded_by)) {
    suppressWarnings(as.numeric(superseded_by))
  }
  if (length(sb) != 1L || is.na(sb) || sb < 1 || sb != round(sb) ||
        sb > .Machine$integer.max) {
    stop("study_close(): outcome 'superseded' needs superseded_by, one ST ",
         "number", call. = FALSE)
  }
  as.integer(sb)
}

.cp_check_string <- function(x, caller, what) {
  if (!is.character(x) || length(x) != 1L || is.na(x)) {
    stop(caller, "(): ", what, " must be one character string", call. = FALSE)
  }
}

#' Close or reopen a study
#'
#' @description
#' \code{study_close()} records how a study ended: it takes a final
#' checkpoint snapshot, tags it \code{closed-<outcome>-<n>} and records a
#' closure in the outbox. It does not make the study read-only: the folder
#' stays writable, and a checkpoint taken on a closed study is still recorded,
#' with a warning. The closure tag is what fixes the code as it stood at
#' closure. \code{study_reopen()} records a reopening and tags the current
#' snapshot \code{reopened-<n>}; the next checkpoint snapshots as
#' usual. A study may be closed and reopened any number of times, and every
#' cycle is kept.
#'
#' @details
#' The outcomes follow the StudyTracker closure rules:
#' \itemize{
#'   \item \code{"published"} needs \code{publication} (\code{title},
#'     \code{journal}, \code{accepted_on}, \code{published_on}, and at least
#'     one of \code{doi} and \code{pmid}) and an earlier
#'     \code{"manuscript_published"} checkpoint.
#'   \item \code{"superseded"} needs \code{superseded_by}, the ST number of
#'     the study that replaced it.
#'   \item \code{"not_published"} and \code{"abandoned"} need nothing further.
#' }
#' These rules are checked before anything is written, so a close made
#' offline fails at once rather than when the outbox is delivered.
#'
#' Whether the study is closed is read from the latest \code{closed-*} or
#' \code{reopened-*} tag on the checkpoint history, counting tags pushed from
#' other copies of the study. Before deciding, both functions sync with the
#' remote, delivering any pending checkpoints first. When the remote cannot
#' be reached, a message says that the closure state is from this copy's last
#' fetch and may be out of date. When a closure or reopening tag in this copy
#' is not on its history, which an interrupted delivery can leave, the state
#' cannot be determined and both functions stop; run
#' \code{\link{study_checkpoint_push}} while the remote is reachable.
#'
#' \code{reason} is written to the snapshot, the tag and the outbox, so it
#' leaves the study folder. A message says so whenever it is given: it must
#' not contain patient information.
#'
#' @param outcome Character(1). One of \code{"published"},
#'   \code{"not_published"}, \code{"superseded"} or \code{"abandoned"}.
#' @param reason Optional character(1). For \code{study_reopen()}, required.
#' @param publication Named list of publication details; required for
#'   \code{"published"}.
#' @param superseded_by One whole positive number, the ST number, given as an
#'   integer, a double or a string; required for \code{"superseded"}.
#' @param closed_at,reopened_at Date of the event. Defaults to today.
#' @param new_lead Optional character(1), the username of a new study lead.
#' @param root Character. Study root. Defaults to \code{study_root()}.
#'
#' @return An object of class \code{"study_checkpoint"}, returned invisibly.
#'
#' @seealso \code{\link{study_checkpoint}}, \code{\link{study_status}}
#'
#' @export
#'
#' @examples
#' \donttest{
#' if (nzchar(Sys.which("git"))) {
#'   root <- file.path(tempdir(), "close-example")
#'   study_setup(root, "Close example", 1267L)
#'   # A throwaway identity, so the example commits on a machine with no
#'   # git user configured.
#'   withr::with_envvar(c(GIT_AUTHOR_NAME = "Example",
#'                        GIT_AUTHOR_EMAIL = "example@example.org",
#'                        GIT_COMMITTER_NAME = "Example",
#'                        GIT_COMMITTER_EMAIL = "example@example.org"), {
#'     study_close("abandoned", reason = "PI left", root = root)
#'     study_reopen("new PI", root = root)
#'   })
#'   unlink(root, recursive = TRUE)
#' }
#' }
study_close <- function(outcome, reason = NULL, publication = NULL,
                        superseded_by = NULL, closed_at = Sys.Date(),
                        root = study_root()) {
  .cp_require_git("study_close")
  root <- normalizePath(root, mustWork = TRUE)
  held <- .cp_lock(root, "study_close")
  on.exit(.cp_unlock(held), add = TRUE)
  .cp_reconcile(root)
  study <- .cp_study(root, "study_close")
  if (length(outcome) != 1L || is.na(outcome) || !outcome %in% .cp_outcomes()) {
    stop("study_close(): outcome must be one of ",
         paste(.cp_outcomes(), collapse = ", "),
         if (identical(outcome, "unrecorded")) {
           "; 'unrecorded' is reserved for the legacy migration"
         },
         call. = FALSE)
  }
  if (!is.null(reason)) .cp_check_string(reason, "study_close", "reason")
  if (outcome == "published") {
    publication <- .cp_check_publication(publication)
  }
  if (outcome == "superseded") {
    superseded_by <- .cp_check_superseded_by(superseded_by)
  }
  # Spec 6.1 step 1 and spec 2026-10-01 3.2: clone or sync with the remote
  # first, so the tag guards below see closures made from other copies.
  .cp_sync(root, study)
  closed <- .cp_is_closed(root)
  if (is.na(closed)) .cp_stop_unknown("study_close")
  if (closed) {
    stop("study_close(): the study is already closed; run study_reopen() ",
         "first", call. = FALSE)
  }
  if (outcome == "published") .cp_check_published_tag(root)
  .cp_free_text_notice(reason)

  entry <- list(
    type = "closure", closure_id = uuid::UUIDgenerate(), st_id = study$st_id,
    workspace_id = study$workspace_id, outcome = outcome,
    closed_at = .cp_date(closed_at), reason = reason,
    publication = publication, superseded_by = superseded_by,
    git_commit = NULL, tag = NULL, state = NULL,
    delivery = list(git = "none", st = "pending")
  )
  tag_fn <- function(repo) {
    tags <- .cp_tags(repo, "^closed-[a-z_]+-[0-9]+$")
    n <- if (length(tags)) max(.cp_seq_of(tags)) + 1L else 1L
    paste0("closed-", outcome, "-", n)
  }
  snap <- .cp_snapshot(root, study, tag_fn, entry, "study_close", held)
  .cp_lock_touch(held)
  .cp_deliver(root, study)
  invisible(.cp_result(.cp_or(.cp_log_find(root, entry$closure_id),
                              snap$entry), snap))
}

#' @rdname study_close
#' @export
study_reopen <- function(reason, new_lead = NULL, reopened_at = Sys.Date(),
                         root = study_root()) {
  .cp_require_git("study_reopen")
  root <- normalizePath(root, mustWork = TRUE)
  held <- .cp_lock(root, "study_reopen")
  on.exit(.cp_unlock(held), add = TRUE)
  .cp_reconcile(root)
  study <- .cp_study(root, "study_reopen")
  if (missing(reason) || !is.character(reason) || length(reason) != 1L ||
        is.na(reason) || !nzchar(reason)) {
    stop("study_reopen(): a reason is required, as one character string",
         call. = FALSE)
  }
  if (!is.null(new_lead)) .cp_check_string(new_lead, "study_reopen", "new_lead")
  .cp_sync(root, study)
  closed <- .cp_is_closed(root)
  if (is.na(closed)) .cp_stop_unknown("study_reopen")
  if (!closed) {
    stop("study_reopen(): the study is not closed", call. = FALSE)
  }
  .cp_free_text_notice(reason)
  repo <- .cp_repo_init(root, study$remote)
  # max + 1, not a count: delivery renumbers past remote tags, leaving gaps.
  tag <- .cp_next_tag(repo, "reopened")
  entry <- list(
    type = "reopening", reopening_id = uuid::UUIDgenerate(),
    st_id = study$st_id, workspace_id = study$workspace_id,
    reopened_at = .cp_date(reopened_at), reason = reason, new_lead = new_lead,
    git_commit = NULL, tag = tag, state = "committing",
    delivery = list(git = "pending", st = "pending")
  )
  id <- entry$reopening_id
  .cp_log_append(root, entry)
  done <- FALSE
  tagged <- FALSE
  undo <- function() {
    if (tagged) .cp_git(repo, c("tag", "-d", tag))
    try(.cp_log_update(root, id, list(state = "abandoned")), silent = TRUE)
  }
  # Ahead of the unlock, so the entry is settled while the lock is held.
  on.exit(if (!done) undo(), add = TRUE, after = FALSE)
  sha <- .cp_tag_head(repo, tag, .cp_tag_message(entry))
  tagged <- TRUE
  entry <- .cp_log_update(root, id, list(state = "committed", git_commit = sha))
  done <- TRUE
  .cp_lock_touch(held)
  .cp_deliver(root, study)
  invisible(.cp_result(.cp_or(.cp_log_find(root, id), entry), NULL))
}
