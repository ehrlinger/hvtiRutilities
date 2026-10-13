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

test_that("a working read of a registered study reads the source and writes nothing", {
  local_working_signal()
  root <- versioned_study()
  cfg <- study_config(root)
  src <- built_path(cfg)
  utils::write.csv(data.frame(id = 1:4, DEAD = c(1L, 0L, 0L, 1L)), src, row.names = FALSE)
  before <- list(files = sort(list.files(dirname(src))),
                 manifest = digest::digest(file.path(root, "manifest.yaml"), algo = "sha256", file = TRUE))
  expect_message(d <- read_built(cfg, working = TRUE), class = "hvtiRutilities_working_read")
  expect_identical(nrow(d), 4L)
  expect_identical(names(d), c("id", "dead"))
  expect_identical(sort(list.files(dirname(src))), before$files)
  expect_identical(digest::digest(file.path(root, "manifest.yaml"), algo = "sha256", file = TRUE), before$manifest)
  expect_identical(nrow(suppressMessages(read_built(cfg))), 3L)
})

test_that("HVTI_DATA=working switches the default and refresh is refused", {
  local_working_signal()
  root <- versioned_study()
  cfg <- study_config(root)
  withr::local_envvar(HVTI_DATA = "working")
  expect_message(read_built(cfg), class = "hvtiRutilities_working_read")
  expect_error(read_built(cfg, refresh = TRUE), "nothing is cached")
  expect_no_message(read_built(cfg, working = FALSE), class = "hvtiRutilities_working_read")
})

test_that("an analysis job cannot read a study with no dated version, whatever HVTI_DATA says", {
  local_working_signal()
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Unregistered", 42L))
  utils::write.csv(data.frame(id = 1:3, DEAD = c(1L, 0L, 0L)),
                   file.path(study_dir("datasets", root), "built.csv"), row.names = FALSE)
  raw <- yaml::read_yaml(file.path(root, "_study.yml"))
  raw$built <- "built.csv"
  yaml::write_yaml(raw, file.path(root, "_study.yml"))
  cfg <- study_config(root)
  withr::local_envvar(HVTI_DATA = NA)
  local_mocked_bindings(.is_interactive = function() FALSE,
                        .job_file = function() file.path(study_dir("analyses", root), "km", "km.qmd"))
  expect_error(read_built(cfg), "jobs read registered data only")

  local_mocked_bindings(.job_file = function() file.path(study_dir("descriptive", root), "dc", "dc.qmd"))
  expect_message(read_built(cfg), class = "hvtiRutilities_working_read")
  # The cache wrote a role: source entry on that read; the dataset is still not registered.
  local_mocked_bindings(.job_file = function() file.path(study_dir("analyses", root), "km", "km.qmd"))
  expect_error(read_built(cfg), "jobs read registered data only")
})

test_that("a legacy role: source entry is gated until update_manifest() converts it", {
  root <- versioned_study()
  mp <- file.path(root, "manifest.yaml")
  m <- .read_manifest(mp)
  e <- m$datasets[[1]]
  m$datasets[[1]] <- list(file = e$file, extract_date = e$extract_date, n_rows = e$n_rows,
                          sha256 = e$source_sha256, role = "source", n_cols = e$n_cols)
  m$provenance <- NULL
  yaml::write_yaml(m, mp)
  local_mocked_bindings(.is_interactive = function() FALSE,
                        .job_file = function() file.path(study_dir("graphs", root), "g", "g.qmd"))
  expect_error(read_built(study_config(root)), "update_manifest")
})

test_that("a release-pinned dataset keeps reading ungated while the release path is deprecated", {
  local_working_signal()
  fx <- suppressMessages(suppressWarnings(make_release_aware_study(withr::local_tempdir())))
  local_mocked_bindings(.is_interactive = function() FALSE,
                        .job_file = function() file.path(study_dir("analyses", fx$root), "km", "km.qmd"))
  cfg <- suppressWarnings(study_config(fx$root), classes = "deprecatedWarning")
  expect_no_message(read_built(cfg), class = "hvtiRutilities_working_read")
})

test_that("provenance_data records the source for a working read", {
  root <- versioned_study()
  cfg <- study_config(root)
  expect_match(provenance_data(cfg = cfg)$path, "built_20260915[.]parquet$")
  expect_match(provenance_data(cfg = cfg, working = TRUE)$path, "built[.]csv$")
})

test_that("the real .signal_working_read() emits the classed message", {
  local_working_signal()
  expect_message(.signal_working_read("built.csv"), class = "hvtiRutilities_working_read")
})
