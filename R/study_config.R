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
.study_required <- function(require_data = TRUE) {
  if (!require_data) return("study")

  c(
    "study",
    "built",
    "cohort.n",
    "cohort.n_events",
    "cohort.n_censored",
    "cohort.event",
    "cohort.time"
  )
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

.study_validate_additional <- function(value, found) {
  if (is.null(value)) return(value)
  has_names <- !is.null(names(value)) &&
    length(names(value)) == length(value) &&
    all(nzchar(names(value))) && !anyDuplicated(names(value))
  named <- is.list(value) && (length(value) == 0L || has_names)
  if (!named) {
    stop(
      "study_config(): ", found,
      " additional_datasets must be a named mapping.",
      call. = FALSE
    )
  }
  for (name in names(value)) {
    contract <- value[[name]]
    valid_name <- !identical(name, "study") &&
      grepl("^[a-z][a-z0-9_]*$", name)
    valid_file <- is.list(contract) &&
      is.character(contract$built) && length(contract$built) == 1L &&
      !is.na(contract$built) && nzchar(contract$built) &&
      identical(basename(contract$built), contract$built) &&
      nzchar(tools::file_ext(contract$built))
    if (!valid_name || !valid_file) {
      stop(
        "study_config(): ", found,
        " has an invalid additional dataset contract for '", name, "'.",
        call. = FALSE
      )
    }
    cohort <- contract$cohort
    if (!is.null(cohort)) {
      required <- c("n", "n_events", "n_censored", "event", "time")
      if (!is.list(cohort) || any(vapply(
        required,
        function(key) is.null(cohort[[key]]),
        logical(1)
      ))) {
        stop(
          "study_config(): ", found,
          " has an incomplete cohort for dataset '", name, "'.",
          call. = FALSE
        )
      }
      raw_counts <- unlist(
        cohort[c("n", "n_events", "n_censored")],
        use.names = FALSE
      )
      valid_text <- vapply(
        cohort[c("event", "time")],
        function(x) {
          is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
        },
        logical(1)
      )
      counts <- if (is.numeric(raw_counts)) {
        as.integer(raw_counts)
      } else {
        integer(0)
      }
      if (!is.numeric(raw_counts) || length(counts) != 3L ||
            anyNA(counts) || any(counts < 0L) ||
            any(as.numeric(counts) != raw_counts) || !all(valid_text) ||
            counts[[1L]] != counts[[2L]] + counts[[3L]]) {
        stop(
          "study_config(): ", found,
          " has an inconsistent cohort for dataset '", name, "'.",
          call. = FALSE
        )
      }
      value[[name]]$cohort$n <- counts[[1L]]
      value[[name]]$cohort$n_events <- counts[[2L]]
      value[[name]]$cohort$n_censored <- counts[[3L]]
    }
  }
  value
}

#' Read the study manifest
#'
#' @description
#' Walks up from \code{start} until a \code{_study.yml} is found, parses it,
#' validates the requested identity or data contract, and returns the result
#' with the study root attached.
#'
#' A study without a manifest must not render, so an absent
#' \code{_study.yml} is an error rather than a set of defaults. The directories
#' walked are named in the error, because the usual cause is starting from
#' outside the study tree.
#'
#' Study identity always requires \code{study}. With
#' \code{require_data = TRUE}, \code{built} and a \code{cohort} block holding
#' \code{n}, \code{n_events}, \code{n_censored}, \code{event} and \code{time}
#' are also required. \code{built} must carry its file extension, because the
#' reader dispatches on it.
#'
#' @param start Character. Directory to start the upward walk from. Defaults
#'   to \code{getwd()}.
#' @param require_data Logical. If \code{TRUE}, require the default dataset and
#'   cohort contract. Use \code{FALSE} when only study identity is needed.
#'
#' @return The manifest as a list, with \code{root} and \code{file} attached.
#'   Additive identity and named-dataset fields are retained.
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
study_config <- function(start = getwd(), require_data = TRUE) {
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
    stop("study_config(): no _study.yml found.\n\n",
         "Recovery may be available from CORR_STUDIES:\n",
         "  study-setup --recover\n\n",
         "If the Study Tracker ID cannot be determined from this ",
         "repository:\n",
         "  study-setup 42 --recover\n\n",
         "Walked, in order:\n  ",
         paste(walked, collapse = "\n  "),
         "\nStart from inside a study tree.",
         call. = FALSE)
  }

  raw <- yaml::read_yaml(found)
  raw$additional_datasets <- .study_validate_additional(
    raw$additional_datasets,
    found
  )

  missing <- Filter(function(k) is.null(.study_pluck(raw, k)),
                    .study_required(require_data))
  if (length(missing)) {
    action <- if (require_data && "built" %in% missing) {
      " Run register_data() after the default study dataset exists."
    } else {
      ""
    }
    stop("study_config(): ", found, " is missing required key",
         if (length(missing) > 1) "s" else "", ": ",
         paste(gsub(".", ":", missing, fixed = TRUE), collapse = ", "),
         ". No defaults are supplied for a study manifest.", action,
         call. = FALSE)
  }

  if (!is.null(raw$built) && !nzchar(tools::file_ext(raw$built))) {
    stop("study_config(): built: '", raw$built, "' has no file extension. ",
         "Give the dataset filename in full (for example ",
         "'built080426.sas7bdat'); the reader dispatches on the extension.",
         call. = FALSE)
  }

  if (!is.null(raw$cohort)) {
    raw$cohort$n <- as.integer(raw$cohort$n)
    raw$cohort$n_events <- as.integer(raw$cohort$n_events)
    raw$cohort$n_censored <- as.integer(raw$cohort$n_censored)
  }

  # An internally inconsistent cohort block would make assert_cohort() a
  # gate that can never pass, and the error it raised would point at the
  # data rather than at the manifest that is actually wrong.
  if (!is.null(raw$cohort)) {
    n <- raw$cohort$n
    ev <- raw$cohort$n_events
    cen <- raw$cohort$n_censored
    if (!identical(n, ev + cen)) {
      stop("study_config(): ", found, " cohort is inconsistent: n = ", n,
           " but n_events + n_censored = ", ev + cen,
           " (n_events = ", ev, ", n_censored = ", cen, ").",
           call. = FALSE)
    }
  }

  out <- c(list(root = dir, file = found), raw)
  out$root <- dir
  out$file <- found
  out
}
