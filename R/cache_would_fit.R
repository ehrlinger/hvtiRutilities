#' Would cache_fit() compute, or load?
#'
#' Answers, without computing anything, whether [cache_fit()] called
#' with the same arguments would run its computation. A job uses it to guard a
#' resource, memory or cores, only when a fit will actually run, rather than
#' refusing a session for a fit it would simply load from the cache.
#'
#' @details
#' The arguments are `cache_fit()`'s, with the same names, order and
#' defaults, and none is dropped: `name` and `dir` locate the file,
#' `code`, `seed` and `packages` make the key, and `refit`
#' decides what a stale or unkeyed file does. Write the call exactly as the
#' `cache_fit()` call it guards, for example
#' `cache_would_fit("forest", rfsrc(f, data = d), seed = 1)` before
#' `cache_fit("forest", rfsrc(f, data = d), seed = 1)`. `code` is
#' captured as `cache_fit()` captures it, by substitution, and is never
#' evaluated: inline code and a variable holding a call quoted with
#' [base::quote()] both work, and an already-computed object is refused as it is there.
#' The same rule about wrappers applies; see [cache_fit()].
#'
#' The answer comes from the same internal decision `cache_fit()` makes,
#' not from a copy of it, so the two cannot drift apart:
#' \itemize{
#'   \item no file: `TRUE`;
#'   \item a file whose key matches: `FALSE`, whatever `refit` is,
#'     because a valid cache is loaded even under `refit = TRUE`;
#'   \item a stale file (the code, an input, the seed or a package version
#'     changed) or an unkeyed or unreadable file: `TRUE` with
#'     `refit = TRUE`, and `FALSE` without it.
#' }
#' The last case is deliberate. Without `refit`, `cache_fit()` stops
#' on a stale or unkeyed file before it computes anything, so nothing will run
#' and there is nothing to guard; the error that follows is
#' `cache_fit()`'s to raise, with the list of what changed. For the same
#' reason, an existing file under `refit = FALSE` is not read at all,
#' since every outcome there computes nothing.
#'
#' Arguments are checked as `cache_fit()` checks them, and a bad one
#' raises the same error, naming `cache_fit()`, including a `dir`
#' that does not exist. Under `refit = TRUE` an existing file is read to
#' compare its key, so a matching fit is read here and again by
#' `cache_fit()`.
#'
#' @inheritParams cache_fit
#'
#' @return `TRUE` if `cache_fit()` with the same arguments would run
#'   `code`, `FALSE` if it would load the cached result or stop on a
#'   stale or unkeyed file without computing.
#'
#' @seealso [cache_fit()]
#'
#' @export
#'
#' @examples
#' dir <- file.path(tempdir(), "cache-would-fit-example")
#' dir.create(dir, showWarnings = FALSE)
#' x <- c(3, 1, 2)
#' cache_would_fit("sorted", sort(x), dir = dir)
#' fit <- cache_fit("sorted", sort(x), dir = dir)
#' cache_would_fit("sorted", sort(x), dir = dir)
#' x <- c(4, 1, 2)
#' cache_would_fit("sorted", sort(x), dir = dir)
#' cache_would_fit("sorted", sort(x), dir = dir, refit = TRUE)
#' unlink(dir, recursive = TRUE)
cache_would_fit <- function(name, code, seed = NULL,
                            dir = study_dir("estimates"), refit = FALSE,
                            packages = NULL) {
  plan <- .cache_plan(name, substitute(code), parent.frame(), seed, dir,
                      refit, packages, read = FALSE)
  identical(plan$action, "compute")
}
