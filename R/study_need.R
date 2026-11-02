#' Install a package a study needs, or say how
#'
#' @description
#' Called where a function needs a package the study may not have, such as
#' \pkg{arrow} for registered data. In the study's active renv project the
#' packages are declared (see \code{\link{study_declare}}); a missing one is
#' installed into the study's library after one question, when the session is
#' interactive, and recorded in \code{renv.lock}. Otherwise the call stops and
#' names \code{hvtiR::setup()}, which installs everything a study needs.
#'
#' Nothing is declared until every package is installed: if the user declines
#' the install, or it fails, the study's \code{DESCRIPTION} is left as it was.
#'
#' A package that is installed but absent from \code{renv.lock} is declared and
#' recorded too, because a restore would not bring it back otherwise. Recording
#' takes one question, since the snapshot also moves every other package in the
#' lock to the version in the library. The caller already has what it needs, so
#' when the package cannot be recorded (the session is not interactive, the
#' question is declined, \code{\link{guard_snapshot}} refuses, or the snapshot
#' fails) the call warns and carries on. Base packages, which renv never locks, are left out.
#'
#' An installed package is never upgraded, whatever its version: moving a
#' study's package versions is \code{hvtiR::update()}'s job.
#'
#' @param packages Character. Package names.
#' @param root Character(1). The study root; by default the study enclosing the
#'   working directory, if any.
#' @param caller Character(1). The function that needs the packages, named in
#'   the question and the error.
#' @param note Character(1) or \code{NULL}. Appended to the error.
#' @param only_in_renv Logical(1). Do nothing outside an active renv study.
#' @param r_upgrade Logical(1). Leave \code{FALSE}. A \code{renv.lock}
#'   snapshot is refused from an R whose major.minor
#'   differs from the R the lockfile records (see
#'   \code{\link{guard_snapshot}}). Set \code{TRUE} only when you are
#'   deliberately moving the study to this session's R.
#' @return The names of the packages installed, invisibly.
#' @export
#' @examples
#' # Nothing to install, and nothing written, outside a study:
#' study_need("stats")
study_need <- function(packages, root = NULL, caller = "study_need", note = NULL,
                       only_in_renv = FALSE, r_upgrade = FALSE) {
  root <- .need_root(root)
  in_renv <- !is.null(root) && .renv_active(root)
  if (only_in_renv && !in_renv) return(invisible(character(0)))
  missing <- packages[!vapply(packages, .package_installed, logical(1))]
  # Nothing is declared until nothing is left to ask: a refusal or a failed
  # install leaves the study's DESCRIPTION as it was.
  if (!length(missing)) {
    if (in_renv && length(packages)) {
      study_declare(packages, root)
      .need_record(packages, root, caller, r_upgrade)
    }
    return(invisible(character(0)))
  }
  declined <- FALSE
  if (in_renv && .study_interactive()) {
    # Refuse before asking or installing; .need_snapshot() checks again.
    guard_snapshot(root, r_upgrade)
    if (isTRUE(.need_ask(missing, caller))) {
      .need_install(missing, root)
      still <- missing[!vapply(missing, .package_installed, logical(1))]
      if (length(still)) {
        stop(caller, "(): ", paste(still, collapse = ", "), " did not install; run hvtiR::setup() ",
             "in the study project to install everything the study needs.",
             if (!is.null(note)) paste0(" ", note) else "", call. = FALSE)
      }
      study_declare(packages, root)
      .need_snapshot(root, r_upgrade)
      return(invisible(missing))
    }
    declined <- TRUE
  }
  stop(caller, "(): needs ", paste(missing, collapse = ", "), ", which is not installed",
       if (in_renv) " in this study's library" else "",
       if (declined) ", and was not installed" else "",
       ". Run hvtiR::setup() in the study project to install everything the study needs.",
       if (!is.null(note)) paste0(" ", note) else "", call. = FALSE)
}

.package_installed <- function(pkg) nzchar(system.file(package = pkg))

.need_root <- function(root) {
  if (!is.null(root)) return(normalizePath(root, mustWork = TRUE))
  tryCatch(study_root(), error = function(e) {
    if (!grepl("no _study.yml found", conditionMessage(e), fixed = TRUE)) stop(e)
    NULL
  })
}

.renv_active <- function(root) {
  project <- Sys.getenv("RENV_PROJECT", "")
  nzchar(project) && identical(normalizePath(project, winslash = "/", mustWork = FALSE),
                               normalizePath(root, winslash = "/", mustWork = FALSE))
}

.need_ask <- function(pkgs, caller) {
  utils::askYesNo(paste0(caller, "() needs ", paste(pkgs, collapse = ", "),
                         ". Install into this study's library and record it in renv.lock?"),
                  default = TRUE)
}

# Writes the lock only from a person's session: a batch render is no place to move
# the study's recorded versions, and two renders could write it at once.
.need_record <- function(packages, root, caller, r_upgrade = FALSE) {
  absent <- .need_unlocked(packages, root)
  if (!length(absent)) return(invisible(NULL))
  why <- if (.study_interactive()) {
    .need_try_record(absent, root, caller, r_upgrade)
  } else {
    "This session is not interactive."
  }
  if (!is.null(why)) {
    warning(caller, "(): installed but not in renv.lock: ", paste(absent, collapse = ", "),
            ". renv::restore() will not bring back what the lock lacks. ", why, call. = FALSE)
  }
  invisible(NULL)
}

# NULL when the lock now holds them, otherwise why it does not.
.need_try_record <- function(absent, root, caller, r_upgrade) {
  tryCatch({
    guard_snapshot(root, r_upgrade)
    if (!isTRUE(.need_ask_record(absent, caller))) return("You declined to record it.")
    .need_snapshot(root, r_upgrade)
    if (length(.need_unlocked(absent, root))) "The snapshot did not record it."
  }, error = conditionMessage)
}

# An unreadable lock holds nothing we can count on; guard_snapshot() names the fault.
.need_unlocked <- function(packages, root) {
  lock_file <- file.path(root, "renv.lock")
  locked <- if (file.exists(lock_file)) {
    tryCatch(names(jsonlite::read_json(lock_file, simplifyVector = FALSE)$Packages),
             error = function(e) NULL)
  }
  setdiff(packages, c(locked, tools::standard_package_names()$base))
}

.need_ask_record <- function(pkgs, caller) {
  utils::askYesNo(paste0(caller, "() needs ", paste(pkgs, collapse = ", "),
                         ": installed, but not in renv.lock. Record now? The snapshot also moves other ",
                         "locked packages to their installed versions, and drops any the library ",
                         "or DESCRIPTION no longer holds."),
                  default = TRUE)
}

# renv's own installer, not pak: the pak back end skips LinkingTo packages (cpp11,
# say), after which renv::snapshot() validation aborts.
.need_install <- function(pkgs, root) {
  withr::with_envvar(c(RENV_CONFIG_PAK_ENABLED = "FALSE"),
                     renv::install(pkgs, project = root, prompt = FALSE))
}

.need_snapshot <- function(root, r_upgrade = FALSE) {
  guard_snapshot(root, r_upgrade)
  renv::snapshot(project = root, prompt = FALSE)
}
