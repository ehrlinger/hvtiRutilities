# Each case sets up a cache file, asks cache_would_fit(), then lets
# cache_fit() act with the same arguments and records whether it ran `code`,
# by a counter that only the computation moves. The two must agree.
would_and_did <- function(setup, refit) {
  dir <- withr::local_tempdir()
  calls <- new.env()
  calls$n <- 0L
  counted <- function(x) {
    calls$n <- calls$n + 1L
    sum(x)
  }
  d <- 1:10
  setup(dir, counted, d)
  if (exists("d_after", envir = calls)) d <- calls$d_after
  before <- calls$n
  would <- cache_would_fit("s", counted(d), dir = dir, refit = refit,
                           packages = "withr")
  outcome <- tryCatch({
    suppressMessages(cache_fit("s", counted(d), dir = dir, refit = refit,
                               packages = "withr"))
    "returned"
  }, error = function(e) class(e)[1L])
  list(would = would, did = calls$n > before, outcome = outcome)
}

no_file <- function(dir, counted, d) invisible()

fresh <- function(dir, counted, d) {
  cache_fit("s", counted(d), dir = dir, packages = "withr")
}

# The input `d` changes between the write and the question.
stale_input <- function(dir, counted, d) {
  cache_fit("s", counted(d), dir = dir, packages = "withr")
  assign("d_after", 1:11, envir = environment(counted)$calls)
}

# The stored key records an older version of a package the key names.
stale_version <- function(dir, counted, d) {
  cache_fit("s", counted(d), dir = dir, packages = "withr")
  path <- file.path(dir, "s.rds")
  rec <- readRDS(path)
  rec$key$packages$withr <- "0.0.1"
  saveRDS(rec, path)
}

unkeyed <- function(dir, counted, d) {
  saveRDS(42, file.path(dir, "s.rds"))
}

corrupt <- function(dir, counted, d) {
  writeLines("not an rds", file.path(dir, "s.rds"))
}

cases <- list(
  "no file"                 = list(no_file,       FALSE, TRUE,  "returned"),
  "no file, refit"          = list(no_file,       TRUE,  TRUE,  "returned"),
  "matching key"            = list(fresh,         FALSE, FALSE, "returned"),
  "matching key, refit"     = list(fresh,         TRUE,  FALSE, "returned"),
  "stale input"             = list(stale_input,   FALSE, FALSE,
                                   "hvtiRutilities_stale_cache"),
  "stale input, refit"      = list(stale_input,   TRUE,  TRUE,  "returned"),
  "stale version"           = list(stale_version, FALSE, FALSE,
                                   "hvtiRutilities_stale_cache"),
  "stale version, refit"    = list(stale_version, TRUE,  TRUE,  "returned"),
  "unkeyed file"            = list(unkeyed,       FALSE, FALSE,
                                   "hvtiRutilities_unkeyed_cache"),
  "unkeyed file, refit"     = list(unkeyed,       TRUE,  TRUE,  "returned"),
  "corrupt file"            = list(corrupt,       FALSE, FALSE,
                                   "hvtiRutilities_unkeyed_cache"),
  "corrupt file, refit"     = list(corrupt,       TRUE,  TRUE,  "returned")
)

for (nm in names(cases)) {
  local({
    case <- cases[[nm]]
    test_that(paste0("cache_would_fit() agrees with cache_fit(): ", nm), {
      r <- would_and_did(case[[1L]], refit = case[[2L]])
      expect_identical(r$would, case[[3L]])
      expect_identical(r$would, r$did)
      expect_identical(r$outcome, case[[4L]])
    })
  })
}

test_that("cache_would_fit() computes nothing and writes nothing", {
  dir <- withr::local_tempdir()
  calls <- new.env()
  calls$n <- 0L
  counted <- function(x) {
    calls$n <- calls$n + 1L
    sum(x)
  }
  d <- 1:10
  expect_true(cache_would_fit("s", counted(d), dir = dir))
  expect_identical(calls$n, 0L)
  expect_length(list.files(dir, all.files = TRUE, no.. = TRUE), 0L)
})

test_that("cache_would_fit() takes cache_fit()'s arguments exactly", {
  expect_identical(formals(cache_would_fit), formals(cache_fit))
})

test_that("a quoted call and a seed are keyed as cache_fit() keys them", {
  dir <- withr::local_tempdir()
  n <- 5
  q <- quote(stats::runif(n))
  cache_fit("r", q, seed = 1, dir = dir)
  expect_false(cache_would_fit("r", stats::runif(n), seed = 1, dir = dir))
  expect_false(cache_would_fit("r", q, seed = 1, dir = dir, refit = TRUE))
  expect_true(cache_would_fit("r", q, seed = 2, dir = dir, refit = TRUE))
})

test_that("cache_would_fit() refuses what cache_fit() refuses", {
  dir <- withr::local_tempdir()
  fitted <- sum(1:3)
  expect_error(cache_would_fit("f", fitted, dir = dir), "already-computed")
  expect_error(cache_would_fit("f", sum(1:3), dir = file.path(dir, "nope")),
               "directory does not exist")
  expect_error(cache_would_fit("a/b", sum(1:3), dir = dir), "`name`")
})

test_that("cache_would_fit() does not read a file under refit = FALSE", {
  dir <- withr::local_tempdir()
  d <- 1:10
  cache_fit("s", sum(d), dir = dir)
  plan <- .cache_plan("s", quote(sum(d)), environment(), NULL, dir, FALSE,
                      NULL, read = FALSE)
  expect_identical(plan$action, "kept")
  expect_null(plan$stored)
})

# Mutation proof. The agreement above holds because both functions read one
# decision, .cache_plan(). Break that decision for cache_would_fit()'s call
# alone (the only caller passing read = FALSE) by inverting its answer, and
# the agreement must fail in every case. If it did not, the agreement tests
# would not be testing the shared decision.
test_that("breaking the shared decision for one caller breaks agreement", {
  real <- .cache_plan
  local_mocked_bindings(.cache_plan = function(..., read = TRUE) {
    plan <- real(..., read = read)
    if (!read) {
      plan$action <- if (identical(plan$action, "compute")) "kept" else
        "compute"
    }
    plan
  })
  for (nm in names(cases)) {
    case <- cases[[nm]]
    r <- would_and_did(case[[1L]], refit = case[[2L]])
    expect_false(identical(r$would, r$did), label = nm)
  }
})

test_that("readRDS() is never called for an existing file under refit = FALSE", {
  dir <- withr::local_tempdir()
  d <- 1:10
  cache_fit("s", sum(d), dir = dir)
  suppressMessages(trace("readRDS", quote(stop("readRDS was called")),
                         where = baseenv(), print = FALSE))
  withr::defer(suppressMessages(untrace("readRDS", where = baseenv())))
  expect_false(cache_would_fit("s", sum(d), dir = dir))
  expect_error(readRDS(file.path(dir, "s.rds")), "readRDS was called")
})

test_that("inside a function, a local variable in `code` keys as cache_fit()", {
  dir <- withr::local_tempdir()
  calls <- new.env()
  calls$n <- 0L
  counted <- function(x) {
    calls$n <- calls$n + 1L
    sum(x)
  }
  job <- function(n, refit = FALSE) {
    local_d <- seq_len(n)
    would <- cache_would_fit("loc", counted(local_d), dir = dir,
                             refit = refit)
    before <- calls$n
    tryCatch(
      suppressMessages(cache_fit("loc", counted(local_d), dir = dir,
                                 refit = refit)),
      hvtiRutilities_stale_cache = function(e) NULL
    )
    c(would = would, did = calls$n > before)
  }
  expect_identical(job(10), c(would = TRUE, did = TRUE))
  expect_identical(job(10), c(would = FALSE, did = FALSE))
  expect_identical(job(11), c(would = FALSE, did = FALSE))
  expect_identical(job(11, refit = TRUE), c(would = TRUE, did = TRUE))
  expect_identical(job(11, refit = TRUE), c(would = FALSE, did = FALSE))
})
