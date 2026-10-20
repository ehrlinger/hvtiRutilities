test_that("an unchanged source is reviewed without a comparison", {
  root <- versioned_study()
  r <- review_built(study_config(root))
  expect_s3_class(r, "built_review")
  expect_false(r$changed)
  expect_null(r$comparison)
  expect_identical(r$registered$parquet, "built_20260915.parquet")
  expect_output(print(r), "unchanged since 2026-09-15")
})

test_that("a rebuilt source is compared with the registered version", {
  root <- versioned_study()
  cfg <- study_config(root)
  utils::write.csv(data.frame(id = 1:4, DEAD = c(1L, 0L, 0L, 1L), AGE = 60:63), built_path(cfg), row.names = FALSE)
  r <- review_built(cfg)
  expect_true(r$changed)
  expect_identical(r$working$n_rows, 4L)
  expect_identical(r$comparison$rows_old, 3L)
  expect_identical(r$comparison$rows_new, 4L)
  expect_identical(r$comparison$cols_added, "age")
  expect_output(print(r), "update_manifest")
})

test_that("a missing source stops rather than reading as unchanged", {
  root <- versioned_study()
  cfg <- study_config(root)
  unlink(built_path(cfg))
  expect_error(review_built(cfg), "is not on disk")
})

test_that("a dataset with no dated version stops", {
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Nothing registered", 42L, renv = FALSE))
  raw <- yaml::read_yaml(file.path(root, "_study.yml"))
  raw$built <- "built.csv"
  yaml::write_yaml(raw, file.path(root, "_study.yml"))
  utils::write.csv(data.frame(id = 1:3), file.path(study_dir("datasets", root), "built.csv"), row.names = FALSE)
  expect_error(review_built(study_config(root)), "nothing is registered to compare against")
})

test_that("a source rewritten while it is being reviewed stops the review", {
  root <- versioned_study()
  cfg <- study_config(root)
  src <- built_path(cfg)
  real <- read_clinical_data
  local_mocked_bindings(read_clinical_data = function(...) {
    out <- real(...)
    utils::write.csv(data.frame(id = 1:5, DEAD = 0L), src, row.names = FALSE)
    out
  })
  expect_error(review_built(cfg), "changed while it was being reviewed")
})
