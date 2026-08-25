# Lazy parquet cache for the read layer.
#
# Conversion happens on first read, never in a bulk sweep, so a dataset nobody
# reads is never converted and superseded copies cost nothing.
#
# Validity follows the manifest entry's role, a fact about whether SAS still
# builds the dataset, not a caching policy. role: "primary" means the parquet
# IS the data and the source is never consulted. role: "source" is decided by
# a stat of the source's size and mtime -- not a read -- falling back to the
# recorded sha256 only when mtime cannot settle it (see .cache_valid()).
# Re-hashing the source on every call would read the whole file and defeat
# the cache entirely, so that fallback is deliberately rare.

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

# Two thresholds guard the mtime comparison, for two different reasons:
#
# - ROUNDTRIP_EPSILON absorbs formatting noise, not filesystem noise. The
#   recorded mtime is serialized to text (%OS6) and reparsed on every check;
#   that round trip alone introduces ~1e-6s of floating error even when
#   nothing on disk changed (measured). Below this, treat the stamp as an
#   exact match and trust it -- this is the fast path that keeps a routine
#   cache hit from paying for a hash.
#
# - AMBIGUITY_WINDOW is about the filesystem, not formatting: the study tree
#   is an SMB mount, and SMB mtime resolution is commonly no finer than one
#   whole second. A difference smaller than that cannot be trusted as
#   "genuinely different" -- it may be real, or it may be rounding -- so
#   instead of guessing, the recorded sha256 is verified. A difference at or
#   above the window is large enough to trust directly: the file changed.
.MTIME_ROUNDTRIP_EPSILON_SECONDS <- 0.001
.MTIME_AMBIGUITY_WINDOW_SECONDS  <- 1

.cache_valid <- function(path, derived, entry) {
  if (is.null(entry) || !file.exists(derived$parquet)) return(FALSE)

  # role: primary means the parquet IS the data. The source may have been
  # retired and need not exist; it is never consulted for this role.
  if (identical(entry$role, "primary")) return(TRUE)

  if (!file.exists(path)) return(FALSE)

  info <- file.info(path)

  # A .sas7bdat is page-aligned, so a rewrite that changes the row count can
  # leave the file size identical (both round up to the same 16 KB page).
  # Size differing is still a hard signal of change; size cannot prove
  # sameness on its own.
  if (!identical(as.numeric(entry$source_size), as.numeric(info$size))) {
    return(FALSE)
  }

  diff <- abs(as.numeric(as.POSIXct(entry$source_mtime, tz = "UTC")) -
                as.numeric(info$mtime))

  if (diff < .MTIME_ROUNDTRIP_EPSILON_SECONDS) return(TRUE)
  if (diff >= .MTIME_AMBIGUITY_WINDOW_SECONDS) return(FALSE)

  # Ambiguous: the mtime moved, but by less than the filesystem's reliable
  # granularity. A full read, but only for this genuinely ambiguous case.
  identical(entry$sha256,
            digest::digest(path, algo = "sha256", file = TRUE))
}

# Read `path`, using or populating the parquet cache beside it.
#
# manifest_path is passed in rather than derived from `path`: study_init()
# writes manifest.yaml at the STUDY ROOT while datasets live in
# <root>/datasets/, so dirname(path) is the wrong directory. Derived files
# (.parquet, .schema.csv) do sit beside the source.
#
# refresh = TRUE forces a re-read from the source and a reconversion
# regardless of role or stamp. It exists because "the source changed" is not
# always something a timestamp can express -- a rebuild that preserves
# mtime, a restored backup, a correction applied out of band.
.cache_read <- function(path, reader, manifest_path, refresh = FALSE) {
  if (!.cache_enabled()) return(reader(path))

  derived  <- .derived_paths(path)
  manifest <- manifest_path
  entry    <- .manifest_entry(manifest, path)
  promoted <- identical(entry$role, "primary")

  if (refresh && promoted) {
    stop("read_built(): refresh = TRUE cannot re-read ", basename(path),
         " -- its manifest entry has role \"primary\", meaning the source ",
         "has been retired and the parquet is the data.", call. = FALSE)
  }

  if (!refresh && .cache_valid(path, derived, entry)) {
    return(as.data.frame(arrow::read_parquet(derived$parquet)))
  }

  # Stat BEFORE reading, never after: captured afterwards, a source rewritten
  # during the read would be stamped with its new mtime against partly-old
  # data, and that pairing would validate forever. Stamped from before, a
  # mid-read change looks stale on the next call and self-heals.
  info <- file.info(path)
  d <- reader(path)

  # Order matters: the sidecar comes off this read, never off the parquet, so
  # the baseline is independent of the conversion it exists to check.
  #
  # A promoted entry's sidecar is the only surviving record of the SAS
  # dataset. Rewriting it from a later read would launder that away, so it is
  # written once and never again.
  if (!promoted) {
    utils::write.csv(dataset_schema(d), derived$schema, row.names = FALSE)
  }

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
