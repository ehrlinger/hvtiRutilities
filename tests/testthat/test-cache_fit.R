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

test_that("a variable holding a quoted call is the same computation as inline code", {
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

test_that("refit = TRUE recomputes a stale object and the new one is then a hit", {
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

test_that("arguments are checked", {
  dir <- withr::local_tempdir()
  expect_error(cache_fit("a/b", sum(1), dir = dir), "file stem")
  expect_error(cache_fit(c("a", "b"), sum(1), dir = dir), "file stem")
  expect_error(cache_fit("a", sum(1), dir = dir, refit = NA), "refit")
  expect_error(cache_fit("a", sum(1), dir = dir, seed = "x"), "seed")
  expect_error(cache_fit("a", sum(1), dir = file.path(dir, "nope")),
               "does not exist")
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
