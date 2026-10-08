# Registered versions. A study dataset's accepted states, each converted once
# to a dated parquet that R jobs read, while the source (built.sas7bdat) stays
# free to be rebuilt. Design and reasoning: hvtiR
# dev/specs/2026-10-07-dated-parquet-manifest-design.md.
#
# An entry is "versioned" when it carries a `parquet:` field. Everything here
# keys on that field, so entries without it (unregistered studies, release-aware
# contracts, studies registered before 2026-10) keep their existing code paths.

.arrow_available <- function() requireNamespace("arrow", quietly = TRUE)

# `action` says what needed arrow, so a read and a registration each get an
# accurate message: only a registration can promise that nothing was written.
.require_arrow <- function(caller, action = c("register", "read")) {
  action <- match.arg(action)
  if (!.arrow_available()) {
    why <- if (action == "register") {
      "registering a dataset converts it to parquet, which needs the arrow package. "
    } else {
      "the registered version of this dataset is a parquet file, and reading it needs the arrow package. "
    }
    stop(caller, "(): ", why, "Install it with install.packages(\"arrow\") and run this again.",
         if (action == "register") " Nothing was written." else "", call. = FALSE)
  }
  invisible(TRUE)
}

.version_fields <- c("parquet", "sha256", "source_sha256", "extract_date", "n_rows", "n_cols",
                     "schema_sha256", "reader", "recovered_from")

.is_versioned <- function(entry) {
  is.list(entry) && is.character(entry$parquet) && length(entry$parquet) == 1L &&
    !is.na(entry$parquet) && nzchar(entry$parquet)
}

# The file jobs read for this entry, beside its source.
.authoritative_path <- function(entry, source_path) {
  if (.is_versioned(entry)) return(file.path(dirname(source_path), entry$parquet))
  if (identical(entry$role, "primary")) return(.derived_paths(source_path)$parquet)
  source_path
}

.version_schema_name <- function(parquet) sub("[.]parquet$", ".schema.csv", parquet)

# Every parquet and schema file a versioned entry records, current or in history.
.recorded_version_names <- function(datasets) {
  if (!is.list(datasets)) return(character())
  unique(unlist(lapply(datasets, function(e) {
    if (!.is_versioned(e)) return(character())
    history <- if (is.list(e$history)) Filter(is.list, e$history) else list()
    p <- c(e$parquet, unlist(lapply(history, function(h) if (is.character(h$parquet)) h$parquet)))
    c(p, .version_schema_name(p))
  })))
}

# Names a new version must not take: every recorded version, and the legacy
# read-cache names (<stem>.parquet, <stem>.schema.csv) of every entry. A dataset
# whose file is cohort_20260915.csv caches to cohort_20260915.parquet, which is
# also the name cohort.csv would get when registered on 2026-09-15.
.reserved_names <- function(datasets) {
  if (!is.list(datasets)) return(character())
  caches <- unlist(lapply(datasets, function(e) {
    if (is.character(e$file) && length(e$file) == 1L) basename(unlist(.derived_paths(e$file)))
  }))
  unique(c(caches, .recorded_version_names(datasets)))
}

# The entry whose registered version `file`'s read cache would overwrite, or NULL.
.cache_name_clash <- function(file, datasets) {
  cache <- basename(unlist(.derived_paths(file)))
  for (e in if (is.list(datasets)) datasets else list()) {
    if (any(cache %in% .recorded_version_names(list(e)))) return(e)
  }
  NULL
}

# <stem>_YYYYMMDD.parquet, then _r2, _r3 for further versions on the same date.
# A name is taken when it or its schema name is in `taken` or either file exists.
.version_filename <- function(stem, extract_date, dir, taken = character()) {
  base <- paste0(stem, "_", format(as.Date(extract_date), "%Y%m%d"))
  rev <- 1L
  repeat {
    name <- paste0(base, if (rev > 1L) paste0("_r", rev) else "", ".parquet")
    free <- !name %in% taken && !.version_schema_name(name) %in% taken &&
      !file.exists(file.path(dir, name)) &&
      !file.exists(file.path(dir, .version_schema_name(name)))
    if (free) return(name)
    rev <- rev + 1L
  }
}

# The local calendar date a file was last written. as.Date() on an mtime
# converts in UTC, which files an evening rebuild in the Americas under the
# next day; format() uses the session's time zone, as a person reading the
# file listing would.
.mtime_date <- function(path) format(file.info(path)$mtime, "%Y-%m-%d")

.source_stamp <- function(path) {
  info <- file.info(path)
  list(source_size = as.numeric(info$size),
       source_mtime = format(info$mtime, "%Y-%m-%d %H:%M:%OS6", tz = "UTC"))
}

# Convert `source` once. Writes <name>.parquet and <name>.schema.csv in `dir`
# and returns the version record. On any error neither file is left behind.
# The frame is stored as read, before read_built()'s normalisation, as the read
# cache stores it, so a version reads back exactly as a cached source did.
.write_version <- function(source, dir, extract_date, taken = character(), caller = "register_data") {
  .require_arrow(caller)
  before <- file.info(source)
  d <- as.data.frame(read_clinical_data(source, convert_types = FALSE))
  .assert_no_lowercase_collision(d, source, caller)
  after <- file.info(source)
  if (!identical(as.numeric(before$size), as.numeric(after$size)) ||
        !identical(as.numeric(before$mtime), as.numeric(after$mtime))) {
    stop(caller, "(): ", basename(source), " changed while it was being read. Nothing was written; ",
         "wait for the build that writes it to finish, then run this again.", call. = FALSE)
  }

  name <- .version_filename(tools::file_path_sans_ext(basename(source)), extract_date, dir, taken)
  parquet <- file.path(dir, name)
  schema <- file.path(dir, .version_schema_name(name))
  done <- FALSE
  on.exit(if (!done) unlink(c(parquet, schema)), add = TRUE)

  .write_parquet_atomic(d, parquet)
  .verify_parquet_roundtrip(d, parquet, caller)
  .atomic_write(schema, function(tmp) utils::write.csv(dataset_schema(d), tmp, row.names = FALSE))

  record <- c(
    list(
      parquet = name,
      sha256 = digest::digest(parquet, algo = "sha256", file = TRUE),
      source_sha256 = digest::digest(source, algo = "sha256", file = TRUE),
      extract_date = format(as.Date(extract_date), "%Y-%m-%d"),
      n_rows = as.integer(nrow(d)),
      n_cols = as.integer(ncol(d)),
      schema_sha256 = digest::digest(schema, algo = "sha256", file = TRUE)
    ),
    .source_stamp(source)
  )
  reader <- .reader_provenance(source)
  if (!is.null(reader)) record$reader <- reader
  done <- TRUE
  record
}

# `extra` carries fields the entry had besides the version (source, sort_key),
# so an update never drops what registration recorded.
.versioned_entry <- function(file, version, extra = list(), history = list()) {
  entry <- c(list(file = file, role = "primary"), version)
  for (nm in setdiff(names(extra), names(entry))) entry[[nm]] <- extra[[nm]]
  if (length(history)) entry$history <- history
  entry
}

.history_record <- function(entry) entry[intersect(.version_fields, names(entry))]

# The fields an entry carries besides its version, its identity and its history.
.entry_extra <- function(entry) {
  entry[setdiff(names(entry), c("file", "role", "history", "source_size", "source_mtime", .version_fields))]
}

# Has the source changed since this version was registered? A stat settles it
# when the filesystem resolves sub-second mtimes, as .cache_valid() reasons;
# otherwise, or when the stat differs, the hash decides, so a touch without a
# change is not reported. A missing source is not a change: jobs keep reading
# the registered version.
.source_changed <- function(source_path, entry) {
  if (!.is_versioned(entry) || !file.exists(source_path)) return(FALSE)
  if (!is.null(entry$source_size) && !is.null(entry$source_mtime)) {
    info <- file.info(source_path)
    mtime <- as.numeric(info$mtime)
    same_size <- identical(as.numeric(entry$source_size), as.numeric(info$size))
    # An unparsable recorded mtime (a hand-edited manifest) cannot settle it:
    # fall through to the hash rather than test an NA.
    recorded <- suppressWarnings(as.numeric(tryCatch(as.POSIXct(entry$source_mtime, tz = "UTC"),
                                                     error = function(e) NA)))
    same_mtime <- !is.na(recorded) && abs(mtime - recorded) < 1e-4
    if (same_size && same_mtime && mtime != floor(mtime)) return(FALSE)
  }
  !identical(entry$source_sha256, digest::digest(source_path, algo = "sha256", file = TRUE))
}

.source_changed_condition <- function(entry) {
  structure(
    class = c("hvtiRutilities_source_changed", "hvtiRutilities_out_of_date", "message", "condition"),
    list(
      message = paste0(
        entry$file, " has changed since it was registered on ", entry$extract_date,
        ". This job used the registered version, ", entry$parquet,
        ". Run hvtiRutilities::update_manifest() to register the new one.\n"
      ),
      call = NULL
    )
  )
}

# Register a rebuilt source as the next version; the current one moves to the
# head of history. Unchanged sources are left alone.
.next_version <- function(entry, source_path, extract_date, reserved = character()) {
  if (!.source_changed(source_path, entry)) {
    return(list(entry = entry, written = character(), action = "unchanged",
                detail = paste0("unchanged since ", entry$extract_date, " (", entry$parquet, ")")))
  }
  dir <- dirname(source_path)
  history <- if (is.list(entry$history)) entry$history else list()
  taken <- c(reserved, entry$parquet, vapply(history, function(h) h$parquet, character(1)))
  date <- if (is.null(extract_date)) .mtime_date(source_path) else extract_date
  version <- .write_version(source_path, dir, date, taken, caller = "update_manifest")
  list(
    entry = .versioned_entry(entry$file, version, extra = .entry_extra(entry),
                             history = c(list(.history_record(entry)), history)),
    written = file.path(dir, c(version$parquet, .version_schema_name(version$parquet))),
    action = "registered",
    detail = paste0("registered ", version$parquet, " (", version$n_rows, " rows, ", version$n_cols,
                    " columns); previous version kept as ", entry$parquet)
  )
}

.manifest_update_row <- function(dataset, action, detail) {
  data.frame(dataset = dataset, action = action, detail = detail, stringsAsFactors = FALSE)
}

# update_manifest() with no file: find the study from the working directory and
# register every dataset (or the one named) whose source has changed.
.update_study_manifest <- function(dataset = NULL, extract_date = NULL) {
  cfg <- tryCatch(study_config(require_data = FALSE), error = function(e) NULL)
  if (is.null(cfg)) {
    stop("update_manifest() with no file looks for a study (a _study.yml in this directory or above) ",
         "and found none. To record a single file, pass it: update_manifest(\"path/to/file\").",
         call. = FALSE)
  }
  .require_arrow("update_manifest")
  targets <- if (is.null(dataset)) {
    c(if (!is.null(cfg$built)) "study", names(cfg$additional_datasets))
  } else {
    .study_dataset(cfg, dataset)
    dataset
  }
  if (!length(targets)) {
    stop("update_manifest(): the study at ", cfg$root, " has no registered dataset to update. ",
         "Register one with register_data().", call. = FALSE)
  }
  manifest_path <- file.path(cfg$root, "manifest.yaml")
  manifest <- yaml::read_yaml(manifest_path)
  written <- character()
  # A recovered cache was renamed, not copied: it is the only copy of that
  # version, so a failed update renames it back rather than deleting it.
  restore <- list(from = character(), to = character())
  drop <- character()
  committed <- FALSE
  on.exit(if (!committed) {
    unlink(written)
    file.rename(restore$from, restore$to)
  }, add = TRUE)
  rows <- list()

  for (name in targets) {
    contract <- .study_dataset(cfg, name)
    if (!is.null(contract$release)) {
      if (!is.null(dataset)) {
        stop("update_manifest(): '", name, "' is a release-aware dataset. Review and adopt a published ",
             "release with review_data_update() and adopt_data_update().", call. = FALSE)
      }
      rows[[name]] <- .manifest_update_row(name, "skipped", "release-aware; use review_data_update() and adopt_data_update()")
      next
    }
    hit <- which(vapply(manifest$datasets, function(e) identical(e$file, contract$built), logical(1)))
    if (length(hit) != 1L) {
      stop("update_manifest(): ", contract$built, " has ", if (length(hit)) "more than one entry" else "no entry",
           " in manifest.yaml. Register it with register_data().", call. = FALSE)
    }
    entry <- manifest$datasets[[hit]]
    source_path <- file.path(study_dir("datasets", cfg$root), contract$built)
    if (!file.exists(source_path)) {
      reading <- if (.is_versioned(entry)) entry$parquet else contract$built
      rows[[name]] <- .manifest_update_row(name, "unchanged",
                                           paste0(contract$built, " is not on disk; jobs keep reading ", reading))
      next
    }
    step <- if (.is_versioned(entry)) {
      .next_version(entry, source_path, extract_date, reserved = .reserved_names(manifest$datasets))
    } else {
      .migrate_entry(entry, source_path, extract_date, datasets = manifest$datasets)
    }
    written <- c(written, step$written)
    restore$from <- c(restore$from, step$restore$from)
    restore$to <- c(restore$to, step$restore$to)
    drop <- c(drop, step$drop)
    manifest$datasets[[hit]] <- step$entry
    rows[[name]] <- .manifest_update_row(name, step$action, step$detail)
  }

  out <- do.call(rbind, unname(rows))
  if (any(out$action %in% c("registered", "migrated"))) {
    .atomic_write(manifest_path, function(tmp) yaml::write_yaml(manifest, tmp))
  }
  committed <- TRUE
  # A legacy cache name can be another dataset's registered version; that file is never removed.
  unlink(drop[!basename(drop) %in% .recorded_version_names(manifest$datasets)])
  message(paste0(format(out$dataset), ": ", out$detail, collapse = "\n"))
  if (any(out$action %in% c("registered", "migrated"))) {
    message("Commit manifest.yaml so the record of which version is current travels with the study.")
  }
  invisible(out)
}

# The old read cache (<stem>.parquet and <stem>.schema.csv beside the source)
# still holds the version registered before the source was overwritten when
# its row count, column count and column record match the old entry. Rename it
# to a dated version rather than copy it: it is the only copy.
.recover_cached_version <- function(entry, source_path, datasets = list()) {
  # A parquet source has no cache: <stem>.parquet is the source itself, and
  # renaming it would take the data away. Never recover from it.
  if (identical(tolower(tools::file_ext(source_path)), "parquet")) return(NULL)
  # Nor from a file another entry registered: it holds that dataset's data.
  if (!is.null(.cache_name_clash(source_path, datasets))) return(NULL)
  cache <- .derived_paths(source_path)
  usable <- file.exists(cache$parquet) && file.exists(cache$schema) && !is.null(entry$schema_sha256) &&
    identical(digest::digest(cache$schema, algo = "sha256", file = TRUE), entry$schema_sha256)
  if (!usable) return(NULL)
  d <- tryCatch(arrow::read_parquet(cache$parquet, mmap = FALSE), error = function(e) NULL)
  if (is.null(d) || !identical(nrow(d), as.integer(entry$n_rows)) ||
        (!is.null(entry$n_cols) && !identical(ncol(d), as.integer(entry$n_cols)))) {
    return(NULL)
  }
  dir <- dirname(source_path)
  date <- if (is.null(entry$extract_date)) Sys.Date() else entry$extract_date
  name <- .version_filename(tools::file_path_sans_ext(entry$file), date, dir, .reserved_names(datasets))
  parquet <- file.path(dir, name)
  schema <- file.path(dir, .version_schema_name(name))
  if (!file.rename(cache$parquet, parquet)) return(NULL)
  if (!file.rename(cache$schema, schema)) {
    file.rename(parquet, cache$parquet)
    return(NULL)
  }
  record <- list(parquet = name, sha256 = digest::digest(parquet, algo = "sha256", file = TRUE),
                 source_sha256 = entry$sha256, extract_date = format(as.Date(date), "%Y-%m-%d"),
                 n_rows = as.integer(nrow(d)), n_cols = as.integer(ncol(d)),
                 schema_sha256 = entry$schema_sha256, recovered_from = "cache")
  if (!is.null(entry$reader)) record$reader <- entry$reader
  record
}

# A study registered before 2026-10 has role "source" and no parquet. Its first
# update converts it. Three cases: the source still matches (convert it); it
# was overwritten and the cache still holds the old data (keep that as the
# earlier version); or neither (say the earlier version is gone, and register
# the new one anyway). In every case the new version is dated as a fresh
# registration is: the caller's extract_date, else the source's modification date.
.migrate_entry <- function(entry, source_path, extract_date, datasets = list()) {
  unchanged <- identical(entry$sha256, digest::digest(source_path, algo = "sha256", file = TRUE))
  history <- list()
  note <- NULL
  restore <- list(from = character(), to = character())
  returned <- FALSE
  if (!unchanged) {
    old <- .recover_cached_version(entry, source_path, datasets)
    if (is.null(old)) {
      note <- paste0("the previous version cannot be recovered: ", entry$file,
                     " was overwritten and no matching cached copy exists")
    } else {
      history <- list(old)
      cache <- .derived_paths(source_path)
      restore <- list(from = file.path(dirname(source_path), c(old$parquet, .version_schema_name(old$parquet))),
                      to = c(cache$parquet, cache$schema))
      # Until this function returns, its caller cannot undo the rename.
      on.exit(if (!returned) file.rename(restore$from, restore$to), add = TRUE)
      note <- paste0("previous version recovered from the read cache as ", old$parquet,
                     ", not from the original ", entry$file)
    }
  }
  date <- if (is.null(extract_date)) .mtime_date(source_path) else extract_date
  taken <- c(.reserved_names(datasets), vapply(history, function(h) h$parquet, character(1)))
  version <- .write_version(source_path, dirname(source_path), date, taken, caller = "update_manifest")
  # The superseded cache is dropped once the manifest is written, so a failed
  # update leaves the legacy entry and its sidecar intact. Never a parquet
  # source, whose derived name is itself.
  drop <- if (unchanged && !identical(tolower(tools::file_ext(source_path)), "parquet")) {
    unlist(.derived_paths(source_path), use.names = FALSE)
  } else {
    character()
  }
  returned <- TRUE
  list(
    entry = .versioned_entry(entry$file, version, extra = .entry_extra(entry), history = history),
    restore = restore,
    drop = drop,
    written = file.path(dirname(source_path), c(version$parquet, .version_schema_name(version$parquet))),
    action = "migrated",
    detail = paste0("registered ", version$parquet, " (", version$n_rows, " rows, ", version$n_cols, " columns)",
                    if (!is.null(note)) paste0("; ", note) else "")
  )
}
