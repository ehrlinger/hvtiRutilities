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
#' @return The names of the packages installed, invisibly.
#' @export
#' @examples
#' # Nothing to install, and nothing written, outside a study:
#' study_need("stats")
study_need <- function(packages, root = NULL, caller = "study_need", note = NULL,
                       only_in_renv = FALSE) {
  root <- .need_root(root)
  in_renv <- !is.null(root) && .renv_active(root)
  if (only_in_renv && !in_renv) return(invisible(character(0)))
  missing <- packages[!vapply(packages, .package_installed, logical(1))]
  # What is installed is declared now, so explicit-mode renv locks it. What is
  # missing is declared only once it has been installed.
  if (in_renv && length(setdiff(packages, missing))) study_declare(setdiff(packages, missing), root)
  if (!length(missing)) return(invisible(character(0)))
  declined <- FALSE
  if (in_renv && .study_interactive()) {
    if (isTRUE(.need_ask(missing, caller))) {
      .need_install(missing, root)
      still <- missing[!vapply(missing, .package_installed, logical(1))]
      if (length(still)) {
        stop(caller, "(): ", paste(still, collapse = ", "), " did not install; run hvtiR::setup() ",
             "in the study project to install everything the study needs.",
             if (!is.null(note)) paste0(" ", note) else "", call. = FALSE)
      }
      study_declare(missing, root)
      .need_snapshot(root)
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

# renv's own installer, not pak: the pak back end skips LinkingTo packages (cpp11,
# say), after which renv::snapshot() validation aborts.
.need_install <- function(pkgs, root) {
  withr::with_envvar(c(RENV_CONFIG_PAK_ENABLED = "FALSE"),
                     renv::install(pkgs, project = root, prompt = FALSE))
}

.need_snapshot <- function(root) renv::snapshot(project = root, prompt = FALSE)
