snap_root <- function(r = "4.5.3",
                      pkgs = c(boostmtree = "2.0.8",
                               ggBoostedTrees = "0.10.0")) {
  root <- withr::local_tempdir(.local_envir = parent.frame())
  lock <- list(R = list(Version = r),
               Packages = lapply(names(pkgs), function(p) {
                 list(Package = p, Version = pkgs[[p]])
               }))
  names(lock$Packages) <- names(pkgs)
  jsonlite::write_json(lock, file.path(root, "renv.lock"), auto_unbox = TRUE)
  root
}

test_that("a snapshot from another R major.minor is refused, naming both", {
  root <- snap_root("4.5.3")
  expect_error(guard_snapshot(root, session = numeric_version("4.6.1")),
               "4[.]5[.]3.*4[.]6[.]1")
  expect_error(guard_snapshot(root, session = numeric_version("4.6.1")),
               "/opt/R/4[.]5[.]3/bin/R")
})

test_that("r_upgrade = TRUE refuses while a locked package is missing", {
  root <- snap_root("4.5.3")
  lacks_boostmtree <- function(p) {
    if (p == "boostmtree") NA_character_ else "0.10.0"
  }
  expect_error(
    guard_snapshot(root, r_upgrade = TRUE, session = numeric_version("4.6.1"),
                   installed = lacks_boostmtree),
    "boostmtree.*renv::restore"
  )
})

test_that("r_upgrade = TRUE passes once every locked package is installed", {
  root <- snap_root("4.5.3")
  expect_silent(guard_snapshot(root, r_upgrade = TRUE,
                               session = numeric_version("4.6.1"),
                               installed = function(p) "1.0"))
})

test_that("a patch difference, or no lock, passes", {
  expect_silent(guard_snapshot(snap_root("4.5.1"),
                               session = numeric_version("4.5.3")))
  expect_silent(guard_snapshot(withr::local_tempdir(),
                               session = numeric_version("4.6.1")))
})

test_that(".need_snapshot() never calls renv::snapshot from a mismatched R", {
  root <- snap_root("4.5.3")
  called <- FALSE
  local_mocked_bindings(snapshot = function(...) called <<- TRUE,
                        .package = "renv")
  local_mocked_bindings(.session_r = function() numeric_version("4.6.1"))
  expect_error(.need_snapshot(root), "4[.]5[.]3")
  expect_false(called)
})

test_that(".need_snapshot() passes r_upgrade through to the guard", {
  root <- snap_root("4.5.3", pkgs = c(stats = "1.0"))
  called <- FALSE
  local_mocked_bindings(snapshot = function(...) called <<- TRUE,
                        .package = "renv")
  local_mocked_bindings(.session_r = function() numeric_version("4.6.1"),
                        .installed_version = function(p) "1.0")
  .need_snapshot(root, r_upgrade = TRUE)
  expect_true(called)
})

test_that(".study_init_renv() guards before the child snapshot starts", {
  root <- withr::local_tempdir()
  lock <- snap_root("4.5.3")
  local_mocked_bindings(.session_r = function() numeric_version("4.6.1"))
  local_mocked_bindings(study_declare = function(...) invisible(NULL))
  local_mocked_bindings(.study_rscript = function(expr, root, flags) {
    # The init step runs; the snapshot step must never be reached.
    if (!grepl("renv::init", expr, fixed = TRUE)) stop("child snapshot ran")
    file.copy(file.path(lock, "renv.lock"), file.path(root, "renv.lock"))
    list(status = 0L, output = "")
  })
  expect_error(.study_init_renv(root), "4[.]5[.]3.*4[.]6[.]1")
})

test_that("study_need() refuses a mismatched R before asking or installing", {
  root <- snap_root("4.5.3")
  study <- root
  installs <- 0L
  asks <- 0L
  local_mocked_bindings(
    .package_installed = function(pkg) FALSE,
    .need_root = function(root) study,
    .renv_active = function(root) TRUE,
    .study_interactive = function() TRUE,
    .need_ask = function(pkgs, caller) {
      asks <<- asks + 1L
      TRUE
    },
    .need_install = function(pkgs, root) installs <<- installs + 1L,
    .session_r = function() numeric_version("4.6.1")
  )
  expect_error(study_need("arrow"), "4[.]5[.]3.*4[.]6[.]1")
  expect_identical(installs, 0L)
  expect_identical(asks, 0L)
})

test_that("a malformed R version in the lock passes like a missing one", {
  for (bad in c("", "devel", "4")) {
    expect_silent(guard_snapshot(snap_root(bad),
                                 session = numeric_version("4.6.1")))
  }
})

test_that("the default lookup ignores a loaded package outside .libPaths()", {
  skip_on_cran()
  pkg <- "guardprobe"
  src <- file.path(withr::local_tempdir(), pkg)
  dir.create(src)
  writeLines(c(paste("Package:", pkg), "Version: 1.0.0", "Title: Probe",
               "Description: Probe.", "License: GPL-3", "Author: A B",
               "Maintainer: A B <a@example.com>"),
             file.path(src, "DESCRIPTION"))
  writeLines("", file.path(src, "NAMESPACE"))
  lib <- withr::local_tempdir()
  status <- system2(file.path(R.home("bin"), "R"),
                    c("CMD", "INSTALL", "--no-test-load", "-l", shQuote(lib),
                      shQuote(src)), stdout = FALSE, stderr = FALSE)
  skip_if(status != 0L, "could not install the probe package")
  loadNamespace(pkg, lib.loc = lib)
  withr::defer(unloadNamespace(pkg))
  expect_false(lib %in% normalizePath(.libPaths()))
  root <- snap_root("4.5.3", pkgs = c(guardprobe = "1.0.0"))
  expect_error(
    guard_snapshot(root, r_upgrade = TRUE, session = numeric_version("4.6.1")),
    "guardprobe.*renv::restore"
  )
})
