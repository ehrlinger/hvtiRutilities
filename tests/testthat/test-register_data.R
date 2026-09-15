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
