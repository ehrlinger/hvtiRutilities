# The study manifest. One `_study.yml` at the study root replaces the sixteen
# identity lines that every SAS job carried as literals, and the drift that
# came with them: in distributions/ac.dead_JR.sas the study path appears twice
# with two different values, because one copy of an edit was made and the other
# was not.
#
# This is the primitive the rest of the data contract is built on. It does the
# directory walk itself; study_root() is a thin accessor over it, not the other
# way round.

# Required keys, in the order they are reported. Nested keys are dotted.
.study_required <- function() {
  c("study", "built",
    "cohort.n", "cohort.n_events", "cohort.n_censored",
    "cohort.event", "cohort.time")
}

.study_pluck <- function(cfg, key) {
  parts <- strsplit(key, ".", fixed = TRUE)[[1]]
  out <- cfg
  for (p in parts) {
    if (!is.list(out) || is.null(out[[p]])) return(NULL)
    out <- out[[p]]
  }
  out
}

#' Read the study manifest
#'
#' @description
#' Walks up from \code{start} until a \code{_study.yml} is found, parses it,
#' validates that every required key is present, and returns the result with
#' the study root attached.
#'
#' A study without a manifest must not render, so an absent or incomplete
#' \code{_study.yml} is an error rather than a set of defaults. The directories
#' walked are named in the error, because the usual cause is starting from
#' outside the study tree.
#'
#' Required keys are \code{study}, \code{built}, and a \code{cohort} block
#' holding \code{n}, \code{n_events}, \code{n_censored}, \code{event} and
#' \code{time}. \code{population} and \code{citation} are optional.
#' \code{built} must carry its file extension, because the reader dispatches
#' on it.
#'
#' @param start Character. Directory to start the upward walk from. Defaults
#'   to \code{getwd()}.
#'
#' @return A list with elements \code{root}, \code{file}, \code{study},
#'   \code{population}, \code{built}, \code{citation}, and \code{cohort} (a
#'   list of \code{n}, \code{n_events}, \code{n_censored}, \code{event},
#'   \code{time}).
#'
#' @seealso \code{\link{study_root}}, \code{\link{record_provenance}}
#'
#' @export
#'
#' @examples
#' root <- file.path(tempdir(), "study-example")
#' dir.create(root, showWarnings = FALSE)
#' yaml::write_yaml(
#'   list(study = "Example", built = "example.sas7bdat",
#'        cohort = list(n = 10L, n_events = 4L, n_censored = 6L,
#'                      event = "dead", time = "iv_dead")),
#'   file.path(root, "_study.yml")
#' )
#' cfg <- study_config(root)
#' cfg$study
#' unlink(root, recursive = TRUE)
study_config <- function(start = getwd()) {
  dir     <- normalizePath(start, mustWork = TRUE)
  walked  <- character(0)
  found   <- NULL

  repeat {
    walked <- c(walked, dir)
    candidate <- file.path(dir, "_study.yml")
    if (file.exists(candidate)) {
      found <- candidate
      break
    }
    parent <- dirname(dir)
    if (identical(parent, dir)) break
    dir <- parent
  }

  if (is.null(found)) {
    stop("study_config(): no _study.yml found. Walked, in order:\n  ",
         paste(walked, collapse = "\n  "),
         "\nStart from inside a study tree, or create a _study.yml at its root.",
         call. = FALSE)
  }

  raw <- yaml::read_yaml(found)

  missing <- Filter(function(k) is.null(.study_pluck(raw, k)),
                    .study_required())
  if (length(missing)) {
    stop("study_config(): ", found, " is missing required key",
         if (length(missing) > 1) "s" else "", ": ",
         paste(gsub(".", ":", missing, fixed = TRUE), collapse = ", "),
         ". No defaults are supplied for a study manifest.", call. = FALSE)
  }

  if (!nzchar(tools::file_ext(raw$built))) {
    stop("study_config(): built: '", raw$built, "' has no file extension. ",
         "Give the dataset filename in full (for example ",
         "'built080426.sas7bdat'); the reader dispatches on the extension.",
         call. = FALSE)
  }

  n   <- as.integer(raw$cohort$n)
  ev  <- as.integer(raw$cohort$n_events)
  cen <- as.integer(raw$cohort$n_censored)

  # An internally inconsistent cohort block would make assert_cohort() a
  # gate that can never pass, and the error it raised would point at the
  # data rather than at the manifest that is actually wrong.
  if (!identical(n, ev + cen)) {
    stop("study_config(): ", found, " cohort is inconsistent: n = ", n,
         " but n_events + n_censored = ", ev + cen,
         " (n_events = ", ev, ", n_censored = ", cen, ").", call. = FALSE)
  }

  list(
    root       = dir,
    file       = found,
    study      = raw$study,
    population = raw$population,
    built      = raw$built,
    citation   = raw$citation,
    cohort     = list(
      n          = n,
      n_events   = ev,
      n_censored = cen,
      event      = raw$cohort$event,
      time       = raw$cohort$time
    )
  )
}
