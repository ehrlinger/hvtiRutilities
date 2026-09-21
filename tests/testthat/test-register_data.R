registration_study <- function() {
  root <- file.path(withr::local_tempdir(.local_envir = parent.frame()),
                    "study")
  study_setup(root, "Registration fixture", 42L)
  root
}

write_registration_csv <- function(root, file, n = 5L, n_events = 2L) {
  path <- file.path(study_dir("datasets", root), file)
  d <- data.frame(
    id = seq_len(n),
    dead = c(rep(1L, n_events), rep(0L, n - n_events)),
    iv_dead = seq_len(n)
  )
  write.csv(d, path, row.names = FALSE)
  path
}

study_manifest_bytes <- function(root) {
  list(
    study = readBin(file.path(root, "_study.yml"), "raw",
                    file.info(file.path(root, "_study.yml"))$size),
    data = readBin(file.path(root, "manifest.yaml"), "raw",
                   file.info(file.path(root, "manifest.yaml"))$size)
  )
}

test_that("register_data derives the default cohort", {
  root <- registration_study()
  write_registration_csv(root, "built.csv", n = 5L, n_events = 2L)

  status <- register_data(root, "built.csv", "dead", "iv_dead")

  expect_s3_class(status, "study_status")
  cfg <- study_config(root)
  expect_identical(cfg$built, "built.csv")
  expect_identical(
    cfg$cohort[c("n", "n_events", "n_censored")],
    list(n = 5L, n_events = 2L, n_censored = 3L)
  )
  manifest <- yaml::read_yaml(file.path(root, "manifest.yaml"))
  expect_identical(manifest$datasets[[1L]]$n_rows, 5L)
})

test_that("register_data adds a named cohort without changing the default", {
  root <- registration_study()
  write_registration_csv(root, "built.csv")
  register_data(root, "built.csv", "dead", "iv_dead")
  before <- study_config(root)
  write_registration_csv(root, "subset.csv", n = 3L, n_events = 1L)

  register_data(
    root,
    "subset.csv",
    "dead",
    "iv_dead",
    dataset = "complete_cases",
    role = "named",
    population = "Complete cases"
  )

  after <- study_config(root)
  expect_identical(after$built, before$built)
  expect_identical(after$cohort, before$cohort)
  expect_identical(
    after$additional_datasets$complete_cases$cohort$n,
    3L
  )
  expect_identical(
    after$additional_datasets$complete_cases$population,
    "Complete cases"
  )
})

test_that("register_data permits ancillary data before the default", {
  root <- registration_study()
  write_registration_csv(root, "imaging.csv")

  register_data(
    root,
    "imaging.csv",
    dataset = "imaging",
    role = "named"
  )

  cfg <- study_config(root, require_data = FALSE)
  expect_null(cfg$built)
  expect_null(cfg$additional_datasets$imaging$cohort)
  expect_error(study_config(root), "register_data")
})

test_that("register_data refuses duplicate registrations without changes", {
  root <- registration_study()
  write_registration_csv(root, "built.csv")
  register_data(root, "built.csv", "dead", "iv_dead")
  before <- study_manifest_bytes(root)

  expect_error(
    register_data(root, "built.csv", "dead", "iv_dead"),
    "already registered"
  )

  expect_identical(study_manifest_bytes(root), before)
})

test_that("register_data validates named data before writing", {
  root <- registration_study()
  write_registration_csv(root, "built.csv")
  register_data(root, "built.csv", "dead", "iv_dead")
  write_registration_csv(root, "subset.csv")
  before <- study_manifest_bytes(root)

  expect_error(
    register_data(root, "subset.csv", "dead",
                  dataset = "Complete Cases", role = "named"),
    "together"
  )
  expect_identical(study_manifest_bytes(root), before)

  expect_error(
    register_data(root, "subset.csv", "dead", "iv_dead",
                  dataset = "Complete Cases", role = "named"),
    "lower-snake-case"
  )
  expect_identical(study_manifest_bytes(root), before)
})

test_that("register_data rejects missing cohort columns before writing", {
  root <- registration_study()
  write_registration_csv(root, "built.csv")

  expect_error(
    register_data(root, "built.csv", "dead", "missing_time"),
    "missing_time"
  )

  cfg <- study_config(root, require_data = FALSE)
  expect_null(cfg$built)
  expect_false(file.exists(file.path(root, "manifest.yaml")))
})

test_that("register_data identifies itself in argument errors", {
  root <- registration_study()

  expect_error(register_data(root, "", "dead", "iv_dead"),
               "register_data[(][)]")
})

test_that("register_data records source and the requested extract date", {
  root <- registration_study()
  write_registration_csv(root, "built.csv")

  register_data(
    root,
    "built.csv",
    "dead",
    "iv_dead",
    source = "Synthetic fixture",
    extract_date = "2006-05-03"
  )

  manifest <- yaml::read_yaml(file.path(root, "manifest.yaml"))
  expect_identical(manifest$datasets[[1L]]$source, "Synthetic fixture")
  expect_identical(manifest$datasets[[1L]]$extract_date, "2006-05-03")
})

test_that("register_data defaults extract date to the dataset mtime", {
  root <- registration_study()
  path <- write_registration_csv(root, "built.csv")
  Sys.setFileTime(path, as.POSIXct("2006-05-03 14:03:00", tz = "UTC"))

  register_data(root, "built.csv", "dead", "iv_dead")

  manifest <- yaml::read_yaml(file.path(root, "manifest.yaml"))
  expect_identical(manifest$datasets[[1L]]$extract_date, "2006-05-03")
})

test_that("register_data creates a verifiable manifest entry", {
  root <- registration_study()
  write_registration_csv(root, "built.csv")
  register_data(root, "built.csv", "dead", "iv_dead")

  report <- verify_manifest(
    file.path(root, "manifest.yaml"),
    stop_on_error = FALSE
  )

  expect_identical(report$file, "built.csv")
  expect_identical(report$status, "OK")
})

test_that("verify_manifest refuses a mixed study layout by default", {
  root <- registration_study()
  write_registration_csv(root, "built.csv")
  register_data(root, "built.csv", "dead", "iv_dead")
  dir.create(file.path(root, "datasets"))

  expect_error(
    verify_manifest(file.path(root, "manifest.yaml")),
    "mixed"
  )
})

test_that("register_data refuses files that share derived output paths", {
  root <- registration_study()
  write_registration_csv(root, "built.csv")
  register_data(root, "built.csv", "dead", "iv_dead")
  before <- study_manifest_bytes(root)
  d <- data.frame(id = 1:2, dead = c(0L, 1L), iv_dead = 1:2)
  saveRDS(d, file.path(study_dir("datasets", root), "built.rds"))

  expect_error(
    register_data(root, "built.rds", dataset = "secondary", role = "named"),
    "derived path stem"
  )
  expect_identical(study_manifest_bytes(root), before)
})

test_that("pair replacement retains a backup when restoration fails", {
  root <- withr::local_tempdir()
  targets <- file.path(root, c("_study.yml", "manifest.yaml"))
  prepared <- file.path(root, c("._study-new", ".manifest-new"))
  writeLines("old study", targets[[1L]])
  writeLines("old manifest", targets[[2L]])
  writeLines("new study", prepared[[1L]])
  writeLines("new manifest", prepared[[2L]])

  local_mocked_bindings(
    .registration_rename = function(from, to) {
      if (grepl("^\\.manifest-new$", basename(from))) return(FALSE)
      if (grepl("-backup-", basename(from)) &&
            identical(basename(to), "_study.yml")) {
        return(FALSE)
      }
      file.rename(from, to)
    }
  )
  expect_warning(
    expect_error(.replace_study_pair(prepared, targets), "prepared manifest"),
    "backup remains"
  )
  backups <- list.files(root, pattern = "_study[.]yml-backup",
                        all.files = TRUE, full.names = TRUE)
  expect_length(backups, 1L)
  expect_identical(readLines(backups), "old study")
  expect_identical(readLines(targets[[2L]]), "old manifest")
})

test_that("register_data rejects an unnamed additional dataset sequence", {
  root <- registration_study()
  cfg <- yaml::read_yaml(file.path(root, "_study.yml"))
  cfg$additional_datasets <- list(list(built = "old.csv"))
  yaml::write_yaml(cfg, file.path(root, "_study.yml"))
  write_registration_csv(root, "new.csv")
  before <- readLines(file.path(root, "_study.yml"))

  expect_error(
    register_data(
      root,
      "new.csv",
      dataset = "secondary",
      role = "named"
    ),
    "named mapping"
  )
  expect_identical(readLines(file.path(root, "_study.yml")), before)
  expect_false(file.exists(file.path(root, "manifest.yaml")))
})

test_that("register_data refuses an absent or extensionless file", {
  root <- registration_study()
  before <- readLines(file.path(root, "_study.yml"))

  expect_error(
    register_data(root, "missing.csv", "dead", "iv_dead"),
    "missing"
  )
  expect_error(
    register_data(root, "missing", "dead", "iv_dead"),
    "extension"
  )

  expect_identical(readLines(file.path(root, "_study.yml")), before)
  expect_false(file.exists(file.path(root, "manifest.yaml")))
})

test_that("register_data attaches a verified published release", {
  root <- registration_study()
  fx <- write_release_fixture(root)

  register_data(
    root,
    "cohort_20260920.csv",
    "dead",
    "iv_dead",
    catalog_dataset = "surgery_cohort",
    release_id = "surgery_cohort-20260920-r1"
  )

  cfg <- study_config(root)
  expect_identical(cfg$release, list(
    dataset_id = "surgery_cohort",
    release_id = "surgery_cohort-20260920-r1"
  ))
  manifest <- yaml::read_yaml(file.path(root, "manifest.yaml"))
  expect_identical(
    manifest$datasets[[1L]]$sha256,
    fx$catalog$datasets$surgery_cohort$releases[[1L]]$sha256
  )
})

test_that("release registration refuses a filename mismatch without writes", {
  root <- registration_study()
  write_release_fixture(root)
  before <- readLines(file.path(root, "_study.yml"))

  expect_error(
    register_data(
      root,
      "cohort_20260921.csv",
      "dead",
      "iv_dead",
      catalog_dataset = "surgery_cohort",
      release_id = "surgery_cohort-20260920-r1"
    ),
    "does not name"
  )
  expect_identical(readLines(file.path(root, "_study.yml")), before)
  expect_false(file.exists(file.path(root, "manifest.yaml")))
})

test_that("release registration requires both catalog identifiers", {
  root <- registration_study()
  write_release_fixture(root)

  expect_error(
    register_data(
      root,
      "cohort_20260920.csv",
      "dead",
      "iv_dead",
      catalog_dataset = "surgery_cohort"
    ),
    "supplied together"
  )
  expect_error(
    register_data(
      root,
      "cohort_20260920.csv",
      "dead",
      "iv_dead",
      release_id = "surgery_cohort-20260920-r1"
    ),
    "supplied together"
  )
})

test_that("release registration rejects withdrawn or changed releases", {
  withdrawn_root <- registration_study()
  withdrawn <- write_release_fixture(withdrawn_root)
  catalog <- yaml::read_yaml(withdrawn$catalog_path)
  catalog$datasets$surgery_cohort$releases[[1L]]$status <- "withdrawn"
  catalog$datasets$surgery_cohort$releases[[1L]]$withdrawal_reason <-
    "Incorrect cohort"
  yaml::write_yaml(catalog, withdrawn$catalog_path)

  expect_error(
    register_data(
      withdrawn_root,
      "cohort_20260920.csv",
      "dead",
      "iv_dead",
      catalog_dataset = "surgery_cohort",
      release_id = "surgery_cohort-20260920-r1"
    ),
    "withdrawn"
  )

  changed_root <- registration_study()
  changed <- write_release_fixture(changed_root)
  writeLines("changed", file.path(changed$data_dir, "cohort_20260920.csv"))
  expect_error(
    register_data(
      changed_root,
      "cohort_20260920.csv",
      "dead",
      "iv_dead",
      catalog_dataset = "surgery_cohort",
      release_id = "surgery_cohort-20260920-r1"
    ),
    class = "hvtiRutilities_release_integrity"
  )
})

test_that("release registration reconciles catalog provenance", {
  root <- registration_study()
  fx <- write_release_fixture(root)
  catalog <- yaml::read_yaml(fx$catalog_path)
  catalog$datasets$surgery_cohort$releases[[1L]]$source <- "Synthetic registry"
  yaml::write_yaml(catalog, fx$catalog_path)

  expect_error(
    register_data(
      root,
      "cohort_20260920.csv",
      "dead",
      "iv_dead",
      source = "Different source",
      catalog_dataset = "surgery_cohort",
      release_id = "surgery_cohort-20260920-r1"
    ),
    "source disagrees"
  )
  expect_error(
    register_data(
      root,
      "cohort_20260920.csv",
      "dead",
      "iv_dead",
      extract_date = "2026-09-19",
      catalog_dataset = "surgery_cohort",
      release_id = "surgery_cohort-20260920-r1"
    ),
    "extract_date disagrees"
  )

  expect_no_error(register_data(
    root,
    "cohort_20260920.csv",
    "dead",
    "iv_dead",
    source = "Synthetic registry",
    extract_date = "2026-09-20",
    catalog_dataset = "surgery_cohort",
    release_id = "surgery_cohort-20260920-r1"
  ))
})

test_that("register_data attaches a release to a legacy registration once", {
  root <- registration_study()
  write_release_fixture(root)
  register_data(
    root,
    "cohort_20260920.csv",
    "dead",
    "iv_dead",
    population = "Synthetic cohort"
  )

  register_data(
    root,
    "cohort_20260920.csv",
    "dead",
    "iv_dead",
    catalog_dataset = "surgery_cohort",
    release_id = "surgery_cohort-20260920-r1"
  )

  cfg <- study_config(root)
  expect_identical(cfg$population, "Synthetic cohort")
  expect_identical(cfg$release$release_id,
                   "surgery_cohort-20260920-r1")
  manifest <- yaml::read_yaml(file.path(root, "manifest.yaml"))
  files <- vapply(manifest$datasets, function(x) x$file, character(1))
  expect_identical(sum(files == "cohort_20260920.csv"), 1L)

  expect_error(
    register_data(
      root,
      "cohort_20260920.csv",
      "dead",
      "iv_dead",
      catalog_dataset = "surgery_cohort",
      release_id = "surgery_cohort-20260920-r1"
    ),
    "already registered"
  )
})
