# Published dataset release catalogs are producer-owned state. These helpers
# validate that boundary before any study contract trusts a release record.

.catalog_abort <- function(message) {
  stop("dataset catalog: ", message, call. = FALSE)
}

.catalog_scalar <- function(x, name, type = "character") {
  valid <- length(x) == 1L
  if (valid) valid <- !is.na(x)
  if (valid && identical(type, "character")) {
    valid <- is.character(x) && nzchar(x)
  }
  if (valid && identical(type, "integer")) {
    valid <- is.numeric(x) && is.finite(x) &&
      x >= -.Machine$integer.max && x <= .Machine$integer.max &&
      x == as.integer(x)
  }
  if (!valid) .catalog_abort(paste0(name, " is invalid"))
  if (identical(type, "integer")) as.integer(x) else x
}

.catalog_named_mapping <- function(x, name) {
  has_names <- !is.null(names(x)) && length(names(x)) == length(x) &&
    all(nzchar(names(x))) && !anyDuplicated(names(x))
  if (!is.list(x) || (length(x) && !has_names)) {
    .catalog_abort(paste0(name, " must be a named mapping"))
  }
  x
}

.catalog_valid_dataset_id <- function(x) {
  grepl("^[a-z][a-z0-9_]*$", x)
}

.catalog_valid_release_id <- function(x) {
  grepl("^[a-z0-9][a-z0-9_-]*$", x) && !identical(x, "latest")
}

.catalog_valid_file <- function(x) {
  identical(basename(x), x) && nzchar(tools::file_ext(x))
}

.catalog_valid_date <- function(x) {
  parsed <- suppressWarnings(as.Date(x, format = "%Y-%m-%d"))
  !is.na(parsed) && identical(format(parsed, "%Y-%m-%d"), x)
}

.catalog_valid_timestamp <- function(x) {
  shape <- grepl(
    paste0(
      "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}",
      "(Z|[+-][0-9]{2}:[0-9]{2})$"
    ),
    x
  )
  compact <- sub("Z$", "+0000", x)
  compact <- sub("([+-][0-9]{2}):([0-9]{2})$", "\\1\\2", compact)
  parsed <- suppressWarnings(strptime(
    compact,
    format = "%Y-%m-%dT%H:%M:%S%z",
    tz = "UTC"
  ))
  shape && !is.na(parsed)
}

.catalog_validate_release <- function(release, dataset_id, index) {
  where <- paste0("datasets.", dataset_id, ".releases[", index, "]")
  if (!is.list(release)) {
    .catalog_abort(paste0(where, " must be a mapping"))
  }
  required <- c(
    "release_id", "sequence", "file", "extract_date", "revision",
    "published_at", "sha256", "n_rows", "n_cols", "status"
  )
  missing <- required[!vapply(required, function(x) {
    !is.null(release[[x]])
  }, logical(1))]
  if (length(missing)) {
    .catalog_abort(paste0(where, " is missing ", paste(missing, collapse = ", ")))
  }

  release$release_id <- .catalog_scalar(
    release$release_id,
    paste0(where, ".release_id")
  )
  if (!.catalog_valid_release_id(release$release_id)) {
    .catalog_abort(paste0(where, ".release_id is invalid"))
  }
  release$sequence <- .catalog_scalar(
    release$sequence,
    paste0(where, ".sequence"),
    "integer"
  )
  release$revision <- .catalog_scalar(
    release$revision,
    paste0(where, ".revision"),
    "integer"
  )
  release$n_rows <- .catalog_scalar(
    release$n_rows,
    paste0(where, ".n_rows"),
    "integer"
  )
  release$n_cols <- .catalog_scalar(
    release$n_cols,
    paste0(where, ".n_cols"),
    "integer"
  )
  if (release$sequence < 1L) {
    .catalog_abort(paste0(where, ".sequence must be positive"))
  }
  if (release$revision < 1L) {
    .catalog_abort(paste0(where, ".revision must be positive"))
  }
  if (release$n_rows < 0L) {
    .catalog_abort(paste0(where, ".n_rows must be non-negative"))
  }
  if (release$n_cols < 1L) {
    .catalog_abort(paste0(where, ".n_cols must be positive"))
  }

  release$file <- .catalog_scalar(release$file, paste0(where, ".file"))
  if (!.catalog_valid_file(release$file)) {
    .catalog_abort(paste0(where, ".file must be one basename with an extension"))
  }
  release$extract_date <- .catalog_scalar(
    release$extract_date,
    paste0(where, ".extract_date")
  )
  if (!.catalog_valid_date(release$extract_date)) {
    .catalog_abort(paste0(where, ".extract_date is invalid"))
  }
  release$published_at <- .catalog_scalar(
    release$published_at,
    paste0(where, ".published_at")
  )
  if (!.catalog_valid_timestamp(release$published_at)) {
    .catalog_abort(paste0(where, ".published_at is invalid"))
  }
  release$sha256 <- .catalog_scalar(
    release$sha256,
    paste0(where, ".sha256")
  )
  if (!grepl("^[0-9a-f]{64}$", release$sha256)) {
    .catalog_abort(paste0(where, ".sha256 is invalid"))
  }
  release$status <- .catalog_scalar(
    release$status,
    paste0(where, ".status")
  )
  if (!release$status %in% c("published", "withdrawn")) {
    .catalog_abort(paste0(where, ".status is invalid"))
  }
  if (!is.null(release$source)) {
    release$source <- .catalog_scalar(
      release$source,
      paste0(where, ".source")
    )
  }
  if (identical(release$status, "withdrawn")) {
    release$withdrawal_reason <- .catalog_scalar(
      release$withdrawal_reason,
      paste0(where, ".withdrawal_reason")
    )
  }
  if (!is.null(release$replacement_release_id)) {
    release$replacement_release_id <- .catalog_scalar(
      release$replacement_release_id,
      paste0(where, ".replacement_release_id")
    )
    if (!.catalog_valid_release_id(release$replacement_release_id)) {
      .catalog_abort(paste0(where, ".replacement_release_id is invalid"))
    }
  }
  release
}

.read_dataset_catalog <- function(path) {
  if (!file.exists(path)) {
    .catalog_abort(paste0("file not found: ", path))
  }
  catalog <- yaml::read_yaml(path)
  if (!is.list(catalog)) .catalog_abort("root must be a mapping")
  version <- .catalog_scalar(
    catalog$format_version,
    "format_version",
    "integer"
  )
  if (!identical(version, 1L)) {
    .catalog_abort(paste0("unsupported format_version: ", version))
  }
  datasets <- .catalog_named_mapping(catalog$datasets, "datasets")

  for (dataset_id in names(datasets)) {
    if (!.catalog_valid_dataset_id(dataset_id)) {
      .catalog_abort(paste0("invalid dataset_id: ", dataset_id))
    }
    dataset <- datasets[[dataset_id]]
    if (!is.list(dataset) || !is.list(dataset$releases) ||
          !length(dataset$releases)) {
      .catalog_abort(paste0("datasets.", dataset_id,
                            ".releases must be a non-empty sequence"))
    }
    releases <- lapply(seq_along(dataset$releases), function(i) {
      .catalog_validate_release(dataset$releases[[i]], dataset_id, i)
    })
    ids <- vapply(releases, function(x) x$release_id, character(1))
    sequences <- vapply(releases, function(x) x$sequence, integer(1))
    if (anyDuplicated(ids)) {
      .catalog_abort(paste0("datasets.", dataset_id,
                            ".releases contains a duplicate release_id"))
    }
    if (anyDuplicated(sequences)) {
      .catalog_abort(paste0("datasets.", dataset_id,
                            ".releases contains a duplicate sequence"))
    }
    if (length(sequences) > 1L && any(diff(sequences) <= 0L)) {
      .catalog_abort(paste0("datasets.", dataset_id,
                            ".releases sequence must be strictly increasing"))
    }
    extract_dates <- vapply(releases, function(x) x$extract_date, character(1))
    for (extract_date in unique(extract_dates)) {
      revisions <- vapply(
        releases[extract_dates == extract_date],
        function(x) x$revision,
        integer(1)
      )
      if (!identical(revisions, seq_along(revisions))) {
        .catalog_abort(paste0(
          "datasets.", dataset_id,
          ".releases revision must start at 1 and increase by 1 for ",
          "extract_date ", extract_date
        ))
      }
    }
    replacements <- vapply(releases, function(x) {
      if (is.null(x$replacement_release_id)) "" else x$replacement_release_id
    }, character(1))
    unknown <- setdiff(replacements[nzchar(replacements)], ids)
    if (length(unknown)) {
      .catalog_abort(paste0("datasets.", dataset_id,
                            " has unknown replacement_release_id: ",
                            paste(unknown, collapse = ", ")))
    }
    dataset$releases <- releases
    datasets[[dataset_id]] <- dataset
  }

  files <- unlist(lapply(datasets, function(dataset) {
    vapply(dataset$releases, function(x) x$file, character(1))
  }), use.names = FALSE)
  repeated <- unique(files[duplicated(files)])
  if (length(repeated)) {
    .catalog_abort(paste0("file listed more than once: ",
                          paste(repeated, collapse = ", ")))
  }

  catalog$format_version <- version
  catalog$datasets <- datasets
  catalog
}

.catalog_path <- function(cfg) {
  file.path(study_dir("datasets", cfg$root), "dataset-catalog.yml")
}

.catalog_release <- function(catalog, dataset_id, release_id) {
  dataset <- catalog$datasets[[dataset_id]]
  if (is.null(dataset)) {
    .catalog_abort(paste0("unknown dataset_id '", dataset_id, "'"))
  }
  hit <- vapply(dataset$releases, function(x) {
    identical(x$release_id, release_id)
  }, logical(1))
  if (sum(hit) != 1L) {
    .catalog_abort(paste0("unknown release_id '", release_id,
                          "' for '", dataset_id, "'"))
  }
  dataset$releases[[which(hit)]]
}

.catalog_file <- function(release, data_dir) {
  file.path(data_dir, release$file)
}

.verify_catalog_file <- function(release, data_dir) {
  path <- .catalog_file(release, data_dir)
  actual <- if (file.exists(path)) {
    digest::digest(path, algo = "sha256", file = TRUE)
  } else {
    NA_character_
  }
  if (is.na(actual) || !identical(actual, release$sha256)) {
    msg <- if (is.na(actual)) {
      paste0("published release is missing: ", path)
    } else {
      paste0("published release changed in place: ", release$file,
             "\n  expected: ", release$sha256,
             "\n  actual:   ", actual)
    }
    stop(structure(
      list(message = msg, call = NULL, release = release),
      class = c("hvtiRutilities_release_integrity", "error", "condition")
    ))
  }
  path
}
