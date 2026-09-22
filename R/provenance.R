# Provenance capture and publication are separate. Capture freezes the R
# session and explicit input records while the job is executing. Publication
# later binds that payload to the completed rendered output.

.provenance_required <- function() {
  c(
    job = "character",
    rendered = "character",
    study = "list",
    r = "list",
    packages = "list",
    renv_lock = "list",
    data = "list",
    artifacts = "list"
  )
}

.provenance_reserved <- function() {
  c(names(.provenance_required()), "output")
}

.loaded_packages <- function() {
  namespaces <- sort(loadedNamespaces())
  lapply(namespaces, function(package) {
    description <- tryCatch(
      utils::packageDescription(package),
      error = function(e) NULL
    )
    source <- if (is.null(description)) {
      NA_character_
    } else if (!is.null(description$RemoteType)) {
      description$RemoteType
    } else if (!is.null(description$Repository)) {
      description$Repository
    } else if (identical(description$Priority, "base")) {
      "base"
    } else {
      NA_character_
    }
    list(
      package = package,
      version = as.character(utils::packageVersion(package)),
      source = source
    )
  })
}

.provenance_scalar_character <- function(value, name, caller) {
  valid <- is.character(value) && length(value) == 1L &&
    !is.na(value) && nzchar(value)
  if (!valid) {
    stop(caller, "(): `", name,
         "` must be one non-empty character string.", call. = FALSE)
  }
  value
}

.provenance_role <- function(role, caller) {
  .provenance_scalar_character(role, "role", caller)
}

.provenance_is_absolute <- function(path) {
  grepl("^(/|[A-Za-z]:[/\\\\]|\\\\\\\\)", path)
}

.provenance_relative_path <- function(path, cfg, caller) {
  .provenance_scalar_character(path, "path", caller)
  root <- normalizePath(cfg$root, winslash = "/", mustWork = TRUE)
  if (!.provenance_is_absolute(path) &&
        grepl("(^|[/\\\\])\\.\\.($|[/\\\\])", path)) {
    stop(caller, "(): path is outside the study root: ", path,
         call. = FALSE)
  }
  candidate <- if (.provenance_is_absolute(path)) {
    path
  } else {
    file.path(root, path)
  }
  unresolved <- normalizePath(candidate, winslash = "/", mustWork = FALSE)
  prefix <- paste0(root, "/")
  if (!startsWith(unresolved, prefix)) {
    stop(caller, "(): path is outside the study root: ", path,
         call. = FALSE)
  }
  if (!file.exists(candidate)) {
    stop(caller, "(): missing file: ", path, call. = FALSE)
  }
  resolved <- normalizePath(candidate, winslash = "/", mustWork = TRUE)
  if (!startsWith(resolved, prefix)) {
    stop(caller, "(): path resolves outside the study root: ", path,
         call. = FALSE)
  }
  if (dir.exists(resolved)) {
    stop(caller, "(): path must name a regular file: ", path,
         call. = FALSE)
  }
  list(
    absolute = resolved,
    relative = substring(resolved, nchar(prefix) + 1L)
  )
}

.provenance_file_snapshot <- function(path, relative, caller) {
  before <- file.info(path)
  if (is.na(before$size) || isTRUE(before$isdir)) {
    stop(caller, "(): path must name a readable regular file: ", path,
         call. = FALSE)
  }
  sha256 <- tryCatch(
    digest::digest(path, algo = "sha256", file = TRUE),
    error = function(e) {
      stop(caller, "(): could not hash ", path, ": ", conditionMessage(e),
           call. = FALSE)
    }
  )
  after <- file.info(path)
  unchanged <- identical(unname(before$size), unname(after$size)) &&
    identical(as.numeric(before$mtime), as.numeric(after$mtime))
  if (!unchanged) {
    stop(caller, "(): file changed while it was being recorded: ", path,
         call. = FALSE)
  }
  list(
    path = relative,
    bytes = unname(as.numeric(before$size)),
    mtime = format(before$mtime, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    sha256 = sha256
  )
}

.provenance_record_path_valid <- function(path) {
  is.character(path) && length(path) == 1L && !is.na(path) &&
    nzchar(path) && !.provenance_is_absolute(path) &&
    !grepl("\\\\", path) && !grepl("(^|/)\\.{1,2}(/|$)", path) &&
    !grepl("//|/$", path)
}

.provenance_named_shape <- function(value, fields) {
  is.list(value) && !is.null(names(value)) &&
    !anyDuplicated(names(value)) && setequal(names(value), fields)
}

.provenance_hash_valid <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) &&
    grepl("^[0-9a-f]{64}$", value)
}

.provenance_timestamp_valid <- function(value, fractional = FALSE) {
  if (!is.character(value) || length(value) != 1L || is.na(value)) {
    return(FALSE)
  }
  pattern <- if (fractional) {
    "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$"
  } else {
    "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
  }
  if (!grepl(pattern, value)) return(FALSE)
  whole_seconds <- sub("\\.[0-9]+Z$", "Z", value)
  parsed <- as.POSIXct(
    whole_seconds,
    format = "%Y-%m-%dT%H:%M:%SZ",
    tz = "UTC"
  )
  !is.na(parsed) && identical(
    format(parsed, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    whole_seconds
  )
}

.provenance_validate_record <- function(record, kind, index,
                                        caller = "capture_provenance") {
  fields <- if (identical(kind, "data")) {
    c("dataset", "path", "role", "bytes", "mtime", "sha256")
  } else {
    c("path", "role", "bytes", "mtime", "sha256")
  }
  label <- paste(kind, "record", index)
  named <- .provenance_named_shape(record, fields)
  valid_role <- named && is.character(record$role) &&
    length(record$role) == 1L && !is.na(record$role) && nzchar(record$role)
  valid_bytes <- named && is.numeric(record$bytes) &&
    length(record$bytes) == 1L && !is.na(record$bytes) &&
    is.finite(record$bytes) && record$bytes >= 0 &&
    record$bytes == floor(record$bytes)
  valid_mtime <- named && .provenance_timestamp_valid(
    record$mtime,
    fractional = TRUE
  )
  valid_hash <- named && .provenance_hash_valid(record$sha256)
  valid_dataset <- identical(kind, "artifact") ||
    (named && is.character(record$dataset) && length(record$dataset) == 1L &&
       !is.na(record$dataset) && nzchar(record$dataset))

  if (!named || !valid_role || !valid_bytes || !valid_mtime ||
        !valid_hash || !valid_dataset) {
    stop(caller, "(): malformed ", label, ".", call. = FALSE)
  }
  if (!.provenance_record_path_valid(record$path)) {
    stop(caller, "(): ", label,
         " path must be a canonical study-relative path.", call. = FALSE)
  }
  record[fields]
}

.provenance_validate_records <- function(records, kind,
                                         caller = "capture_provenance") {
  if (!is.list(records)) {
    stop(caller, "(): `", kind,
         "` must be a list of explicit records.", call. = FALSE)
  }
  if (length(records) == 0L) return(list())
  validated <- lapply(seq_along(records), function(index) {
    .provenance_validate_record(records[[index]], kind, index, caller)
  })
  paths <- vapply(validated, `[[`, "", "path")
  roles <- vapply(validated, `[[`, "", "role")
  datasets <- if (identical(kind, "data")) {
    vapply(validated, `[[`, "", "dataset")
  } else {
    rep.int("", length(validated))
  }
  validated[order(paths, roles, datasets, method = "radix")]
}

.provenance_validate_extra <- function(extra) {
  valid_names <- !is.null(names(extra)) && all(nzchar(names(extra))) &&
    !anyDuplicated(names(extra))
  valid <- is.list(extra) && (length(extra) == 0L || valid_names)
  if (!valid) {
    stop("capture_provenance(): `extra` must be a named list with unique, non-empty names.",
         call. = FALSE)
  }
  extra[setdiff(names(extra), .provenance_reserved())]
}

.provenance_validate_payload <- function(payload) {
  required <- names(.provenance_required())
  valid <- is.list(payload) && !is.null(names(payload)) &&
    !anyDuplicated(names(payload)) && all(required %in% names(payload))
  if (!valid) {
    stop("publish_provenance(): malformed captured payload.", call. = FALSE)
  }
  if ("output" %in% names(payload)) {
    stop("publish_provenance(): captured payload must not contain `output`.",
         call. = FALSE)
  }
  scalar <- function(value) {
    is.character(value) && length(value) == 1L &&
      !is.na(value) && nzchar(value)
  }
  study_valid <- .provenance_named_shape(
    payload$study,
    c("name", "file", "sha256")
  ) && scalar(payload$study$name) &&
    identical(payload$study$file, "_study.yml") &&
    .provenance_hash_valid(payload$study$sha256)
  r_valid <- .provenance_named_shape(
    payload$r,
    c("version", "platform")
  ) && scalar(payload$r$version) && scalar(payload$r$platform)
  lock_valid <- is.null(payload$renv_lock) || (
    .provenance_named_shape(payload$renv_lock, c("path", "sha256")) &&
      identical(payload$renv_lock$path, "renv.lock") &&
      .provenance_hash_valid(payload$renv_lock$sha256)
  )
  package_valid <- function(entry) {
    named <- .provenance_named_shape(
      entry,
      c("package", "version", "source")
    )
    source_valid <- named && (
      is.null(entry$source) ||
        (is.character(entry$source) && length(entry$source) == 1L &&
           (is.na(entry$source) || nzchar(entry$source)))
    )
    named && scalar(entry$package) && scalar(entry$version) && source_valid
  }
  packages_valid <- is.list(payload$packages) && length(payload$packages) > 0L &&
    all(vapply(payload$packages, package_valid, logical(1)))
  if (packages_valid) {
    package_names <- vapply(payload$packages, `[[`, "", "package")
    packages_valid <- !anyDuplicated(package_names)
  }
  valid <- scalar(payload$job) &&
    .provenance_timestamp_valid(payload$rendered) && study_valid && r_valid &&
    lock_valid && packages_valid
  if (!valid) {
    stop("publish_provenance(): malformed captured payload.", call. = FALSE)
  }
  payload$data <- .provenance_validate_records(
    payload$data,
    "data",
    "publish_provenance"
  )
  payload$artifacts <- .provenance_validate_records(payload$artifacts,
                                                    "artifact",
                                                    "publish_provenance")
  payload
}

.provenance_write_json <- function(record, path) {
  jsonlite::write_json(
    record,
    path,
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null",
    digits = NA
  )
}

.provenance_rename <- function(from, to) {
  file.rename(from, to)
}

#' Name the provenance sidecar for an output
#'
#' @description
#' Returns the path of the sidecar belonging to a rendered output: the output
#' path with its extension replaced by \code{.provenance.json}.
#'
#' @param path Character(1). Path to a rendered output.
#'
#' @return Character(1). The sidecar path.
#'
#' @seealso \code{\link{publish_provenance}},
#'   \code{\link{record_provenance}}
#'
#' @export
#'
#' @examples
#' provenance_path("_output/death-hz-ac.html")
provenance_path <- function(path) {
  file.path(
    dirname(path),
    paste0(tools::file_path_sans_ext(basename(path)), ".provenance.json")
  )
}

#' Snapshot a registered data file for provenance
#'
#' @description
#' Records the authoritative physical file selected by \code{dataset}. For a
#' manifest entry with \code{role: "primary"}, this is the promoted Parquet
#' file rather than the retired source. The returned plain list contains the
#' logical dataset name, a canonical study-relative path, its role, byte count,
#' modification time, and SHA-256 hash.
#'
#' @param dataset Character(1). Logical registered dataset name.
#' @param cfg List. A study manifest from \code{\link{study_config}}.
#' @param role Character(1). The file's role in this job.
#'
#' @return A plain list containing one immutable-by-convention data record.
#'
#' @seealso \code{\link{provenance_artifact}},
#'   \code{\link{capture_provenance}}
#'
#' @export
provenance_data <- function(dataset = "study", cfg = study_config(),
                            role = "analysis") {
  .provenance_role(role, "provenance_data")
  .study_dataset(cfg, dataset)
  source <- built_path(cfg, dataset)
  entry <- .manifest_entry(file.path(cfg$root, "manifest.yaml"), source)
  authoritative <- if (identical(entry$role, "primary")) {
    .derived_paths(source)$parquet
  } else {
    source
  }
  resolved <- .provenance_relative_path(
    authoritative,
    cfg,
    "provenance_data"
  )
  snapshot <- .provenance_file_snapshot(
    resolved$absolute,
    resolved$relative,
    "provenance_data"
  )
  c(list(dataset = dataset), snapshot["path"], list(role = role),
    snapshot[c("bytes", "mtime", "sha256")])
}

#' Snapshot an input artifact for provenance
#'
#' @description
#' Records an existing artifact beneath the study root by canonical
#' study-relative path, role, byte count, modification time, and SHA-256 hash.
#'
#' @param path Character(1). Existing artifact path, absolute or relative to
#'   the study root.
#' @param role Character(1). The artifact's role in this job.
#' @param cfg List. A study manifest from \code{\link{study_config}}.
#'
#' @return A plain list containing one immutable-by-convention artifact record.
#'
#' @seealso \code{\link{provenance_data}},
#'   \code{\link{capture_provenance}}
#'
#' @export
provenance_artifact <- function(path, role = "input", cfg = study_config()) {
  .provenance_role(role, "provenance_artifact")
  resolved <- .provenance_relative_path(path, cfg, "provenance_artifact")
  snapshot <- .provenance_file_snapshot(
    resolved$absolute,
    resolved$relative,
    "provenance_artifact"
  )
  c(snapshot["path"], list(role = role),
    snapshot[c("bytes", "mtime", "sha256")])
}

#' Capture an explicit job provenance payload
#'
#' @description
#' Freezes the study identity, executing R session, loaded packages, lockfile,
#' and explicit data and artifact records. Capture never resolves a current
#' dataset implicitly. Pass \code{list()} deliberately when a job has no known
#' direct data input.
#'
#' Capture does not write a sidecar or inspect a rendered output. Use
#' \code{\link{publish_provenance}} only after the completed output exists.
#'
#' @param job Character(1). Stable job identity.
#' @param data List of records returned by \code{\link{provenance_data}}.
#' @param artifacts List of records returned by
#'   \code{\link{provenance_artifact}}.
#' @param extra Named list of job-specific fields. Reserved capture and
#'   publication fields cannot be displaced.
#' @param cfg List. A study manifest from \code{\link{study_config}}.
#'
#' @return A captured provenance payload as a plain list.
#'
#' @seealso \code{\link{publish_provenance}},
#'   \code{\link{record_provenance}}
#'
#' @export
capture_provenance <- function(job, data, artifacts = list(), extra = list(),
                               cfg = study_config()) {
  .provenance_scalar_character(job, "job", "capture_provenance")
  if (missing(data)) {
    stop("capture_provenance(): `data` is required; pass `list()` deliberately for no direct data.",
         call. = FALSE)
  }
  data <- .provenance_validate_records(data, "data")
  artifacts <- .provenance_validate_records(artifacts, "artifact")
  extra <- .provenance_validate_extra(extra)

  lock <- file.path(cfg$root, "renv.lock")
  lock_record <- if (file.exists(lock)) {
    list(
      path = "renv.lock",
      sha256 = digest::digest(lock, algo = "sha256", file = TRUE)
    )
  } else {
    NULL
  }

  record <- list(
    job = job,
    rendered = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    study = list(
      name = cfg$study,
      file = basename(cfg$file),
      sha256 = digest::digest(cfg$file, algo = "sha256", file = TRUE)
    ),
    r = list(
      version = paste(R.version$major, R.version$minor, sep = "."),
      platform = R.version$platform
    ),
    packages = .loaded_packages(),
    renv_lock = lock_record,
    data = data,
    artifacts = artifacts
  )
  c(record, extra)
}

#' Publish captured provenance beside a completed output
#'
#' @description
#' Requires an existing regular output, binds its byte count and SHA-256 hash
#' to a previously captured payload, and writes the JSON sidecar through a
#' same-directory temporary file and rename. Capture-session facts are not
#' recomputed during publication.
#'
#' @param path Character(1). Existing completed output path.
#' @param payload A payload returned by \code{\link{capture_provenance}}.
#'
#' @return Invisibly, the published record as a list.
#'
#' @seealso \code{\link{capture_provenance}},
#'   \code{\link{record_provenance}}, \code{\link{provenance_path}}
#'
#' @export
publish_provenance <- function(path, payload) {
  .provenance_scalar_character(path, "path", "publish_provenance")
  if (!file.exists(path)) {
    stop("publish_provenance(): requires an existing completed output: ",
         path, call. = FALSE)
  }
  if (dir.exists(path)) {
    stop("publish_provenance(): output must be a regular file: ", path,
         call. = FALSE)
  }
  payload <- .provenance_validate_payload(payload)
  output <- .provenance_file_snapshot(path, basename(path),
                                      "publish_provenance")
  output$path <- NULL
  output$mtime <- NULL
  output <- c(list(file = basename(path)), output)
  record <- c(payload, list(output = output))

  sidecar <- provenance_path(path)
  temporary <- tempfile(
    pattern = paste0(".", basename(sidecar), "-"),
    tmpdir = dirname(sidecar),
    fileext = ".tmp"
  )
  on.exit(if (file.exists(temporary)) unlink(temporary), add = TRUE)
  tryCatch(
    withCallingHandlers(
      .provenance_write_json(record, temporary),
      warning = function(w) stop(w)
    ),
    error = function(e) {
      stop("publish_provenance(): could not write the provenance sidecar ",
           sidecar, ": ", conditionMessage(e), call. = FALSE)
    }
  )

  confirmed <- .provenance_file_snapshot(path, basename(path),
                                         "publish_provenance")
  if (!identical(output$bytes, confirmed$bytes) ||
        !identical(output$sha256, confirmed$sha256)) {
    stop("publish_provenance(): output changed before its sidecar could be published: ",
         path, call. = FALSE)
  }
  renamed <- suppressWarnings(.provenance_rename(temporary, sidecar))
  if (!isTRUE(renamed)) {
    stop("publish_provenance(): could not publish the provenance sidecar ",
         sidecar, ".", call. = FALSE)
  }
  invisible(record)
}

#' Capture and publish provenance for an existing output
#'
#' @description
#' Convenience wrapper for an output that already exists. It captures an
#' explicit provenance payload and immediately publishes it beside the output.
#'
#' @param path Character(1). Existing completed output path.
#' @param data List of records returned by \code{\link{provenance_data}}.
#' @param artifacts List of records returned by
#'   \code{\link{provenance_artifact}}.
#' @param extra Named list of job-specific fields. Reserved fields cannot be
#'   displaced.
#' @param cfg List. A study manifest from \code{\link{study_config}}.
#'
#' @return Invisibly, the published record as a list.
#'
#' @seealso \code{\link{capture_provenance}},
#'   \code{\link{publish_provenance}}, \code{\link{provenance_path}}
#'
#' @export
record_provenance <- function(path, data, artifacts = list(), extra = list(),
                              cfg = study_config()) {
  job <- tools::file_path_sans_ext(basename(path))
  payload <- capture_provenance(
    job = job,
    data = data,
    artifacts = artifacts,
    extra = extra,
    cfg = cfg
  )
  publish_provenance(path, payload)
}
