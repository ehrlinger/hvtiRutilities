shape_study <- function(study_fields = list(), additional = NULL, env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  dir.create(file.path(root, "datasets"))
  raw <- c(list(study = "Shape", built = "built.csv"), study_fields)
  if (!is.null(additional)) raw$additional_datasets <- additional
  yaml::write_yaml(raw, file.path(root, "_study.yml"))
  root
}

test_that("kind, key and parents are returned with the dataset", {
  root <- shape_study(
    study_fields = list(key = "ccfid"),
    additional = list(
      echo = list(built = "echo.csv", kind = "ancillary", key = c("ccfid", "echo_date")),
      built_echo = list(built = "be.csv", kind = "combined", key = c("ccfid", "echo_date"),
                        parents = c("study", "echo"))
    )
  )
  cfg <- study_config(root)
  expect_identical(.study_dataset(cfg, "study")$kind, "built")
  expect_identical(.study_dataset(cfg, "study")$key, "ccfid")
  expect_identical(.study_dataset(cfg, "echo")$key, c("ccfid", "echo_date"))
  expect_identical(.study_dataset(cfg, "built_echo")$parents, c("study", "echo"))
})

test_that("an invalid kind, key or parents stops with the dataset named", {
  bad <- function(contract) {
    root <- shape_study(additional = list(echo = c(list(built = "echo.csv"), contract)))
    expect_error(study_config(root), "'echo'")
  }
  bad(list(kind = "lab"))
  bad(list(kind = "built"))
  bad(list(key = list()))
  bad(list(key = c("ccfid", "ccfid")))
  bad(list(kind = "combined"))
  bad(list(kind = "combined", parents = "nope"))
  bad(list(kind = "combined", parents = "echo"))
  bad(list(kind = "ancillary", parents = "study"))
  expect_error(study_config(shape_study(study_fields = list(kind = "subset"))), "'study'")
})

test_that("a contract without kind or key reads as before", {
  cfg <- study_config(shape_study(additional = list(extra = list(built = "x.csv"))))
  expect_null(.study_dataset(cfg, "extra")$kind)
  expect_null(.study_dataset(cfg, "extra")$key)
})

test_that("a cycle among parents stops with the datasets named", {
  combined <- function(parents) list(built = "x.csv", kind = "combined", parents = parents)
  two <- shape_study(additional = list(a = combined("b"), b = combined("a")))
  expect_error(study_config(two), "cycle.*a.*b")
  three <- shape_study(additional = list(a = combined("b"), b = combined("c"), c = combined("a")))
  expect_error(study_config(three), "cycle")
  fine <- shape_study(additional = list(a = combined("b"), b = combined("study"), c = combined(c("a", "b"))))
  expect_no_error(study_config(fine))
})

registered_shape_study <- function(env = parent.frame()) {
  testthat::skip_if_not_installed("arrow")
  root <- file.path(withr::local_tempdir(.local_envir = env), "study")
  suppressMessages(study_setup(root, "Shape registration", 42L))
  data_dir <- study_dir("datasets", root)
  utils::write.csv(data.frame(ccfid = 1:3, dead = c(1L, 0L, 0L)), file.path(data_dir, "built.csv"), row.names = FALSE)
  utils::write.csv(data.frame(ccfid = c(1L, 1L, 2L, 9L), echo_date = c(10, 20, 10, 10), ef = c(50, 55, 60, 40)),
                   file.path(data_dir, "echo.csv"), row.names = FALSE)
  suppressMessages(register_data(root, "built.csv", key = "ccfid"))
  suppressMessages(register_data(root, "echo.csv", dataset = "echo", role = "named",
                                 kind = "ancillary", key = c("ccfid", "echo_date")))
  root
}

test_that("registration records kind and key and checks the key", {
  root <- registered_shape_study()
  cfg <- study_config(root)
  expect_identical(cfg$key, "ccfid")
  expect_identical(cfg$additional_datasets$echo$kind, "ancillary")
  expect_identical(cfg$additional_datasets$echo$key, c("ccfid", "echo_date"))
})

test_that("a repeating or missing key stops before anything is written", {
  root <- registered_shape_study()
  data_dir <- study_dir("datasets", root)
  utils::write.csv(data.frame(ccfid = c(1L, 1L), lab = 1:2), file.path(data_dir, "labs.csv"), row.names = FALSE)
  before <- list.files(data_dir)

  expect_error(register_data(root, "labs.csv", dataset = "labs", role = "named", kind = "ancillary", key = "ccfid"),
               "1 row repeats")
  expect_error(register_data(root, "labs.csv", dataset = "labs", role = "named", kind = "ancillary", key = "lab_date"),
               "lab_date")
  expect_identical(list.files(data_dir), before)
})

test_that("a combined dataset records its parents' versions in the manifest", {
  root <- registered_shape_study()
  data_dir <- study_dir("datasets", root)
  utils::write.csv(data.frame(ccfid = c(1L, 1L, 2L), echo_date = c(10, 20, 10), dead = c(1L, 1L, 0L)),
                   file.path(data_dir, "be.csv"), row.names = FALSE)
  suppressMessages(register_data(root, "be.csv", dataset = "built_echo", role = "named", kind = "combined",
                                 key = c("ccfid", "echo_date"), parents = c("study", "echo")))

  expect_identical(study_config(root)$additional_datasets$built_echo$parents, c("study", "echo"))
  m <- yaml::read_yaml(file.path(root, "manifest.yaml"))
  e <- Filter(function(x) identical(x$file, "be.csv"), m$datasets)[[1L]]
  expect_match(e$parent_versions$study, "^built_[0-9]{8}[.]parquet$")
  expect_match(e$parent_versions$echo, "^echo_[0-9]{8}[.]parquet$")
})

test_that("register_data refuses parents without kind combined", {
  root <- registered_shape_study()
  utils::write.csv(data.frame(ccfid = 1:2), file.path(study_dir("datasets", root), "x.csv"), row.names = FALSE)
  expect_error(register_data(root, "x.csv", dataset = "x", role = "named", parents = "study"), "combined")
})

test_that("update_manifest re-checks the key on a rebuilt source", {
  root <- registered_shape_study()
  utils::write.csv(data.frame(ccfid = c(1L, 1L), echo_date = c(10, 10), ef = c(50, 55)),
                   file.path(study_dir("datasets", root), "echo.csv"), row.names = FALSE)
  withr::local_dir(root)
  expect_error(update_manifest(dataset = "echo"), "1 row repeats")
})
