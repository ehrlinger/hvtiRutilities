declare_fixture <- function(env = parent.frame()) {
  root <- file.path(withr::local_tempdir(.local_envir = env), "study")
  suppressMessages(study_setup(root, "Declare fixture", 7L, renv = FALSE))
  saveRDS(data.frame(ccfid = 1:3), file.path(study_dir("datasets", root), "study_cohort.rds"))
  root
}

test_that("declare_data() writes the contract and registers nothing", {
  root <- declare_fixture()
  expect_true(declare_data(root, built = "study_cohort.rds", key = "ccfid"))
  yml <- yaml::read_yaml(file.path(root, "_study.yml"))
  expect_identical(yml$built, "study_cohort.rds")
  expect_identical(yml$key, "ccfid")
  expect_length(yaml::read_yaml(file.path(root, "manifest.yaml"))$datasets, 0L)
})

test_that("declaring the same file again is a no-op, and another file stops", {
  root <- declare_fixture()
  declare_data(root, built = "study_cohort.rds", key = "ccfid")
  expect_false(declare_data(root, built = "study_cohort.rds", key = "ccfid"))
  expect_error(declare_data(root, built = "other.rds"), "already declares study_cohort.rds")
})

test_that("a declared dataset registers its first version through update_manifest()", {
  root <- declare_fixture()
  declare_data(root, built = "study_cohort.rds", key = "ccfid")
  withr::local_dir(root)
  out <- update_manifest(dataset = "study")
  expect_identical(out$action[[1L]], "registered")
})

test_that("declare_data() checks its arguments", {
  root <- declare_fixture()
  expect_error(declare_data(root, built = "no_ext"), "one filename with its extension")
  expect_error(declare_data(root, built = "missing.rds"), "dataset is missing")
  expect_error(declare_data(root, built = "study_cohort.rds", key = NA_character_), "key")
})

test_that("a contract the next study_config() would reject is not written", {
  root <- declare_fixture()
  before <- readLines(file.path(root, "_study.yml"))
  expect_error(declare_data(root, built = "study_cohort.rds", key = c("ccfid", "ccfid")))
  expect_identical(readLines(file.path(root, "_study.yml")), before)
})

test_that("a fresh study gets an empty manifest that verify_manifest() accepts", {
  root <- declare_fixture()
  mpath <- file.path(root, "manifest.yaml")
  expect_false(file.exists(mpath))
  declare_data(root, built = "study_cohort.rds", key = "ccfid")
  expect_true(file.exists(mpath))
  expect_length(yaml::read_yaml(mpath)$datasets, 0L)
  out <- verify_manifest(mpath)
  expect_s3_class(out, "data.frame")
  expect_identical(nrow(out), 0L)
})

test_that("an existing manifest is left untouched", {
  root <- declare_fixture()
  mpath <- file.path(root, "manifest.yaml")
  writeLines(c("# kept", "datasets: {}"), mpath)
  before <- readBin(mpath, "raw", file.size(mpath))
  declare_data(root, built = "study_cohort.rds", key = "ccfid")
  expect_identical(readBin(mpath, "raw", file.size(mpath)), before)
})

test_that("a study declared before declare_data() wrote a manifest gets one on re-declaring", {
  root <- declare_fixture()
  declare_data(root, built = "study_cohort.rds", key = "ccfid")
  unlink(file.path(root, "manifest.yaml"))
  expect_false(declare_data(root, built = "study_cohort.rds"))
  expect_length(yaml::read_yaml(file.path(root, "manifest.yaml"))$datasets, 0L)
})

test_that("re-declaring with a different key stops rather than ignoring it", {
  root <- declare_fixture()
  declare_data(root, built = "study_cohort.rds", key = "ccfid")
  expect_error(declare_data(root, built = "study_cohort.rds", key = "mrn"), "with key ccfid")
  expect_identical(yaml::read_yaml(file.path(root, "_study.yml"))$key, "ccfid")
})

test_that("re-declaring with a key records it when none was declared", {
  root <- declare_fixture()
  declare_data(root, built = "study_cohort.rds")
  expect_true(declare_data(root, built = "study_cohort.rds", key = "ccfid"))
  expect_identical(yaml::read_yaml(file.path(root, "_study.yml"))$key, "ccfid")
})

test_that("a draft render of a declared, unregistered dataset caches nothing and leaves the manifest empty", {
  root <- declare_fixture()
  declare_data(root, built = "study_cohort.rds", key = "ccfid")
  job <- file.path(study_dir("analyses", root), "km", "km.qmd")
  local_mocked_bindings(.is_interactive = function() FALSE, .job_file = function() job,
                        .knitr_input = function() job)
  withr::local_envvar(HVTI_TEMPLATE_STRICT = NA)
  dd <- study_dir("datasets", root)
  before <- list.files(dd, recursive = TRUE)
  d <- suppressMessages(read_built(study_config(root)))
  expect_identical(nrow(d), 3L)
  expect_identical(list.files(dd, recursive = TRUE), before)
  expect_length(yaml::read_yaml(file.path(root, "manifest.yaml"))$datasets, 0L)
  saveRDS(data.frame(ccfid = 1:4), file.path(dd, "study_cohort.rds"))
  expect_identical(nrow(suppressMessages(read_built(study_config(root)))), 4L)
})
