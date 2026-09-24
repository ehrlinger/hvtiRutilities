# The study manifest. One `_study.yml` at the study root replaces the sixteen
# identity lines that every SAS job carried as literals, and the drift that
# came with them: in distributions/ac.dead_JR.sas the study path appears twice
# with two different values, because one copy of an edit was made and the other
# was not.
#
# This is the primitive the rest of the data contract is built on. It does the
# directory walk itself; study_root() is a thin accessor over it, not the other
# way round.

.study_required <- function(require_data = TRUE) {
  if (!require_data) return("study")
  c("study", "built")
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

.study_validate_release <- function(value, found, dataset) {
  if (is.null(value)) return(NULL)
  if (!is.list(value)) {
    stop("study_config(): ", found, " release for dataset '", dataset,
         "' must be a mapping.", call. = FALSE)
  }
  required <- c("dataset_id", "release_id")
  for (key in required) {
    field <- value[[key]]
    valid <- is.character(field) && length(field) == 1L &&
      !is.na(field) && nzchar(field)
    if (!valid) {
      stop("study_config(): ", found, " release for dataset '", dataset,
           "' has an invalid ", key, ".", call. = FALSE)
    }
  }
  if (!.catalog_valid_dataset_id(value$dataset_id)) {
    stop("study_config(): ", found, " release for dataset '", dataset,
         "' has an invalid dataset_id.", call. = FALSE)
  }
  if (!.catalog_valid_release_id(value$release_id)) {
    stop("study_config(): ", found, " release for dataset '", dataset,
         "' has an invalid release_id.", call. = FALSE)
  }
  value
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
    valid_population <- is.list(contract) && (
      is.null(contract$population) ||
        (is.character(contract$population) && length(contract$population) == 1L &&
           !is.na(contract$population) && nzchar(contract$population))
    )
    if (is.list(contract) && !valid_population) {
      stop(
        "study_config(): ", found, " population for additional dataset '",
        name, "' must be a non-empty character scalar or null.",
        call. = FALSE
      )
    }
    if (!valid_name || !valid_file || !valid_population) {
      stop(
        "study_config(): ", found,
        " has an invalid additional dataset contract for '", name, "'.",
        call. = FALSE
      )
    }
    value[[name]]$release <- .study_validate_release(
      contract$release,
      found,
      name
    )
  }
  value
}

# identity_source and identity_verified are optional: a manifest written
# before they existed is a Tracker identity. When present they must be the
# values study_setup() writes, and agree with each other (a Tracker identity
# is verified, a manual one is not until verification rewrites it as a
# Tracker identity), because study_status() and recovery decide from them
# whether the identity can be trusted.
.study_validate_identity <- function(raw, found) {
  source <- raw$identity_source
  if (!is.null(source) &&
        !(is.character(source) && length(source) == 1L &&
            source %in% c("tracker", "manual"))) {
    stop("study_config(): ", found, " has an invalid identity_source; ",
         "expected tracker or manual", call. = FALSE)
  }
  verified <- raw$identity_verified
  if (!is.null(verified) &&
        !(is.logical(verified) && length(verified) == 1L && !is.na(verified))) {
    stop("study_config(): ", found, " has an invalid identity_verified; ",
         "expected true or false", call. = FALSE)
  }
  if (!is.null(source) && !is.null(verified) &&
        !identical(verified, identical(source, "tracker"))) {
    stop("study_config(): ", found, " records identity_source: ", source,
         " with identity_verified: ", tolower(as.character(verified)),
         "; a tracker identity is verified and a manual one is not",
         call. = FALSE)
  }
  invisible(raw)
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
#' \code{require_data = TRUE}, \code{built} is also required. It must carry
#' its file extension, because the reader dispatches on the extension.
#'
#' @param start Character. Directory to start the upward walk from. Defaults
#'   to \code{getwd()}.
#' @param require_data Logical. If \code{TRUE}, require the default dataset and
#'   registered file. Use \code{FALSE} when only study identity is needed.
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
#'   list(study = "Example", built = "example.sas7bdat"),
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
  .study_validate_identity(raw, found)
  raw$release <- .study_validate_release(raw$release, found, "study")
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

  out <- c(list(root = dir, file = found), raw)
  out$root <- dir
  out$file <- found
  out
}
