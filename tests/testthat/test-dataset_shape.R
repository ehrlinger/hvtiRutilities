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

# Checksums of the files a failed registration must not touch.
file_snapshot <- function(root) {
  files <- file.path(root, c("_study.yml", "manifest.yaml"))
  unname(tools::md5sum(files))
}

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
  before_files <- file_snapshot(root)

  expect_error(register_data(root, "labs.csv", dataset = "labs", role = "named", kind = "ancillary", key = "ccfid"),
               "1 row repeats")
  expect_error(register_data(root, "labs.csv", dataset = "labs", role = "named", kind = "ancillary", key = "lab_date"),
               "lab_date")
  expect_identical(list.files(data_dir), before)
  expect_identical(file_snapshot(root), before_files)
})

test_that("a registration that fails after the conversion leaves the study untouched", {
  root <- registered_shape_study()
  data_dir <- study_dir("datasets", root)
  utils::write.csv(data.frame(ccfid = 1:2, lab = 3:4), file.path(data_dir, "labs.csv"), row.names = FALSE)
  before_listing <- list.files(data_dir, recursive = TRUE)
  before_files <- file_snapshot(root)

  expect_error(register_data(root, "labs.csv", dataset = "labs", role = "named", kind = "combined",
                             key = "ccfid", parents = "nope"), "nope")
  expect_error(register_data(root, "labs.csv", dataset = "labs", role = "named", kind = "built", key = "ccfid"))

  expect_identical(list.files(data_dir, recursive = TRUE), before_listing)
  expect_identical(file_snapshot(root), before_files)
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

combined_study <- function(env = parent.frame()) {
  root <- registered_shape_study(env)
  data_dir <- study_dir("datasets", root)
  utils::write.csv(data.frame(ccfid = c(1L, 1L, 2L), echo_date = c(10, 20, 10), dead = c(1L, 1L, 0L)),
                   file.path(data_dir, "be.csv"), row.names = FALSE)
  suppressMessages(register_data(root, "be.csv", dataset = "built_echo", role = "named", kind = "combined",
                                 key = c("ccfid", "echo_date"), parents = c("study", "echo")))
  root
}

rebuild <- function(root, file, data, when = "2026-10-08 12:00:00") {
  path <- file.path(study_dir("datasets", root), file)
  utils::write.csv(data, path, row.names = FALSE)
  Sys.setFileTime(path, as.POSIXct(when, tz = "UTC"))
}

test_that("a combined dataset reads current until a parent is updated", {
  root <- combined_study()
  cfg <- study_config(root)
  expect_no_message(read_built(cfg, dataset = "built_echo"))

  rebuild(root, "built.csv", data.frame(ccfid = 1:4, dead = c(1L, 0L, 0L, 1L)))
  withr::with_dir(root, suppressMessages(update_manifest(dataset = "study")))

  msg <- expect_message(d <- read_built(study_config(root), dataset = "built_echo"),
                        class = "hvtiRutilities_parent_changed")
  expect_s3_class(msg, "hvtiRutilities_out_of_date")
  expect_match(conditionMessage(msg), "hvtiRutilities::update_manifest().\n", fixed = TRUE)
  expect_identical(nrow(d), 3L)
})

test_that("the parent-changed message names the parent versions and the update commands", {
  cond <- .parent_changed_condition(
    list(dataset = "built_echo", built = "be.csv"),
    data.frame(parent = "study", recorded = "built_20260915.parquet", current = "built_20261008.parquet")
  )
  expect_s3_class(cond, "hvtiRutilities_out_of_date")
  msg <- conditionMessage(cond)
  expect_match(msg, "built_20260915.parquet", fixed = TRUE)
  expect_match(msg, "built_20261008.parquet", fixed = TRUE)
  expect_match(msg, "update_manifest()", fixed = TRUE)
})

test_that("a parent recorded without a version is out of date, never current", {
  root <- combined_study()
  cfg <- study_config(root)
  manifest <- yaml::read_yaml(file.path(root, "manifest.yaml"))
  i <- which(vapply(manifest$datasets, function(e) identical(e$file, "be.csv"), logical(1)))
  manifest$datasets[[i]]$parent_versions$echo <- NA_character_

  stale <- .stale_parents(cfg, "built_echo", manifest$datasets[[i]], manifest)
  expect_identical(stale$parent, "echo")
  expect_identical(stale$recorded, "unrecorded")

  # also after a round trip through manifest.yaml
  path <- withr::local_tempfile(fileext = ".yaml")
  yaml::write_yaml(manifest, path)
  again <- yaml::read_yaml(path)
  expect_identical(.stale_parents(cfg, "built_echo", again$datasets[[i]], again)$parent, "echo")

  # a parent with no manifest entry now is not current either
  both_na <- manifest
  both_na$datasets[[i]]$parent_versions$echo <- NA_character_
  both_na$datasets <- Filter(function(e) !identical(e$file, "echo.csv"), both_na$datasets)
  j <- which(vapply(both_na$datasets, function(e) identical(e$file, "be.csv"), logical(1)))
  expect_identical(.stale_parents(cfg, "built_echo", both_na$datasets[[j]], both_na)$parent, "echo")
})

test_that("update_manifest() updates parents first and reports a combined dataset left behind", {
  root <- combined_study()
  rebuild(root, "built.csv", data.frame(ccfid = 1:4, dead = c(1L, 0L, 0L, 1L)))
  withr::local_dir(root)

  msgs <- character()
  withCallingHandlers(update_manifest(), message = function(m) {
    msgs <<- c(msgs, conditionMessage(m))
    invokeRestart("muffleMessage")
  })
  expect_true(any(grepl("built_echo is out of date", msgs, fixed = TRUE)))
  expect_true(any(grepl("registered built_", msgs, fixed = TRUE)))
})

test_that("re-registering a combined dataset records its parents' new versions", {
  root <- combined_study()
  rebuild(root, "built.csv", data.frame(ccfid = 1:4, dead = c(1L, 0L, 0L, 1L)))
  rebuild(root, "be.csv", data.frame(ccfid = c(1L, 2L), echo_date = c(10, 10), dead = c(1L, 0L)))
  withr::local_dir(root)
  suppressMessages(update_manifest())

  expect_no_message(read_built(study_config(root), dataset = "built_echo"))
})

test_that("study_status lists an out-of-date combined dataset", {
  root <- combined_study()
  rebuild(root, "built.csv", data.frame(ccfid = 1:4, dead = c(1L, 0L, 0L, 1L)))
  withr::with_dir(root, suppressMessages(update_manifest(dataset = "study")))

  checks <- study_status(root)$checks
  row <- checks[checks$item == "out_of_date:built_echo", ]
  expect_identical(row$status, "OUT OF DATE")
  expect_match(row$detail, "update_manifest()", fixed = TRUE)
  expect_output(print(study_status(root)), "out_of_date:built_echo")
})

drop_parent_versions <- function(root) {
  path <- file.path(root, "manifest.yaml")
  manifest <- yaml::read_yaml(path)
  i <- which(vapply(manifest$datasets, function(e) identical(e$file, "be.csv"), logical(1)))
  manifest$datasets[[i]]$parent_versions <- NULL
  yaml::write_yaml(manifest, path)
}

test_that("a combined dataset with no recorded parent versions stays out of date until it is rebuilt", {
  root <- combined_study()
  drop_parent_versions(root)
  manifest_file <- file.path(root, "manifest.yaml")

  cond <- NULL
  withCallingHandlers(
    read_built(study_config(root), dataset = "built_echo"),
    hvtiRutilities_parent_changed = function(m) {
      cond <<- m
      invokeRestart("muffleMessage")
    }
  )
  expect_s3_class(cond, "hvtiRutilities_parent_changed")
  expect_identical(lengths(regmatches(conditionMessage(cond), gregexpr("was unrecorded", conditionMessage(cond)))), 2L)
  expect_match(conditionMessage(cond), "rebuild be.csv.*then run hvtiRutilities::update_manifest()")

  # source unchanged: update_manifest() must not bless it
  before <- unname(tools::md5sum(manifest_file))
  withr::with_dir(root, suppressMessages(update_manifest()))
  expect_identical(unname(tools::md5sum(manifest_file)), before)
  expect_message(read_built(study_config(root), dataset = "built_echo"), class = "hvtiRutilities_parent_changed")

  # source rebuilt: the new version is registered with the parents recorded
  rebuild(root, "be.csv", data.frame(ccfid = c(1L, 2L), echo_date = c(10, 10), dead = c(1L, 0L)))
  withr::with_dir(root, suppressMessages(update_manifest()))
  expect_no_message(read_built(study_config(root), dataset = "built_echo"))
  m <- yaml::read_yaml(manifest_file)
  e <- Filter(function(x) identical(x$file, "be.csv"), m$datasets)[[1L]]
  expect_named(e$parent_versions, c("study", "echo"))
})

test_that("a combined dataset with no manifest.yaml reads without a yaml error", {
  root <- combined_study()
  cfg <- study_config(root)
  file.remove(file.path(root, "manifest.yaml"))
  err <- tryCatch(suppressMessages(read_built(cfg, dataset = "built_echo")), error = function(e) conditionMessage(e))
  expect_false(is.character(err) && grepl("cannot open|No such file", err))
})

test_that("each context words the out-of-date message for itself and ends with the fix", {
  contract <- list(dataset = "built_echo", built = "be.csv")
  stale <- data.frame(parent = "study", recorded = "a.parquet", current = "b.parquet")
  for (context in c("read", "status", "update")) {
    txt <- .parent_changed_text(contract, stale, context)
    expect_match(txt, "hvtiRutilities::update_manifest().", fixed = TRUE)
    expect_match(txt, "a.parquet", fixed = TRUE)
  }
  expect_match(.parent_changed_text(contract, stale, "read"), "This job used the older combined data", fixed = TRUE)
  expect_no_match(.parent_changed_text(contract, stale, "status"), "This job", fixed = TRUE)
  expect_match(.parent_changed_text(contract, stale, "update"), "^built_echo is out of date")
})

test_that("a status audit does not throw when the manifest cannot be read, and reports the failure", {
  root <- combined_study()
  cfg <- study_config(root)
  writeLines("datasets: [unclosed", file.path(root, "manifest.yaml"))
  row <- .status_out_of_date(cfg, "built_echo")
  expect_identical(row$item, "out_of_date:built_echo")
  expect_identical(row$status, "FAIL")
  expect_true(nzchar(row$detail))
  expect_no_error(study_status(root))
})

test_that("adopting a release for a combined dataset records its parents' versions", {
  fx <- make_release_aware_study(withr::local_tempdir(), pinned_sequence = 1L, named = TRUE)
  raw <- yaml::read_yaml(file.path(fx$root, "_study.yml"))
  raw$additional_datasets$named_data$kind <- "combined"
  raw$additional_datasets$named_data$parents <- "study"
  yaml::write_yaml(raw, file.path(fx$root, "_study.yml"))

  suppressMessages(adopt_data_update(study_config(fx$root), dataset = "named_data",
                                     release_id = "surgery_cohort-20260921-r1"))
  m <- yaml::read_yaml(file.path(fx$root, "manifest.yaml"))
  e <- Filter(function(x) identical(x$file, "cohort_20260921.csv"), m$datasets)[[1L]]
  expect_match(e$parent_versions$study, "^default_[0-9]{8}[.]parquet$")
})
