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
