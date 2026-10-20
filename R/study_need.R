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
study_need <- function(packages, root = NULL, caller = "study_need", note = NULL,
                       only_in_renv = FALSE) {
  root <- .need_root(root)
  in_renv <- !is.null(root) && .renv_active(root)
  if (only_in_renv && !in_renv) return(invisible(character(0)))
  if (in_renv) study_declare(packages, root)
  missing <- packages[!vapply(packages, .package_installed, logical(1))]
  if (!length(missing)) return(invisible(character(0)))
  if (in_renv && .study_interactive() && isTRUE(.need_ask(missing, caller))) {
    .need_install(missing, root)
    still <- missing[!vapply(missing, .package_installed, logical(1))]
    if (length(still)) {
      stop(caller, "(): ", paste(still, collapse = ", "), " did not install; run hvtiR::setup() ",
           "in the study project", call. = FALSE)
    }
    .need_snapshot(root)
    return(invisible(missing))
  }
  stop(caller, "(): needs ", paste(missing, collapse = ", "), ", which is not installed",
       if (in_renv) " in this study's library" else "",
       ". Run hvtiR::setup() in the study project to install everything the study needs",
       if (in_renv) ", or run this again interactively to install only this" else "", ".",
       if (!is.null(note)) paste0(" ", note) else "", call. = FALSE)
}

.package_installed <- function(pkg) nzchar(system.file(package = pkg))

.need_root <- function(root) {
  if (!is.null(root)) return(normalizePath(root, mustWork = TRUE))
  tryCatch(study_root(), error = function(e) NULL)
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

.need_install <- function(pkgs, root) renv::install(pkgs, project = root, prompt = FALSE)

.need_snapshot <- function(root) renv::snapshot(project = root, prompt = FALSE)
