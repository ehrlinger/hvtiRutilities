# Lazy parquet cache for the read layer.
#
# Conversion happens on first read, never in a bulk sweep, so a dataset nobody
# reads is never converted and superseded copies cost nothing.
#
# Validity is decided by the source's size and mtime -- a stat, not a read.
# Re-hashing the source on every call would read the whole file and defeat the
# cache entirely; the sha256 is computed once at conversion, recorded in the
# manifest, and verified on demand by verify_manifest().

.cache_enabled <- function() {
  !isTRUE(getOption("hvtiRutilities.disable_parquet_cache", FALSE)) &&
    requireNamespace("arrow", quietly = TRUE)
}

.derived_paths <- function(path) {
  stem <- tools::file_path_sans_ext(path)
  list(parquet = paste0(stem, ".parquet"),
       schema  = paste0(stem, ".schema.csv"))
}

# Write to a temporary name in the destination directory and rename into
# place. Two jobs can race on the first read of a shared dataset, and rename
# within a filesystem is atomic where a half-written .parquet is not.
.write_parquet_atomic <- function(data, target) {
  tmp <- tempfile(pattern = basename(target), tmpdir = dirname(target),
                  fileext = ".tmp")
  ok <- FALSE
  on.exit(if (!ok && file.exists(tmp)) unlink(tmp), add = TRUE)
  arrow::write_parquet(data, tmp)
  if (!file.rename(tmp, target)) {
    stop("Could not move the converted parquet into place: ", target,
         call. = FALSE)
  }
  ok <- TRUE
  invisible(target)
}

# The manifest entry for one source file, or NULL.
.manifest_entry <- function(manifest_path, file) {
  if (!file.exists(manifest_path)) return(NULL)
  m <- yaml::read_yaml(manifest_path)
  if (is.null(m$datasets)) return(NULL)
  for (e in m$datasets) if (identical(e$file, basename(file))) return(e)
  NULL
}

.cache_valid <- function(path, derived, entry) {
  if (is.null(entry) || !file.exists(derived$parquet)) return(FALSE)
  info <- file.info(path)
  # Sub-second precision matters here: a .sas7bdat is page-aligned, so a
  # rewrite that changes the row count can leave the file size identical
  # (both round up to the same 16 KB page). Size alone therefore cannot be
  # trusted to catch every change, and mtime has to carry the rest of the
  # weight -- which means storing and comparing it to microsecond precision,
  # not truncating to whole seconds. A millisecond tolerance absorbs
  # round-trip noise from formatting/parsing without masking a genuine
  # rewrite the way a 1-second tolerance would.
  identical(as.numeric(entry$source_size), as.numeric(info$size)) &&
    isTRUE(abs(as.numeric(as.POSIXct(entry$source_mtime, tz = "UTC")) -
                 as.numeric(info$mtime)) < 0.001)
}

# Read `path`, using or populating the parquet cache beside it.
#
# manifest_path is passed in rather than derived from `path`: study_init()
# writes manifest.yaml at the STUDY ROOT while datasets live in
# <root>/datasets/, so dirname(path) is the wrong directory. Derived files
# (.parquet, .schema.csv) do sit beside the source.
.cache_read <- function(path, reader, manifest_path) {
  if (!.cache_enabled()) return(reader(path))

  derived  <- .derived_paths(path)
  manifest <- manifest_path
  entry    <- .manifest_entry(manifest, path)

  if (.cache_valid(path, derived, entry)) {
    return(as.data.frame(arrow::read_parquet(derived$parquet)))
  }

  d <- reader(path)

  # Order matters: the sidecar comes off this read, never off the parquet, so
  # the baseline is independent of the conversion it exists to check.
  #
  # A promoted entry's sidecar is the only surviving record of the SAS
  # dataset. Rewriting it from a later read would launder that away, so it is
  # written once and never again.
  promoted <- identical(entry$role, "primary")
  if (!promoted) {
    utils::write.csv(dataset_schema(d), derived$schema, row.names = FALSE)
  }

  info <- file.info(path)
  # update_manifest() replaces the whole entry rather than merging into it, so
  # a cache-driven write that omitted extract_date/source/sort_key would reset
  # them to today's date and NULL -- clobbering values a caller such as
  # study_init() set explicitly, on every cache miss, not just the first.
  # Preserving them here keeps the cache confined to the fields it owns.
  update_manifest(
    file          = path,
    manifest_path = manifest,
    extract_date  = entry$extract_date %||% Sys.Date(),
    source        = entry$source,
    sort_key      = entry$sort_key,
    n_rows        = nrow(d),
    n_cols        = ncol(d),
    schema_sha256 = if (file.exists(derived$schema)) {
      digest::digest(derived$schema, algo = "sha256", file = TRUE)
    } else {
      NULL
    },
    role          = if (promoted) "primary" else "source"
  )
  .stamp_source_state(manifest, basename(path), info)

  .write_parquet_atomic(d, derived$parquet)
  d
}

# The fast key lives beside the entry rather than inside update_manifest(),
# whose contract is about identifying a dataset rather than about caching.
.stamp_source_state <- function(manifest_path, file, info) {
  m <- yaml::read_yaml(manifest_path)
  m$datasets <- lapply(m$datasets, function(e) {
    if (identical(e$file, file)) {
      e$source_size  <- as.numeric(info$size)
      e$source_mtime <- format(info$mtime, "%Y-%m-%d %H:%M:%OS6", tz = "UTC")
    }
    e
  })
  yaml::write_yaml(m, manifest_path)
  invisible(TRUE)
}
