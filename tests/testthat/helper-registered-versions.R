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
  suppressMessages(study_setup(root, "Versioned fixture", 42L, renv = FALSE))
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
  suppressMessages(study_setup(root, "Sidecar fixture", 42L, renv = FALSE))
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

# A legacy promoted entry: the data is <stem>.parquet and the source is retired.
promoted_study <- function(env = parent.frame()) {
  root <- versioned_study(env)
  dir <- study_dir("datasets", root)
  file.rename(file.path(dir, "built_20260915.parquet"), file.path(dir, "built.parquet"))
  file.rename(file.path(dir, "built_20260915.schema.csv"), file.path(dir, "built.schema.csv"))
  mp <- file.path(root, "manifest.yaml")
  e <- .read_manifest(mp)$datasets[[1]]
  yaml::write_yaml(list(datasets = list(list(
    file = "built.csv", role = "primary", sha256 = e$sha256, source_sha256 = e$source_sha256,
    extract_date = e$extract_date, n_rows = e$n_rows, n_cols = e$n_cols, promoted_date = "2026-09-20"
  ))), mp)
  unlink(file.path(dir, "built.csv"))
  root
}

# The suite mutes the working-read message (setup-working-context.R); a test
# that asserts it, or its absence, restores the real signal.
.real_signal_working_read <- hvtiRutilities:::.signal_working_read
local_working_signal <- function(env = parent.frame()) {
  testthat::local_mocked_bindings(.signal_working_read = .real_signal_working_read, .package = "hvtiRutilities", .env = env)
}

# The record hvtiRtemplates' bd.qmd writes beside a build: top-level keys master, settings, attrition and
# hvtiRtemplates, with no `schema` and no `built_sha256`. Synthetic values.
write_foreign_build_record <- function(source) {
  path <- .build_sidecar_path(source)
  yaml::write_yaml(list(
    master = list(view = "cardiac_master_v", n = 10L),
    settings = list(cohort = "cohort", join_by = "id", keep = "dead", id = "id", key = "id", dataset_id = "ds",
                    exclude = "x > 1"),
    attrition = list(n_start = 10L, n_end = 4L),
    hvtiRtemplates = "0.0.1"
  ), path)
  path
}

# A legacy promoted entry whose source is still on disk: the bytes registered (`changed = FALSE`), or a rebuild.
promoted_study_with_source <- function(changed = FALSE, env = parent.frame()) {
  root <- promoted_study(env)
  data <- if (changed) data.frame(id = 1:4, DEAD = c(1L, 1L, 0L, 0L)) else data.frame(id = 1:3, DEAD = c(1L, 0L, 0L))
  path <- file.path(study_dir("datasets", root), "built.csv")
  utils::write.csv(data, path, row.names = FALSE)
  Sys.setFileTime(path, as.POSIXct(if (changed) "2026-10-07 12:00:00" else "2026-09-15 12:00:00", tz = "UTC"))
  root
}
