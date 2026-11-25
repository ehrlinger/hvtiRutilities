# No exported function writes into the working directory by default. A writer
# either requires its destination or finds the study that contains the working
# directory by its _study.yml, and outside a study it stops and writes nothing.
# The CRAN Cookbook's code chapter asks for this; see
# dev/specs/2026-10-27-write-destinations-design.md.

no_study_dir <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_dir(dir, .local_envir = env)
  dir
}

expect_left_empty <- function(dir) {
  testthat::expect_identical(list.files(dir, all.files = TRUE, no.. = TRUE), character(0))
}

test_that("update_manifest(file) needs manifest_path outside a study", {
  data_dir <- withr::local_tempdir()
  csv <- file.path(data_dir, "tiny.csv")
  utils::write.csv(data.frame(id = 1:2), csv, row.names = FALSE)
  here <- no_study_dir()

  expect_error(update_manifest(csv), "manifest_path")
  expect_left_empty(here)
  expect_identical(list.files(data_dir), "tiny.csv")

  # Naming the manifest still works anywhere.
  out <- file.path(data_dir, "manifest.yaml")
  update_manifest(csv, manifest_path = out)
  expect_true(file.exists(out))
  expect_left_empty(here)
})

test_that("update_manifest(file) inside a study writes the study's manifest", {
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Manifest default", 42L, renv = FALSE))
  csv <- file.path(root, "00_datasets", "tiny.csv")
  utils::write.csv(data.frame(id = 1:2), csv, row.names = FALSE)
  withr::local_dir(file.path(root, "30_analyses"))

  update_manifest(csv)

  expect_false(file.exists(file.path(root, "30_analyses", "manifest.yaml")))
  entries <- yaml::read_yaml(file.path(root, "manifest.yaml"))$datasets
  expect_true("tiny.csv" %in% vapply(entries, `[[`, "", "file"))
})

test_that("the study manifest default refuses a file outside the datasets folder", {
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Same basename", 42L, renv = FALSE))
  registered <- file.path(root, "00_datasets", "tiny.csv")
  utils::write.csv(data.frame(id = 1:2), registered, row.names = FALSE)
  withr::with_dir(root, update_manifest(registered))
  manifest <- file.path(root, "manifest.yaml")
  before <- readLines(manifest)

  # A different file with the same name in a job folder would be recorded
  # under the registered file's entry, which the verifier resolves in
  # 00_datasets/.
  withr::local_dir(file.path(root, "30_analyses"))
  utils::write.csv(data.frame(id = 1:4), "tiny.csv", row.names = FALSE)
  expect_error(update_manifest("tiny.csv"), "manifest_path")
  expect_identical(readLines(manifest), before)
  expect_false(file.exists(file.path(root, "30_analyses", "manifest.yaml")))
  expect_identical(verify_manifest(manifest)$status, "OK")

  # Naming a destination still records it.
  local_manifest <- file.path(root, "30_analyses", "manifest.yaml")
  update_manifest("tiny.csv", manifest_path = local_manifest)
  expect_true(file.exists(local_manifest))
  expect_identical(readLines(manifest), before)
})

test_that("update_manifest(file) finds a bare name in the datasets folder, as register_data() does", {
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Bare name", 42L, renv = FALSE))
  utils::write.csv(data.frame(id = 1:3), file.path(root, "00_datasets", "tiny.csv"), row.names = FALSE)

  withr::local_dir(file.path(root, "30_analyses"))
  update_manifest("tiny.csv")

  entries <- yaml::read_yaml(file.path(root, "manifest.yaml"))$datasets
  expect_identical(entries[[1L]]$file, "tiny.csv")
  expect_identical(entries[[1L]]$n_rows, 3L)
  expect_error(update_manifest("absent.csv"), "Dataset file not found: absent.csv.*00_datasets")
})

test_that("update_manifest(file) converts an .rds to parquet and records its shape and schema", {
  skip_if_not_installed("arrow")
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Derived rds", 42L, renv = FALSE))
  data_dir <- file.path(root, "00_datasets")
  saveRDS(data.frame(id = 1:3, x = c(0.5, 1, 2)), file.path(data_dir, "derived.rds"))

  withr::local_dir(root)
  update_manifest("derived.rds", source = "built by run sheet")

  entry <- yaml::read_yaml(file.path(root, "manifest.yaml"))$datasets[[1L]]
  expect_identical(entry$file, "derived.rds")
  expect_identical(entry$n_rows, 3L)
  expect_identical(entry$n_cols, 2L)
  expect_identical(entry$source, "built by run sheet")
  expect_identical(entry$schema_sha256,
                   digest::digest(file.path(data_dir, "derived.schema.csv"), algo = "sha256", file = TRUE))
  expect_equal(as.data.frame(arrow::read_parquet(file.path(data_dir, "derived.parquet"))),
               readRDS(file.path(data_dir, "derived.rds")))
  expect_identical(verify_manifest(file.path(root, "manifest.yaml"))$status, "OK")
})

test_that("update_manifest(file) converts an .rda or .RData the way it converts an .rds", {
  skip_if_not_installed("arrow")
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Derived rda", 42L, renv = FALSE))
  data_dir <- file.path(root, "00_datasets")
  derived <- data.frame(id = 1:3, x = c(0.5, 1, 2))
  labels <- list(id = "Patient")
  save(derived, labels, file = file.path(data_dir, "derived.rda"))
  save(derived, file = file.path(data_dir, "other.RData"))

  withr::local_dir(root)
  update_manifest("derived.rda")
  update_manifest("other.RData", as_parquet = FALSE)

  entries <- yaml::read_yaml(file.path(root, "manifest.yaml"))$datasets
  expect_identical(vapply(entries, `[[`, 0L, "n_rows"), c(3L, 3L))
  expect_false(is.null(entries[[1L]]$schema_sha256))
  expect_null(entries[[2L]]$schema_sha256)
  expect_equal(as.data.frame(arrow::read_parquet(file.path(data_dir, "derived.parquet"))), derived)
  expect_false(file.exists(file.path(data_dir, "other.parquet")))
})

test_that("update_manifest(file) says it refused an .rda with no data frame, and wrote nothing", {
  skip_if_not_installed("arrow")
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Model rda", 42L, renv = FALSE))
  fit <- list(coef = 1)
  save(fit, file = file.path(root, "00_datasets", "model.rda"))

  withr::local_dir(root)
  expect_error(update_manifest("model.rda"), "^update_manifest\\(\\): model.rda holds no data frame.*Nothing was written")
  expect_false(file.exists(file.path(root, "manifest.yaml")))
})

test_that("update_manifest(file, as_parquet = FALSE) lists an .rds as it is", {
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Listed rds", 42L, renv = FALSE))
  data_dir <- file.path(root, "00_datasets")
  saveRDS(data.frame(id = 1:4, x = 1), file.path(data_dir, "listed.rds"))

  withr::local_dir(root)
  update_manifest("listed.rds", as_parquet = FALSE)

  entry <- yaml::read_yaml(file.path(root, "manifest.yaml"))$datasets[[1L]]
  expect_identical(entry$n_rows, 4L)
  expect_identical(entry$n_cols, 2L)
  expect_null(entry$schema_sha256)
  expect_false(file.exists(file.path(data_dir, "listed.parquet")))
  expect_false(file.exists(file.path(data_dir, "listed.schema.csv")))
})

test_that("update_manifest(file) refuses an .rds that does not hold a data frame", {
  skip_if_not_installed("arrow")
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Model rds", 42L, renv = FALSE))
  saveRDS(list(a = 1), file.path(root, "00_datasets", "model.rds"))

  withr::local_dir(root)
  expect_error(update_manifest("model.rds"), "not a data frame")
  expect_error(update_manifest("model.rds", as_parquet = FALSE), "not a data frame")
  expect_false(file.exists(file.path(root, "manifest.yaml")))
})

test_that("update_manifest(file) will not convert an .rds over a recorded parquet", {
  skip_if_not_installed("arrow")
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Parquet clash", 42L, renv = FALSE))
  data_dir <- file.path(root, "00_datasets")
  arrow::write_parquet(data.frame(id = 1:2), file.path(data_dir, "derived.parquet"))
  saveRDS(data.frame(id = 1:5), file.path(data_dir, "derived.rds"))

  withr::local_dir(root)
  update_manifest("derived.parquet", n_rows = 2L)
  before <- readLines(file.path(root, "manifest.yaml"))
  parquet_sha <- digest::digest(file.path(data_dir, "derived.parquet"), algo = "sha256", file = TRUE)

  expect_error(update_manifest("derived.rds"), "derived.parquet's data")
  expect_identical(readLines(file.path(root, "manifest.yaml")), before)
  expect_identical(digest::digest(file.path(data_dir, "derived.parquet"), algo = "sha256", file = TRUE), parquet_sha)
  expect_false(file.exists(file.path(data_dir, "derived.schema.csv")))
})

test_that("update_manifest(file) records nothing when the .rds does not round-trip through parquet", {
  skip_if_not_installed("arrow")
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Round trip", 42L, renv = FALSE))
  data_dir <- file.path(root, "00_datasets")
  # A local-time POSIXct comes back from parquet with a different tzone.
  saveRDS(data.frame(id = 1:2, t = as.POSIXct(c("2026-01-01", "2026-01-02"))), file.path(data_dir, "timed.rds"))

  withr::local_dir(root)
  expect_error(update_manifest("timed.rds"), "did not round-trip")
  expect_false(file.exists(file.path(root, "manifest.yaml")))
  expect_false(file.exists(file.path(data_dir, "timed.parquet")))
  expect_false(file.exists(file.path(data_dir, "timed.schema.csv")))
  expect_identical(list.files(data_dir, all.files = TRUE, no.. = TRUE), "timed.rds")
})

test_that("update_manifest(file) will not convert over an unrecorded parquet, but reconverts its own", {
  skip_if_not_installed("arrow")
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Unrecorded parquet", 42L, renv = FALSE))
  data_dir <- file.path(root, "00_datasets")
  arrow::write_parquet(data.frame(id = 1:2), file.path(data_dir, "cohort.parquet"))
  saveRDS(data.frame(id = 1:5), file.path(data_dir, "cohort.rds"))
  parquet_sha <- digest::digest(file.path(data_dir, "cohort.parquet"), algo = "sha256", file = TRUE)

  withr::local_dir(root)
  expect_error(update_manifest("cohort.rds"), "cohort.parquet already exists")
  expect_identical(digest::digest(file.path(data_dir, "cohort.parquet"), algo = "sha256", file = TRUE), parquet_sha)
  expect_false(file.exists(file.path(root, "manifest.yaml")))

  unlink(file.path(data_dir, "cohort.parquet"))
  update_manifest("cohort.rds")
  saveRDS(data.frame(id = 1:6), file.path(data_dir, "cohort.rds"))
  update_manifest("cohort.rds")
  expect_identical(yaml::read_yaml(file.path(root, "manifest.yaml"))$datasets[[1L]]$n_rows, 6L)
  expect_identical(nrow(arrow::read_parquet(file.path(data_dir, "cohort.parquet"))), 6L)
})

test_that("update_manifest(file) will not convert over an unrecorded or recorded schema sidecar", {
  skip_if_not_installed("arrow")
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Sidecar clash", 42L, renv = FALSE))
  data_dir <- file.path(root, "00_datasets")
  saveRDS(data.frame(id = 1:3), file.path(data_dir, "data.rds"))
  saveRDS(data.frame(id = 1:3), file.path(data_dir, "dict.rds"))
  writeLines(c("variable,label", "id,Patient"), file.path(data_dir, "data.schema.csv"))
  writeLines(c("variable,label", "id,Patient"), file.path(data_dir, "dict.schema.csv"))
  withr::local_dir(root)

  # A dictionary that happens to carry the sidecar's name, recorded by nothing.
  expect_error(update_manifest("data.rds"), "data.schema.csv already exists")
  expect_identical(readLines(file.path(data_dir, "data.schema.csv")), c("variable,label", "id,Patient"))
  expect_false(file.exists(file.path(data_dir, "data.parquet")))

  # The same, recorded as a dataset of its own.
  update_manifest("dict.schema.csv")
  before <- readLines(file.path(root, "manifest.yaml"))
  expect_error(update_manifest("dict.rds"), "dict.schema.csv, which is dict.schema.csv's data")
  expect_identical(readLines(file.path(root, "manifest.yaml")), before)
  expect_identical(readLines(file.path(data_dir, "dict.schema.csv")), c("variable,label", "id,Patient"))
})

test_that("update_manifest(file) leaves the sidecar and parquet alone when the manifest write fails", {
  skip_if_not_installed("arrow")
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Manifest write fails", 42L, renv = FALSE))
  data_dir <- file.path(root, "00_datasets")
  saveRDS(data.frame(id = 1:3), file.path(data_dir, "derived.rds"))
  withr::local_dir(root)
  update_manifest("derived.rds")
  sidecar <- readLines(file.path(data_dir, "derived.schema.csv"))
  parquet_sha <- digest::digest(file.path(data_dir, "derived.parquet"), algo = "sha256", file = TRUE)

  saveRDS(data.frame(id = 1:3, extra = "a"), file.path(data_dir, "derived.rds"))
  local_mocked_bindings(.atomic_write = function(target, write_fn) stop("disk full"))
  expect_error(update_manifest("derived.rds"), "disk full")
  expect_identical(readLines(file.path(data_dir, "derived.schema.csv")), sidecar)
  expect_identical(digest::digest(file.path(data_dir, "derived.parquet"), algo = "sha256", file = TRUE), parquet_sha)
  expect_identical(sort(list.files(data_dir, all.files = TRUE, no.. = TRUE)),
                   c("derived.parquet", "derived.rds", "derived.schema.csv"))
})

test_that("update_manifest(file) refuses an as_parquet that is not TRUE or FALSE", {
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Bad flag", 42L, renv = FALSE))
  saveRDS(data.frame(id = 1:3), file.path(root, "00_datasets", "derived.rds"))
  withr::local_dir(root)
  expect_error(update_manifest("derived.rds", as_parquet = NA), "as_parquet")
  expect_error(update_manifest("derived.rds", as_parquet = "TRUE"), "as_parquet")
  expect_false(file.exists(file.path(root, "manifest.yaml")))
})

test_that("update_manifest() with no file refuses as_parquet", {
  expect_error(update_manifest(as_parquet = FALSE), "as_parquet")
})

test_that("study_setup() needs root outside a study", {
  here <- no_study_dir()
  expect_error(
    study_setup(study = "Nowhere", study_tracker_id = 42L, renv = FALSE),
    "no study contains the working directory"
  )
  expect_left_empty(here)
})

test_that("walk-up writers stop and write nothing outside a study", {
  here <- no_study_dir()
  calls <- list(
    declare_data          = quote(declare_data(file = "x.csv")),
    register_data         = quote(register_data(file = "x.csv")),
    add_abbreviation      = quote(add_abbreviation("Example phrase", "ex")),
    study_update_identity = quote(study_update_identity(list(study = "x", study_tracker_id = 42L))),
    cache_fit             = quote(cache_fit("x", 1 + 1)),
    study_declare         = quote(study_declare("stats")),
    update_manifest       = quote(update_manifest()),
    study_checkpoint      = quote(study_checkpoint("milestone", note = "x")),
    study_checkpoint_push = quote(study_checkpoint_push()),
    study_close           = quote(study_close("published")),
    study_reopen          = quote(study_reopen("x"))
  )
  for (fn in names(calls)) {
    expect_error(eval(calls[[fn]]), "_study.yml", fixed = TRUE, info = fn)
    expect_left_empty(here)
  }
})
