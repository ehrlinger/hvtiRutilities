lock_with <- function(root, pkgs = character(0), r = as.character(getRversion())) {
  packages <- stats::setNames(lapply(pkgs, function(p) list(Package = p)), pkgs)
  jsonlite::write_json(list(R = list(Version = r), Packages = packages), file.path(root, "renv.lock"),
                       auto_unbox = TRUE)
}

local_need <- function(installed = character(0), renv_root = NULL, interactive = FALSE,
                       answer = TRUE, env = parent.frame()) {
  state <- new.env()
  state$installed <- installed
  state$asked <- 0L
  state$snapshots <- 0L
  testthat::local_mocked_bindings(
    .package_installed = function(pkg) pkg %in% state$installed,
    .need_root = function(root) renv_root,
    .renv_active = function(root) !is.null(renv_root),
    .study_interactive = function() interactive,
    .need_ask = function(pkgs, caller) {
      state$asked <- state$asked + 1L
      answer
    },
    .need_ask_record = function(pkgs, caller) {
      state$asked <- state$asked + 1L
      answer
    },
    .need_install = function(pkgs, root) state$installed <- c(state$installed, pkgs),
    .need_snapshot = function(root, r_upgrade = FALSE) {
      state$snapshots <- state$snapshots + 1L
      lock_with(root, state$installed)
    },
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

test_that("an installed package the lock lacks is recorded, after one question", {
  root <- withr::local_tempdir()
  lock_with(root)
  state <- local_need(installed = "cmprsk", renv_root = root, interactive = TRUE)
  expect_identical(study_need("cmprsk"), character(0))
  expect_identical(state$asked, 1L)
  expect_identical(state$snapshots, 1L)
  expect_match(readLines(file.path(root, "DESCRIPTION")), "cmprsk", all = FALSE)
})

test_that("a study with no lock yet has nothing recorded, so it records", {
  root <- withr::local_tempdir()
  state <- local_need(installed = "cmprsk", renv_root = root, interactive = TRUE)
  study_need("cmprsk")
  expect_identical(state$snapshots, 1L)
})

test_that("a package the lock already holds neither asks nor snapshots", {
  root <- withr::local_tempdir()
  lock_with(root, "cmprsk")
  state <- local_need(installed = "cmprsk", renv_root = root, interactive = TRUE)
  expect_no_warning(study_need("cmprsk"))
  expect_identical(state$asked, 0L)
  expect_identical(state$snapshots, 0L)
})

test_that("a base package, which renv never locks, neither asks nor snapshots", {
  root <- withr::local_tempdir()
  lock_with(root)
  state <- local_need(installed = "stats", renv_root = root, interactive = TRUE)
  expect_no_warning(study_need("stats"))
  expect_identical(state$asked, 0L)
  expect_identical(state$snapshots, 0L)
})

test_that("a batch session writes no lock and warns that a restore will miss the package", {
  root <- withr::local_tempdir()
  lock_with(root)
  state <- local_need(installed = "cmprsk", renv_root = root)
  expect_warning(study_need("cmprsk", caller = "add_job"), "add_job\\(\\): .*cmprsk.*renv::restore\\(\\).*not interactive")
  expect_identical(state$asked, 0L)
  expect_identical(state$snapshots, 0L)
})

test_that("declining to record warns and does not stop the caller", {
  root <- withr::local_tempdir()
  lock_with(root)
  state <- local_need(installed = "cmprsk", renv_root = root, interactive = TRUE, answer = FALSE)
  expect_warning(result <- study_need("cmprsk"), "renv::restore\\(\\).*declined")
  expect_identical(result, character(0))
  expect_identical(state$snapshots, 0L)
})

test_that("a lock from another R warns with the guard's reason, asks nothing and does not stop", {
  root <- withr::local_tempdir()
  lock_with(root, r = "3.6.3")
  state <- local_need(installed = "cmprsk", renv_root = root, interactive = TRUE)
  expect_warning(result <- study_need("cmprsk"), "renv::restore\\(\\).*records R 3[.]6[.]3")
  expect_identical(result, character(0))
  expect_identical(state$asked, 0L)
  expect_identical(state$snapshots, 0L)
})

test_that("r_upgrade reaches the guard on the record path", {
  root <- withr::local_tempdir()
  lock_with(root, r = "3.6.3")
  state <- local_need(installed = "cmprsk", renv_root = root, interactive = TRUE)
  expect_no_warning(study_need("cmprsk", r_upgrade = TRUE))
  expect_identical(state$snapshots, 1L)
})

test_that("a snapshot that fails warns with its reason and does not stop the caller", {
  root <- withr::local_tempdir()
  lock_with(root)
  local_need(installed = "cmprsk", renv_root = root, interactive = TRUE)
  local_mocked_bindings(.need_snapshot = function(root, r_upgrade = FALSE) stop("validation aborted"))
  expect_warning(result <- study_need("cmprsk"), "validation aborted")
  expect_identical(result, character(0))
})

test_that("a snapshot that leaves the package out says so", {
  root <- withr::local_tempdir()
  lock_with(root)
  local_need(installed = "cmprsk", renv_root = root, interactive = TRUE)
  local_mocked_bindings(.need_snapshot = function(root, r_upgrade = FALSE) invisible(NULL))
  expect_warning(study_need("cmprsk"), "did not record")
})

test_that("an unreadable lock warns and does not stop the caller, batch or interactive", {
  root <- withr::local_tempdir()
  writeLines("<<<<<<< HEAD", file.path(root, "renv.lock"))
  state <- local_need(installed = "cmprsk", renv_root = root)
  expect_warning(result <- study_need("cmprsk"), "not in renv.lock")
  expect_identical(result, character(0))
  state <- local_need(installed = "cmprsk", renv_root = root, interactive = TRUE)
  expect_warning(study_need("cmprsk"), "not in renv.lock")
  expect_identical(state$snapshots, 0L)
})

test_that("only the packages the lock lacks are named", {
  root <- withr::local_tempdir()
  lock_with(root, "held")
  local_need(installed = c("held", "absent1", "absent2"), renv_root = root)
  w <- tryCatch(study_need(c("held", "absent1", "absent2")), warning = conditionMessage)
  expect_match(w, "absent1, absent2", fixed = TRUE)
  expect_no_match(w, "held")
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

test_that("a declined install declares nothing, installed packages included", {
  root <- withr::local_tempdir()
  state <- local_need(installed = "stats", renv_root = root, interactive = TRUE, answer = FALSE)
  expect_error(study_need(c("stats", "arrow"), caller = "register_data"), "not installed")
  expect_identical(state$snapshots, 0L)
  expect_false(file.exists(file.path(root, "DESCRIPTION")))
})

test_that("a failed install declares nothing, installed packages included", {
  root <- withr::local_tempdir()
  local_need(installed = "stats", renv_root = root, interactive = TRUE)
  local_mocked_bindings(.need_install = function(pkgs, root) invisible(NULL))
  expect_error(study_need(c("stats", "arrow")), "did not install")
  expect_false(file.exists(file.path(root, "DESCRIPTION")))
})

test_that("a successful install declares installed and newly installed packages", {
  root <- withr::local_tempdir()
  state <- local_need(installed = "stats", renv_root = root, interactive = TRUE)
  study_need(c("stats", "arrow"))
  expect_identical(state$snapshots, 1L)
  depends <- unname(read.dcf(file.path(root, "DESCRIPTION"))[1L, "Depends"])
  expect_setequal(trimws(strsplit(depends, ",", fixed = TRUE)[[1L]]), c("arrow", "stats"))
})

test_that("a failed install does not declare the missing package", {
  root <- withr::local_tempdir()
  local_need(renv_root = root, interactive = TRUE)
  local_mocked_bindings(.need_install = function(pkgs, root) invisible(NULL))
  expect_error(study_need("arrow"), "did not install")
  expect_false(file.exists(file.path(root, "DESCRIPTION")))
})

test_that("the declined error names setup() and appends the note, without suggesting a retry", {
  root <- withr::local_tempdir()
  local_need(renv_root = root, interactive = TRUE, answer = FALSE)
  err <- tryCatch(study_need("arrow", note = "Nothing was written."), error = conditionMessage)
  expect_match(err, "was not installed")
  expect_match(err, "hvtiR::setup()", fixed = TRUE)
  expect_match(err, "Nothing was written.", fixed = TRUE)
  expect_no_match(err, "interactively")
})

test_that("the did-not-install error appends the note", {
  root <- withr::local_tempdir()
  local_need(renv_root = root, interactive = TRUE)
  local_mocked_bindings(.need_install = function(pkgs, root) invisible(NULL))
  expect_error(study_need("arrow", note = "Nothing was written."), "Nothing was written")
})

test_that("only a no-study error means not in a study", {
  local_mocked_bindings(study_root = function(...) stop("no _study.yml found above here"))
  expect_null(.need_root(NULL))
  local_mocked_bindings(study_root = function(...) stop("Parser error: broken"))
  expect_error(.need_root(NULL), "Parser error")
})

test_that("the real installer runs with pak off", {
  seen <- NULL
  fake_install <- function(...) {
    seen <<- Sys.getenv("RENV_CONFIG_PAK_ENABLED")
    invisible()
  }
  local_mocked_bindings(install = fake_install, .package = "renv")
  .need_install("arrow", tempdir())
  expect_identical(seen, "FALSE")
})
