built_name_study <- function(env = parent.frame()) {
  testthat::skip_if_not_installed("arrow")  # registration converts to parquet once design 2 has landed
  root <- file.path(withr::local_tempdir(.local_envir = env), "study")
  suppressMessages(study_setup(root, "Built name", 42L))
  data_dir <- study_dir("datasets", root)
  utils::write.csv(data.frame(id = 1:3, dead = c(1L, 0L, 0L)), file.path(data_dir, "built.csv"), row.names = FALSE)
  suppressMessages(register_data(root, "built.csv"))
  root
}

test_that("\"built\" and \"study\" name the same dataset", {
  root <- built_name_study()
  cfg <- study_config(root)
  expect_identical(built_path(cfg, "built"), built_path(cfg, "study"))
  expect_identical(read_built(cfg, dataset = "built"), read_built(cfg, dataset = "study"))
  expect_identical(.study_dataset(cfg, "built")$dataset, "study")
})

test_that("provenance records the canonical name", {
  root <- built_name_study()
  expect_identical(provenance_data("built", cfg = study_config(root))$dataset, "study")
})

test_that("the default dataset may be registered under either name", {
  skip_if_not_installed("arrow")
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Register as built", 42L))
  utils::write.csv(data.frame(id = 1:2), file.path(study_dir("datasets", root), "b.csv"), row.names = FALSE)
  suppressMessages(register_data(root, "b.csv", dataset = "built"))
  expect_identical(study_config(root)$built, "b.csv")
})

test_that("a named dataset may not be called built", {
  root <- built_name_study()
  utils::write.csv(data.frame(id = 1:2), file.path(study_dir("datasets", root), "x.csv"), row.names = FALSE)
  expect_error(register_data(root, "x.csv", dataset = "built", role = "named"), "reserved")
})

test_that("an existing additional dataset named built stops with the way to rename it", {
  root <- built_name_study()
  y <- yaml::read_yaml(file.path(root, "_study.yml"))
  y$additional_datasets <- list(built = list(built = "x.csv"))
  yaml::write_yaml(y, file.path(root, "_study.yml"))
  expect_error(study_config(root), "Rename it under additional_datasets: and in manifest.yaml", fixed = TRUE)
})

test_that("an unknown dataset's message names both spellings", {
  root <- built_name_study()
  expect_error(built_path(study_config(root), "nope"), "study (or built)", fixed = TRUE)
})
