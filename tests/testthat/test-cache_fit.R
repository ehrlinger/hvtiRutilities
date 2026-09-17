test_that("a miss computes, writes one file, and attaches the key", {
  dir <- withr::local_tempdir()
  d <- 1:10
  out <- cache_fit("s", sum(d), dir = dir)
  expect_equal(out, 55L, ignore_attr = TRUE)
  expect_identical(list.files(dir, all.files = TRUE, no.. = TRUE), "s.rds")
  expect_type(attr(out, "hvtiRutilities_cache_key"), "list")
})

test_that("a hit loads without running the computation", {
  dir <- withr::local_tempdir()
  calls <- new.env()
  calls$n <- 0L
  slow <- function(x) {
    calls$n <- calls$n + 1L
    sum(x)
  }
  d <- 1:10
  first <- cache_fit("s", slow(d), dir = dir)
  expect_message(second <- cache_fit("s", slow(d), dir = dir),
                 "loaded 's' from cache")
  expect_identical(calls$n, 1L)
  expect_identical(first, second)
})

test_that("a variable holding a quoted call is the same as inline code", {
  dir <- withr::local_tempdir()
  d <- 1:10
  cache_fit("s", sum(d), dir = dir)
  q <- quote(sum(d))
  expect_message(cache_fit("s", q, dir = dir), "loaded")
})

test_that("a block runs in its own scope and returns its last value", {
  dir <- withr::local_tempdir()
  d <- 1:10
  out <- cache_fit("b", {
    doubled <- d * 2
    sum(doubled)
  }, dir = dir)
  expect_equal(out, 110, ignore_attr = TRUE)
  expect_false(exists("doubled", inherits = FALSE))
})

test_that("an already-computed object is refused", {
  dir <- withr::local_tempdir()
  fitted <- sum(1:3)
  expect_error(cache_fit("f", fitted, dir = dir), "already-computed")
  expect_length(list.files(dir), 0L)
})

test_that("a changed input stops with a classed error naming it", {
  dir <- withr::local_tempdir()
  d <- 1:10
  cache_fit("s", sum(d), dir = dir)
  d <- 1:11
  err <- expect_error(cache_fit("s", sum(d), dir = dir),
                      class = "hvtiRutilities_stale_cache")
  expect_match(conditionMessage(err), "inputs\\$d")
  expect_match(conditionMessage(err), "refit = TRUE")
})

test_that("refit = TRUE recomputes a stale object; the new one is then a hit", {
  dir <- withr::local_tempdir()
  d <- 1:10
  cache_fit("s", sum(d), dir = dir)
  d <- 1:11
  out <- suppressMessages(cache_fit("s", sum(d), dir = dir, refit = TRUE))
  expect_equal(out, 66L, ignore_attr = TRUE)
  expect_message(cache_fit("s", sum(d), dir = dir), "loaded")
})

test_that("an unkeyed file stops unless refit = TRUE", {
  dir <- withr::local_tempdir()
  saveRDS(42, file.path(dir, "old.rds"))
  expect_error(cache_fit("old", sum(1:3), dir = dir),
               class = "hvtiRutilities_unkeyed_cache")
  out <- suppressMessages(cache_fit("old", sum(1:3), dir = dir, refit = TRUE))
  expect_equal(out, 6L, ignore_attr = TRUE)
})

test_that("a corrupt/unreadable cache file is treated as unkeyed", {
  dir <- withr::local_tempdir()
  writeLines("not an rds", file.path(dir, "junk.rds"))
  expect_error(cache_fit("junk", sum(1:3), dir = dir),
               class = "hvtiRutilities_unkeyed_cache")
  out <- suppressMessages(cache_fit("junk", sum(1:3), dir = dir, refit = TRUE))
  expect_equal(out, 6L, ignore_attr = TRUE)
})

test_that("a wrapper forwarding its own argument forces it and is refused", {
  dir <- withr::local_tempdir()
  d <- 1:10
  helper <- function(nm, expr) cache_fit(nm, expr, dir = dir)
  expect_error(helper("w", sum(d)), "already-computed")
  expect_length(list.files(dir), 0L)
})

test_that("a wrapper passed a quoted call works", {
  dir <- withr::local_tempdir()
  d <- 1:10
  helper <- function(nm, expr) cache_fit(nm, expr, dir = dir)
  out <- helper("w", quote(sum(d)))
  expect_equal(out, 55L, ignore_attr = TRUE)
})

test_that("a failing computation writes nothing", {
  dir <- withr::local_tempdir()
  expect_error(cache_fit("boom", stop("fit failed"), dir = dir), "fit failed")
  expect_length(list.files(dir, all.files = TRUE, no.. = TRUE), 0L)
})

test_that("a computation returning NULL is an error", {
  dir <- withr::local_tempdir()
  expect_error(cache_fit("n", invisible(NULL), dir = dir), "NULL")
})

test_that("refitting an upstream object makes a downstream cache stale", {
  dir <- withr::local_tempdir()
  d <- 1:10
  up <- cache_fit("up", sum(d), dir = dir)
  cache_fit("down", up * 2, dir = dir)
  d <- 1:11
  up <- suppressMessages(cache_fit("up", sum(d), dir = dir, refit = TRUE))
  expect_error(cache_fit("down", up * 2, dir = dir),
               class = "hvtiRutilities_stale_cache")
})

test_that("an upstream cache HIT (not just a refit) leaves downstream a hit", {
  dir <- withr::local_tempdir()
  dta <- data.frame(y = c(1, 2, 3, 4, 6), x = c(1, 2, 3, 5, 7))
  up <- cache_fit("up", lm(y ~ x, data = dta), dir = dir)
  cache_fit("down", stats::predict(up), dir = dir)

  # "up" is unchanged, so this call is itself a cache HIT and returns a value
  # loaded via readRDS() -- its $terms environment is detached, unlike the
  # live fit above that "down" was originally cached against. Rebinding to
  # the same name "up" keeps the code text of the "down" call identical.
  up <- suppressMessages(cache_fit("up", lm(y ~ x, data = dta), dir = dir))
  expect_message(cache_fit("down", stats::predict(up), dir = dir),
                 "loaded 'down' from cache")
})

test_that("a chained cache survives across processes", {
  skip_if_not_installed("callr")
  # A fresh subprocess can get a copy of hvtiRutilities two ways: an
  # installed copy that actually has cache_fit() -- R CMD check runs tests
  # against exactly this, where pkgload::pkg_path() has no source
  # DESCRIPTION to walk up to -- or, in a dev session (devtools::test()),
  # by pkgload::load_all()-ing the source tree. Checking for cache_fit()
  # itself (not just the package name) matters because an *older* installed
  # copy without it can otherwise shadow the source tree in .libPaths().
  has_installed_fn <- function() {
    requireNamespace("hvtiRutilities", quietly = TRUE) &&
      exists("cache_fit", where = asNamespace("hvtiRutilities"),
             inherits = FALSE)
  }
  pkg_path <- tryCatch(pkgload::pkg_path(), error = function(e) NULL)
  if (!has_installed_fn() && is.null(pkg_path)) {
    skip("hvtiRutilities is not resolvable from a fresh subprocess")
  }
  dir <- withr::local_tempdir()
  job <- function(dir, pkg_path) {
    if (requireNamespace("hvtiRutilities", quietly = TRUE) &&
          exists("cache_fit", where = asNamespace("hvtiRutilities"),
                 inherits = FALSE)) {
      library(hvtiRutilities)
    } else {
      pkgload::load_all(pkg_path, quiet = TRUE)
    }
    dta <- data.frame(y = c(1, 2, 3, 4, 6), x = c(1, 2, 3, 5, 7))
    up <- cache_fit("up", lm(y ~ x, data = dta), dir = dir)
    cache_fit("down", stats::predict(up), dir = dir)
  }
  callr::r(job, args = list(dir = dir, pkg_path = pkg_path))
  expect_no_error(callr::r(job, args = list(dir = dir, pkg_path = pkg_path)))
})

test_that("arguments are checked", {
  dir <- withr::local_tempdir()
  expect_error(cache_fit("a/b", sum(1), dir = dir), "file stem")
  expect_error(cache_fit(c("a", "b"), sum(1), dir = dir), "file stem")
  expect_error(cache_fit("a", sum(1), dir = dir, refit = NA), "refit")
  expect_error(cache_fit("a", sum(1), dir = dir, seed = "x"), "seed")
  expect_error(cache_fit("a", sum(1), dir = file.path(dir, "nope")),
               "does not exist")
})

test_that("a non-scalar-character dir gives a clear `dir` error", {
  dir <- withr::local_tempdir()
  expect_error(cache_fit("a", sum(1), dir = c(dir, dir)), "`dir`")
  expect_error(cache_fit("a", sum(1), dir = 1), "`dir`")
  expect_error(cache_fit("a", sum(1), dir = NA_character_), "`dir`")
})

test_that("a seed reproduces the result and leaves the global stream alone", {
  dir <- withr::local_tempdir()
  withr::local_seed(1)
  n <- 5
  before <- get(".Random.seed", envir = globalenv())
  a <- cache_fit("r1", stats::runif(n), seed = 42, dir = dir)
  expect_identical(get(".Random.seed", envir = globalenv()), before)
  b <- cache_fit("r2", stats::runif(n), seed = 42, dir = dir)
  expect_identical(as.vector(a), as.vector(b))
  expect_true(attr(a, "hvtiRutilities_cache_key")$reproducible)
})

test_that("RNG use without a seed warns and is recorded as not reproducible", {
  dir <- withr::local_tempdir()
  withr::local_seed(1)
  n <- 5
  expect_warning(x <- cache_fit("r3", stats::runif(n), dir = dir),
                 class = "hvtiRutilities_nonreproducible_fit")
  expect_false(attr(x, "hvtiRutilities_cache_key")$reproducible)
  expect_false(readRDS(file.path(dir, "r3.rds"))$key$reproducible)
})

test_that("a computation that draws no random numbers does not warn", {
  dir <- withr::local_tempdir()
  withr::local_seed(1)
  expect_no_warning(cache_fit("r4", sum(1:3), dir = dir))
})

test_that("changing the seed makes the cache stale", {
  dir <- withr::local_tempdir()
  n <- 5
  cache_fit("r5", stats::runif(n), seed = 1, dir = dir)
  err <- expect_error(cache_fit("r5", stats::runif(n), seed = 2, dir = dir),
                      class = "hvtiRutilities_stale_cache")
  expect_match(conditionMessage(err), "seed")
})

test_that("inside a study the default dir is used; provenance keeps key", {
  root <- make_study_fixture(withr::local_tempdir())
  dir.create(file.path(root, "estimates"))
  withr::local_dir(root)
  d <- 1:10
  out <- cache_fit("s", sum(d))
  expect_true(file.exists(file.path(root, "estimates", "s.rds")))
  side <- file.path(root, "estimates", "s.provenance.json")
  expect_true(file.exists(side))
  rec <- jsonlite::read_json(side)
  expect_identical(rec$cache_key$inputs$d,
                   attr(out, "hvtiRutilities_cache_key")$inputs$d)
})

test_that("outside a study no sidecar is written", {
  dir <- withr::local_tempdir()
  cache_fit("s", sum(1:3), dir = dir)
  expect_identical(list.files(dir, all.files = TRUE, no.. = TRUE), "s.rds")
})

test_that("a provenance failure inside a study leaves nothing cached", {
  root <- make_study_fixture(withr::local_tempdir(), write_data = FALSE)
  dir.create(file.path(root, "estimates"))
  err <- expect_error(
    cache_fit("s", sum(1:3), dir = file.path(root, "estimates"))
  )
  expect_match(conditionMessage(err), "cache_fit", fixed = TRUE)
  expect_match(conditionMessage(err), "NOT kept")
  expect_length(list.files(file.path(root, "estimates"), all.files = TRUE,
                           no.. = TRUE), 0L)
})

test_that("a corrupted _study.yml mentions cache_fit() and leaves nothing cached", {
  root <- make_study_fixture(withr::local_tempdir(), omit = "study")
  dir.create(file.path(root, "estimates"))
  err <- expect_error(
    cache_fit("s", sum(1:3), dir = file.path(root, "estimates"))
  )
  expect_match(conditionMessage(err), "cache_fit", fixed = TRUE)
  expect_length(list.files(file.path(root, "estimates"), all.files = TRUE,
                           no.. = TRUE), 0L)
})

test_that("a record_provenance() failure is raised even if its message contains the not-a-study phrase", {
  root <- make_study_fixture(withr::local_tempdir())
  dir.create(file.path(root, "estimates"))
  local_mocked_bindings(
    record_provenance = function(...) {
      stop("no _study.yml found (coincidentally, from record_provenance())")
    },
    .package = "hvtiRutilities"
  )
  err <- expect_error(
    cache_fit("s", sum(1:3), dir = file.path(root, "estimates"))
  )
  expect_match(conditionMessage(err), "cache_fit", fixed = TRUE)
  expect_match(conditionMessage(err), "NOT kept")
  expect_length(list.files(file.path(root, "estimates"), all.files = TRUE,
                           no.. = TRUE), 0L)
})

test_that("a survival forest round-trips and records its package version", {
  skip_if_not_installed("randomForestSRC")
  withr::local_options(rf.cores = 1L, mc.cores = 1L)
  dir <- withr::local_tempdir()
  utils::data("veteran", package = "randomForestSRC", envir = environment())
  fit <- cache_fit(
    "vet-rfs",
    randomForestSRC::rfsrc(Surv(time, status) ~ ., data = veteran,
                           ntree = 50, seed = -1L),
    dir = dir
  )
  direct <- randomForestSRC::rfsrc(Surv(time, status) ~ ., data = veteran,
                                   ntree = 50, seed = -1L)
  expect_equal(fit$predicted.oob, direct$predicted.oob)
  expect_message(
    again <- cache_fit(
      "vet-rfs",
      randomForestSRC::rfsrc(Surv(time, status) ~ ., data = veteran,
                             ntree = 50, seed = -1L),
      dir = dir
    ),
    "loaded"
  )
  expect_equal(again$predicted.oob, fit$predicted.oob)
  key_pkgs <- attr(fit, "hvtiRutilities_cache_key")$packages
  expect_identical(key_pkgs$randomForestSRC,
                   as.character(utils::packageVersion("randomForestSRC")))
})

test_that("a multiple imputation round-trips with a seed", {
  skip_if_not_installed("mice")
  dir <- withr::local_tempdir()
  aq <- datasets::airquality[1:40, 1:4]
  imp <- cache_fit("aq-mice", mice::mice(aq, m = 2, printFlag = FALSE),
                   seed = 7, dir = dir)
  expect_s3_class(imp, "mids")
  expect_message(
    again <- cache_fit("aq-mice", mice::mice(aq, m = 2, printFlag = FALSE),
                       seed = 7, dir = dir),
    "loaded"
  )
  expect_equal(mice::complete(again), mice::complete(imp))
})
