test_that("identity state classifies the four valid shapes", {
  provisional <- list(derived_from = 7L, provisional_id = "x7-3f9a2c1b")
  promoted <- list(derived_from = 7L, study_tracker_id = 9L)
  expect_identical(.study_identity_state(list(study_tracker_id = 7L)),
                   "registered")
  expect_identical(.study_identity_state(provisional), "provisional")
  expect_identical(.study_identity_state(promoted), "promoted")
  expect_identical(.study_identity_state(list(study = "S")), "legacy")
})

test_that("identity state is NA for a mix of the two shapes", {
  na <- NA_character_
  expect_identical(.study_identity_state(list(provisional_id = "x7-a")), na)
  expect_identical(.study_identity_state(list(derived_from = 7L)), na)
  all_three <- list(derived_from = 7L, provisional_id = "x7-a",
                    study_tracker_id = 9L)
  expect_identical(.study_identity_state(all_three), na)
  bad_parent <- list(derived_from = "seven", provisional_id = "x7-a")
  expect_identical(.study_identity_state(bad_parent), na)
  bad_id <- list(derived_from = 7L, provisional_id = 5L)
  expect_identical(.study_identity_state(bad_id), na)
})

test_that("a provisional id is x, the parent and 8 workspace characters", {
  expect_identical(
    .study_provisional_id(1234L, "3f9a2c1b-7d4e-4a10-9b2f-0c8e5d6a7b31"),
    "x1234-3f9a2c1b"
  )
})

test_that(".study_check_id accepts one positive integer only", {
  expect_identical(.study_check_id(42L, "derived_from", "f"), 42L)
  expect_identical(.study_check_id(42, "derived_from", "f"), 42L)
  for (bad in list(0L, -1L, 4.2, c(1L, 2L), NA_integer_)) {
    expect_error(.study_check_id(bad, "derived_from", "f"),
                 "f\\(\\): derived_from must be one positive integer")
  }
})

test_that(".study_check_id accepts a canonical integer string", {
  expect_identical(.study_check_id("42", "study_tracker_id", "f"), 42L)
  for (bad in list("042", "4.2", "0", "x", c("1", "2"))) {
    expect_error(.study_check_id(bad, "study_tracker_id", "f"),
                 "f\\(\\): study_tracker_id must be one positive integer")
  }
})

test_that("study_config refuses a mixed identity and names the fields", {
  root <- withr::local_tempdir()
  yaml::write_yaml(list(study = "S", derived_from = 7L,
                        provisional_id = "x7-3f9a2c1b", study_tracker_id = 9L),
                   file.path(root, "_study.yml"))
  expect_error(study_config(root, require_data = FALSE),
               "study_tracker_id, derived_from, provisional_id")
})

test_that("study_config accepts provisional, promoted and legacy files", {
  for (cfg in list(
    list(study = "S", derived_from = 7L, provisional_id = "x7-3f9a2c1b"),
    list(study = "S", derived_from = 7L, study_tracker_id = 9L),
    list(study = "S")
  )) {
    root <- withr::local_tempdir()
    yaml::write_yaml(cfg, file.path(root, "_study.yml"))
    expect_no_error(study_config(root, require_data = FALSE))
  }
})
