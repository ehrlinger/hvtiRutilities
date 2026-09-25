# CHECKPOINT.yml: what a snapshot contains and what produced it. It pins the
# data by manifest hash without shipping it, records the checksum of every
# document in 50_documents/ without committing it (spec D9), and records
# verify_manifest()'s verdict so a checkpoint taken against unverified data
# says so.

.cp_sha <- function(path) {
  if (!file.exists(path)) return(NULL)
  digest::digest(path, algo = "sha256", file = TRUE)
}

.cp_hvtir_versions <- function() {
  pkgs <- grep("^hvtiR", .packages(all.available = TRUE), value = TRUE)
  structure(
    lapply(pkgs, function(p) as.character(utils::packageVersion(p))),
    names = pkgs
  )
}

# verify_manifest() runs against the source study: the snapshot holds no
# data. Its warnings are recorded and still reach the caller (the calling
# handler does not muffle them). An entry verify_manifest() passes without
# counting its rows (no n_rows recorded, or a file type it cannot count) is
# recorded as "unchecked", read from its own row_count_checked column; FAIL
# stays FAIL. A mismatch never blocks the checkpoint.
.cp_manifest_check <- function(root) {
  path <- file.path(root, "manifest.yaml")
  if (!file.exists(path)) return(NULL)
  seen <- new.env(parent = emptyenv())
  seen$warnings <- character(0)
  report <- tryCatch(
    withCallingHandlers(
      verify_manifest(path, data_dir = study_dir("datasets", root),
                      stop_on_error = FALSE),
      warning = function(w) {
        seen$warnings <- c(seen$warnings, conditionMessage(w))
      }
    ),
    error = function(e) e
  )
  if (inherits(report, "error")) {
    msg <- paste("manifest could not be verified:", conditionMessage(report))
    warning(msg, call. = FALSE)
    return(list(error = msg))
  }
  status <- ifelse(report$status == "OK" & !report$row_count_checked,
                   "unchecked", report$status)
  list(datasets = structure(as.list(status), names = report$file),
       warnings = seen$warnings)
}

.cp_write_meta <- function(repo, root, entry, selection) {
  meta <- entry[setdiff(names(entry), c("delivery", "git_commit", "state"))]
  if (grepl("-[0-9]+$", entry$tag)) meta$seq <- .cp_seq_of(entry$tag)
  meta$committed_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  meta$user <- Sys.info()[["user"]]
  meta$r_version <- R.version.string
  meta$platform <- R.version$platform
  meta$packages <- .cp_hvtir_versions()
  meta$renv_lock_sha256 <- .cp_sha(file.path(root, "renv.lock"))
  meta$manifest_sha256 <- .cp_sha(file.path(root, "manifest.yaml"))
  meta$manifest_check <- .cp_manifest_check(root)
  meta$files <- structure(
    lapply(selection$files, function(f) .cp_sha(file.path(repo, f))),
    names = selection$files
  )
  # Hashed from the study root: documents are never copied into the repo.
  meta$documents <- lapply(selection$documents, function(f) {
    p <- file.path(root, f)
    list(path = f, bytes = file.size(p), sha256 = .cp_sha(p))
  })
  meta$skipped <- lapply(seq_len(nrow(selection$skipped)), function(i) {
    list(path = selection$skipped$path[i], bytes = selection$skipped$bytes[i])
  })
  meta$denied <- as.list(selection$denied)
  yaml::write_yaml(meta, file.path(repo, "CHECKPOINT.yml"))
  invisible(meta)
}
