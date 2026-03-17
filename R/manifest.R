## =============================================================================
## Internal helper: auto-detect row count by file extension
## Supported: .csv  .sas7bdat  .xlsx  .xls
## All other types require the caller to supply n_rows explicitly.
#' @importFrom utils count.fields
.auto_count_rows <- function(file) {
  ext <- tolower(tools::file_ext(file))
  switch(ext,
    csv      = length(count.fields(file, sep = ",")) - 1L,
    sas7bdat = nrow(haven::read_sas(file)),
    xlsx     = ,
    xls      = nrow(readxl::read_excel(file)),
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
#' Row counts are detected automatically for \strong{CSV}
#' (\code{.csv}), \strong{SAS} (\code{.sas7bdat}), and \strong{Excel}
#' (\code{.xlsx}, \code{.xls}) files.  For any other format supply
#' \code{n_rows} explicitly.
#'
#' @param file Character. Path to the dataset file.
#' @param manifest_path Character. Path to the manifest YAML file.
#'   Created if it does not exist. Defaults to \code{"manifest.yaml"} in the
#'   current working directory.
#' @param extract_date Character or \code{Date}. The date the data were pulled
#'   from the source system.  Stored as \code{"YYYY-MM-DD"}.  Defaults to
#'   today's date.
#' @param n_rows Integer. Number of data rows.  When \code{NULL} (default) the
#'   row count is detected automatically from CSV, SAS, and Excel files.  For
#'   all other file types supply this value explicitly.
#' @param source Character. Free-text description of the data source (e.g.
#'   \code{"Epic EMR, query v4.2, ICD mapping v3.2"}).
#' @param sort_key Character. Column name(s) that define the canonical sort
#'   order of the dataset.
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
                            sort_key      = NULL) {
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
    list(datasets = list())
  }

  existing <- vapply(
    manifest$datasets,
    function(d) identical(d$file, entry$file),
    logical(1)
  )

  if (any(existing)) {
    manifest$datasets[[which(existing)]] <- entry
    message("Manifest updated: ", entry$file)
  } else {
    manifest$datasets <- c(manifest$datasets, list(entry))
    message("Manifest entry added: ", entry$file)
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
#'
#' @return Invisibly returns a data frame with columns \code{file},
#'   \code{status} (\code{"OK"} or \code{"FAIL"}), and \code{message}.
#'
#' @examples
#' \dontrun{
#' # --- Typical usage: top of every analysis script or .qmd -----------
#' hvtiRutilities::verify_manifest(here::here("manifest.yaml"))
#' # cohort_20240115.csv    — SHA-256 match (n = 831)
#' # labs_20240115.sas7bdat — SHA-256 match (n = 1204)
#' # adjudication_20240115.xlsx — SHA-256 match (n = 47)
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
                            stop_on_error = TRUE) {
  if (!file.exists(manifest_path)) {
    stop("Manifest file not found: ", manifest_path)
  }

  manifest <- yaml::read_yaml(manifest_path)

  if (is.null(manifest$datasets) || length(manifest$datasets) == 0L) {
    message("Manifest contains no dataset entries.")
    return(invisible(data.frame(file = character(), status = character(),
                                message = character(), stringsAsFactors = FALSE)))
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
        stringsAsFactors = FALSE
      ))
    }

    # Row-count cross-check for supported formats
    ext <- tolower(tools::file_ext(fpath))
    if (ext %in% c("csv", "sas7bdat", "xlsx", "xls") && !is.null(entry$n_rows)) {
      actual_rows <- tryCatch(
        .auto_count_rows(fpath),
        error = function(e) NA_integer_
      )
      if (!is.na(actual_rows) &&
          !identical(actual_rows, as.integer(entry$n_rows))) {
        return(data.frame(
          file    = entry$file,
          status  = "FAIL",
          message = paste0("Row count mismatch\n  expected: ", entry$n_rows,
                           "\n  actual:   ", actual_rows),
          stringsAsFactors = FALSE
        ))
      }
    }

    message(entry$file, " \u2014 SHA-256 match (n = ", entry$n_rows, ")")
    data.frame(
      file    = entry$file,
      status  = "OK",
      message = paste0("SHA-256 match (n = ", entry$n_rows, ")"),
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
