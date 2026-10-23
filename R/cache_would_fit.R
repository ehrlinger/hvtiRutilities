#' Would cache_fit() compute, or load?
#'
#' Answers, without computing anything, whether \code{\link{cache_fit}} called
#' with the same arguments would run its computation. A job uses it to guard a
#' resource, memory or cores, only when a fit will actually run, rather than
#' refusing a session for a fit it would simply load from the cache.
#'
#' @details
#' The arguments are \code{cache_fit()}'s, with the same names, order and
#' defaults, and none is dropped: \code{name} and \code{dir} locate the file,
#' \code{code}, \code{seed} and \code{packages} make the key, and \code{refit}
#' decides what a stale or unkeyed file does. Write the call exactly as the
#' \code{cache_fit()} call it guards, for example
#' \code{cache_would_fit("forest", rfsrc(f, data = d), seed = 1)} before
#' \code{cache_fit("forest", rfsrc(f, data = d), seed = 1)}. \code{code} is
#' captured as \code{cache_fit()} captures it, by substitution, and is never
#' evaluated: inline code and a variable holding a \code{\link[base]{quote}}d
#' call both work, and an already-computed object is refused as it is there.
#' The same rule about wrappers applies; see \code{\link{cache_fit}}.
#'
#' The answer comes from the same internal decision \code{cache_fit()} makes,
#' not from a copy of it, so the two cannot drift apart:
#' \itemize{
#'   \item no file: \code{TRUE};
#'   \item a file whose key matches: \code{FALSE}, whatever \code{refit} is,
#'     because a valid cache is loaded even under \code{refit = TRUE};
#'   \item a stale file (the code, an input, the seed or a package version
#'     changed) or an unkeyed or unreadable file: \code{TRUE} with
#'     \code{refit = TRUE}, and \code{FALSE} without it.
#' }
#' The last case is deliberate. Without \code{refit}, \code{cache_fit()} stops
#' on a stale or unkeyed file before it computes anything, so nothing will run
#' and there is nothing to guard; the error that follows is
#' \code{cache_fit()}'s to raise, with the list of what changed. For the same
#' reason, an existing file under \code{refit = FALSE} is not read at all,
#' since every outcome there computes nothing.
#'
#' Arguments are checked as \code{cache_fit()} checks them, and a bad one
#' raises the same error, naming \code{cache_fit()}, including a \code{dir}
#' that does not exist. Under \code{refit = TRUE} an existing file is read to
#' compare its key, so a matching fit is read here and again by
#' \code{cache_fit()}.
#'
#' @inheritParams cache_fit
#'
#' @return \code{TRUE} if \code{cache_fit()} with the same arguments would run
#'   \code{code}, \code{FALSE} if it would load the cached result or stop on a
#'   stale or unkeyed file without computing.
#'
#' @seealso \code{\link{cache_fit}}
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
