# Lazy parquet cache for the read layer.
#
# Conversion happens on first read, never in a bulk sweep, so a dataset nobody
# reads is never converted and superseded copies cost nothing.
#
# Validity follows the manifest entry's role, a fact about whether SAS still
# builds the dataset, not a caching policy. role: "primary" means the parquet
# IS the data and the source is never consulted. role: "source" is decided by
# a stat of the source's size and mtime -- not a read -- falling back to the
# recorded sha256 only when the filesystem's own mtime resolution cannot
# settle it (see .cache_valid()). Re-hashing the source on every call would
# read the whole file and defeat the cache entirely, so that fallback is
# deliberately rare.

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
# place. Two jobs can race on the first read/write of a shared dataset --
# racing on the parquet, the schema sidecar, or the manifest itself -- and
# rename within a filesystem is atomic where a half-written file is not.
# `write_fn(tmp)` populates the temp file; every caller shares the same
# create/rename/cleanup discipline rather than each reimplementing it.
.atomic_write <- function(target, write_fn) {
  tmp <- tempfile(pattern = basename(target), tmpdir = dirname(target),
                  fileext = ".tmp")
  ok <- FALSE
  on.exit(if (!ok && file.exists(tmp)) unlink(tmp), add = TRUE)
  write_fn(tmp)
  if (!file.rename(tmp, target)) {
    stop("Could not move the written file into place: ", target,
         call. = FALSE)
  }
  ok <- TRUE
  invisible(target)
}

.write_parquet_atomic <- function(data, target) {
  .atomic_write(target, function(tmp) arrow::write_parquet(data, tmp))
}

# A promoted dataset has no second chance: while an entry is role: "source" a
# bad conversion self-heals at the next invalidation, but once the source is
# retired nothing remains to disagree with the parquet. A hash of the bytes
# just written proves only that the write completed, not that the write was
# correct, so the parquet is read back and compared against the frame haven
# returned -- the one thing a byte hash cannot check.
.verify_parquet_roundtrip <- function(original, target) {
  written <- as.data.frame(original)
  back    <- as.data.frame(arrow::read_parquet(target))

  bad <- if (!identical(names(written), names(back))) {
    "<column names/order>"
  } else {
    hit <- Filter(function(nm) !identical(written[[nm]], back[[nm]]),
                   names(written))
    if (length(hit)) hit[[1]] else NULL
  }

  if (!is.null(bad)) {
    unlink(target)
    stop("read_built(): the parquet conversion of ", basename(target),
         " did not round-trip -- column '", bad, "' differs after writing ",
         "and reading it back. The parquet was removed.", call. = FALSE)
  }
  invisible(TRUE)
}

# The package that actually read `path`, mirroring read_clinical_data()'s own
# dispatch by extension. This is recorded as provenance because once an entry
# is promoted (role: "primary") the parquet is the data, and a reader defect
# discovered later is otherwise unfindable -- re-reading the source is no
# longer an option. NULL for formats read by base R (.csv, .rds), whose
# version is already the R version other provenance already records.
.reader_provenance <- function(path) {
  pkg <- switch(tolower(tools::file_ext(path)),
                sas7bdat = "haven",
                xlsx     = ,
                xls      = "readxl",
                NULL)
  if (is.null(pkg)) return(NULL)
  paste(pkg, as.character(utils::packageVersion(pkg)))
}

# The manifest entry for one source file, or NULL.
.manifest_entry <- function(manifest_path, file) {
  if (!file.exists(manifest_path)) return(NULL)
  m <- yaml::read_yaml(manifest_path)
  if (is.null(m$datasets)) return(NULL)
  for (e in m$datasets) if (identical(e$file, basename(file))) return(e)
  NULL
}

# How wide a same-tick rewrite window is is a property of the filesystem, and
# it is measured here rather than assumed. A `stat` that reports a fractional
# mtime resolves sub-second, so the window a rewrite could hide inside is
# microseconds wide and mtime alone settles it. A `stat` that reports a
# whole-second mtime cannot see inside that second at all -- the window is a
# full second wide -- so the recorded sha256 is verified instead. Production
# runs on a local filesystem with nanosecond mtime, where the fast path
# always applies; development over SMB may see whole-second stamps and pay
# for a hash. Neither is a special case: the same `stat` decides.
#
# An earlier version compared the source's mtime against a client-side
# Sys.time() recorded at conversion -- two different clocks whenever the
# files live on another host, so a client running even one second fast made
# every entry look unambiguous forever. A validity rule may only compare
# readings of the same clock, which is what this does: two mtimes from the
# same `stat`.
.cache_valid <- function(path, derived, entry, manifest_path) {
  if (is.null(entry) || !file.exists(derived$parquet)) return(FALSE)

  # role: primary means the parquet IS the data. The source may have been
  # retired and need not exist; it is never consulted for this role.
  if (identical(entry$role, "primary")) return(TRUE)

  if (!file.exists(path)) return(FALSE)

  # A half-written stamp -- source_size present but source_mtime absent, a
  # hand edit or an interrupted write -- must not reach as.POSIXct(NULL) and
  # error. Any missing stamp field means there is nothing trustworthy to
  # compare against, so it is simply not valid, the same as no entry at all.
  if (is.null(entry$source_size) || is.null(entry$source_mtime)) {
    return(FALSE)
  }

  info <- file.info(path)

  # A .sas7bdat is page-aligned, so a rewrite that changes the row count can
  # leave the file size identical (both round up to the same 16 KB page).
  # Size differing is still a hard signal of change; size cannot prove
  # sameness on its own.
  if (!identical(as.numeric(entry$source_size), as.numeric(info$size))) {
    return(FALSE)
  }

  current_mtime  <- as.numeric(info$mtime)
  recorded_mtime <- as.numeric(as.POSIXct(entry$source_mtime, tz = "UTC"))

  # .MTIME_ROUNDTRIP_TOLERANCE_SECONDS is the manifest's own string
  # round-trip precision limit, not a filesystem assumption: source_mtime is
  # stored as a %OS6-formatted string (microsecond precision), and
  # re-parsing it can land a fraction of a microsecond away from the raw
  # value a fresh `stat` reports (measured empirically at ~1e-6s -- a
  # genuinely unchanged file can straddle a rounding boundary either way). A
  # gap this small is that noise, not a real difference; a gap this large
  # would require a rewrite landing within a hundred microseconds of the
  # original write, which is a different event than what this tolerance
  # exists to absorb.
  .MTIME_ROUNDTRIP_TOLERANCE_SECONDS <- 1e-4
  if (abs(current_mtime - recorded_mtime) >= .MTIME_ROUNDTRIP_TOLERANCE_SECONDS) {
    return(FALSE)
  }

  # size and mtime both tie. Whether that alone proves the source is
  # unchanged depends on what this filesystem's mtime can actually resolve,
  # measured directly from the fresh `stat` rather than the (tolerance-
  # smoothed) comparison above: a fractional mtime means sub-second
  # resolution and it is trusted; an exact whole second means the
  # filesystem cannot see inside that tick, and the recorded sha256 is
  # verified instead.
  if (current_mtime != floor(current_mtime)) return(TRUE)

  identical(entry$sha256, digest::digest(path, algo = "sha256", file = TRUE))
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
  derived  <- .derived_paths(path)
  manifest <- manifest_path
  entry    <- .manifest_entry(manifest, path)
  promoted <- identical(entry$role, "primary")

  # This must fire before the .cache_enabled() early return below: with
  # arrow absent (or the cache disabled), that return would otherwise call
  # reader(path) directly on a retired, possibly-missing source and die
  # inside haven instead of naming the actual reason.
  if (refresh && promoted) {
    stop("read_built(): refresh = TRUE cannot re-read ", basename(path),
         " -- its manifest entry has role \"primary\", meaning the source ",
         "has been retired and the parquet is the data.", call. = FALSE)
  }

  if (!.cache_enabled()) return(reader(path))

  if (!refresh && .cache_valid(path, derived, entry, manifest)) {
    # An unreadable parquet -- truncated, corrupted, an interrupted write
    # from outside this package -- must not be permanently fatal for a
    # role: "source" entry: the source is still there to regenerate it from.
    hit <- tryCatch(as.data.frame(arrow::read_parquet(derived$parquet)),
                     error = function(e) e)
    if (!inherits(hit, "error")) return(hit)

    if (promoted) {
      stop("read_built(): the cached parquet for ", basename(path),
           " could not be read, and role: \"primary\" means it is the ",
           "only copy of this dataset -- there is no source to regenerate ",
           "it from. Underlying error: ", conditionMessage(hit),
           call. = FALSE)
    }
    warning("read_built(): the cached parquet for ", basename(path),
            " could not be read (", conditionMessage(hit), "); it will be ",
            "regenerated from the source.", call. = FALSE)
    # Fall through to the miss path below.
  }

  # Stat BEFORE reading, never after: captured afterwards, a source rewritten
  # during the read would be stamped with its new mtime against partly-old
  # data, and that pairing would validate forever. Stamped from before, a
  # mid-read change looks stale on the next call and self-heals.
  info <- file.info(path)
  d <- reader(path)

  # If size or mtime moved between that stat and here, the read may have
  # straddled a rewrite and handed back a torn frame. Discard it before
  # anything is written -- no sidecar, no manifest entry, no parquet -- and
  # let the caller retry rather than caching a frame that might not
  # correspond to any single state of the file.
  post <- file.info(path)
  if (!identical(as.numeric(info$size), as.numeric(post$size)) ||
      !identical(as.numeric(info$mtime), as.numeric(post$mtime))) {
    stop("read_built(): ", basename(path), " changed while it was being ",
         "read -- the frame may be torn. Nothing was written; try the ",
         "read again.", call. = FALSE)
  }

  reader_prov <- .reader_provenance(path)

  if (promoted) {
    # A miss here can only mean the parquet was lost while the retired
    # source happens to still be present. Reconvert it, but sha256 must
    # describe the PARQUET (once it exists), and update_manifest() would
    # otherwise replace the whole entry -- recording the source's hash and
    # silently dropping promoted_date/source_sha256, which permanently
    # breaks verify_manifest() on a study whose data is intact. The sidecar
    # is never rewritten for a promoted entry (see above).
    .write_parquet_atomic(d, derived$parquet)
    .verify_parquet_roundtrip(d, derived$parquet)
    .update_promoted_entry(manifest, path, derived$parquet,
                            n_rows = nrow(d), n_cols = ncol(d),
                            reader = reader_prov)
    return(d)
  }

  # Order matters: the sidecar comes off this read, never off the parquet, so
  # the baseline is independent of the conversion it exists to check.
  .atomic_write(derived$schema, function(tmp) {
    utils::write.csv(dataset_schema(d), tmp, row.names = FALSE)
  })

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
    role          = "source",
    reader        = reader_prov
  )
  .stamp_source_state(manifest, basename(path), info)

  .write_parquet_atomic(d, derived$parquet)
  .verify_parquet_roundtrip(d, derived$parquet)
  d
}

# A cache miss on a promoted (role: "primary") entry means only that its
# parquet was lost while the retired source happens to still be present.
# update_manifest() replaces the whole entry keyed by a fresh hash of `file`
# -- for a promoted entry that would record the SOURCE's hash as sha256
# (wrong: role: "primary" means sha256 describes the parquet) and silently
# drop promoted_date/source_sha256. This updates only what a reconversion
# can legitimately change and leaves every promotion field exactly as it
# was.
.update_promoted_entry <- function(manifest_path, file, parquet, n_rows,
                                    n_cols, reader) {
  m <- yaml::read_yaml(manifest_path)
  m$datasets <- lapply(m$datasets, function(e) {
    if (identical(e$file, basename(file))) {
      e$sha256 <- digest::digest(parquet, algo = "sha256", file = TRUE)
      e$n_rows <- as.integer(n_rows)
      e$n_cols <- as.integer(n_cols)
      if (!is.null(reader)) e$reader <- reader
    }
    e
  })
  .atomic_write(manifest_path, function(tmp) yaml::write_yaml(m, tmp))
  invisible(TRUE)
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
  .atomic_write(manifest_path, function(tmp) yaml::write_yaml(m, tmp))
  invisible(TRUE)
}
