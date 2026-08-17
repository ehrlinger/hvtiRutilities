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
                            source        = NULL,
                            sort_key      = NULL,
                            verbose       = FALSE) {
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
  if (!is.null(source))   entry$source   <- source
  if (!is.null(sort_key)) entry$sort_key <- sort_key

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

  yaml::write_yaml(manifest, manifest_path)
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
#' @param data_dir Character. Directory in which to look for the dataset files.
#'   When \code{NULL} (default) the directory containing \code{manifest_path}
#'   is used.
#' @param stop_on_error Logical. If \code{TRUE} (default) the function calls
#'   \code{stop()} on the first failed check, preventing the analysis from
#'   proceeding.  Set to \code{FALSE} to collect all errors and report them
#'   together as a warning.
#' @param verbose Logical. If \code{TRUE}, report each passing entry via
#'   \code{\link[base]{message}}.  Defaults to \code{FALSE} so that scripted or
#'   looped calls stay silent; the same information is always available in the
#'   returned data frame.  Failures are reported through \code{stop()} or
#'   \code{warning()} regardless of this setting.
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
                            verbose       = FALSE) {
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

  if (is.null(data_dir)) {
    data_dir <- dirname(normalizePath(manifest_path))
  }

  results <- lapply(manifest$datasets, function(entry) {
    fpath <- file.path(data_dir, entry$file)

    if (!file.exists(fpath)) {
      return(data.frame(
        file    = entry$file,
        status  = "FAIL",
        message = paste("File not found:", fpath),
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
    ext <- tolower(tools::file_ext(fpath))
    rowcount_checked <- FALSE
    if (ext %in% c("csv", "sas7bdat", "xlsx", "xls") && !is.null(entry$n_rows)) {
      actual_rows_result <- tryCatch(
        .auto_count_rows(fpath),
        error = function(e) e
      )
      if (inherits(actual_rows_result, "manifest_heavy_rowcount_disabled")) {
        rowcount_checked <- FALSE
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
