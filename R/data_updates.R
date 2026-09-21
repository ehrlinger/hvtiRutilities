# Release discovery is read-only. It reports catalog state without changing
# the study's pinned contract or creating cache artifacts.

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
    stop("manifest.yaml must contain exactly one entry for ",
         contract$built, call. = FALSE)
  }
  entries[[which(hit)]]
}

.check_one_data_update <- function(cfg, dataset) {
  contract <- .study_dataset(cfg, dataset)
  release_contract <- contract$release
  if (is.null(release_contract)) return(list())

  pinned_id <- release_contract$release_id
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
    if (!identical(contract$built, release$file)) {
      stop("_study.yml names ", contract$built, " but release ", pinned_id,
           " names ", release$file, call. = FALSE)
    }
    entry <- .release_manifest_entry(cfg, contract)
    if (!is.character(entry$sha256) || length(entry$sha256) != 1L ||
          !identical(entry$sha256, release$sha256)) {
      stop("manifest.yaml checksum does not match release ", pinned_id,
           call. = FALSE)
    }
    .verify_catalog_file(release, study_dir("datasets", cfg$root))
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
    paste0("release withdrawn: ", pinned$withdrawal_reason)
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
