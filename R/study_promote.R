# R/study_promote.R
#' Give an exploration its own Study Tracker ID
#'
#' @description
#' An exploration set up with \code{study_setup(derived_from = )} has a
#' \code{provisional_id} and no Study Tracker ID of its own. Once the Tracker
#' has registered it, \code{study_promote()} writes that ID into
#' \code{_study.yml} and removes \code{provisional_id}. \code{derived_from}
#' and \code{workspace_id} stay, so the lineage to the parent study is kept.
#' Checkpoints held locally while the study was provisional are pushed by the
#' next \code{\link{study_checkpoint_push}}; their tags are unchanged.
#' Checkpoint commits and tag messages made while the study was provisional
#' keep the provisional ID; they are pushed unchanged.
#'
#' @param study_tracker_id The study's new Study Tracker ID, one positive
#'   integer.
#' @param start A directory in the study. The study is found as by
#'   \code{\link{study_config}}.
#' @return The number of checkpoint entries rewritten, invisibly. A rerun
#'   after an interrupted promotion rewrites the entries again, and the
#'   provisional ID already recorded is kept. A study that is already
#'   promoted, or whose \file{_study.yml} still has a legacy \code{st_id}
#'   key, is refused, as is one whose checkpoint repository is not on
#'   \code{main}. A rerun with a different ID rewrites every entry to it.
#' @seealso \code{\link{study_setup}}, \code{\link{study_update_identity}}
#' @examples
#' root <- file.path(tempdir(), "promote-example")
#' invisible(study_setup(root, study = "Example exploration",
#'                       derived_from = 1L, renv = FALSE))
#' study_promote(2L, start = root)
#' unlink(root, recursive = TRUE)
#' @export
study_promote <- function(study_tracker_id, start = ".") {
  id <- .study_check_id(study_tracker_id, "study_tracker_id", "study_promote")
  cfg <- study_config(start, require_data = FALSE)
  raw <- .read_study_yml(cfg$file, "study_promote")
  state <- .study_identity_state(raw)
  if (!identical(state, "provisional")) {
    if (state %in% c("registered", "promoted")) {
      stop("study_promote(): ", cfg$file, " already has Study Tracker ID ",
           raw$study_tracker_id, call. = FALSE)
    }
    stop("study_promote(): ", cfg$file, " is not a provisional exploration",
         call. = FALSE)
  }
  if (!is.null(raw$st_id)) {
    stop("study_promote(): ", cfg$file, " has a legacy st_id key; remove ",
         "it before promoting", call. = FALSE)
  }
  if (identical(id, as.integer(raw$derived_from))) {
    warning("study_promote(): ", id, " is the parent's own ID; the ",
            "exploration's checkpoints will be filed under the parent study",
            call. = FALSE)
  }
  # The outbox first: its entries are posted to the Workspace API unchanged,
  # so none may keep the provisional string once the study can deliver. If
  # this is interrupted before _study.yml is written, the study is still
  # provisional and a rerun repeats the (idempotent) rewrite.
  root <- dirname(cfg$file)
  lock <- .cp_lock(root, "study_promote")
  on.exit(.cp_unlock(lock), add = TRUE)
  # Reconciliation can reset the checkpoint repository, so it must not run
  # against a checkout that is off main. Both are no-ops with no repository.
  .cp_check_main(root, "study_promote")
  .cp_reconcile(root)
  log <- .cp_log_read(root)
  # Automatic kinds are logged "recorded" with no "provisional" reason, so
  # select on the provisional string itself as well as on the reason.
  # An entry rewritten by an interrupted promotion has an integer st_id and
  # the exploration's provisional_id: a retry with another ID takes it too.
  held <- which(vapply(log, function(e) {
    is.character(e$st_id) || identical(e$delivery$reason, "provisional") ||
      identical(e$provisional_id, raw$provisional_id)
  }, logical(1)))
  for (i in held) {
    # Keep only a still-provisional (character) st_id: an entry rewritten
    # earlier and re-held by a later checkpoint has the integer already.
    if (is.character(log[[i]]$st_id)) log[[i]]$provisional_id <- log[[i]]$st_id
    log[[i]]$st_id <- id
    if (identical(log[[i]]$delivery$reason, "provisional")) {
      log[[i]]$delivery["reason"] <- list(NULL)
    }
  }
  if (length(held)) .cp_log_write(root, log)
  raw <- append(raw[names(raw) != "provisional_id"],
                list(study_tracker_id = id), after = 1L)
  .study_write_atomic(raw, cfg$file)
  invisible(length(held))
}
