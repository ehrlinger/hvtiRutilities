# Release discovery is read-only. It reports catalog state without changing
# the study's pinned contract or creating cache artifacts.

.update_notices <- new.env(parent = emptyenv())

.reset_update_notices <- function() {
  keys <- ls(.update_notices, all.names = TRUE)
  if (length(keys)) rm(list = keys, envir = .update_notices)
  invisible(TRUE)
}

.update_notice_key <- function(cfg, dataset, status, candidate = "") {
  paste(
    normalizePath(cfg$root, mustWork = FALSE),
    dataset,
    status,
    candidate,
    sep = "\r"
  )
}

.signal_update_notice <- function(cfg, dataset, status, candidate, message,
                                  class, report) {
  key <- .update_notice_key(cfg, dataset, status, candidate)
  if (exists(key, envir = .update_notices, inherits = FALSE)) {
    return(invisible(FALSE))
  }
  assign(key, TRUE, envir = .update_notices)
  condition <- structure(
    list(message = message, call = NULL, report = report),
    class = c(class, "message", "condition")
  )
  base::message(condition)
  invisible(TRUE)
}

.release_abort <- function(class, message, report) {
  condition <- structure(
    list(message = message, call = NULL, report = report),
    class = c(class, "error", "condition")
  )
  stop(condition)
}

.update_row <- function(dataset, scope, pinned_release_id,
                        candidate_release_id = NA_character_,
                        sequence = NA_integer_, file = NA_character_,
                        status, is_latest = FALSE, detail) {
  data.frame(
    dataset = dataset,
    scope = scope,
    pinned_release_id = pinned_release_id,
    candidate_release_id = candidate_release_id,
    sequence = as.integer(sequence),
    file = file,
    status = status,
    is_latest = is_latest,
    detail = detail,
    stringsAsFactors = FALSE
  )
}

.empty_update_report <- function() {
  data.frame(
    dataset = character(),
    scope = character(),
    pinned_release_id = character(),
    candidate_release_id = character(),
    sequence = integer(),
    file = character(),
    status = character(),
    is_latest = logical(),
    detail = character(),
    stringsAsFactors = FALSE
  )
}

.as_update_report <- function(rows) {
  out <- if (length(rows)) {
    do.call(rbind, rows)
  } else {
    .empty_update_report()
  }
  rownames(out) <- NULL
  class(out) <- c("data_update_report", "data.frame")
  out
}

.release_manifest_entry <- function(cfg, contract) {
  path <- file.path(cfg$root, "manifest.yaml")
  if (!file.exists(path)) {
    stop("manifest.yaml is missing", call. = FALSE)
  }
  manifest <- yaml::read_yaml(path)
  entries <- manifest$datasets
  if (!is.list(entries)) {
    stop("manifest.yaml has no dataset entries", call. = FALSE)
  }
  hit <- vapply(entries, function(x) {
    is.list(x) && identical(x$file, contract$built)
  }, logical(1))
  if (sum(hit) != 1L) {
    stop("manifest.yaml must contain exactly one manifest entry for ",
         contract$built, call. = FALSE)
  }
  entries[[which(hit)]]
}

.release_integrity_abort <- function(message) {
  stop(structure(
    list(message = message, call = NULL),
    class = c("hvtiRutilities_release_integrity", "error", "condition")
  ))
}

.verify_pinned_release <- function(cfg, contract, release = NULL,
                                   verified = NULL) {
  if (is.null(verified)) {
    entry <- tryCatch(
      .release_manifest_entry(cfg, contract),
      error = function(e) .release_integrity_abort(conditionMessage(e))
    )
    valid_sha <- is.character(entry$sha256) && length(entry$sha256) == 1L &&
      !is.na(entry$sha256) && grepl("^[0-9a-f]{64}$", entry$sha256)
    if (!valid_sha) {
      .release_integrity_abort(
        paste0("manifest.yaml has an invalid checksum for ", contract$built)
      )
    }
    path <- file.path(study_dir("datasets", cfg$root), contract$built)
    actual <- if (file.exists(path)) {
      digest::digest(path, algo = "sha256", file = TRUE)
    } else {
      NA_character_
    }
    if (is.na(actual)) {
      .release_integrity_abort(paste0("pinned release is missing: ", path))
    }
    if (!identical(actual, entry$sha256)) {
      .release_integrity_abort(paste0(
        "pinned release changed in place relative to manifest.yaml: ",
        contract$built,
        "\n  expected: ", entry$sha256,
        "\n  actual:   ", actual
      ))
    }
    verified <- list(entry = entry, path = path, sha256 = actual)
  }

  if (!is.null(release)) {
    if (!identical(contract$built, release$file)) {
      .release_integrity_abort(paste0(
        "_study.yml names ", contract$built, " but release ",
        release$release_id, " names ", release$file
      ))
    }
    if (!identical(verified$entry$sha256, release$sha256)) {
      .release_integrity_abort(paste0(
        "manifest.yaml checksum does not match release ", release$release_id
      ))
    }
  }
  verified
}

.check_one_data_update <- function(cfg, dataset) {
  contract <- .study_dataset(cfg, dataset)
  release_contract <- contract$release
  if (is.null(release_contract)) return(list())

  pinned_id <- release_contract$release_id
  verified <- tryCatch(
    .verify_pinned_release(cfg, contract),
    error = function(e) e
  )
  if (inherits(verified, "error")) {
    return(list(.update_row(
      dataset = dataset,
      scope = "pinned",
      pinned_release_id = pinned_id,
      status = "FAIL",
      detail = conditionMessage(verified)
    )))
  }

  catalog_path <- .catalog_path(cfg)
  if (!file.exists(catalog_path)) {
    return(list(.update_row(
      dataset = dataset,
      scope = "catalog",
      pinned_release_id = pinned_id,
      status = "UPDATE STATUS UNKNOWN",
      detail = paste0("dataset catalog is unavailable: ", catalog_path)
    )))
  }

  catalog <- tryCatch(
    .read_dataset_catalog(catalog_path),
    error = function(e) e
  )
  if (inherits(catalog, "error")) {
    return(list(.update_row(
      dataset = dataset,
      scope = "catalog",
      pinned_release_id = pinned_id,
      status = "FAIL",
      detail = conditionMessage(catalog)
    )))
  }

  pinned <- tryCatch({
    release <- .catalog_release(
      catalog,
      release_contract$dataset_id,
      pinned_id
    )
    .verify_pinned_release(cfg, contract, release, verified)
    release
  }, error = function(e) e)
  if (inherits(pinned, "error")) {
    return(list(.update_row(
      dataset = dataset,
      scope = "pinned",
      pinned_release_id = pinned_id,
      status = "FAIL",
      detail = conditionMessage(pinned)
    )))
  }

  pinned_status <- if (identical(pinned$status, "withdrawn")) {
    "WITHDRAWN"
  } else {
    "CURRENT"
  }
  pinned_detail <- if (identical(pinned_status, "WITHDRAWN")) {
    detail <- paste0("release withdrawn: ", pinned$withdrawal_reason)
    if (!is.null(pinned$replacement_release_id)) {
      detail <- paste0(
        detail,
        "; replacement: ",
        pinned$replacement_release_id
      )
    }
    detail
  } else {
    paste0("pinned release verified: ", pinned$release_id)
  }
  rows <- list(.update_row(
    dataset = dataset,
    scope = "pinned",
    pinned_release_id = pinned_id,
    sequence = pinned$sequence,
    file = pinned$file,
    status = pinned_status,
    detail = pinned_detail
  ))

  releases <- catalog$datasets[[release_contract$dataset_id]]$releases
  later <- Filter(function(x) {
    x$sequence > pinned$sequence && identical(x$status, "published")
  }, releases)
  for (candidate in later) {
    checked <- tryCatch(
      .verify_catalog_file(candidate, study_dir("datasets", cfg$root)),
      error = function(e) e
    )
    valid <- !inherits(checked, "error")
    rows[[length(rows) + 1L]] <- .update_row(
      dataset = dataset,
      scope = "candidate",
      pinned_release_id = pinned_id,
      candidate_release_id = candidate$release_id,
      sequence = candidate$sequence,
      file = candidate$file,
      status = if (valid) "UPDATE AVAILABLE" else "FAIL",
      detail = if (valid) {
        paste0("published release available: ", candidate$release_id)
      } else {
        conditionMessage(checked)
      }
    )
  }

  valid <- which(vapply(rows, function(x) {
    identical(x$status, "UPDATE AVAILABLE")
  }, logical(1)))
  if (length(valid)) {
    sequences <- vapply(rows[valid], function(x) x$sequence, integer(1))
    latest <- valid[[which.max(sequences)]]
    rows[[latest]]$is_latest <- TRUE
  }
  rows
}

#' Check a study for published dataset updates
#'
#' @description
#' Compares each release-aware dataset contract with its producer-owned
#' catalog. The check verifies the pinned release and every later published
#' candidate without changing \code{_study.yml}, \code{manifest.yaml}, or any
#' cache file. Legacy dataset contracts have no update rows.
#'
#' @param cfg List. A study manifest from \code{\link{study_config}}.
#' @param dataset Character(1) or \code{NULL}. Logical dataset name. When
#'   omitted, check every release-aware dataset in the study.
#'
#' @return An object of class \code{"data_update_report"}: a data frame with
#'   columns \code{dataset}, \code{scope}, \code{pinned_release_id},
#'   \code{candidate_release_id}, \code{sequence}, \code{file}, \code{status},
#'   \code{is_latest}, and \code{detail}. Status is one of \code{"CURRENT"},
#'   \code{"UPDATE AVAILABLE"}, \code{"UPDATE STATUS UNKNOWN"},
#'   \code{"WITHDRAWN"}, or \code{"FAIL"}.
#'
#' @seealso \code{\link{review_data_update}},
#'   \code{\link{adopt_data_update}}, \code{\link{read_built}}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' cfg <- study_config()
#' check_data_updates(cfg)
#' check_data_updates(cfg, dataset = "complete_cases")
#' }
check_data_updates <- function(cfg = study_config(), dataset = NULL) {
  datasets <- if (is.null(dataset)) {
    c("study", names(cfg$additional_datasets))
  } else {
    .study_dataset(cfg, dataset)
    dataset
  }
  rows <- unlist(
    lapply(datasets, function(x) .check_one_data_update(cfg, x)),
    recursive = FALSE
  )
  .as_update_report(rows)
}

.enforce_release_read <- function(cfg, dataset, allow_withdrawn) {
  report <- check_data_updates(cfg, dataset)
  pinned_failure <- report$scope == "pinned" & report$status == "FAIL"
  if (any(pinned_failure)) {
    .release_abort(
      "hvtiRutilities_release_integrity",
      paste0(
        "read_built(): pinned release integrity failed: ",
        report$detail[which(pinned_failure)[[1L]]]
      ),
      report
    )
  }

  withdrawn <- report$scope == "pinned" & report$status == "WITHDRAWN"
  if (any(withdrawn) && !allow_withdrawn) {
    .release_abort(
      "hvtiRutilities_withdrawn_release",
      paste0(
        "read_built(): pinned release is withdrawn: ",
        report$detail[which(withdrawn)[[1L]]],
        ". Set allow_withdrawn = TRUE only for a deliberate revision run."
      ),
      report
    )
  }

  available <- report$scope == "candidate" &
    report$status == "UPDATE AVAILABLE" & report$is_latest
  if (any(available)) {
    row <- report[which(available)[[1L]], , drop = FALSE]
    .signal_update_notice(
      cfg,
      dataset,
      row$status,
      row$candidate_release_id,
      paste0(
        "Dataset update available for '", dataset, "': ",
        row$candidate_release_id, ". The pinned release remains in use."
      ),
      "hvtiRutilities_update_available",
      report
    )
  }

  uncertain <- report$scope == "catalog" | (
    report$scope == "candidate" & report$status == "FAIL"
  )
  if (any(uncertain)) {
    rows <- report[uncertain, , drop = FALSE]
    candidates <- rows$candidate_release_id[!is.na(rows$candidate_release_id)]
    candidate_key <- paste(candidates, collapse = ",")
    subject <- if (any(rows$scope == "candidate")) {
      "candidate update status unknown"
    } else {
      "update status unknown"
    }
    .signal_update_notice(
      cfg,
      dataset,
      "UPDATE STATUS UNKNOWN",
      candidate_key,
      paste0(
        "Dataset ", subject, " for '", dataset, "': ",
        paste(rows$detail, collapse = "; "),
        ". The pinned release remains in use."
      ),
      "hvtiRutilities_update_status_unknown",
      report
    )
  }

  invisible(report)
}

.assert_catalog_dimensions <- function(data, release) {
  actual <- c(n_rows = nrow(data), n_cols = ncol(data))
  expected <- c(n_rows = release$n_rows, n_cols = release$n_cols)
  if (!identical(as.integer(actual), as.integer(expected))) {
    stop(
      "review_data_update(): observed dimensions for ",
      release$release_id,
      " are ", actual[["n_rows"]], " rows x ", actual[["n_cols"]],
      " columns; catalog dimensions are ", expected[["n_rows"]],
      " rows x ", expected[["n_cols"]], " columns",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

#' Review one published dataset release
#'
#' @description
#' Verifies the pinned release and one exact, newer candidate, then compares
#' their structure and cohort counts. Review reads the source files directly;
#' it does not write caches or change either study manifest. It describes data
#' drift, but it does not certify that a candidate is analytically or
#' clinically correct.
#'
#' @param cfg List. A study manifest from \code{\link{study_config}}.
#' @param dataset Character(1). Logical dataset name. Defaults to
#'   \code{"study"}.
#' @param release_id Character(1). Exact candidate release ID. The value
#'   \code{"latest"} is not accepted as an alias.
#'
#' @return An object of class \code{"data_update_review"} with
#'   \describe{
#'     \item{dataset}{The logical study dataset name.}
#'     \item{pinned,candidate}{The catalog records for both releases.}
#'     \item{comparison}{A \code{\link{compare_datasets}} result.}
#'     \item{cohort_old,cohort_new}{Cohort counts, or \code{NULL} when the
#'       selected dataset has no cohort contract.}
#'   }
#'
#' @seealso \code{\link{check_data_updates}},
#'   \code{\link{adopt_data_update}}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' review_data_update(
#'   study_config(),
#'   release_id = "surgery_cohort-20260921-r1"
#' )
#' }
review_data_update <- function(cfg = study_config(), dataset = "study",
                               release_id) {
  if (identical(release_id, "latest")) {
    stop(
      "review_data_update(): supply an exact release ID; 'latest' is not accepted",
      call. = FALSE
    )
  }
  contract <- .study_dataset(cfg, dataset)
  if (is.null(contract$release)) {
    stop(
      "review_data_update(): dataset '", dataset,
      "' is not registered to a catalog release",
      call. = FALSE
    )
  }

  catalog <- .read_dataset_catalog(.catalog_path(cfg))
  dataset_id <- contract$release$dataset_id
  pinned <- .catalog_release(
    catalog,
    dataset_id,
    contract$release$release_id
  )
  .verify_pinned_release(cfg, contract, pinned)
  candidate <- .catalog_release(catalog, dataset_id, release_id)
  if (candidate$sequence <= pinned$sequence) {
    stop(
      "review_data_update(): candidate release must be newer than the pinned release",
      call. = FALSE
    )
  }
  if (!identical(candidate$status, "published")) {
    stop(
      "review_data_update(): candidate release must have status published",
      call. = FALSE
    )
  }
  if (!identical(contract$built, pinned$file)) {
    stop(
      "review_data_update(): _study.yml does not name the pinned release file",
      call. = FALSE
    )
  }

  data_dir <- study_dir("datasets", cfg$root)
  pinned_path <- .verify_catalog_file(pinned, data_dir)
  candidate_path <- .verify_catalog_file(candidate, data_dir)
  old <- .read_registration_data(pinned_path)
  new <- .read_registration_data(candidate_path)
  .assert_catalog_dimensions(old, pinned)
  .assert_catalog_dimensions(new, candidate)

  out <- list(
    dataset = dataset,
    pinned = pinned,
    candidate = candidate,
    comparison = compare_datasets(old, new),
    cohort_old = if (is.null(contract$cohort)) NULL else
      cohort_counts(old, cfg, dataset),
    cohort_new = if (is.null(contract$cohort)) NULL else
      cohort_counts(new, cfg, dataset)
  )
  class(out) <- "data_update_review"
  out
}

#' @export
print.data_update_review <- function(x, ...) {
  cat(
    "Dataset update review: ", x$dataset, "\n",
    "  Pinned:    ", x$pinned$release_id, " (", x$pinned$file, ")\n",
    "  Candidate: ", x$candidate$release_id, " (", x$candidate$file, ")\n",
    sep = ""
  )
  print(x$comparison)
  if (!is.null(x$cohort_old) && !is.null(x$cohort_new)) {
    cat(
      "Cohort\n",
      "  N: ", x$cohort_old$n, " -> ", x$cohort_new$n, "\n",
      "  Events: ", x$cohort_old$n_events, " -> ",
      x$cohort_new$n_events, "\n",
      "  Censored: ", x$cohort_old$n_censored, " -> ",
      x$cohort_new$n_censored, "\n",
      sep = ""
    )
  }
  invisible(x)
}

.adoption_manifest_files <- function(manifest) {
  if (!is.list(manifest) || !is.list(manifest$datasets)) {
    stop(
      "adopt_data_update(): manifest.yaml has an invalid datasets field",
      call. = FALSE
    )
  }
  vapply(manifest$datasets, function(entry) {
    file <- entry$file
    if (!is.character(file) || length(file) != 1L || is.na(file) ||
          !nzchar(file)) {
      stop(
        "adopt_data_update(): manifest.yaml has an invalid dataset entry",
        call. = FALSE
      )
    }
    file
  }, character(1))
}

#' Adopt one published dataset release
#'
#' @description
#' Repeats the candidate review, derives its cohort counts, and replaces
#' \code{_study.yml} and \code{manifest.yaml} as one recoverable pair. The old
#' dated release and its cache files remain on disk. Adoption does not make a
#' Git commit.
#'
#' The candidate must be named by its exact release ID. The value
#' \code{"latest"} is never accepted, because the reviewed release and the
#' adopted release must be the same object.
#'
#' @param cfg List. A study manifest from \code{\link{study_config}}.
#' @param dataset Character(1). Logical dataset name. Defaults to
#'   \code{"study"}.
#' @param release_id Character(1). Exact, newer, published candidate release
#'   ID.
#'
#' @return The updated \code{\link{study_status}} object, returned visibly.
#'
#' @seealso \code{\link{check_data_updates}},
#'   \code{\link{review_data_update}}, \code{\link{register_data}}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' adopt_data_update(
#'   study_config(),
#'   release_id = "surgery_cohort-20260921-r1"
#' )
#' }
adopt_data_update <- function(cfg = study_config(), dataset = "study",
                              release_id) {
  review <- review_data_update(cfg, dataset, release_id)
  current_cfg <- study_config(cfg$root, require_data = FALSE)
  original_contract <- .study_dataset(cfg, dataset)
  contract <- .study_dataset(current_cfg, dataset)
  same_pin <- !is.null(contract$release) &&
    identical(contract$built, review$pinned$file) &&
    identical(contract$release$dataset_id,
              original_contract$release$dataset_id) &&
    identical(contract$release$release_id, review$pinned$release_id)
  if (!same_pin) {
    stop(
      "adopt_data_update(): the study contract changed after review; review the candidate again",
      call. = FALSE
    )
  }

  raw <- yaml::read_yaml(current_cfg$file)
  manifest_path <- file.path(current_cfg$root, "manifest.yaml")
  if (!file.exists(manifest_path)) {
    stop("adopt_data_update(): manifest.yaml is missing", call. = FALSE)
  }
  manifest <- yaml::read_yaml(manifest_path)

  data_dir <- study_dir("datasets", current_cfg$root)
  candidate_path <- .verify_catalog_file(review$candidate, data_dir)
  candidate_data <- .read_registration_data(candidate_path)
  .verify_catalog_file(review$candidate, data_dir)
  .assert_catalog_dimensions(candidate_data, review$candidate)
  cohort <- if (is.null(contract$cohort)) {
    NULL
  } else {
    c(
      cohort_counts(candidate_data, current_cfg, dataset),
      contract$cohort[c("event", "time")]
    )
  }

  release <- contract$release
  release$release_id <- review$candidate$release_id
  if (identical(dataset, "study")) {
    raw$built <- review$candidate$file
    raw$cohort <- cohort
    raw$release <- release
  } else {
    raw$additional_datasets[[dataset]]$built <- review$candidate$file
    raw$additional_datasets[[dataset]]$cohort <- cohort
    raw$additional_datasets[[dataset]]$release <- release
  }

  files <- .adoption_manifest_files(manifest)
  old <- files == contract$built
  if (sum(old) != 1L) {
    stop(
      "adopt_data_update(): adoption requires exactly one manifest entry for ",
      contract$built,
      call. = FALSE
    )
  }
  candidate_stem <- tools::file_path_sans_ext(review$candidate$file)
  other_stems <- tools::file_path_sans_ext(files[!old])
  if (candidate_stem %in% other_stems) {
    conflict <- files[!old][[match(candidate_stem, other_stems)]]
    stop(
      "adopt_data_update(): ", review$candidate$file, " and ", conflict,
      " share the derived path stem '", candidate_stem, "'",
      call. = FALSE
    )
  }

  entry <- .registration_manifest_entry(
    candidate_path,
    candidate_data,
    review$candidate$extract_date,
    review$candidate$source
  )
  if (!identical(entry$sha256, review$candidate$sha256) ||
        !identical(entry$n_rows, review$candidate$n_rows) ||
        !identical(entry$n_cols, review$candidate$n_cols)) {
    stop(
      "adopt_data_update(): prepared manifest entry disagrees with the catalog",
      call. = FALSE
    )
  }
  manifest$datasets[[which(old)]] <- entry

  targets <- c(current_cfg$file, manifest_path)
  prepared <- c(
    tempfile(pattern = "._study-", tmpdir = current_cfg$root),
    tempfile(pattern = ".manifest-", tmpdir = current_cfg$root)
  )
  on.exit(unlink(prepared[file.exists(prepared)]), add = TRUE)
  yaml::write_yaml(raw, prepared[[1L]])
  yaml::write_yaml(manifest, prepared[[2L]])
  .replace_study_pair(prepared, targets)
  study_status(current_cfg$root)
}
