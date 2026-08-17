# A study's R/ directory is sourced wholesale by every document:
#
#   for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)
#
# so a file there with top-level executable code runs on every render. This was
# not hypothetical: a helper file called read_built() and ran a 500-replicate
# bootstrap at its top level, meaning every render fired a long job nobody
# asked for. Scripts belong in scripts/.
#
# The check is syntactic, not behavioural: parse each file and require every
# top-level expression to be an assignment. That admits function definitions
# and constants, and rejects calls.

.is_assignment <- function(e) {
  is.call(e) && as.character(e[[1]])[1] %in% c("<-", "=", "<<-", "assign")
}

#' Report top-level executable code in an R directory
#'
#' @description
#' Parses every \code{.R} file in \code{dir} and reports any top-level
#' expression that is not an assignment. Function definitions and constants
#' pass; calls do not.
#'
#' Use this on any directory that is sourced wholesale, where a stray call
#' would execute on every render.
#'
#' @param dir Character(1). Directory to check.
#'
#' @return A character vector of complaints, one per offending expression,
#'   empty when the directory is clean. The caller decides whether to warn or
#'   to fail.
#'
#' @export
#'
#' @examples
#' d <- file.path(tempdir(), "purity-example")
#' dir.create(d, showWarnings = FALSE)
#' writeLines(c("f <- function(x) x + 1", "print(f(1))"),
#'            file.path(d, "example.R"))
#' r_dir_impurities(d)
#' unlink(d, recursive = TRUE)
r_dir_impurities <- function(dir) {
  files <- list.files(dir, pattern = "[.]R$", full.names = TRUE)
  out <- character(0)
  for (f in files) {
    for (e in parse(f)) {
      # Only calls can have side effects. A bare constant cannot - and the
      # roxygen package-doc idiom is a top-level NULL or "_PACKAGE", so
      # rejecting constants would fail every correctly documented package.
      if (is.call(e) && !.is_assignment(e)) {
        out <- c(out, paste0(
          basename(f), ": top-level expression is not an assignment: ",
          paste(deparse(e), collapse = " ")))
      }
    }
  }
  out
}
