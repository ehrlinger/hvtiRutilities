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
  expect_null(cfg$citation)
  expect_match(
    paste(readLines(file.path(root, "_study.yml")), collapse = "\n"),
    "citation"
  )
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
  expect_true(".checkpoint/" %in% ignore)
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

test_that("the replaced study_init API is unavailable", {
  expect_error(
    getExportedValue("hvtiRutilities", "study_init"),
    "not an exported object"
  )
})

test_that("study_setup writes an R project named for the study directory", {
  root <- file.path(tempfile("rproj-"), "bio_example")
  on.exit(unlink(dirname(root), recursive = TRUE), add = TRUE)
  suppressMessages(
    study_setup(root, study = "Rproj test", study_tracker_id = 1L)
  )

  proj <- file.path(root, "bio_example.Rproj")
  expect_true(file.exists(proj))
  expect_identical(readLines(proj, n = 1L), "Version: 1.0")
})

test_that("study_setup leaves an existing R project alone", {
  root <- tempfile("rproj-existing-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  suppressMessages(
    study_setup(root, study = "Rproj adopt", study_tracker_id = 2L)
  )
  unlink(list.files(root, "[.]Rproj$", full.names = TRUE))
  writeLines(
    "Version: 1.0\n\nRestoreWorkspace: Yes",
    file.path(root, "mine.Rproj")
  )

  suppressMessages(
    study_setup(
      root, study = "Rproj adopt", study_tracker_id = 2L, adopt = TRUE
    )
  )

  expect_identical(list.files(root, "[.]Rproj$"), "mine.Rproj")
  expect_identical(
    readLines(file.path(root, "mine.Rproj"))[[3L]],
    "RestoreWorkspace: Yes"
  )
})

test_that("study_setup sees a hidden existing R project", {
  root <- tempfile("rproj-hidden-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  suppressMessages(
    study_setup(root, study = "Rproj adopt", study_tracker_id = 3L)
  )
  unlink(list.files(root, "[.]Rproj$", full.names = TRUE))
  writeLines(
    "Version: 1.0\n\nRestoreWorkspace: Yes",
    file.path(root, ".hidden.Rproj")
  )

  suppressMessages(
    study_setup(
      root, study = "Rproj adopt", study_tracker_id = 3L, adopt = TRUE
    )
  )

  expect_identical(
    list.files(root, "[.]Rproj$", all.files = TRUE),
    ".hidden.Rproj"
  )
})

test_that("study_setup records a Tracker identity as verified by default", {
  root <- file.path(withr::local_tempdir(), "new-study")

  study_setup(root, "Example study", 42L)

  cfg <- study_config(root, require_data = FALSE)
  expect_identical(cfg$identity_source, "tracker")
  expect_true(cfg$identity_verified)
})

test_that("study_setup records a manual identity as unverified", {
  root <- file.path(withr::local_tempdir(), "new-study")

  status <- study_setup(root, "Example study", 42L,
                        identity_source = "manual")

  cfg <- study_config(root, require_data = FALSE)
  expect_identical(cfg$identity_source, "manual")
  expect_false(cfg$identity_verified)
  row <- status$checks[status$checks$item == "_study.yml", ]
  expect_identical(row$status, "UNVERIFIED")
})

test_that("study_setup rejects an unknown identity source without writing", {
  root <- file.path(withr::local_tempdir(), "new-study")

  expect_error(
    study_setup(root, "Example study", 42L, identity_source = "typed"),
    "identity_source"
  )
  expect_false(dir.exists(root))
})

test_that("adoption keeps an existing identity and its source", {
  root <- file.path(withr::local_tempdir(), "new-study")
  study_setup(root, "Example study", 42L, identity_source = "manual")

  study_setup(root, "Example study", 42L, adopt = TRUE)

  cfg <- study_config(root, require_data = FALSE)
  expect_identical(cfg$identity_source, "manual")
  expect_false(cfg$identity_verified)
})

test_that("study_setup rejects an abbreviated identity source", {
  root <- file.path(withr::local_tempdir(), "new-study")

  expect_error(
    study_setup(root, "Example study", 42L, identity_source = "man"),
    "identity_source"
  )
  expect_false(dir.exists(root))
})

test_that("study_setup sets up the working directory when root is omitted", {
  root <- file.path(withr::local_tempdir(), "here-study")
  dir.create(root)
  withr::local_dir(root)

  suppressMessages(study_setup(study = "Here", study_tracker_id = 42L))

  expect_true(file.exists(file.path(root, "_study.yml")))
  expect_true(dir.exists(file.path(root, "00_datasets")))
})

test_that("an omitted root resolves to the enclosing study, not a nested one", {
  root <- file.path(withr::local_tempdir(), "outer")
  suppressMessages(study_setup(root, "Outer", 42L))
  withr::local_dir(file.path(root, "30_analyses"))
  local_mocked_bindings(.study_interactive = function() FALSE)

  expect_error(study_setup(study = "Outer", study_tracker_id = 42L), "adopt = TRUE")
  expect_false(file.exists(file.path(root, "30_analyses", "_study.yml")))

  suppressMessages(study_setup(study = "Outer", study_tracker_id = 42L, adopt = TRUE))
  expect_false(file.exists(file.path(root, "30_analyses", "_study.yml")))
})

test_that("an omitted root outside any study still refuses a folder with files", {
  root <- file.path(withr::local_tempdir(), "busy")
  dir.create(root)
  writeLines("x", file.path(root, "notes.txt"))
  withr::local_dir(root)

  expect_error(study_setup(study = "Busy", study_tracker_id = 42L), "adopt = TRUE")
  expect_false(file.exists(file.path(root, "_study.yml")))
})

test_that("a malformed _study.yml above the working directory is not taken as no study", {
  root <- file.path(withr::local_tempdir(), "broken")
  dir.create(file.path(root, "sub"), recursive = TRUE)
  writeLines("study: [unclosed", file.path(root, "_study.yml"))
  withr::local_dir(file.path(root, "sub"))

  expect_error(study_setup(study = "Broken", study_tracker_id = 42L), "Parser error")
  expect_false(file.exists(file.path(root, "sub", "_study.yml")))
})

test_that("study_setup asks before adopting an existing study when interactive", {
  root <- file.path(withr::local_tempdir(), "asked")
  suppressMessages(study_setup(root, "Asked", 42L))
  file.remove(file.path(root, ".renvignore"))
  before <- readLines(file.path(root, "_study.yml"))
  asked <- character(0)
  local_mocked_bindings(
    .study_interactive = function() TRUE,
    .study_ask_adopt = function(root) {
      asked <<- c(asked, root)
      TRUE
    }
  )

  suppressMessages(study_setup(root, "Asked", 42L))

  expect_length(asked, 1L)
  expect_true(file.exists(file.path(root, ".renvignore")))
  expect_identical(readLines(file.path(root, "_study.yml")), before)
})

test_that("declining the adopt prompt stops without writing", {
  root <- file.path(withr::local_tempdir(), "declined")
  suppressMessages(study_setup(root, "Declined", 42L))
  file.remove(file.path(root, ".renvignore"))
  local_mocked_bindings(
    .study_interactive = function() TRUE,
    .study_ask_adopt = function(root) FALSE
  )

  expect_error(study_setup(root, "Declined", 42L), "adopt = TRUE")
  expect_false(file.exists(file.path(root, ".renvignore")))
})

test_that("study_setup does not ask when the existing study has another Tracker ID", {
  root <- file.path(withr::local_tempdir(), "other-id")
  suppressMessages(study_setup(root, "Other", 42L))
  local_mocked_bindings(
    .study_interactive = function() TRUE,
    .study_ask_adopt = function(root) stop("should not ask")
  )

  expect_error(study_setup(root, "Other", 43L), "already exists for Study Tracker ID 42")
})

test_that("study_setup does not ask when not interactive", {
  root <- file.path(withr::local_tempdir(), "batch")
  suppressMessages(study_setup(root, "Batch", 42L))
  local_mocked_bindings(
    .study_interactive = function() FALSE,
    .study_ask_adopt = function(root) stop("should not ask")
  )

  expect_error(study_setup(root, "Batch", 42L), "adopt = TRUE")
})
