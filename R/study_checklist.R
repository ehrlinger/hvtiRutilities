# The audit, rendered for a human. Kept separate from study_status() so that
# the audit stays a data structure a caller can act on, rather than a report
# that has to be parsed back.

#' Render a study audit as a markdown checklist
#'
#' @description
#' Turns a [study_status()] result into markdown: one checkbox per
#' check, ticked where the check passed (`"OK"`) or the study is closed
#' (`"CLOSED"`) and left open otherwise, with the detail alongside. File
#' counts follow.
#'
#' @param status An object of class `"study_status"`, from
#'   [study_status()] or [study_setup()].
#' @param path Character(1) or `NULL`. Where to write the markdown. When
#'   `NULL` (default) the lines are returned instead of written.
#'
#' @return When `path` is `NULL`, a character vector of markdown
#'   lines. Otherwise `path`, invisibly, after writing.
#'
#' @seealso [study_status()], [study_setup()]
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
         "study_status() or study_setup().", call. = FALSE)
  }

  boxes <- vapply(
    seq_len(nrow(status$checks)),
    function(i) {
      # A closed study is a settled state, not an open task.
      paste0(if (status$checks$status[i] %in% c("OK", "CLOSED")) {
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
    paste0("- `.qmd`/`.Rmd` sources: ", status$counts$qmd),
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
