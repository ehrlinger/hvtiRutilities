# Verification and recovery, run from R. Both read systems this package never
# reads (Study Tracker, CORR_STUDIES): the qhsprograms study-setup command does,
# in its own process, from the shared runtime on the LRI servers. The Study
# Tracker credentials are loaded into that process only; R never sees them.

.qhs_paths <- function() {
  list(
    python = "/programs/execs/venvs/study-setup/bin/python",
    command = "/programs/execs/cmd/study-setup",
    tracker_env = path.expand("~/.config/study-setup/tracker.env")
  )
}

# The one place a process starts, so tests replace it and never run one.
.qhs_exec <- function(command, args) {
  system2(command, args)
}

.qhs_study_setup <- function(caller, args, tracker = FALSE) {
  p <- .qhs_paths()
  if (!file.exists(p$python) || !file.exists(p$command)) {
    stop(caller, "(): runs only on the LRI servers; the study-setup ",
         "command was not found at ", p$command, ".", call. = FALSE)
  }
  if (tracker) {
    if (!file.exists(p$tracker_env)) {
      stop(caller, "(): Study Tracker access is not set up for this ",
           "account (no ", p$tracker_env, "). Verifying against Study ",
           "Tracker is planned but not available yet.", call. = FALSE)
    }
    script <- 'set -a; . "$1"; set +a; shift; exec "$@"'
    status <- .qhs_exec("/bin/sh", c("-c", shQuote(script), "sh",
                                     shQuote(c(p$tracker_env, p$python,
                                               p$command, args))))
  } else {
    status <- .qhs_exec(p$python, shQuote(c(p$command, args)))
  }
  if (!identical(as.integer(status), 0L)) {
    stop(caller, "(): study-setup stopped (exit status ", status,
         "); its message is above.", call. = FALSE)
  }
  invisible(TRUE)
}

#' Verify a hand-entered study identity against Study Tracker
#'
#' @description
#' Compares the identity typed into `_study.yml` with the study's Study
#' Tracker record and, when they agree, records it as verified with
#' [study_update_identity()]. Checkpoints held back for an unverified
#' identity are then delivered by [study_checkpoint_push()].
#'
#' @details
#' Runs the qhsprograms `study-setup --verify` command on the LRI servers,
#' which reads Study Tracker with the credentials in
#' `~/.config/study-setup/tracker.env`. Those credentials are loaded into
#' that command's process only. Verification against Study Tracker is
#' planned and not yet available to every account; without the credentials
#' file the function stops and says so.
#'
#' When the typed identity differs from the record, the differences are
#' printed. The command offers to replace the typed identity only when it
#' can ask at a terminal: in R started from a terminal it asks; in RStudio
#' it cannot, and nothing changes. Correct `_study.yml` to match the record
#' and call again.
#'
#' @param root The study root. Defaults to the working directory.
#'
#' @return `TRUE`, invisibly, once the identity is verified. Stops with an
#'   error otherwise.
#'
#' @seealso [study_update_identity()], [study_checkpoint_push()],
#'   [study_status()]
#'
#' @examples
#' \dontrun{
#' # On the LRI servers, from inside the study:
#' study_verify()
#' }
#'
#' @export
study_verify <- function(root = getwd()) {
  root <- normalizePath(root, mustWork = TRUE)
  .qhs_study_setup("study_verify",
                   c("--verify", root),
                   tracker = TRUE)
}

#' Recover a missing `_study.yml` from CORR_STUDIES
#'
#' @description
#' Restores a study's `_study.yml`, and a missing `README.md`, from the
#' study's repository in the CORR_STUDIES project.
#'
#' @details
#' Runs the qhsprograms `study-setup --recover` command on the LRI servers.
#' It first runs a dry run that prints what it would restore, then writes
#' only with consent: `yes = TRUE`, or a yes to the question it asks in an
#' interactive session. A non-interactive call without `yes = TRUE` stops
#' after the dry run and writes nothing. Recovery from
#' CORR_STUDIES is planned and not yet available; until it is, the command
#' stops with its reason.
#'
#' @param st_id The Study Tracker ID, a whole number. Leave it `NULL` when
#'   the command can infer it from the study's repository.
#' @param root The study root. Defaults to the working directory.
#' @param yes `TRUE` to restore without asking. Defaults to `FALSE`.
#'
#' @return `TRUE`, invisibly, once the files are restored; `FALSE`,
#'   invisibly, when the restore is declined. Stops with an error otherwise.
#'
#' @seealso [study_config()], [study_status()]
#'
#' @examples
#' \dontrun{
#' # On the LRI servers, from inside the study:
#' study_recover()
#' study_recover(42)
#' }
#'
#' @export
study_recover <- function(st_id = NULL, root = getwd(), yes = FALSE) {
  if (!is.null(st_id) && !.study_whole_id(st_id)) {
    stop("study_recover(): st_id must be one positive whole number.",
         call. = FALSE)
  }
  root <- normalizePath(root, mustWork = TRUE)
  args <- c("--recover", if (!is.null(st_id)) format(st_id, scientific = FALSE),
            root)
  .qhs_study_setup("study_recover", c(args, "--dry-run"))
  if (!isTRUE(yes)) {
    if (!interactive()) {
      stop("study_recover(): wrote nothing. Check the dry run above, then ",
           "call again with yes = TRUE.", call. = FALSE)
    }
    if (!isTRUE(utils::askYesNo("Restore these files?", default = FALSE))) {
      return(invisible(FALSE))
    }
  }
  .qhs_study_setup("study_recover", c(args, "--yes"))
}
