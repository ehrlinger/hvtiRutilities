#' Cache an expensive computation, strictly
#'
#' Runs an expensive computation (a random forest, a varPro fit, an
#' imputation, a hazard model, a partial dependence grid) once, saves the
#' result, and on later calls loads it instead of recomputing. The saved result
#' is used only if nothing it was built from has changed: the code, every
#' outside value the code reads, the versions of the packages its functions
#' come from, and the seed. If anything changed, \code{cache_fit()} stops and
#' lists what changed. It never returns a stale result.
#'
#' @details
#' \code{code} is not evaluated on a cache hit. It can be written inline, as a
#' single call or a \code{\{\}} block of several steps, or passed as a
#' variable holding a \code{\link[base]{quote}}d call built beforehand. Both
#' forms give the same key for the same computation. Passing an object that has
#' already been computed is an error, because the cache could never skip it.
#'
#' \code{code} must be written in the call to \code{cache_fit()} itself. A
#' wrapper function that forwards its own argument, e.g.
#' \code{function(nm, expr) cache_fit(nm, expr)}, forces that argument's
#' promise when it resolves \code{code}, so the value is already computed and
#' the call is refused as already-computed. A wrapper should instead build and
#' pass a quoted call, for example \code{cache_fit(nm, bquote(...))} or by
#' passing \code{quote(...)} through.
#'
#' The code runs in a new environment whose parent is the caller's, so names
#' assigned inside a block do not appear in the caller.
#'
#' The key digests each free variable of the code: a name bound by an
#' assignment, a \code{function} formal, or a \code{for} index is local within
#' that binding's scope, so a name that is also read free elsewhere in the
#' code still counts as an input. Values read indirectly (inside the body of a
#' function it calls, or through \code{get()}) are not seen; pass such values
#' into the code as arguments. The exception is a function defined in the
#' global environment
#' (as in a shared \code{_common.R}): its own body is part of the key, so
#' editing it invalidates a cache that calls it, even though values it in turn
#' reads indirectly are still not seen. This reaches only one level deep: a
#' global helper is part of the key only through its own body, not through the
#' bodies of further helpers it in turn calls, so editing a callee of a helper
#' does not invalidate a cache that calls the helper. For example, if
#' \code{hA <- function(z) hB(z)} is defined globally and \code{hB}'s body is
#' later edited, the key computed for code that calls \code{hA} is unchanged.
#'
#' The result is returned with its key attached as an attribute, and that
#' attached key, not the object's own content, is what a downstream
#' \code{cache_fit()} digests when this result is passed to it as an input.
#' Mutating the returned object afterwards, for example
#' \code{fit$coefficients <- ...}, is invisible to that downstream cache,
#' because the attached key does not change to reflect the mutation. If a
#' cached object is modified in place, strip its
#' \code{hvtiRutilities_cache_key} attribute or re-wrap the result so a
#' downstream cache is not fooled into treating it as unchanged.
#'
#' The attached-key short cut above applies only to a cached object passed
#' directly as an input. A cached object wrapped inside a list, or a model
#' object built outside \code{cache_fit()}, carries no such key and is
#' digested whole instead; such objects can digest differently across
#' sessions or platforms even when nothing meaningful about them changed.
#' This shows up as a loud, classed \code{hvtiRutilities_stale_cache} error
#' rather than a silently wrong cache hit, which is the safer failure mode,
#' but is worth knowing about when a downstream cache goes stale for no
#' apparent reason.
#'
#' The computation must return a value; a result of \code{NULL} is an error,
#' because there would be nothing to cache.
#'
#' When \code{seed} is given, the code runs inside
#' \code{\link[withr]{with_seed}}, which leaves the global random number stream
#' as it was. When \code{seed} is \code{NULL} and the code consumes random
#' numbers, the result is still saved, with a warning of class
#' \code{hvtiRutilities_nonreproducible_fit}, and the key records
#' \code{reproducible = FALSE}.
#'
#' A stale file stops with an error of class
#' \code{hvtiRutilities_stale_cache}; a file not written by \code{cache_fit()}
#' stops with class \code{hvtiRutilities_unkeyed_cache}. Both are recomputed
#' with \code{refit = TRUE}.
#'
#' The result is written to a temporary file and renamed into place, so an
#' interrupted run never leaves a partial file. When \code{dir} lies inside a
#' study, a provenance sidecar carrying the key is written with
#' \code{\link{record_provenance}}.
#'
#' @param name Character(1). File stem; the result is stored at
#'   \code{file.path(dir, paste0(name, ".rds"))}.
#' @param code The computation: an inline call or \code{\{\}} block, or a
#'   variable holding a quoted call.
#' @param seed \code{NULL} or a single whole number.
#' @param dir Character(1). An existing directory. Defaults to the study's
#'   estimates folder.
#' @param refit Logical(1). \code{TRUE} recomputes and overwrites the file only
#'   when it is stale or unkeyed; a valid cache is still loaded, not
#'   recomputed, regardless of \code{refit}.
#'
#' @return The result of \code{code}, computed or loaded, with its key attached
#'   as attribute \code{hvtiRutilities_cache_key}.
#'
#' @seealso \code{\link{record_provenance}}, \code{\link{study_dir}}
#'
#' @export
#'
#' @examples
#' dir <- file.path(tempdir(), "cache-fit-example")
#' dir.create(dir, showWarnings = FALSE)
#' x <- c(3, 1, 2)
#' first <- cache_fit("sorted", sort(x), dir = dir)
#' again <- cache_fit("sorted", sort(x), dir = dir)
#' identical(first, again)
#' unlink(dir, recursive = TRUE)
cache_fit <- function(name, code, seed = NULL, dir = study_dir("estimates"),
                      refit = FALSE) {
  expr <- substitute(code)
  env  <- parent.frame()
  .cache_check_args(name, seed, refit, dir)
  if (!is.null(seed)) seed <- as.integer(seed)
  code <- .cache_resolve(expr, env)

  if (!dir.exists(dir)) {
    stop("cache_fit(): directory does not exist: ", dir, call. = FALSE)
  }
  path <- file.path(dir, paste0(name, ".rds"))
  key  <- .cache_key(code, env, seed)

  if (file.exists(path)) {
    stored <- tryCatch(readRDS(path), error = function(e) NULL)
    if (!.cache_is_record(stored)) {
      if (!refit) .cache_abort("unkeyed", name, path)
    } else {
      diff <- .cache_key_diff(stored$key, key)
      if (length(diff) == 0L) {
        message("cache_fit(): loaded '", name, "' from cache")
        return(.cache_attach(stored$value, stored$key))
      }
      if (!refit) .cache_abort("stale", name, path, diff)
    }
    message("cache_fit(): recomputing '", name, "' (refit = TRUE)")
  }

  run <- .cache_run(code, env, seed)
  if (is.null(run$value)) {
    stop("cache_fit(): '", name, "' returned NULL; there is nothing to cache.",
         call. = FALSE)
  }
  key$reproducible <- run$reproducible
  if (!run$reproducible) .cache_warn_nonreproducible(name)

  record <- list(hvtiRutilities_cache = 1L, key = key, value = run$value)
  .cache_write(record, path, key, dir)
  .cache_attach(run$value, key)
}

.cache_check_args <- function(name, seed, refit, dir) {
  if (!is.character(name) || length(name) != 1L || is.na(name) ||
        !nzchar(name) || grepl("[/\\\\]", name)) {
    stop("cache_fit(): `name` must be a single file stem with no path ",
         "separators.", call. = FALSE)
  }
  if (!is.null(seed) && (!is.numeric(seed) || length(seed) != 1L ||
                           is.na(seed) || seed != round(seed))) {
    stop("cache_fit(): `seed` must be NULL or a single whole number.",
         call. = FALSE)
  }
  if (!is.logical(refit) || length(refit) != 1L || is.na(refit)) {
    stop("cache_fit(): `refit` must be TRUE or FALSE.", call. = FALSE)
  }
  if (!is.character(dir) || length(dir) != 1L || is.na(dir)) {
    stop("cache_fit(): `dir` must be a single, non-NA character string.",
         call. = FALSE)
  }
}

# The code is what was written, unless what was written is a single name bound
# to a call or expression, in which case that value is the code.
.cache_resolve <- function(expr, env) {
  if (!is.symbol(expr)) return(expr)
  nm <- as.character(expr)
  if (!exists(nm, envir = env, inherits = TRUE)) {
    stop("cache_fit(): `code` names '", nm, "', which does not exist.",
         call. = FALSE)
  }
  value <- get(nm, envir = env, inherits = TRUE)
  if (is.call(value)) return(value)
  if (is.expression(value)) {
    if (length(value) == 1L) return(value[[1L]])
    return(as.call(c(as.name("{"), as.list(value))))
  }
  stop("cache_fit(): `code` is '", nm, "', an already-computed ",
       class(value)[1L], ". Pass the computation itself, or quote() it, so ",
       "a cache hit can skip it.", call. = FALSE)
}

.cache_is_record <- function(x) {
  is.list(x) && identical(x$hvtiRutilities_cache, 1L) &&
    is.list(x$key) && "value" %in% names(x)
}

.cache_attach <- function(value, key) {
  attr(value, "hvtiRutilities_cache_key") <- key
  value
}

# Runs the code in a child scope of the caller. With a seed, inside
# withr::with_seed(), which restores the global stream afterwards. Without
# one, compares .Random.seed before and after to detect random number use
# anywhere in the computation, including inside compiled package code.
.cache_run <- function(code, env, seed) {
  scope <- new.env(parent = env)
  if (!is.null(seed)) {
    value <- withr::with_seed(seed, eval(code, envir = scope))
    return(list(value = value, reproducible = TRUE))
  }
  before <- get0(".Random.seed", envir = globalenv(), inherits = FALSE)
  value  <- eval(code, envir = scope)
  after  <- get0(".Random.seed", envir = globalenv(), inherits = FALSE)
  list(value = value, reproducible = identical(before, after))
}

.cache_abort <- function(kind, name, path, diff = character(0)) {
  msg <- if (identical(kind, "stale")) {
    paste0("Cached object '", name, "' is stale (", path, "):\n",
           paste(diff, collapse = "\n"),
           "\nRecompute with refit = TRUE, or restore the inputs it was ",
           "built from.")
  } else {
    paste0("Cached object '", name, "' has no cache key or could not be ",
           "read (", path, ").\n",
           "It was not written by cache_fit(), or the file is unreadable, ",
           "so it cannot be checked. Recompute with refit = TRUE.")
  }
  stop(structure(
    class = c(paste0("hvtiRutilities_", kind, "_cache"), "error", "condition"),
    list(message = msg, call = NULL)
  ))
}

.cache_warn_nonreproducible <- function(name) {
  warning(structure(
    class = c("hvtiRutilities_nonreproducible_fit", "warning", "condition"),
    list(message = paste0("cache_fit(): '", name, "' used the random number ",
                          "generator without a seed. It was cached but will ",
                          "not reproduce. Pass seed = to cache_fit()."),
         call = NULL)
  ))
}

# Save to a temporary file beside the target, record provenance, then rename.
# A failure at any step leaves no file at `path`.
.cache_write <- function(record, path, key, dir) {
  tmp <- tempfile(
    pattern = paste0(".", tools::file_path_sans_ext(basename(path)), "-"),
    tmpdir = dirname(path), fileext = ".rds.tmp"
  )
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  saveRDS(record, tmp)
  .cache_provenance(path, key, dir)
  if (!file.rename(tmp, path)) {
    stop("cache_fit(): could not move the cached object into place at ",
         path, call. = FALSE)
  }
  invisible(path)
}

# Records provenance when `dir` lies inside a study. Only "no _study.yml
# found" means "not a study"; every other failure, from study_root(),
# study_config(), or record_provenance() alike, propagates as an error naming
# cache_fit(), and because this runs before the rename, a failure leaves
# nothing cached. All three calls share one tryCatch so a malformed
# _study.yml cannot escape as a raw study_config()/study_root() error that
# never mentions cache_fit() or that the operation's result was discarded.
# The text match on "no _study.yml found" is a coupling to study_config()'s
# own stop() in R/study_config.R (it raises a plain, unclassed condition);
# replace it if that ever gains a class.
.cache_provenance <- function(path, key, dir) {
  tryCatch({
    root <- study_root(dir)
    # require_data = FALSE matches the leniency of study_root()'s own
    # detection above; study_config()'s default (require_data = TRUE) would
    # otherwise apply a stricter read here than what "is this a study" just
    # decided.
    cfg <- study_config(root, require_data = FALSE)
    record_provenance(path, extra = list(cache_key = key), cfg = cfg)
    invisible(NULL)
  }, error = function(e) {
    if (grepl("no _study.yml found", conditionMessage(e), fixed = TRUE)) {
      return(invisible(NULL))
    }
    # Re-raise as the same condition, classes included, with the message
    # prefixed so the failure is traceable to cache_fit() rather than
    # discarded as an unattributed study_config()/record_provenance() error.
    cnd <- e
    cnd$message <- paste0(
      "cache_fit(): provenance could not be recorded for '",
      basename(path), "'; the computed result was NOT kept.\n",
      conditionMessage(e)
    )
    stop(cnd)
  })
}
