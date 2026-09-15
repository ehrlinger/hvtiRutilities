test_that("study_setup creates numbered identity state", {
  root <- file.path(withr::local_tempdir(), "new-study")

  status <- study_setup(
    root,
    study = "Example study",
    study_tracker_id = 42L,
    umbrella = "Aorta program",
    owner = "Analyst"
  )

  expect_s3_class(status, "study_status")
  expect_true(all(dir.exists(file.path(
    root,
    c("00_datasets", "10_descriptive", "20_distributions",
      "30_analyses", "40_graphs", "50_documents", "90_estimates")
  ))))

  cfg <- study_config(root, require_data = FALSE)
  expect_identical(cfg$study, "Example study")
  expect_identical(cfg$study_tracker_id, 42L)
  expect_identical(cfg$umbrella, "Aorta program")
  expect_identical(cfg$owner, "Analyst")
  expect_null(cfg$built)
  expect_null(cfg$cohort)
  expect_error(study_config(root), "register_data")
  expect_equal(normalizePath(study_root(root)), normalizePath(root))
})

test_that("study_setup creates missing environment files", {
  root <- file.path(withr::local_tempdir(), "new-study")

  study_setup(root, "Example study", 42L)

  expect_identical(
    readLines(file.path(root, ".Renviron")),
    "RENV_CONFIG_CACHE_SYMLINKS=FALSE"
  )
  ignore <- readLines(file.path(root, ".renvignore"))
  expect_true(all(c("00_datasets/", "datasets/", "40_graphs/", "graphs/",
                    "90_estimates/", "estimates/", "templates/") %in%
                  ignore))
})

test_that("study_setup adopts a legacy layout without replacing files", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "datasets"))
  writeLines("keep me", file.path(root, ".Renviron"))

  study_setup(root, "Legacy study", 42L, adopt = TRUE)

  expect_identical(readLines(file.path(root, ".Renviron")), "keep me")
  expect_true(all(dir.exists(file.path(
    root,
    c("datasets", "descriptive", "distributions", "analyses", "graphs",
      "documents", "estimates")
  ))))
  expect_false(dir.exists(file.path(root, "30_analyses")))
})

test_that("study_setup adopts an empty root with numbered directories", {
  root <- withr::local_tempdir()

  study_setup(root, "Empty legacy study", 42L, adopt = TRUE)

  expect_true(dir.exists(file.path(root, "00_datasets")))
  expect_false(dir.exists(file.path(root, "datasets")))
})

test_that("study_setup refuses unsafe existing roots without writing", {
  root <- withr::local_tempdir()
  writeLines("existing", file.path(root, "work.R"))

  expect_error(study_setup(root, "Example", 42L), "adopt")
  expect_false(file.exists(file.path(root, "_study.yml")))
  expect_false(file.exists(file.path(root, ".Renviron")))
})

test_that("study_setup refuses a mixed layout without writing", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "datasets"))
  dir.create(file.path(root, "30_analyses"))

  expect_error(study_setup(root, "Example", 42L, adopt = TRUE), "mixed")
  expect_false(file.exists(file.path(root, "_study.yml")))
  expect_false(file.exists(file.path(root, ".Renviron")))
})

test_that("study_setup refuses to replace study identity", {
  root <- file.path(withr::local_tempdir(), "new-study")
  study_setup(root, "Example", 42L)
  before <- readLines(file.path(root, "_study.yml"))

  expect_error(
    study_setup(root, "Other", 43L, adopt = TRUE),
    "already exists"
  )
  expect_identical(readLines(file.path(root, "_study.yml")), before)
})

test_that("study_setup resumes matching adoption without replacing identity", {
  root <- file.path(withr::local_tempdir(), "new-study")
  study_setup(root, "Example", 42L)
  before <- readLines(file.path(root, "_study.yml"))
  file.remove(file.path(root, ".renvignore"))

  study_setup(root, "Example", 42L, adopt = TRUE)

  expect_identical(readLines(file.path(root, "_study.yml")), before)
  expect_true(file.exists(file.path(root, ".renvignore")))
})
