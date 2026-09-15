# Data registration is the second half of study setup. Both manifests are
# prepared completely before either authoritative file is moved, then replaced
# as a recoverable pair.

.registration_manifest_entry <- function(path, data, extract_date, source) {
  entry <- list(
    file = basename(path),
    extract_date = format(as.Date(extract_date), "%Y-%m-%d"),
    n_rows = as.integer(nrow(data)),
    sha256 = digest::digest(path, algo = "sha256", file = TRUE),
    role = "source",
    n_cols = as.integer(ncol(data))
  )
  if (!is.null(source)) entry$source <- source
  entry
}

.replace_study_pair <- function(prepared, targets) {
  backups <- vapply(
    targets,
    function(path) {
      tempfile(
        pattern = paste0(".", basename(path), "-backup-"),
        tmpdir = dirname(path)
      )
    },
    character(1)
  )
  existed <- file.exists(targets)
  backed_up <- logical(length(targets))
  placed <- logical(length(targets))
  complete <- FALSE

  on.exit({
    if (!complete) {
      unlink(targets[placed])
      for (i in which(backed_up)) {
        file.rename(backups[[i]], targets[[i]])
      }
    }
    unlink(prepared[file.exists(prepared)])
    unlink(backups[file.exists(backups)])
  }, add = TRUE)

  for (i in which(existed)) {
    if (!file.rename(targets[[i]], backups[[i]])) {
      stop("register_data(): could not prepare existing manifest: ",
           targets[[i]], call. = FALSE)
    }
    backed_up[[i]] <- TRUE
  }

  for (i in seq_along(targets)) {
    if (!file.rename(prepared[[i]], targets[[i]])) {
      stop("register_data(): could not move prepared manifest into place: ",
           targets[[i]], call. = FALSE)
    }
    placed[[i]] <- TRUE
  }

  complete <- TRUE
  invisible(targets)
}

.read_registration_data <- function(path) {
  data <- as.data.frame(read_clinical_data(path, convert_types = FALSE))
  .assert_no_lowercase_collision(data, path)
  names(data) <- tolower(names(data))
  data
}

#' Register a study dataset
#'
#' @description
#' Completes the default study data contract or adds one distinctly named
#' dataset. The function derives row and cohort counts from the file and
#' replaces \code{_study.yml} and \code{manifest.yaml} only after both updated
#' files have been prepared successfully.
#'
#' @param root Character. Study root or a directory beneath it.
#' @param built Character(1). Dataset filename within the logical
#'   \code{datasets} directory, including its extension.
#' @param event,time Character(1) or \code{NULL}. Event and follow-up columns.
#'   Supply both or neither. The default study dataset requires both.
#' @param dataset Character(1). Logical dataset name. \code{"study"} is
#'   reserved for the default.
#' @param role Character. Either \code{"study"} or \code{"named"}.
#' @param population Character(1) or \code{NULL}. Population description.
#' @param source Character(1) or \code{NULL}. Data-source description.
#' @param extract_date Character, \code{Date}, or \code{NULL}. Extraction
#'   date. The file modification date is used when omitted.
#'
#' @return An object of class \code{"study_status"}, returned visibly.
#'
#' @seealso \code{\link{study_setup}}, \code{\link{study_config}},
#'   \code{\link{update_manifest}}
#'
#' @export
register_data <- function(root = getwd(), built, event = NULL, time = NULL,
                          dataset = "study",
                          role = c("study", "named"),
                          population = NULL, source = NULL,
                          extract_date = NULL) {
  role <- match.arg(role)
  scalar <- function(x, name, required = FALSE) {
    .study_scalar(x, name, required, caller = "register_data")
  }
  built <- scalar(built, "built", required = TRUE)
  dataset <- scalar(dataset, "dataset", required = TRUE)
  population <- scalar(population, "population")
  source <- scalar(source, "source")

  if (!identical(basename(built), built) ||
        !nzchar(tools::file_ext(built))) {
    stop("register_data(): built must be one filename with its extension",
         call. = FALSE)
  }
  if (xor(is.null(event), is.null(time))) {
    stop("register_data(): event and time must be supplied together",
         call. = FALSE)
  }
  if (!is.null(event)) {
    event <- tolower(scalar(event, "event", required = TRUE))
    time <- tolower(scalar(time, "time", required = TRUE))
  }

  if (role == "study") {
    if (!identical(dataset, "study")) {
      stop("register_data(): role = 'study' requires dataset = 'study'",
           call. = FALSE)
    }
    if (is.null(event)) {
      stop("register_data(): the default study dataset requires event and ",
           "time", call. = FALSE)
    }
  } else {
    if (identical(dataset, "study") ||
          !grepl("^[a-z][a-z0-9_]*$", dataset)) {
      stop("register_data(): a named dataset must have a non-reserved ",
           "lower-snake-case name", call. = FALSE)
    }
  }

  cfg <- study_config(root, require_data = FALSE)
  raw <- yaml::read_yaml(cfg$file)
  if (role == "study" && !is.null(raw$built)) {
    stop("register_data(): the default dataset is already registered",
         call. = FALSE)
  }
  if (role == "named" &&
        !is.null(raw$additional_datasets[[dataset]])) {
    stop("register_data(): dataset '", dataset, "' is already registered",
         call. = FALSE)
  }

  path <- file.path(study_dir("datasets", cfg$root), built)
  if (!file.exists(path)) {
    stop("register_data(): dataset is missing: ", path, call. = FALSE)
  }
  data <- .read_registration_data(path)
  cohort <- if (is.null(event)) {
    NULL
  } else {
    counts <- cohort_counts(
      data,
      list(cohort = list(event = event, time = time))
    )
    c(counts, list(event = event, time = time))
  }

  if (role == "study") {
    raw$built <- built
    if (!is.null(population)) raw$population <- population
    raw$cohort <- cohort
  } else {
    if (is.null(raw$additional_datasets)) {
      raw$additional_datasets <- list()
    }
    if (!is.list(raw$additional_datasets)) {
      stop("register_data(): additional_datasets must be a mapping",
           call. = FALSE)
    }
    raw$additional_datasets[[dataset]] <- list(
      built = built,
      population = population,
      cohort = cohort
    )
  }

  if (is.null(extract_date)) extract_date <- as.Date(file.info(path)$mtime)
  entry <- .registration_manifest_entry(
    path,
    data,
    extract_date,
    source
  )
  manifest_path <- file.path(cfg$root, "manifest.yaml")
  manifest <- if (file.exists(manifest_path)) {
    yaml::read_yaml(manifest_path)
  } else {
    list()
  }
  if (is.null(manifest)) manifest <- list()
  if (!is.list(manifest) ||
        (!is.null(manifest$datasets) && !is.list(manifest$datasets))) {
    stop("register_data(): manifest.yaml has an invalid datasets field",
         call. = FALSE)
  }
  if (is.null(manifest$datasets)) manifest$datasets <- list()
  listed <- vapply(
    manifest$datasets,
    function(item) identical(item$file, built),
    logical(1)
  )
  if (any(listed)) {
    stop("register_data(): ", built, " is already listed in manifest.yaml",
         call. = FALSE)
  }
  manifest$datasets <- c(manifest$datasets, list(entry))

  targets <- c(cfg$file, manifest_path)
  prepared <- c(
    tempfile(pattern = "._study-", tmpdir = cfg$root),
    tempfile(pattern = ".manifest-", tmpdir = cfg$root)
  )
  on.exit(unlink(prepared[file.exists(prepared)]), add = TRUE)
  yaml::write_yaml(raw, prepared[[1L]])
  yaml::write_yaml(manifest, prepared[[2L]])
  .replace_study_pair(prepared, targets)

  study_status(cfg$root)
}
