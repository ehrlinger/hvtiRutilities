# Study identity exists before study data. This function creates only the
# package-owned study structure and identity state; register_data() completes
# the data contract later.

.study_write_atomic <- function(value, path) {
  tmp <- tempfile(pattern = paste0(".", basename(path), "-"),
                  tmpdir = dirname(path))
  on.exit(unlink(tmp), add = TRUE)
  yaml::write_yaml(value, tmp)
  if (!file.rename(tmp, path)) {
    stop("could not move the prepared file into place: ", path,
         call. = FALSE)
  }
  invisible(path)
}

.study_write_lines_if_missing <- function(lines, path) {
  if (file.exists(path)) return(invisible(FALSE))

  tmp <- tempfile(pattern = paste0(".", basename(path), "-"),
                  tmpdir = dirname(path))
  on.exit(unlink(tmp), add = TRUE)
  writeLines(lines, tmp)
  if (!file.rename(tmp, path)) {
    stop("could not move the prepared file into place: ", path,
         call. = FALSE)
  }
  invisible(TRUE)
}

.study_renvignore <- function() {
  c(
    "00_datasets/",
    "datasets/",
    "40_graphs/",
    "graphs/",
    "50_documents/",
    "documents/",
    "90_estimates/",
    "estimates/",
    "templates/",
    "*.sas",
    "*.log",
    "*.lst",
    "*.doc*",
    "*.pp*"
  )
}

.study_scalar <- function(x, name, required = FALSE,
                          caller = "study_setup") {
  if (is.null(x) && !required) return(NULL)
  if (length(x) != 1L || is.na(x) || !nzchar(as.character(x))) {
    stop(caller, "(): ", name, " must be one non-empty value",
         call. = FALSE)
  }
  x
}

#' Set up study identity and directories
#'
#' @description
#' Creates the numbered directory structure for a new study and writes an
#' identity-only \code{_study.yml}. With \code{adopt = TRUE}, an existing
#' study keeps its legacy or numbered directory layout and every existing
#' initialization file.
#'
#' Data are deliberately not required. Call \code{\link{register_data}} after
#' the default or a named dataset exists.
#'
#' When the root holds no \code{.Rproj} file, one named for the root
#' directory is written, so that opening the project and
#' \code{\link{study_root}} agree on the study root. An existing project is
#' left unchanged.
#'
#' @param root Character. Study root to create or adopt.
#' @param study Character(1). Study title.
#' @param study_tracker_id Integer(1). Study Tracker topic ID.
#' @param umbrella,owner,irb_number,cvir_no Optional identity values.
#' @param study_creation_date Optional Study Tracker creation date.
#' @param adopt Logical. Permit additive setup in an existing root.
#' @param identity_source Character(1). Where the identity values came
#'   from: \code{"tracker"} (the default), for a Study Tracker record, or
#'   \code{"manual"}, for values typed by hand while the Tracker was
#'   unavailable. A new \code{_study.yml} records it as
#'   \code{identity_source}, with \code{identity_verified} set to
#'   \code{TRUE} for \code{"tracker"} and \code{FALSE} for
#'   \code{"manual"}. An existing \code{_study.yml} is not rewritten, so
#'   adoption keeps the recorded source.
#'
#' @return An object of class \code{"study_status"}, returned visibly.
#'
#' @seealso \code{\link{study_status}}, \code{\link{study_config}},
#'   \code{\link{study_dir}}
#'
#' @export
study_setup <- function(root, study, study_tracker_id,
                        umbrella = NULL, owner = NULL,
                        irb_number = NULL, cvir_no = NULL,
                        study_creation_date = NULL, adopt = FALSE,
                        identity_source = c("tracker", "manual")) {
  # Exact values only: match.arg() would accept an abbreviation such as
  # "man", and a provenance field should record what the caller meant.
  sources <- c("tracker", "manual")
  if (identical(identity_source, sources)) identity_source <- "tracker"
  if (!is.character(identity_source) || length(identity_source) != 1L ||
        !identity_source %in% sources) {
    stop("study_setup(): identity_source must be \"tracker\" or ",
         "\"manual\"", call. = FALSE)
  }
  root <- .study_scalar(root, "root", required = TRUE)
  study <- .study_scalar(study, "study", required = TRUE)
  tracker <- suppressWarnings(as.integer(study_tracker_id))
  if (length(tracker) != 1L || is.na(tracker) || tracker < 1L ||
        !identical(as.character(tracker), as.character(study_tracker_id))) {
    stop("study_setup(): study_tracker_id must be one positive integer",
         call. = FALSE)
  }
  umbrella <- .study_scalar(umbrella, "umbrella")
  owner <- .study_scalar(owner, "owner")
  irb_number <- .study_scalar(irb_number, "irb_number")
  cvir_no <- .study_scalar(cvir_no, "cvir_no")
  if (!is.null(study_creation_date)) {
    study_creation_date <- .study_scalar(
      as.character(study_creation_date),
      "study_creation_date"
    )
  }
  if (length(adopt) != 1L || is.na(adopt) || !is.logical(adopt)) {
    stop("study_setup(): adopt must be TRUE or FALSE", call. = FALSE)
  }

  existed <- file.exists(root) || dir.exists(root)
  if (file.exists(root) && !dir.exists(root)) {
    stop("study_setup(): root is a file, not a directory: ", root,
         call. = FALSE)
  }

  entries <- if (dir.exists(root)) {
    setdiff(list.files(root, all.files = TRUE, no.. = TRUE), "")
  } else {
    character(0)
  }
  if (existed && length(entries) && !adopt) {
    stop("study_setup(): root already contains files; use adopt = TRUE",
         call. = FALSE)
  }
  if (existed && !length(entries) && !adopt) {
    stop("study_setup(): root already exists; use adopt = TRUE",
         call. = FALSE)
  }
  yml <- file.path(root, "_study.yml")
  identity_exists <- file.exists(yml)
  if (identity_exists) {
    existing <- yaml::read_yaml(yml)
    existing_tracker <- suppressWarnings(
      as.integer(existing$study_tracker_id)
    )
    if (length(existing_tracker) != 1L || is.na(existing_tracker)) {
      stop("study_setup(): existing _study.yml has no Study Tracker ID",
           call. = FALSE)
    }
    if (!identical(existing_tracker, tracker)) {
      stop("study_setup(): _study.yml already exists for Study Tracker ID ",
           existing_tracker, call. = FALSE)
    }
  }

  layout <- if (!existed || !length(entries)) {
    "numbered"
  } else {
    .study_layout(root)
  }

  if (!dir.exists(root) && !dir.create(root, recursive = TRUE)) {
    stop("study_setup(): could not create root: ", root, call. = FALSE)
  }
  root <- normalizePath(root, mustWork = TRUE)

  folders <- .study_folders()
  leaves <- if (layout == "numbered") unname(folders) else names(folders)
  for (leaf in leaves) {
    path <- file.path(root, leaf)
    if (!dir.exists(path) && !dir.create(path)) {
      stop("study_setup(): could not create directory: ", path,
           call. = FALSE)
    }
  }

  identity <- list(
    study = study,
    study_tracker_id = tracker,
    umbrella = umbrella,
    owner = owner,
    irb_number = irb_number,
    cvir_no = cvir_no,
    study_creation_date = study_creation_date,
    identity_source = identity_source,
    identity_verified = identical(identity_source, "tracker"),
    population = NULL,
    built = NULL,
    citation = NULL
  )
  if (!identity_exists) {
    .study_write_atomic(identity, yml)
  }
  .study_write_lines_if_missing(
    "RENV_CONFIG_CACHE_SYMLINKS=FALSE",
    file.path(root, ".Renviron")
  )
  .study_write_lines_if_missing(
    .study_renvignore(),
    file.path(root, ".renvignore")
  )

  # An R project beside _study.yml means opening the project, here::here()
  # and study_root() all name the same directory. An existing project, of
  # any name, is the author's and is left alone.
  if (!length(list.files(root, pattern = "[.]Rproj$", all.files = TRUE))) {
    .study_write_lines_if_missing(
      c("Version: 1.0", "", "RestoreWorkspace: No", "SaveWorkspace: No",
        "AlwaysSaveHistory: No", "", "EnableCodeIndexing: Yes",
        "Encoding: UTF-8"),
      file.path(root, paste0(basename(root), ".Rproj"))
    )
  }

  study_status(root)
}
