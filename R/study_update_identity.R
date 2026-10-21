# Verification rewrites only the identity keys of an existing _study.yml.
# Whether the record matches the typed identity is the caller's decision
# (study-setup --verify); this function only writes the verified result.

.study_identity_keys <- c(
  "study", "umbrella", "owner", "irb_number", "cvir_no",
  "study_creation_date"
)

# A Study Tracker ID is one positive whole number. Checked before any integer
# coercion, which would truncate 42.9 to 42 and verify the wrong study.
.study_whole_id <- function(x) {
  is.numeric(x) && length(x) == 1L && !is.na(x) && is.finite(x) &&
    x >= 1 && x == round(x)
}

#' Record a verified study identity
#'
#' @description
#' Writes a Study Tracker identity into an existing \code{_study.yml} and marks
#' it verified: \code{identity_source: tracker} and
#' \code{identity_verified: true}. Every other key, including the data
#' contract (\code{built}, \code{cohort}, \code{additional_datasets},
#' \code{population}, \code{citation}), keeps its value.
#'
#' @details
#' This is the write step of verifying a manual identity. It does not read
#' Study Tracker or compare the record with the typed identity; the caller
#' does both, and passes the record only when they match. A field the record
#' leaves \code{NULL} keeps its current value.
#'
#' The file is rewritten whole and atomically, as \code{\link{register_data}}
#' rewrites it, so comments in \code{_study.yml} are not kept.
#'
#' @param identity A named list from the Study Tracker record. It must hold
#'   \code{study_tracker_id}, equal to the manifest's, and \code{study}; it may
#'   hold \code{umbrella}, \code{owner}, \code{irb_number}, \code{cvir_no} and
#'   \code{study_creation_date}.
#' @param start A directory inside the study; the study is found as
#'   \code{\link{study_config}} finds it.
#'
#' @return The names of the keys whose values changed, invisibly.
#'
#' @seealso \code{\link{study_setup}}, \code{\link{study_status}}.
#'
#' @export
#'
#' @examples
#' root <- file.path(tempdir(), "update-identity-example")
#' study_setup(root, "Typed title", 42L, identity_source = "manual",
#'             renv = FALSE)
#' study_update_identity(
#'   list(study_tracker_id = 42L, study = "Typed title", owner = "Analyst"),
#'   start = root
#' )
#' study_config(root, require_data = FALSE)$identity_verified
#' unlink(root, recursive = TRUE)
study_update_identity <- function(identity, start = getwd()) {
  if (!is.list(identity) || is.null(names(identity))) {
    stop("study_update_identity(): 'identity' must be a named list.",
         call. = FALSE)
  }
  unknown <- setdiff(names(identity), c("study_tracker_id", .study_identity_keys))
  if (length(unknown)) {
    stop("study_update_identity(): unknown identity field: ",
         paste(unknown, collapse = ", "), call. = FALSE)
  }
  for (key in .study_identity_keys) {
    value <- identity[[key]]
    if (!is.null(value) &&
          !(is.character(value) && length(value) == 1L && !is.na(value))) {
      stop("study_update_identity(): '", key, "' must be one string or NULL.",
           call. = FALSE)
    }
  }
  if (is.null(identity$study) || !nzchar(trimws(identity$study))) {
    stop("study_update_identity(): 'study' is required.", call. = FALSE)
  }
  id <- identity$study_tracker_id
  if (!.study_whole_id(id)) {
    stop("study_update_identity(): 'study_tracker_id' must be one positive ",
         "whole number.", call. = FALSE)
  }

  cfg <- study_config(start, require_data = FALSE)
  raw <- .read_study_yml(cfg$file, "study_update_identity")
  if (!.study_whole_id(raw$study_tracker_id) ||
        id != raw$study_tracker_id) {
    stop("study_update_identity(): the record's Study Tracker ID ",
         format(id), " does not match ", cfg$file, " (",
         format(raw$study_tracker_id), ").", call. = FALSE)
  }

  changed <- character(0)
  for (key in .study_identity_keys) {
    value <- identity[[key]]
    if (!is.null(value) && !identical(raw[[key]], value)) {
      raw[key] <- list(value)
      changed <- c(changed, key)
    }
  }
  for (key in c("identity_source", "identity_verified")) {
    value <- if (key == "identity_source") "tracker" else TRUE
    if (!identical(raw[[key]], value)) {
      raw[key] <- list(value)
      changed <- c(changed, key)
    }
  }
  if (length(changed)) {
    .study_write_atomic(raw, cfg$file)
  }
  invisible(changed)
}
