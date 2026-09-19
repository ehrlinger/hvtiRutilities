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

test_that("the study layout map names exactly the taxonomy's folders", {
  # study_dir() resolves only the folders in its layout map, so a folder added
  # to hvti_taxonomy() and not to the map is one study_dir() and
  # hvtiRtemplates::add_job() refuse as unknown. Names only: the digits are
  # assigned, not derived from row order (estimates is 90 though it is fifth).
  expect_setequal(
    names(hvtiRutilities:::.study_folders()),
    unique(hvti_taxonomy()$folder)
  )
})
