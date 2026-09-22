library(testthat)
library(hvtiRutilities)

make_output <- function(root, name = "death-hz-ac.html") {
  dir.create(file.path(root, "_output"), recursive = TRUE,
             showWarnings = FALSE)
  path <- file.path(root, "_output", name)
  writeLines("<html></html>", path)
  path
}

make_artifact <- function(root, name = "estimates/death-hz-fit.rds") {
  path <- file.path(root, name)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  saveRDS(list(fit = 1L), path)
  path
}

expect_file_record <- function(record, path, role) {
  expect_identical(record$path, path)
  expect_identical(record$role, role)
  expect_true(is.numeric(record$bytes) && length(record$bytes) == 1L)
  expect_match(record$mtime,
               "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}(\\.[0-9]+)?Z$")
  expect_match(record$sha256, "^[0-9a-f]{64}$")
}

test_that("provenance_path swaps the extension for .provenance.json", {
  expect_equal(basename(provenance_path("a/b/death-hz-ac.html")),
               "death-hz-ac.provenance.json")
  expect_equal(basename(provenance_path("a/b/death-hz-ac.qmd")),
               "death-hz-ac.provenance.json")
})

test_that("provenance_data snapshots a registered file with an explicit role", {
  root <- make_registered_study(withr::local_tempdir())
  cfg <- study_config(root)

  study <- provenance_data(cfg = cfg)
  named <- provenance_data("complete_cases", cfg, role = "validation")

  expect_identical(study$dataset, "study")
  expect_file_record(study, "00_datasets/built.csv", "analysis")
  expect_identical(named$dataset, "complete_cases")
  expect_file_record(named, "00_datasets/complete.csv", "validation")
  expect_identical(
    study$sha256,
    digest::digest(file.path(root, study$path), algo = "sha256", file = TRUE)
  )
})

test_that("provenance_data snapshots the authoritative file for a promoted dataset", {
  skip_if_not_installed("arrow")
  root <- make_study_fixture(withr::local_tempdir())
  cfg <- study_config(root)
  read_built(cfg)

  manifest_path <- file.path(root, "manifest.yaml")
  manifest <- yaml::read_yaml(manifest_path)
  manifest$datasets[[1]]$role <- "primary"
  yaml::write_yaml(manifest, manifest_path)
  source <- built_path(cfg)
  parquet <- hvtiRutilities:::.derived_paths(source)$parquet
  unlink(source)

  record <- provenance_data(cfg = cfg)

  expect_file_record(record, "datasets/built_test.parquet", "analysis")
  expect_identical(
    record$sha256,
    digest::digest(parquet, algo = "sha256", file = TRUE)
  )
})

test_that("provenance_artifact snapshots canonical study-relative bytes", {
  root <- make_registered_study(withr::local_tempdir())
  cfg <- study_config(root)
  path <- make_artifact(root)

  relative <- provenance_artifact("estimates/death-hz-fit.rds", cfg = cfg)
  absolute <- provenance_artifact(path, "forest", cfg)

  expect_file_record(relative, "estimates/death-hz-fit.rds", "input")
  expect_file_record(absolute, "estimates/death-hz-fit.rds", "forest")
  expect_identical(relative[names(relative) != "role"],
                   absolute[names(absolute) != "role"])
})

test_that("snapshot helpers reject missing files and invalid roles", {
  root <- make_registered_study(withr::local_tempdir())
  cfg <- study_config(root)
  unlink(built_path(cfg))

  expect_error(provenance_data(cfg = cfg), "missing")
  expect_error(provenance_artifact("estimates/no-fit.rds", cfg = cfg),
               "missing")
  expect_error(provenance_artifact(make_output(root), role = "", cfg = cfg),
               "role")
})

test_that("snapshot helpers reject files outside the study root", {
  root <- make_registered_study(withr::local_tempdir())
  cfg <- study_config(root)
  outside <- tempfile(fileext = ".rds")
  withr::defer(unlink(outside))
  saveRDS(1L, outside)

  expect_error(provenance_artifact(outside, cfg = cfg), "outside")
  expect_error(provenance_artifact("../escape.rds", cfg = cfg), "outside")
})

test_that("capture requires explicit well-formed record lists", {
  root <- make_registered_study(withr::local_tempdir())
  cfg <- study_config(root)
  data <- provenance_data(cfg = cfg)
  artifact <- provenance_artifact(make_artifact(root), cfg = cfg)

  expect_error(capture_provenance("death-hz-ac", cfg = cfg), "data")
  expect_error(capture_provenance("death-hz-ac", list(data), artifact,
                                  cfg = cfg),
               "artifact")
  expect_error(capture_provenance("death-hz-ac", list(data[-1L]), cfg = cfg),
               "data record")
  bad <- artifact
  bad$bytes <- -1
  expect_error(capture_provenance("death-hz-ac", list(data), list(bad),
                                  cfg = cfg),
               "artifact record")
  bad <- data
  bad$path <- "../built.csv"
  expect_error(capture_provenance("death-hz-ac", list(bad), cfg = cfg),
               "canonical study-relative")
})

test_that("capture accepts an intentional empty data list", {
  root <- make_registered_study(withr::local_tempdir())
  record <- capture_provenance(
    "cohort-eda-dc-tables",
    data = list(),
    cfg = study_config(root, require_data = FALSE)
  )

  expect_identical(record$data, list())
  expect_identical(record$artifacts, list())
})

test_that("capture uses explicit records and never resolves current data", {
  root <- make_registered_study(withr::local_tempdir())
  cfg <- study_config(root)
  frozen <- provenance_data(cfg = cfg)

  local_mocked_bindings(
    built_manifest = function(...) stop("registry was read"),
    built_path = function(...) stop("registry was read"),
    .package = "hvtiRutilities"
  )
  record <- capture_provenance("death-hz-ac", list(frozen), cfg = cfg)

  expect_identical(record$data, list(frozen))
})

test_that("capture orders explicit lineage records deterministically", {
  root <- make_registered_study(withr::local_tempdir(), ancillary = TRUE)
  cfg <- study_config(root)
  a <- provenance_data("imaging", cfg, role = "validation")
  b <- provenance_data("study", cfg, role = "training")
  z <- provenance_artifact(make_artifact(root, "estimates/z.rds"), cfg = cfg)
  c <- provenance_artifact(make_artifact(root, "estimates/c.rds"), cfg = cfg)

  record <- capture_provenance(
    "death-hz-ac",
    data = list(a, b),
    artifacts = list(z, c),
    cfg = cfg
  )

  expect_identical(vapply(record$data, `[[`, "", "path"),
                   sort(c(a$path, b$path)))
  expect_identical(vapply(record$artifacts, `[[`, "", "path"),
                   sort(c(z$path, c$path)))
})

test_that("capture records the complete session snapshot", {
  root <- make_registered_study(withr::local_tempdir())
  cfg <- study_config(root)
  writeLines('{"R": {"Version": "4.5.1"}}', file.path(root, "renv.lock"))
  record <- capture_provenance(
    "death-hz-ac",
    data = list(provenance_data(cfg = cfg)),
    artifacts = list(),
    cfg = cfg
  )

  required <- hvtiRutilities:::.provenance_required()
  expect_identical(names(record)[seq_along(required)], names(required))
  expect_match(record$rendered, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$")
  expect_identical(record$study$name, cfg$study)
  expect_identical(record$study$file, "_study.yml")
  expect_match(record$study$sha256, "^[0-9a-f]{64}$")
  expect_identical(record$r$version,
                   paste(R.version$major, R.version$minor, sep = "."))
  expect_identical(record$r$platform, R.version$platform)
  expect_true(length(record$packages) > 0L)
  expect_identical(record$renv_lock$path, "renv.lock")
  expect_match(record$renv_lock$sha256, "^[0-9a-f]{64}$")
})

test_that("capture extras cannot displace reserved fields", {
  root <- make_registered_study(withr::local_tempdir())
  cfg <- study_config(root)
  data <- list(provenance_data(cfg = cfg))
  record <- capture_provenance(
    "death-hz-ac",
    data = data,
    extra = list(
      job = "spoofed",
      rendered = "spoofed",
      data = list(),
      artifacts = list(list(path = "spoofed")),
      output = list(sha256 = "spoofed"),
      subject = "death"
    ),
    cfg = cfg
  )

  expect_identical(record$job, "death-hz-ac")
  expect_false(identical(record$rendered, "spoofed"))
  expect_identical(record$data, data)
  expect_identical(record$artifacts, list())
  expect_false("output" %in% names(record))
  expect_identical(record$subject, "death")
})

test_that("publish requires an existing regular output", {
  root <- make_registered_study(withr::local_tempdir())
  payload <- capture_provenance("death-hz-ac", list(),
                                cfg = study_config(root, require_data = FALSE))
  missing <- file.path(root, "_output", "missing.html")
  dir.create(dirname(missing), recursive = TRUE)

  expect_error(publish_provenance(missing, payload), "existing")
  expect_false(file.exists(provenance_path(missing)))
  expect_error(publish_provenance(dirname(missing), payload), "regular file")
})

test_that("publish binds the sidecar to the completed output bytes", {
  root <- make_registered_study(withr::local_tempdir())
  out <- make_output(root)
  payload <- capture_provenance("death-hz-ac", list(),
                                cfg = study_config(root, require_data = FALSE))

  expect_invisible(publish_provenance(out, payload))
  record <- jsonlite::read_json(provenance_path(out), simplifyVector = FALSE)

  expect_identical(record$output$file, basename(out))
  expect_equal(record$output$bytes, unname(file.info(out)$size))
  expect_identical(
    record$output$sha256,
    digest::digest(out, algo = "sha256", file = TRUE)
  )
  expect_identical(record$rendered, payload$rendered)
  expect_identical(record$r, payload$r)
  expect_identical(
    vapply(record$packages, `[[`, "", "version"),
    vapply(payload$packages, `[[`, "", "version")
  )
})

test_that("publish accepts a captured payload after a JSON round trip", {
  root <- make_registered_study(withr::local_tempdir())
  cfg <- study_config(root)
  out <- make_output(root)
  payload <- capture_provenance(
    "death-hz-ac",
    data = list(provenance_data(cfg = cfg)),
    artifacts = list(provenance_artifact(make_artifact(root), cfg = cfg)),
    cfg = cfg
  )
  transported <- jsonlite::fromJSON(
    jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null", digits = NA),
    simplifyVector = FALSE
  )

  expect_invisible(publish_provenance(out, transported))
  expect_true(file.exists(provenance_path(out)))
})

test_that("publish rejects malformed payloads", {
  root <- make_registered_study(withr::local_tempdir())
  out <- make_output(root)
  payload <- capture_provenance("death-hz-ac", list(),
                                cfg = study_config(root, require_data = FALSE))

  expect_error(publish_provenance(out, payload[-1L]), "payload")
  payload$output <- list(sha256 = "spoofed")
  expect_error(publish_provenance(out, payload), "output")
})

test_that("publish deeply validates a round-tripped captured payload", {
  root <- make_registered_study(withr::local_tempdir())
  cfg <- study_config(root)
  out <- make_output(root)
  writeLines('{"R": {"Version": "4.5.1"}}', file.path(root, "renv.lock"))
  payload <- capture_provenance(
    "death-hz-ac",
    data = list(provenance_data(cfg = cfg)),
    artifacts = list(provenance_artifact(make_artifact(root), cfg = cfg)),
    cfg = cfg
  )
  payload <- jsonlite::fromJSON(
    jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null", digits = NA),
    simplifyVector = FALSE
  )

  malformed <- list(
    rendered_value = within(payload, rendered <- "2026-99-99T25:61:61Z"),
    study_shape = within(payload, study$unexpected <- "field"),
    study_scalar = within(payload, study$name <- character()),
    study_hash = within(payload, study$sha256 <- "not-a-hash"),
    r_shape = within(payload, r$platform <- NULL),
    r_scalar = within(payload, r$version <- list("4.5.1")),
    lock_shape = within(payload, renv_lock$unexpected <- "field"),
    lock_path = within(payload, renv_lock$path <- "../renv.lock"),
    lock_hash = within(payload, renv_lock$sha256 <- "not-a-hash"),
    package_shape = within(payload, packages[[1]]$unexpected <- "field"),
    package_scalar = within(payload, packages[[1]]$version <- character()),
    package_source = within(payload, packages[[1]]$source <- list("CRAN")),
    package_list = within(payload, packages <- list()),
    data_record = within(payload, data[[1]]$mtime <- "2026-99-99T25:61:61Z"),
    artifact_record = within(payload, artifacts[[1]]$sha256 <- "not-a-hash")
  )

  for (case in malformed) {
    expect_error(publish_provenance(out, case), "malformed")
  }
  expect_false(file.exists(provenance_path(out)))
})

test_that("publication failure preserves the previous sidecar atomically", {
  root <- make_registered_study(withr::local_tempdir())
  out <- make_output(root)
  sidecar <- provenance_path(out)
  writeLines("previous sidecar", sidecar)
  payload <- capture_provenance("death-hz-ac", list(),
                                cfg = study_config(root, require_data = FALSE))
  local_mocked_bindings(
    .provenance_rename = function(...) FALSE,
    .package = "hvtiRutilities"
  )

  expect_error(publish_provenance(out, payload), "publish")
  expect_identical(readLines(sidecar), "previous sidecar")
  expect_identical(list.files(dirname(out), pattern = "[.]tmp$"), character())
})

test_that("a JSON write failure preserves the previous sidecar", {
  root <- make_registered_study(withr::local_tempdir())
  out <- make_output(root)
  sidecar <- provenance_path(out)
  writeLines("previous sidecar", sidecar)
  payload <- capture_provenance("death-hz-ac", list(),
                                cfg = study_config(root, require_data = FALSE))
  local_mocked_bindings(
    .provenance_write_json = function(...) stop("disk full"),
    .package = "hvtiRutilities"
  )

  expect_error(publish_provenance(out, payload), "disk full")
  expect_identical(readLines(sidecar), "previous sidecar")
})

test_that("record_provenance is an existing-output convenience", {
  root <- make_registered_study(withr::local_tempdir())
  cfg <- study_config(root)
  out <- make_output(root)
  data <- list(provenance_data(cfg = cfg))
  artifact <- list(provenance_artifact(make_artifact(root), cfg = cfg))

  expect_invisible(record_provenance(
    out,
    data = data,
    artifacts = artifact,
    extra = list(subject = "death"),
    cfg = cfg
  ))
  record <- jsonlite::read_json(provenance_path(out), simplifyVector = FALSE)

  expect_identical(record$job, "death-hz-ac")
  expect_equal(record$data, data)
  expect_equal(record$artifacts, artifact)
  expect_identical(record$subject, "death")
  expect_match(record$output$sha256, "^[0-9a-f]{64}$")
})
