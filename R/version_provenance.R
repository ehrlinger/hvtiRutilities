# Provenance of a registered version: how its data were produced. Design:
# dev/specs/2026-10-13-one-version-scheme-design.md, section 4.
#
# Kept in a top-level `provenance:` map keyed by parquet name, never on the
# version record. hvtiRutilities 1.5.1 and 1.5.2 copy every field they do not
# know onto the next version they write, so an origin on the entry would be
# inherited by a later rebuild; they rewrite only `datasets:` and keep other
# top-level keys, so a version they register has no row and reads as legacy.

.legacy_row <- function() list(origin = "legacy")

.version_provenance <- function(manifest, parquet) {
  rows <- if (is.list(manifest$provenance)) manifest$provenance else list()
  row <- rows[[parquet]]
  if (is.list(row) && is.character(row$origin) && length(row$origin) == 1L) row else .legacy_row()
}

.set_version_provenance <- function(manifest, parquet, row) {
  rows <- if (is.list(manifest$provenance)) manifest$provenance else list()
  rows[[parquet]] <- row
  manifest$provenance <- rows
  manifest
}

# bd writes <stem>.build.yml beside the working file; a registered version's
# record shares the version's name.
.build_sidecar_path <- function(source_path) {
  file.path(dirname(source_path), paste0(tools::file_path_sans_ext(basename(source_path)), ".build.yml"))
}

.version_record_name <- function(parquet) sub("[.]parquet$", ".build.yml", parquet)

.build_required <- c("schema", "built_sha256", "job", "view", "as_of", "cohort_sha256",
                     "overlay_sha256", "derived_after_overlay")

.is_sha256 <- function(x) is.character(x) && length(x) == 1L && !is.na(x) && grepl("^[0-9a-f]{64}$", x)

# The whole timestamp, not its prefix: the shape, then the calendar and clock
# (strptime() returns NA for 2026-02-30 and for hour 25; measured 2026-10-13).
.is_iso_timestamp <- function(x) {
  shape <- "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})$"
  is.character(x) && length(x) == 1L && !is.na(x) && grepl(shape, x) &&
    !is.na(as.POSIXct(substr(x, 1L, 19L), format = "%Y-%m-%dT%H:%M:%S", tz = "UTC"))
}

.validate_build_record <- function(rec, file, caller) {
  bad <- function(why) {
    stop(caller, "(): ", file, " is not a valid build record: ", why, ". Nothing was written.", call. = FALSE)
  }
  text <- function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
  missing <- setdiff(.build_required, names(rec))
  if (length(missing)) bad(paste0("missing ", paste(missing, collapse = ", ")))
  if (!identical(rec[["schema", exact = TRUE]], 1L)) bad("schema must be 1")
  if (!text(rec[["job", exact = TRUE]])) bad("job must be the job file's study-relative path")
  if (!text(rec[["view", exact = TRUE]])) bad("missing view")
  if (!.is_iso_timestamp(rec[["as_of", exact = TRUE]])) bad("as_of must be an ISO 8601 timestamp, such as 2026-10-01T00:00:00Z")
  if (!.is_sha256(rec[["cohort_sha256", exact = TRUE]])) bad("cohort_sha256 must be a SHA-256")
  overlay <- rec[["overlay_sha256", exact = TRUE]]
  if (!is.null(overlay) && !.is_sha256(overlay)) bad("overlay_sha256 must be a SHA-256 or null")
  if (!is.logical(rec[["derived_after_overlay", exact = TRUE]]) || length(rec[["derived_after_overlay", exact = TRUE]]) != 1L ||
        is.na(rec[["derived_after_overlay", exact = TRUE]])) {
    bad("derived_after_overlay must be true or false")
  }
  invisible(rec)
}

# Claim the sidecar for the version just written from `source_path`. Only a
# record whose built_sha256 is the hash of the bytes converted is claimed; a
# record for other bytes is left where it is and the version is legacy. The
# caller renames `from` back to `to` if its manifest write fails.
.claim_build_record <- function(source_path, source_sha256, parquet, caller) {
  none <- list(row = .legacy_row(), from = character(), to = character(), note = NULL)
  sidecar <- .build_sidecar_path(source_path)
  if (!file.exists(sidecar)) return(none)
  fail <- function(why) {
    stop(caller, "(): ", basename(sidecar), " ", why, ". Nothing was written.", call. = FALSE)
  }
  # Read the bytes once and parse those bytes, so the record validated is the
  # record whose hash is checked after the move: bd rewriting the sidecar
  # between the read and the rename cannot pair one record's fields with
  # another's checksum.
  bytes <- readBin(sidecar, "raw", file.size(sidecar))
  claimed_sha256 <- digest::digest(bytes, algo = "sha256", serialize = FALSE)
  rec <- tryCatch(yaml::yaml.load(rawToChar(bytes)), error = function(e) {
    fail(paste0("is not valid YAML (", conditionMessage(e), ")"))
  })
  if (!is.list(rec)) fail("is not a valid build record: it is not a mapping")
  # A record without a valid built_sha256 is malformed, not stale: it must
  # not fall through to the legacy branch below.
  if (!.is_sha256(rec[["built_sha256", exact = TRUE]])) fail("is not a valid build record: built_sha256 must be a SHA-256")
  if (!identical(rec[["built_sha256", exact = TRUE]], source_sha256)) {
    none$note <- paste0(basename(sidecar), " describes a different ", basename(source_path),
                        ", so this version is recorded as legacy")
    return(none)
  }
  .validate_build_record(rec, basename(sidecar), caller)
  if (!isTRUE(rec[["derived_after_overlay", exact = TRUE]])) {
    fail(paste0("says its derivations were not recomputed after the corrections overlay was applied, so ",
                basename(source_path), " cannot be registered. Re-run the build"))
  }
  dest <- file.path(dirname(source_path), .version_record_name(parquet))
  # .registration_rename() (R/register_data.R) is file.rename() behind a binding tests can mock.
  if (file.exists(dest) || !.registration_rename(sidecar, dest)) fail(paste0("could not be moved to ", basename(dest)))
  if (!identical(digest::digest(dest, algo = "sha256", file = TRUE), claimed_sha256)) {
    if (!file.rename(dest, sidecar)) {
      stop(caller, "(): ", basename(sidecar), " changed while it was being registered and could not be moved back; ",
           "it was left at ", dest, ". Nothing else was written.", call. = FALSE)
    }
    fail("changed while it was being registered. Wait for the build that writes it to finish, then run this again")
  }
  list(
    row = list(origin = "bd", build = list(
      record = basename(dest), record_sha256 = claimed_sha256,
      job = rec[["job", exact = TRUE]], view = rec[["view", exact = TRUE]], as_of = rec[["as_of", exact = TRUE]],
      cohort_sha256 = rec[["cohort_sha256", exact = TRUE]], overlay_sha256 = rec[["overlay_sha256", exact = TRUE]]
    )),
    from = dest, to = sidecar, note = NULL
  )
}
