# Write a small CSV source for the registered-version tests and return its path.
write_source_csv <- function(dir, data = data.frame(id = 1:3, x = c(1.5, 2.5, 3.5)), file = "built.csv") {
  path <- file.path(dir, file)
  utils::write.csv(data, path, row.names = FALSE)
  path
}

# A registered study whose source was last modified on 2026-09-15.
versioned_study <- function(env = parent.frame(), data = data.frame(id = 1:3, DEAD = c(1L, 0L, 0L))) {
  testthat::skip_if_not_installed("arrow")
  root <- file.path(withr::local_tempdir(.local_envir = env), "study")
  suppressMessages(study_setup(root, "Versioned fixture", 42L))
  path <- file.path(study_dir("datasets", root), "built.csv")
  utils::write.csv(data, path, row.names = FALSE)
  Sys.setFileTime(path, as.POSIXct("2026-09-15 12:00:00", tz = "UTC"))
  suppressMessages(register_data(root, "built.csv"))
  root
}

manifest_entry_for <- function(root, file = "built.csv") {
  m <- .read_manifest(file.path(root, "manifest.yaml"))
  Filter(function(e) identical(e$file, file), m$datasets)[[1L]]
}

# A build record for the bytes at `source`, as bd will write it.
write_build_sidecar <- function(source, ..., built_sha256 = digest::digest(source, algo = "sha256", file = TRUE)) {
  rec <- utils::modifyList(list(
    schema = 1L, built_sha256 = built_sha256, job = "00_datasets/bd.qmd", view = "cardiac_master_v",
    as_of = "2026-10-01T00:00:00Z", cohort_sha256 = strrep("a", 64), overlay_sha256 = NULL,
    derived_after_overlay = TRUE, attrition = list(n_start = 10L, n_end = 4L)
  ), list(...))
  path <- .build_sidecar_path(source)
  yaml::write_yaml(rec, path)
  path
}

unregistered_study <- function(env = parent.frame()) {
  testthat::skip_if_not_installed("arrow")
  root <- file.path(withr::local_tempdir(.local_envir = env), "study")
  suppressMessages(study_setup(root, "Sidecar fixture", 42L))
  src <- file.path(study_dir("datasets", root), "built.csv")
  utils::write.csv(data.frame(id = 1:3, DEAD = c(1L, 0L, 0L)), src, row.names = FALSE)
  Sys.setFileTime(src, as.POSIXct("2026-09-15 12:00:00", tz = "UTC"))
  list(root = root, src = src)
}

rebuild_source <- function(root, data = data.frame(id = 1:4, DEAD = c(1L, 1L, 0L, 0L)), when = "2026-10-07 12:00:00") {
  path <- built_path(study_config(root))
  utils::write.csv(data, path, row.names = FALSE)
  Sys.setFileTime(path, as.POSIXct(when, tz = "UTC"))
  path
}
