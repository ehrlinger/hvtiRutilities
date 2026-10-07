# Registered versions. A study dataset's accepted states, each converted once
# to a dated parquet that R jobs read, while the source (built.sas7bdat) stays
# free to be rebuilt. Design and reasoning: hvtiR
# dev/specs/2026-10-07-dated-parquet-manifest-design.md.
#
# An entry is "versioned" when it carries a `parquet:` field. Everything here
# keys on that field, so entries without it (unregistered studies, release-aware
# contracts, studies registered before 2026-10) keep their existing code paths.

.arrow_available <- function() requireNamespace("arrow", quietly = TRUE)

.require_arrow <- function(caller) {
  if (!.arrow_available()) {
    stop(caller, "(): registering a dataset converts it to parquet, which needs the arrow package. ",
         "Install it with install.packages(\"arrow\") and run this again. Nothing was written.",
         call. = FALSE)
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

# <stem>_YYYYMMDD.parquet, then _r2, _r3 for further versions on the same date.
# A name is taken when the manifest records it or either of its files exists.
.version_filename <- function(stem, extract_date, dir, taken = character()) {
  base <- paste0(stem, "_", format(as.Date(extract_date), "%Y%m%d"))
  rev <- 1L
  repeat {
    name <- paste0(base, if (rev > 1L) paste0("_r", rev) else "", ".parquet")
    free <- !name %in% taken &&
      !file.exists(file.path(dir, name)) &&
      !file.exists(file.path(dir, .version_schema_name(name)))
    if (free) return(name)
    rev <- rev + 1L
  }
}

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
  .assert_no_lowercase_collision(d, source)
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
  .verify_parquet_roundtrip(d, parquet)
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
    same_mtime <- abs(mtime - as.numeric(as.POSIXct(entry$source_mtime, tz = "UTC"))) < 1e-4
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
