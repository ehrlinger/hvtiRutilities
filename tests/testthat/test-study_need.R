local_need <- function(installed = character(0), renv_root = NULL, interactive = FALSE,
                       answer = TRUE, env = parent.frame()) {
  state <- new.env()
  state$installed <- installed
  state$asked <- 0L
  state$snapshots <- 0L
  local_mocked_bindings(
    .package_installed = function(pkg) pkg %in% state$installed,
    .need_root = function(root) renv_root,
    .renv_active = function(root) !is.null(renv_root),
    .study_interactive = function() interactive,
    .need_ask = function(pkgs, caller) { state$asked <- state$asked + 1L; answer },
    .need_install = function(pkgs, root) state$installed <- c(state$installed, pkgs),
    .need_snapshot = function(root) state$snapshots <- state$snapshots + 1L,
    .env = env
  )
  state
}

test_that("an installed package needs nothing", {
  state <- local_need(installed = "arrow")
  expect_identical(study_need("arrow"), character(0))
  expect_identical(state$asked, 0L)
})

test_that("in a renv study, interactively, a missing package is installed and locked", {
  root <- withr::local_tempdir()
  state <- local_need(renv_root = root, interactive = TRUE)
  expect_identical(study_need("arrow", caller = "register_data"), "arrow")
  expect_identical(state$snapshots, 1L)
  expect_match(readLines(file.path(root, "DESCRIPTION")), "arrow", all = FALSE)
})

test_that("declining the install stops and names setup()", {
  root <- withr::local_tempdir()
  local_need(renv_root = root, interactive = TRUE, answer = FALSE)
  expect_error(study_need("arrow", caller = "register_data"), "register_data\\(\\).*hvtiR::setup\\(\\)")
})

test_that("outside renv a missing package stops and names setup(), with the note", {
  local_need()
  expect_error(study_need("arrow", caller = "register_data", note = "Nothing was written."),
               "hvtiR::setup\\(\\).*Nothing was written")
})

test_that("only_in_renv does nothing outside a renv study", {
  state <- local_need()
  expect_identical(study_need("randomForestSRC", only_in_renv = TRUE), character(0))
  expect_identical(state$asked, 0L)
})

test_that("an install that leaves the package missing stops", {
  root <- withr::local_tempdir()
  state <- local_need(renv_root = root, interactive = TRUE)
  local_mocked_bindings(.need_install = function(pkgs, root) invisible(NULL))
  expect_error(study_need("arrow"), "did not install")
})
