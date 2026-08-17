# The audit, rendered for a human. Kept separate from study_status() so that
# the audit stays a data structure a caller can act on, rather than a report
# that has to be parsed back.

#' Render a study audit as a markdown checklist
#'
#' @description
#' Turns a \code{\link{study_status}} result into markdown: one checkbox per
#' check, ticked where the check passed and left open otherwise, with the
#' detail alongside. File counts follow.
#'
#' @param status An object of class \code{"study_status"}, from
#'   \code{\link{study_status}} or \code{\link{study_init}}.
#' @param path Character(1) or \code{NULL}. Where to write the markdown. When
#'   \code{NULL} (default) the lines are returned instead of written.
#'
#' @return When \code{path} is \code{NULL}, a character vector of markdown
#'   lines. Otherwise \code{path}, invisibly, after writing.
#'
#' @seealso \code{\link{study_status}}, \code{\link{study_init}}
#'
#' @export
#'
#' @examples
#' root <- file.path(tempdir(), "study-checklist-example")
#' dir.create(root, showWarnings = FALSE)
#' cat(study_checklist(study_status(root)), sep = "\n")
#' unlink(root, recursive = TRUE)
study_checklist <- function(status, path = NULL) {
  if (!inherits(status, "study_status")) {
    stop("study_checklist(): status must be a study_status object, from ",
         "study_status() or study_init().", call. = FALSE)
  }

  boxes <- vapply(
    seq_len(nrow(status$checks)),
    function(i) {
      paste0(if (identical(status$checks$status[i], "OK")) {
               "- [x] "
             } else {
               "- [ ] "
             },
             "**", status$checks$item[i], "** \u2014 ",
             status$checks$detail[i])
    },
    character(1)
  )

  lines <- c(
    "# Study readiness",
    "",
    paste0("Study root: `", status$root, "`"),
    "",
    "## Checks",
    "",
    boxes,
    "",
    "## Counts",
    "",
    paste0("- `.R` files: ", status$counts$r_files),
    paste0("- `.qmd` sources: ", status$counts$qmd),
    paste0("- `.sas` jobs: ", status$counts$sas_jobs),
    paste0("- provenance sidecars: ", status$counts$sidecars)
  )

  if (is.null(path)) return(lines)

  # file() warns and then errors for the same cause, so an unwritable path
  # would emit a warning that merely duplicates the error raised below. The
  # warning is muffled and the error is the single reported failure.
  written <- tryCatch({
    withCallingHandlers(
      writeLines(lines, path),
      warning = function(w) invokeRestart("muffleWarning"))
    TRUE
  }, error = function(e) conditionMessage(e))

  if (!isTRUE(written)) {
    stop("study_checklist(): could not write ", path, ": ", written,
         call. = FALSE)
  }
  invisible(path)
}
