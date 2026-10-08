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

.registration_rename <- function(from, to) {
  file.rename(from, to)
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
      restore_failures <- character(0)
      for (i in which(backed_up)) {
        restored <- .registration_rename(backups[[i]], targets[[i]])
        if (!restored) {
          restore_failures <- c(
            restore_failures,
            paste0(targets[[i]], " (backup: ", backups[[i]], ")")
          )
        }
      }
      if (length(restore_failures)) {
        warning(
          "register_data(): could not restore: ",
          paste(restore_failures, collapse = "; "),
          "; each backup remains in place",
          call. = FALSE
        )
      }
    }
    unlink(prepared[file.exists(prepared)])
    if (complete) unlink(backups[file.exists(backups)])
  }, add = TRUE)

  for (i in which(existed)) {
    if (!.registration_rename(targets[[i]], backups[[i]])) {
      stop("register_data(): could not prepare existing manifest: ",
           targets[[i]], call. = FALSE)
    }
    backed_up[[i]] <- TRUE
  }

  for (i in seq_along(targets)) {
    if (!.registration_rename(prepared[[i]], targets[[i]])) {
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
#' dataset. The function derives row and column counts from the file and
#' replaces \code{_study.yml} and \code{manifest.yaml} only after both updated
#' files have been prepared successfully.
#'
#' Registration converts the file once to a dated parquet in the same folder,
#' \code{<name>_YYYYMMDD.parquet}, with its column record beside it as
#' \code{<name>_YYYYMMDD.schema.csv}. That parquet is what \code{\link{read_built}}
#' and the job templates read, so the source file may be rebuilt freely; run
#' \code{\link{update_manifest}()} to register a rebuilt file as a new version.
#' The date is the file's modification date unless \code{extract_date} is given.
#' Conversion needs the \pkg{arrow} package. A release-aware registration
#' (\code{catalog_dataset} and \code{release_id}) records the catalog's file as
#' it is and converts nothing.
#'
#' A dataset is registered once: registering it again stops with "already
#' registered". So a study whose datasets are already registered adds
#' \code{kind}, \code{key} or \code{parents} by editing that dataset's entry in
#' \code{_study.yml}, then running \code{\link{update_manifest}()}. The key is
#' checked when the next version is registered. A combined dataset records its
#' parents' versions only once its source has been rebuilt, and reads as out of
#' date until then. A release-aware dataset is skipped by
#' \code{update_manifest()}: its parents' versions are recorded when a release is
#' adopted with \code{\link{adopt_data_update}()}, and its key is checked only at
#' registration.
#'
#' @param root Character. Study root or a directory beneath it.
#' @param built Character(1). Dataset filename within the logical
#'   \code{datasets} directory, including its extension.
#' @param dataset Character(1). Logical dataset name. \code{"study"} is
#'   reserved for the default, and \code{"built"} is a second name for it.
#' @param role Character. Either \code{"study"} or \code{"named"}.
#' @param population Character(1) or \code{NULL}. Population description.
#' @param source Character(1) or \code{NULL}. Data-source description.
#' @param extract_date Character, \code{Date}, or \code{NULL}. Extraction
#'   date. The file modification date is used when omitted.
#' @param catalog_dataset,release_id Character(1) or \code{NULL}. Producer
#'   catalog dataset ID and exact published release ID. Supply both to make
#'   the study contract release-aware, or neither for a legacy registration.
#' @param kind Character(1) or \code{NULL}. What the dataset is:
#'   \code{"built"} (the study dataset), \code{"subset"}, \code{"ancillary"}
#'   (many rows per patient, such as echoes or labs, joined to the cohort by a
#'   job) or \code{"combined"} (built by joining others).
#' @param key Character or \code{NULL}. The columns that make each row unique,
#'   such as \code{c("ccfid", "echo_date")}. Checked at registration, which
#'   stops if any row repeats on it. Jobs use it unless they set their own.
#' @param parents Character or \code{NULL}. For \code{kind = "combined"} only:
#'   the registered datasets it was built from. Their current versions are
#'   recorded, so a later update to a parent marks this dataset out of date.
#'
#' @return An object of class \code{"study_status"}, returned visibly.
#'
#' @seealso \code{\link{study_setup}}, \code{\link{study_config}},
#'   \code{\link{update_manifest}}
#'
#' @export
register_data <- function(root = getwd(), built, dataset = "study",
                          role = c("study", "named"),
                          population = NULL, source = NULL,
                          extract_date = NULL,
                          catalog_dataset = NULL, release_id = NULL,
                          kind = NULL, key = NULL, parents = NULL) {
  role <- match.arg(role)
  scalar <- function(x, name, required = FALSE) {
    .study_scalar(x, name, required, caller = "register_data")
  }
  built <- scalar(built, "built", required = TRUE)
  dataset <- scalar(dataset, "dataset", required = TRUE)
  if (identical(role, "named") && identical(dataset, "built")) {
    stop("register_data(): \"built\" is reserved: it is a second name for the study dataset. ",
         "Give the named dataset another name.", call. = FALSE)
  }
  dataset <- .canonical_dataset(dataset)
  population <- scalar(population, "population")
  source <- scalar(source, "source")
  catalog_dataset <- scalar(catalog_dataset, "catalog_dataset")
  release_id <- scalar(release_id, "release_id")

  if (xor(is.null(catalog_dataset), is.null(release_id))) {
    stop("register_data(): catalog_dataset and release_id must be supplied ",
         "together", call. = FALSE)
  }
  if (!is.null(catalog_dataset) &&
        !.catalog_valid_dataset_id(catalog_dataset)) {
    stop("register_data(): catalog_dataset is invalid", call. = FALSE)
  }
  if (!is.null(release_id) && !.catalog_valid_release_id(release_id)) {
    stop("register_data(): release_id is invalid", call. = FALSE)
  }

  if (!is.null(parents) && !identical(kind, "combined")) {
    stop("register_data(): parents are recorded only for kind = \"combined\".", call. = FALSE)
  }

  if (!identical(basename(built), built) ||
        !nzchar(tools::file_ext(built))) {
    stop("register_data(): built must be one filename with its extension",
         call. = FALSE)
  }
  if (role == "study") {
    if (!identical(dataset, "study")) {
      stop("register_data(): role = 'study' requires dataset = 'study'",
           call. = FALSE)
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
  existing <- if (role == "study" && !is.null(raw$built)) {
    list(
      built = raw$built,
      population = raw$population,
      release = raw$release
    )
  } else if (role == "named") {
    raw$additional_datasets[[dataset]]
  } else {
    NULL
  }
  migrating <- !is.null(release_id) && !is.null(existing) &&
    is.null(existing$release) && identical(existing$built, built)
  if (role == "study" && !is.null(raw$built) && !migrating) {
    stop("register_data(): the default dataset is already registered",
         call. = FALSE)
  }
  if (role == "named" &&
        !is.null(raw$additional_datasets[[dataset]]) && !migrating) {
    stop("register_data(): dataset '", dataset, "' is already registered",
         call. = FALSE)
  }

  path <- file.path(study_dir("datasets", cfg$root), built)
  if (!file.exists(path)) {
    stop("register_data(): dataset is missing: ", path, call. = FALSE)
  }
  release <- NULL
  if (!is.null(release_id)) {
    catalog <- .read_dataset_catalog(.catalog_path(cfg))
    release <- .catalog_release(catalog, catalog_dataset, release_id)
    if (!identical(release$status, "published")) {
      stop("register_data(): release is withdrawn: ", release_id,
           call. = FALSE)
    }
    if (!identical(release$file, built)) {
      stop("register_data(): release ", release_id, " does not name ", built,
           call. = FALSE)
    }
    .verify_catalog_file(release, study_dir("datasets", cfg$root))

    if (!is.null(extract_date)) {
      supplied_date <- format(as.Date(extract_date), "%Y-%m-%d")
      if (!identical(supplied_date, release$extract_date)) {
        stop("register_data(): extract_date disagrees with the catalog",
             call. = FALSE)
      }
    }
    if (!is.null(source) && !identical(source, release$source)) {
      stop("register_data(): source disagrees with the catalog",
           call. = FALSE)
    }
    extract_date <- release$extract_date
    source <- release$source
  }
  # A release-aware contract records the catalog's file as it is; every other
  # registration converts the file to a dated parquet below, which reads it.
  data <- if (!is.null(release)) .read_registration_data(path) else NULL
  if (!is.null(release)) .check_registration_key(data, key, built, "register_data")
  if (!is.null(release)) {
    .verify_catalog_file(release, study_dir("datasets", cfg$root))
  }
  if (!is.null(release) &&
        (!identical(nrow(data), release$n_rows) ||
           !identical(ncol(data), release$n_cols))) {
    stop("register_data(): observed dimensions disagree with the catalog: ",
         nrow(data), " x ", ncol(data), " versus ", release$n_rows, " x ",
         release$n_cols, call. = FALSE)
  }
  if (role == "study") {
    raw$built <- built
    if (!is.null(kind)) raw$kind <- kind
    if (!is.null(key)) raw$key <- key
    if (!is.null(population)) {
      raw$population <- population
    } else if (migrating) {
      raw$population <- existing$population
    }
    if (!is.null(release)) {
      raw$release <- list(
        dataset_id = catalog_dataset,
        release_id = release_id
      )
    }
  } else {
    if (is.null(raw$additional_datasets)) {
      raw$additional_datasets <- list()
    }
    if (!is.list(raw$additional_datasets)) {
      stop("register_data(): additional_datasets must be a mapping",
           call. = FALSE)
    }
    contract <- existing
    if (is.null(contract)) {
      contract <- list(built = built, population = population)
    } else if (!is.null(population)) {
      contract$population <- population
    }
    if (!is.null(release)) {
      contract$release <- list(
        dataset_id = catalog_dataset,
        release_id = release_id
      )
    }
    if (!is.null(kind)) contract$kind <- kind
    if (!is.null(key)) contract$key <- key
    if (!is.null(parents)) contract$parents <- parents
    raw$additional_datasets[[dataset]] <- contract
  }

  if (is.null(extract_date)) extract_date <- .mtime_date(path)
  manifest_path <- file.path(cfg$root, "manifest.yaml")
  prior <- if (file.exists(manifest_path)) .read_manifest(manifest_path)$datasets
  clash <- .cache_name_clash(built, prior)
  if (!is.null(clash)) {
    stop("register_data(): ", built, " would be read through ", basename(.derived_paths(built)$parquet),
         ", which is the registered version of ", clash$file, ". Nothing was written. Rename ", built,
         " (for a catalog release, ask the data manager to publish it under another name) and run ",
         "register_data() again.", call. = FALSE)
  }
  version_files <- character()
  entry <- if (is.null(release)) {
    version <- .write_version(path, dirname(path), extract_date, taken = .reserved_names(prior), key = key)
    version_files <- file.path(dirname(path), c(version$parquet, .version_schema_name(version$parquet)))
    .versioned_entry(built, version, extra = if (is.null(source)) list() else list(source = source))
  } else {
    .registration_manifest_entry(path, data, extract_date, source)
  }
  registered <- FALSE
  on.exit(if (!registered) unlink(version_files), add = TRUE)
  if (!is.null(parents)) entry$parent_versions <- .parent_versions(cfg, parents, list(datasets = prior))
  if (!is.null(release) &&
        (!identical(entry$sha256, release$sha256) ||
           !identical(entry$n_rows, release$n_rows) ||
           !identical(entry$n_cols, release$n_cols))) {
    stop(
      "register_data(): prepared manifest entry disagrees with the catalog",
      call. = FALSE
    )
  }
  manifest <- if (file.exists(manifest_path)) {
    .read_manifest(manifest_path)
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
  files <- vapply(
    manifest$datasets,
    function(item) {
      if (!is.character(item$file) || length(item$file) != 1L ||
            is.na(item$file) || !nzchar(item$file)) {
        stop("register_data(): manifest.yaml has an invalid dataset entry",
             call. = FALSE)
      }
      item$file
    },
    character(1)
  )
  listed <- vapply(
    manifest$datasets,
    function(item) identical(item$file, built),
    logical(1)
  )
  if (migrating && sum(listed) != 1L) {
    stop("register_data(): migration requires exactly one manifest entry for ",
         built, call. = FALSE)
  }
  if (any(listed) && !migrating) {
    stop("register_data(): ", built, " is already listed in manifest.yaml",
         call. = FALSE)
  }
  stem <- tools::file_path_sans_ext(built)
  existing_stems <- tools::file_path_sans_ext(files)
  other <- !listed
  if (stem %in% existing_stems[other]) {
    conflict <- files[other][[match(stem, existing_stems[other])]]
    stop(
      "register_data(): ", built, " and ", conflict,
      " share the derived path stem '", stem, "'",
      call. = FALSE
    )
  }
  if (migrating) {
    manifest$datasets[[which(listed)]] <- entry
  } else {
    manifest$datasets <- c(manifest$datasets, list(entry))
  }

  targets <- c(cfg$file, manifest_path)
  prepared <- c(
    tempfile(pattern = "._study-", tmpdir = cfg$root),
    tempfile(pattern = ".manifest-", tmpdir = cfg$root)
  )
  on.exit(unlink(prepared[file.exists(prepared)]), add = TRUE)
  .study_validate_shapes(raw, cfg$file)
  yaml::write_yaml(raw, prepared[[1L]])
  .write_manifest(manifest, prepared[[2L]])
  .replace_study_pair(prepared, targets)
  registered <- TRUE

  study_status(cfg$root)
}
