test_that("HVTI_DATA accepts only 'working'", {
  withr::local_envvar(HVTI_DATA = NA)
  expect_false(.hvti_working_default())
  withr::local_envvar(HVTI_DATA = "")
  expect_false(.hvti_working_default())
  withr::local_envvar(HVTI_DATA = "working")
  expect_true(.hvti_working_default())
  withr::local_envvar(HVTI_DATA = "wroking")
  expect_error(.hvti_working_default(), "only accepted value is \"working\"")
})

stage_study <- function(env = parent.frame()) {
  root <- file.path(withr::local_tempdir(.local_envir = env), "study")
  suppressMessages(study_setup(root, "Stage fixture", 42L))
  study_config(root, require_data = FALSE)
}

test_that("the gate allows datasets and descriptive jobs and refuses the rest", {
  cfg <- stage_study()
  local_mocked_bindings(.is_interactive = function() FALSE)
  for (stage in c("datasets", "descriptive")) {
    job <- file.path(study_dir(stage, cfg$root), "job.qmd")
    local_mocked_bindings(.job_file = function() job)
    expect_true(.assert_working_stage(cfg, "built.csv"))
  }
  for (stage in c("distributions", "analyses", "graphs")) {
    job <- file.path(study_dir(stage, cfg$root), "fit", "fit.qmd")
    local_mocked_bindings(.job_file = function() job)
    expect_error(.assert_working_stage(cfg, "built.csv"),
                 paste0(basename(study_dir(stage, cfg$root)), " jobs read registered data only"))
  }
  local_mocked_bindings(.job_file = function() file.path(tempdir(), "elsewhere.qmd"))
  expect_error(.assert_working_stage(cfg, "built.csv"), "outside the study")
  local_mocked_bindings(.job_file = function() NULL)
  expect_error(.assert_working_stage(cfg, "built.csv"), "non-interactive session with no job file")
})

test_that("the interactive console is allowed", {
  cfg <- stage_study()
  local_mocked_bindings(.is_interactive = function() TRUE, .job_file = function() NULL)
  expect_true(.assert_working_stage(cfg, "built.csv"))
})

test_that("a legacy (bare-name) layout is gated by the same stages", {
  root <- file.path(withr::local_tempdir(), "study")
  dir.create(file.path(root, "descriptive"), recursive = TRUE)
  dir.create(file.path(root, "analyses"))
  cfg <- list(root = root)
  local_mocked_bindings(.is_interactive = function() FALSE,
                        .job_file = function() file.path(root, "descriptive", "dc.qmd"))
  expect_true(.assert_working_stage(cfg, "built.csv"))
  local_mocked_bindings(.job_file = function() file.path(root, "analyses", "km.qmd"))
  expect_error(.assert_working_stage(cfg, "built.csv"), "analyses jobs read registered data only")
})

test_that("Rscript's --file names the job", {
  local_mocked_bindings(.knitr_input = function() NULL,
                        .command_args = function() c("/usr/lib/R/bin/exec/R", "--file=30_analyses/fit.R"))
  expect_identical(basename(.job_file()), "fit.R")
})

test_that("Rscript's encoding of spaces in --file is decoded", {
  local_mocked_bindings(.knitr_input = function() NULL,
                        .command_args = function() c("R", "--file=/studies/a~+~b/10_descriptive/dc.R"))
  expect_identical(.job_file(), "/studies/a b/10_descriptive/dc.R")
})

test_that("paths resolve the same whether or not they exist", {
  root <- withr::local_tempdir()
  expect_identical(.real_path(file.path(root, "no", "such.qmd")),
                   file.path(normalizePath(root), "no", "such.qmd"))
})

test_that("the working-read condition carries its class", {
  cnd <- .working_read_condition("built.csv")
  expect_s3_class(cnd, "hvtiRutilities_working_read")
  expect_match(conditionMessage(cnd), "Results from it are a draft")
})
