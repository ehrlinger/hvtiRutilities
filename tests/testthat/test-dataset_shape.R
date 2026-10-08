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
