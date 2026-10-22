#' Refuse a renv snapshot taken from the wrong R
#'
#' @description
#' Stops before \code{renv::snapshot()} when the R running this session has a
#' different major.minor version than the R recorded in the study's
#' \code{renv.lock}. A snapshot from the wrong R rewrites the lockfile's R
#' version and drops every locked package the session's library lacks. On
#' 2026-10-22, R 4.6.1 snapshotted a study locked to R 4.5.3, and
#' \pkg{boostmtree} and \pkg{ggBoostedTrees} fell out of its lockfile.
#'
#' A patch difference (4.5.1 against 4.5.3) passes, as does a study with no
#' \code{renv.lock}.
#'
#' Use \code{r_upgrade = TRUE} only when you are deliberately moving the study
#' to a new R. The guard then still stops if any package in the lockfile is
#' not installed in this session's library, because the snapshot would drop
#' it; restore those first with \code{renv::restore()}.
#'
#' \code{\link{study_need}} and \code{\link{study_setup}} call this before
#' they snapshot, so you need to call it yourself only before a snapshot of
#' your own.
#'
#' @param root Character(1). The study root, holding \code{renv.lock}.
#' @param r_upgrade Logical(1). The study is being moved to this session's R
#'   on purpose.
#' @param session The R version of this session, a
#'   \code{\link[base]{numeric_version}}. Defaults to the running R; set it
#'   only to test the guard.
#' @param installed A function taking a package name and returning its
#'   installed version, or \code{NA_character_} when it is not installed.
#'   Defaults to a lookup in this session's library; set it only to test the
#'   guard.
#' @return \code{TRUE}, invisibly, when the snapshot may go ahead. Otherwise
#'   an error that names both R versions and the R to start.
#' @export
#' @examples
#' root <- tempfile("study")
#' dir.create(root)
#' # A study with no renv.lock has nothing to protect:
#' guard_snapshot(root)
#'
#' # A lock written by R 4.5.3, checked from a session running R 4.6.1:
#' writeLines('{"R": {"Version": "4.5.3"}, "Packages": {}}',
#'            file.path(root, "renv.lock"))
#' try(guard_snapshot(root, session = numeric_version("4.6.1")))
#' unlink(root, recursive = TRUE)
guard_snapshot <- function(root, r_upgrade = FALSE, session = .session_r(),
                           installed = .installed_version) {
  lock_file <- file.path(root, "renv.lock")
  if (!file.exists(lock_file)) return(invisible(TRUE))
  lock <- jsonlite::read_json(lock_file, simplifyVector = FALSE)
  want <- lock$R$Version
  if (!is.character(want) || length(want) != 1L) return(invisible(TRUE))
  # A version renv could not have written ("", "devel", "4") is treated
  # like a lock that records no R.
  if (is.na(.major_minor(want))) return(invisible(TRUE))
  have <- as.character(session)
  if (identical(.major_minor(want), .major_minor(have))) {
    return(invisible(TRUE))
  }
  if (!isTRUE(r_upgrade)) {
    stop("renv.lock records R ", want, " but this is R ", have,
         ". A snapshot now would record the wrong R and drop packages ",
         "this R's library lacks. Start R ", want, " (/opt/R/", want,
         "/bin/R), or pass r_upgrade = TRUE to move the study to R ",
         have, " on purpose.", call. = FALSE)
  }
  pkgs <- names(lock$Packages)
  gone <- pkgs[is.na(vapply(pkgs, installed, character(1)))]
  if (length(gone)) {
    stop("Moving to R ", have, " would drop ", paste(gone, collapse = ", "),
         " from renv.lock. Install them first: renv::restore(packages = c(",
         paste0('"', gone, '"', collapse = ", "), ")).", call. = FALSE)
  }
  invisible(TRUE)
}

.session_r <- function() getRversion()

.installed_version <- function(pkg) {
  tryCatch(as.character(utils::packageVersion(pkg)),
           error = function(e) NA_character_)
}

.major_minor <- function(v) {
  parts <- tryCatch(unlist(numeric_version(as.character(v))),
                    error = function(e) NULL)
  if (length(parts) < 2L) return(NA_character_)
  paste(parts[1:2], collapse = ".")
}
