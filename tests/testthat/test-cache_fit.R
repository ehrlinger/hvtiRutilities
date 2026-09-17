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
