test_that("study_dir resolves numbered study directories", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "00_datasets"))

  expect_identical(
    study_dir("datasets", root),
    file.path(root, "00_datasets")
  )
})

test_that("study_dir preserves legacy study directories", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "datasets"))

  expect_identical(
    study_dir("datasets", root),
    file.path(root, "datasets")
  )
})

test_that("study_dir refuses mixed directory layouts", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "datasets"))
  dir.create(file.path(root, "30_analyses"))

  expect_error(study_dir("datasets", root), "mixed")
})
