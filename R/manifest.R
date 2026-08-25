## =============================================================================
## Internal helper: auto-detect row count by file extension
## Supported (lightweight): .csv
## Supported (heavy, opt-in via options(manifest.allow_heavy_rowcount = TRUE)):
##   .sas7bdat  .xlsx  .xls
## All other types require the caller to supply n_rows explicitly.
##
## "Counting is not permitted here" and "counting was attempted and failed"
## are different events, and a caller has to be able to tell them apart: the
## first is a policy the caller may reasonably skip past, the second means the
## file is unreadable. The policy refusal therefore carries the condition class
## "manifest_heavy_rowcount_disabled" so it can be caught by class rather than
## by matching the text of its message.
.heavy_rowcount_disabled <- function(what, loads) {
  errorCondition(
    paste0(
      "Automatic row counting for ", what, " loads the entire ", loads,
      " into memory and is disabled by default. ",
      "Either supply n_rows explicitly or enable this behavior with ",
      "options(manifest.allow_heavy_rowcount = TRUE)."
    ),
    class = "manifest_heavy_rowcount_disabled"
  )
}

#' @importFrom utils count.fields
.auto_count_rows <- function(file) {
  ext <- tolower(tools::file_ext(file))
  allow_heavy <- isTRUE(getOption("manifest.allow_heavy_rowcount", FALSE))
  switch(
    ext,
    csv = length(count.fields(file, sep = ",")) - 1L,
    sas7bdat = {
      if (!allow_heavy) {
        stop(.heavy_rowcount_disabled("SAS files (.sas7bdat)", "dataset"))
      }
      nrow(haven::read_sas(file))
    },
    xlsx = ,
    xls = {
      if (!allow_heavy) {
        stop(.heavy_rowcount_disabled("Excel files (.xls/.xlsx)", "workbook"))
      }
      nrow(readxl::read_excel(file))
    },
    stop(
      "Cannot auto-detect n_rows for file type '.", ext, "'. ",
      "Supported formats: csv, sas7bdat, xlsx, xls. ",
      "Please supply n_rows explicitly."
    )
  )
}

## =============================================================================
#' Create or update a dataset manifest file
#'
#' @description
#' Records dataset metadata — including a SHA-256 checksum, row count, extract
#' date, and optional provenance fields — into a \code{manifest.yaml} file.
#' If the manifest already contains an entry for the named file it is updated
#' in place; otherwise a new entry is appended.  The manifest is intended to be
#' committed to version control while the data files themselves are not.
#'
#' Row counts are detected automatically for \strong{CSV} (\code{.csv}) files.
#' For \strong{SAS} (\code{.sas7bdat}) and \strong{Excel} (\code{.xlsx},
#' \code{.xls}) files, automatic row counting is considered "heavy" because it
#' loads the entire dataset/workbook into memory; it is therefore disabled by
#' default and only performed when
#' \code{options(manifest.allow_heavy_rowcount = TRUE)} is set.  For any other
#' format, or when heavy counting is disabled, supply \code{n_rows}
#' explicitly.
#'
#' @param file Character. Path to the dataset file.
#' @param manifest_path Character. Path to the manifest YAML file.
#'   Created if it does not exist. Defaults to \code{"manifest.yaml"} in the
#'   current working directory.
#' @param extract_date Character or \code{Date}. The date the data were pulled
#'   from the source system.  Stored as \code{"YYYY-MM-DD"}.  Defaults to
#'   today's date.
#' @param n_rows Integer. Number of data rows.  When \code{NULL} (default) the
#'   row count is detected automatically from CSV files, and from SAS/Excel
#'   files only when \code{options(manifest.allow_heavy_rowcount = TRUE)} is
#'   set.
#'   all other file types supply this value explicitly.
#' @param source Character. Free-text description of the data source (e.g.
#'   \code{"Epic EMR, query v4.2, ICD mapping v3.2"}).
#' @param sort_key Character. Column name(s) that define the canonical sort
#'   order of the dataset.
#' @param n_cols Integer. Column count. Pass it from a frame already read; a
#'   row count alone cannot detect a dropped column.
#' @param schema_sha256 Character. SHA-256 of this dataset's schema sidecar,
#'   making the manifest-to-sidecar link tamper-evident.
#' @param role Either \code{"source"} (the file is authoritative and any
#'   parquet beside it is a disposable cache) or \code{"primary"} (the parquet
#'   is authoritative because the source has been retired). See the
#'   \emph{Promotion} section of the read-layer design spec.
#' @param reader Character. The package and version that produced this
#'   derived file (e.g. \code{"haven 2.5.5"}). Under \code{role = "primary"}
#'   the parquet is the data, so the reader that produced it is part of its
#'   provenance: a reader defect found later is otherwise unfindable once the
#'   source is retired. \code{NULL} (default) omits the field.
#' @param verbose Logical. If \code{TRUE}, report which manifest entry was
#'   added or updated via \code{\link[base]{message}}.  Defaults to
#'   \code{FALSE} so that scripted or looped calls stay silent.
#'
#' @return Invisibly returns the updated manifest as a named list.
#'
#' @examples
#' \dontrun{
#' # --- CSV ------------------------------------------------------------
#' update_manifest(
#'   file         = here::here("datasets", "cohort_20240115.csv"),
#'   extract_date = "2024-01-15",
#'   source       = "Epic EMR, query v4.2, ICD mapping v3.2",
#'   sort_key     = "patient_id"
#' )
#'
#' # --- SAS ------------------------------------------------------------
#' # .sas7bdat files exported from SAS or pulled via SASConnect
#' update_manifest(
#'   file         = here::here("datasets", "labs_20240115.sas7bdat"),
#'   extract_date = "2024-01-15",
#'   source       = "SAS dataset from CORR registry, labs module v2.1",
#'   sort_key     = "pat_id"
#' )
#'
#' # --- Excel ----------------------------------------------------------
#' update_manifest(
#'   file         = here::here("datasets", "adjudication_20240115.xlsx"),
#'   extract_date = "2024-01-15",
#'   source       = "Clinical events committee adjudication log"
#' )
#'
#' # --- Verify all three at once ---------------------------------------
#' verify_manifest(here::here("manifest.yaml"))
#' }
#'
#' @seealso \code{\link{verify_manifest}}
#' @export
update_manifest <- function(file,
                            manifest_path = "manifest.yaml",
                            extract_date  = Sys.Date(),
                            n_rows        = NULL,
                            n_cols        = NULL,
                            source        = NULL,
                            sort_key      = NULL,
                            schema_sha256 = NULL,
                            role          = c("source", "primary"),
                            reader        = NULL,
                            verbose       = FALSE) {
  role <- match.arg(role)
  if (!file.exists(file)) {
    stop("Dataset file not found: ", file)
  }

  sha256 <- digest::digest(file, algo = "sha256", file = TRUE)

  if (is.null(n_rows)) {
    n_rows <- .auto_count_rows(file)
  }

  entry <- list(
    file         = basename(file),
    extract_date = format(as.Date(extract_date), "%Y-%m-%d"),
    n_rows       = as.integer(n_rows),
    sha256       = sha256
  )
  # role is written even though every entry starts as "source". Adding the
  # field once manifests exist across many studies would mean migrating them,
  # which is the schema-drift problem this file exists to prevent.
  entry$role <- role
  if (!is.null(n_cols))        entry$n_cols        <- as.integer(n_cols)
  if (!is.null(schema_sha256)) entry$schema_sha256 <- schema_sha256
  if (!is.null(source))   entry$source   <- source
  if (!is.null(sort_key)) entry$sort_key <- sort_key
  if (!is.null(reader))   entry$reader   <- reader

  manifest <- if (file.exists(manifest_path)) {
    yaml::read_yaml(manifest_path)
  } else {
    list()
  }

  # Normalize and validate manifest structure
  if (is.null(manifest) || !is.list(manifest)) {
    manifest <- list()
  }
  if (is.null(manifest$datasets)) {
    manifest$datasets <- list()
  }
  if (!is.list(manifest$datasets)) {
    stop("Invalid manifest: 'datasets' field must be a list.")
  }

  existing <- vapply(
    manifest$datasets,
    function(d) identical(d$file, entry$file),
    logical(1)
  )

  if (any(existing)) {
    manifest$datasets[[which(existing)]] <- entry
    if (verbose) message("Manifest updated: ", entry$file)
  } else {
    manifest$datasets <- c(manifest$datasets, list(entry))
    if (verbose) message("Manifest entry added: ", entry$file)
  }

  .atomic_write(manifest_path, function(tmp) yaml::write_yaml(manifest, tmp))
  invisible(manifest)
}

## =============================================================================
#' Verify all datasets listed in a manifest
#'
#' @description
#' Reads a \code{manifest.yaml} produced by \code{\link{update_manifest}} and,
#' for every entry, confirms that (a) the file exists, (b) its SHA-256
#' checksum matches the recorded value, and (c) its row count matches.
#' Supported formats for automatic row-count verification: CSV
#' (\code{.csv}), SAS (\code{.sas7bdat}), and Excel (\code{.xlsx},
#' \code{.xls}).  For other file types the row-count check is skipped and
#' only the SHA-256 is verified.
#'
#' Re-deriving the row count of a SAS or Excel file means reading the whole
#' file, so it only happens under
#' \code{options(manifest.allow_heavy_rowcount = TRUE)}.  Without that option
#' the row count is skipped rather than failed, and the entry passes on its
#' checksum, which is the stronger of the two checks.  A check that could not
#' run is not a check that failed.  A file that cannot be read at all is a
#' different matter and still fails.
#'
#' An entry recording no SHA-256 fails, because the checksum is the whole of
#' what this function verifies and there is nothing to compare it against.
#' Manifests written by an md5-based writer are the case that turns up in
#' practice; the failure names the algorithm that was recorded instead.
#'
#' Three outcomes are therefore possible for an entry that passes, and the
#' report distinguishes them rather than reporting all three as simply
#' verified.  The count was compared; the count is recorded but was not
#' re-derived; or the manifest records no count at all.  The
#' \code{row_count_checked} column is \code{TRUE} only in the first case, and
#' the message names which of the three it was.
#'
#' Call this function at the top of every analysis script or Quarto document
#' to ensure data integrity before any results are generated.
#'
#' @param manifest_path Character. Path to the manifest YAML file.
#'   Defaults to \code{"manifest.yaml"} in the current working directory.
#' @param data_dir Character. Directory holding the dataset files. When
#'   supplied, it is used exactly as given. When \code{NULL} (default), each
#'   entry is resolved individually: \code{datasets/} beneath the manifest's
#'   own directory is preferred for that entry when the file actually exists
#'   there, matching the layout \code{\link{study_init}} creates, where
#'   \code{manifest.yaml} sits at the study root and datasets one level down;
#'   otherwise the entry resolves beside the manifest, so a flat layout is
#'   equally supported even when an unrelated \code{datasets/} directory is
#'   also present.
#' @param stop_on_error Logical. If \code{TRUE} (default) the function calls
#'   \code{stop()} on the first failed check, preventing the analysis from
#'   proceeding.  Set to \code{FALSE} to collect all errors and report them
#'   together as a warning.
#' @param verbose Logical. If \code{TRUE}, report each passing entry via
#'   \code{\link[base]{message}}.  Defaults to \code{FALSE} so that scripted or
#'   looped calls stay silent; the same information is always available in the
#'   returned data frame.  Failures are reported through \code{stop()} or
#'   \code{warning()} regardless of this setting.
#' @param strict Logical. If \code{TRUE}, an entry whose row count could not be
#'   re-derived is reported as \code{"FAIL"} rather than passing on its
#'   checksum alone, and the message names which of the three causes applies:
#'   no count recorded in the manifest, a file type whose rows cannot be
#'   counted, or heavy row counting left disabled.  Defaults to \code{FALSE},
#'   which preserves the permissive behaviour described above.
#'
#'   Use it where the question is "did every check actually run", not "is the
#'   data intact": a release gate, an archival gate, or a hand-off where a
#'   downstream reader will treat \code{"OK"} as meaning fully verified. Under
#'   the default, \code{"OK"} can mean "checksum verified, row count not
#'   examined", and the \code{row_count_checked} column is the only thing that
#'   distinguishes the two.
#'
#' @return Invisibly returns a data frame with columns \code{file},
#'   \code{status} (\code{"OK"} or \code{"FAIL"}), \code{message}, and
#'   \code{row_count_checked} (logical; \code{TRUE} when the row count was
#'   re-derived from the file and compared with the manifest).
#'
#' @examples
#' \dontrun{
#' # --- Typical usage: top of every analysis script or .qmd -----------
#' # Silent unless a check fails.
#' hvtiRutilities::verify_manifest(here::here("manifest.yaml"))
#'
#' # --- Interactive use: report each passing entry ---------------------
#' hvtiRutilities::verify_manifest(here::here("manifest.yaml"), verbose = TRUE)
#' # cohort_20240115.csv    — SHA-256 match (n = 831)
#' # labs_20240115.sas7bdat — SHA-256 match (n = 1204); row count not re-derived
#' # adjudication_20240115.xlsx — SHA-256 match (n = 47); row count not re-derived
#'
#' # --- Collect all failures instead of stopping on the first ---------
#' report <- verify_manifest(
#'   here::here("manifest.yaml"),
#'   stop_on_error = FALSE
#' )
#' report[report$status == "FAIL", ]
#' }
#'
#' @seealso \code{\link{update_manifest}}
#' @export
verify_manifest <- function(manifest_path = "manifest.yaml",
                            data_dir      = NULL,
                            stop_on_error = TRUE,
                            verbose       = FALSE,
                            strict        = FALSE) {
  if (!file.exists(manifest_path)) {
    stop("Manifest file not found: ", manifest_path)
  }

  manifest <- yaml::read_yaml(manifest_path)

  if (is.null(manifest$datasets) || length(manifest$datasets) == 0L) {
    if (verbose) message("Manifest contains no dataset entries.")
    return(invisible(data.frame(file = character(), status = character(),
                                message = character(),
                                row_count_checked = logical(),
                                stringsAsFactors = FALSE)))
  }

  # An explicit data_dir is used exactly as given. Only the default searches,
  # because study_init() writes manifest.yaml at the study root while datasets
  # live one level down -- but a flat layout is equally legal, and choosing on
  # directory existence alone would send a flat study's lookups into an
  # unrelated datasets/ directory and fail every entry.
  search_nested <- is.null(data_dir)
  if (is.null(data_dir)) {
    data_dir <- dirname(normalizePath(manifest_path))
  }

  resolve_entry <- function(file) {
    if (search_nested) {
      nested <- file.path(data_dir, "datasets", file)
      if (file.exists(nested)) return(nested)
    }
    file.path(data_dir, file)
  }

  results <- lapply(manifest$datasets, function(entry) {
    fpath <- resolve_entry(entry$file)

    if (!file.exists(fpath)) {
      return(data.frame(
        file    = entry$file,
        status  = "FAIL",
        message = paste("File not found:", fpath),
        row_count_checked = FALSE,
        stringsAsFactors = FALSE
      ))
    }

    # An entry with no sha256 cannot be compared at all. That has to fail,
    # because the checksum is the whole of what this function verifies, but
    # reporting it as a mismatch blames a comparison that never ran and prints
    # a blank "expected:". A manifest written by an md5-based writer is the
    # case that turns up in practice, so name the algorithm it did record.
    if (is.null(entry$sha256)) {
      alt <- intersect(c("md5", "sha1", "sha512", "crc32"), names(entry))
      return(data.frame(
        file    = entry$file,
        status  = "FAIL",
        message = paste0(
          "No SHA-256 recorded for this entry",
          if (length(alt)) {
            paste0("; the manifest records ", alt[1],
                   ", which this function does not verify")
          } else {
            ""
          },
          "."
        ),
        row_count_checked = FALSE,
        stringsAsFactors = FALSE
      ))
    }

    sha256 <- digest::digest(fpath, algo = "sha256", file = TRUE)
    if (!identical(sha256, entry$sha256)) {
      return(data.frame(
        file    = entry$file,
        status  = "FAIL",
        message = paste0("SHA-256 mismatch\n  expected: ", entry$sha256,
                         "\n  actual:   ", sha256),
        row_count_checked = FALSE,
        stringsAsFactors = FALSE
      ))
    }

    if (!is.null(entry$schema_sha256)) {
      side <- resolve_entry(basename(.derived_paths(entry$file)$schema))
      if (!file.exists(side)) {
        return(data.frame(
          file = entry$file, status = "FAIL",
          message = paste0("Schema sidecar not found: ", side),
          row_count_checked = FALSE, stringsAsFactors = FALSE))
      }
      side_sha <- digest::digest(side, algo = "sha256", file = TRUE)
      if (!identical(side_sha, entry$schema_sha256)) {
        return(data.frame(
          file = entry$file, status = "FAIL",
          message = paste0("Schema sidecar SHA-256 mismatch\n  expected: ",
                           entry$schema_sha256, "\n  actual:   ", side_sha),
          row_count_checked = FALSE, stringsAsFactors = FALSE))
      }
    }

    # Row-count cross-check for supported formats.
    #
    # A check that cannot be performed is not a check that failed. For
    # .sas7bdat and Excel the count can only be re-derived by loading the whole
    # file, which is off by default, so on every real study this branch is
    # reached with counting disabled. Failing there would put an intact dataset
    # permanently in FAIL and, at the default stop_on_error = TRUE, halt an
    # analysis whose data is provably unchanged. The count is skipped and the
    # entry passes on its checksum, which is the stronger of the two checks.
    # A genuine counting failure, an unreadable or truncated file, is a
    # different condition class and still fails.
    #
    # WHY THE SKIP CARRIES A REASON. `strict = TRUE` turns a skipped check into
    # a failure, and "the row count was not verified" is useless to act on
    # without knowing which of the three causes applies: the manifest never
    # recorded a count, the count is recorded but this file type cannot be
    # counted at all, or it could be counted if the caller opted in to the
    # expensive path. Each has a different fix, so each is named.
    ext <- tolower(tools::file_ext(fpath))
    rowcount_checked <- FALSE
    skip_reason      <- NULL
    if (!(ext %in% c("csv", "sas7bdat", "xlsx", "xls"))) {
      skip_reason <- paste0("the row count cannot be re-derived for a '.", ext,
                            "' file")
    } else if (is.null(entry$n_rows)) {
      skip_reason <- "the row count is not recorded in the manifest"
    }
    if (ext %in% c("csv", "sas7bdat", "xlsx", "xls") && !is.null(entry$n_rows)) {
      actual_rows_result <- tryCatch(
        .auto_count_rows(fpath),
        error = function(e) e
      )
      if (inherits(actual_rows_result, "manifest_heavy_rowcount_disabled")) {
        rowcount_checked <- FALSE
        skip_reason <- paste0(
          "counting rows in a '.", ext, "' file loads it entirely and is off ",
          "by default; set options(manifest.allow_heavy_rowcount = TRUE) to ",
          "verify it"
        )
      } else if (inherits(actual_rows_result, "error")) {
        return(data.frame(
          file    = entry$file,
          status  = "FAIL",
          message = paste0(
            "Row count auto-detection failed: ",
            conditionMessage(actual_rows_result)
          ),
          row_count_checked = FALSE,
          stringsAsFactors = FALSE
        ))
      } else {
        rowcount_checked <- TRUE
        actual_rows      <- actual_rows_result
        if (!is.na(actual_rows) &&
            !identical(actual_rows, as.integer(entry$n_rows))) {
          return(data.frame(
            file    = entry$file,
            status  = "FAIL",
            message = paste0("Row count mismatch\n  expected: ", entry$n_rows,
                             "\n  actual:   ", actual_rows),
            row_count_checked = TRUE,
            stringsAsFactors = FALSE
          ))
        }
      }
    }

    if (strict && !rowcount_checked) {
      return(data.frame(
        file    = entry$file,
        status  = "FAIL",
        message = paste0("Row count not verified: ", skip_reason,
                         ". The checksum matched; strict = TRUE requires ",
                         "every applicable check to have run."),
        row_count_checked = FALSE,
        stringsAsFactors = FALSE
      ))
    }

    # Three states the caller has to be able to tell apart: the count was
    # compared, the count is recorded but could not be re-derived, or no count
    # was ever recorded. Interpolating a missing n_rows yields "(n = )", which
    # reads as a verified count of nothing rather than as an absent one.
    msg <- if (is.null(entry$n_rows)) {
      "SHA-256 match; no row count recorded"
    } else if (rowcount_checked) {
      paste0("SHA-256 match (n = ", entry$n_rows, ")")
    } else {
      paste0("SHA-256 match (n = ", entry$n_rows, "); row count not re-derived")
    }
    if (verbose) {
      message(entry$file, " \u2014 ", msg)
    }
    data.frame(
      file    = entry$file,
      status  = "OK",
      message = msg,
      row_count_checked = rowcount_checked,
      stringsAsFactors = FALSE
    )
  })

  # Derived paths are stem-based, so two sources differing only by extension
  # would claim the same .parquet and .schema.csv. A manifest listing both
  # cohort.sas7bdat and cohort.csv -- a source and an export of it -- has
  # always been legal on its own; the collision is only real once one of them
  # has actually produced a derived artifact that the other would overwrite.
  # Reporting it pre-emptively would abort verification for an intact study,
  # so the row fires only when a `<stem>.parquet` or `<stem>.schema.csv`
  # already exists on disk, resolved the same way entries are.
  stems <- vapply(manifest$datasets,
                  function(e) tools::file_path_sans_ext(e$file), character(1))
  clash <- unique(stems[duplicated(stems)])
  if (length(clash)) {
    files <- vapply(manifest$datasets, function(e) e$file, character(1))
    real_clash <- Filter(function(s) {
      file.exists(resolve_entry(paste0(s, ".parquet"))) ||
        file.exists(resolve_entry(paste0(s, ".schema.csv")))
    }, clash)
    collisions <- lapply(real_clash, function(s) data.frame(
      file    = s,
      status  = "FAIL",
      message = paste0("Entries ", paste(files[stems == s], collapse = ", "),
                       " share the derived path stem '", s,
                       "' and would claim the same .parquet and .schema.csv."),
      row_count_checked = FALSE, stringsAsFactors = FALSE))
    results <- c(results, collisions)
  }

  report <- do.call(rbind, results)
  failures <- report[report$status == "FAIL", , drop = FALSE]

  if (nrow(failures) > 0L) {
    msg <- paste(
      "STOP: manifest verification failed for:\n",
      paste(
        paste0("  ", failures$file, ": ", failures$message),
        collapse = "\n"
      )
    )
    if (stop_on_error) stop(msg, call. = FALSE)
    warning(msg, call. = FALSE)
  }

  invisible(report)
}
