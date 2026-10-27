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
#' The key records the version of the package that owns each function called
#' in \code{code}, and no other. A wrapper is therefore keyed on itself only:
#' \code{gg_partial_rfsrc(forest, ...)} records ggRandomForests, though
#' randomForestSRC computes the partial dependence when it runs. An upgrade of
#' randomForestSRC reaches that key only through \code{forest}'s own key,
#' which holds the version at fit time, not the version that runs now. Name
#' such a package in \code{packages}, e.g.
#' \code{packages = "randomForestSRC"}, and its version joins the key, so an
#' upgrade makes the cache stale. Adding \code{packages} to an existing call
#' makes its cache stale once, with the package reported as
#' \code{(absent)} in the stored key. Base-priority packages are ignored, as
#' they are for functions called in \code{code}.
#'
#' The computation must return a value; a result of \code{NULL} is an error,
#' because there would be nothing to cache.
#'
#' When \code{seed} is given, \code{cache_fit()} calls \code{set.seed(seed)}
#' before the code runs and again after it, even when it fails, and calls it
#' once when the result is loaded instead. If the code changes the generator
#' with \code{\link{RNGkind}}, the kinds in use when \code{cache_fit()} was
#' called are put back before that second call. A computed and a loaded result
#' therefore leave the global random number stream in the same state, the one
#' \code{set.seed(seed)} sets, so code after \code{cache_fit()} draws the
#' same numbers whether or not the cache was hit. Seed any later random step yourself rather than relying on
#' that state. When \code{seed} is \code{NULL}, \code{cache_fit()} sets no
#' seed: the code draws from the caller's stream, and a loaded result leaves
#' the stream untouched. If that code consumes random numbers, the result is
#' still saved, with a warning of class
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
#' study, a provenance sidecar carrying the key and the completed cache file's
#' hash is published with \code{\link{capture_provenance}} and
#' \code{\link{publish_provenance}}. The cache records an explicit empty data
#' list rather than inferring that the currently registered dataset was an
#' input to the computation.
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
#' @param packages \code{NULL} or a character vector of package names whose
#'   versions are added to the key. Use it for a package that does the work
#'   beneath a wrapper and so never appears in \code{code} itself; see
#'   Details.
#'
#' @return The result of \code{code}, computed or loaded, with its key attached
#'   as attribute \code{hvtiRutilities_cache_key}.
#'
#' @seealso \code{\link{capture_provenance}},
#'   \code{\link{publish_provenance}}, \code{\link{study_dir}}
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
                      refit = FALSE, packages = NULL) {
  expr <- substitute(code)
  env  <- parent.frame()
  plan <- .cache_plan(name, expr, env, seed, dir, refit, packages)
  switch(
    plan$action,
    load = {
      message("cache_fit(): loaded '", name, "' from cache")
      if (!is.null(plan$seed)) set.seed(plan$seed)
      return(.cache_attach(plan$stored$value, plan$stored$key))
    },
    unkeyed = .cache_abort("unkeyed", name, plan$path),
    stale   = .cache_abort("stale", name, plan$path, plan$diff)
  )
  if (plan$exists) {
    message("cache_fit(): recomputing '", name, "' (refit = TRUE)")
  }

  key <- plan$key
  path <- plan$path
  run <- .cache_run(plan$code, env, plan$seed)
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

# The one decision cache_fit() and cache_would_fit() share, so the two can
# never disagree: check the arguments, resolve the code, key it, and say what
# a call would do with the file. `action` is "compute", "load" (the key
# matches; `stored` holds the record), "stale" or "unkeyed" (cache_fit()
# stops; `diff` lists a stale key's changes), or "kept". "kept" is returned
# only when `read = FALSE`, for an existing file under refit = FALSE: every
# outcome there loads or stops and none computes, so cache_would_fit() can
# answer without reading what may be a large fit into memory. `exists` says
# whether the file was there, which is when a computation is a recompute.
.cache_plan <- function(name, expr, env, seed, dir, refit, packages,
                        read = TRUE) {
  .cache_check_args(name, seed, refit, dir)
  .cache_check_packages(packages)
  if (!is.null(seed)) seed <- as.integer(seed)
  code <- .cache_resolve(expr, env)

  if (!dir.exists(dir)) {
    stop("cache_fit(): directory does not exist: ", dir, call. = FALSE)
  }
  path <- file.path(dir, paste0(name, ".rds"))
  key  <- .cache_key(code, env, seed, as.character(packages))
  plan <- list(action = "compute", code = code, seed = seed, path = path,
               key = key, exists = file.exists(path))
  if (!plan$exists) return(plan)
  if (!read && !refit) {
    plan$action <- "kept"
    return(plan)
  }

  stored <- tryCatch(readRDS(path), error = function(e) NULL)
  if (!.cache_is_record(stored)) {
    if (!refit) plan$action <- "unkeyed"
    return(plan)
  }
  diff <- .cache_key_diff(stored$key, key)
  if (length(diff) == 0L) {
    plan$action <- "load"
    plan$stored <- stored
  } else if (!refit) {
    plan$action <- "stale"
    plan$diff <- diff
  }
  plan
}

.cache_check_args <- function(name, seed, refit, dir) {
  if (!is.character(name) || length(name) != 1L || is.na(name) ||
        !nzchar(name) || grepl("[/\\\\]", name)) {
    stop("cache_fit(): `name` must be a single file stem with no path ",
         "separators.", call. = FALSE)
  }
  # is.finite() rules out Inf and NaN, which satisfy `seed == round(seed)`,
  # and the range test rules out whole numbers that as.integer() would turn
  # into NA. Either would reach set.seed() as NA, which fails there with a
  # message that does not name cache_fit() or its argument.
  if (!is.null(seed) && (!is.numeric(seed) || length(seed) != 1L ||
                           is.na(seed) || !is.finite(seed) ||
                           seed != round(seed) ||
                           abs(seed) > .Machine$integer.max)) {
    stop("cache_fit(): `seed` must be NULL or a single whole number no ",
         "larger than ", .Machine$integer.max, " in absolute value.",
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

# A package named in `packages` must be installed: a typo would otherwise key
# on NA and go unnoticed, which is the silent miss the argument exists to stop.
.cache_check_packages <- function(packages) {
  if (is.null(packages)) return(invisible())
  if (!is.character(packages) || anyNA(packages) || !all(nzchar(packages))) {
    stop("cache_fit(): `packages` must be NULL or a character vector of ",
         "package names.", call. = FALSE)
  }
  missing <- packages[!nzchar(vapply(packages, function(p) system.file(package = p),
                                     character(1)))]
  if (length(missing) > 0L) {
    stop("cache_fit(): `packages` names packages that are not installed: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  invisible()
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

# Reseeds under the generator kinds in `kinds`, restoring them only when they
# changed. RNGkind() warns whenever sample.kind = "Rounding" is set, and the
# caller already had that warning when they chose it.
.cache_reseed <- function(seed, kinds) {
  if (!identical(RNGkind(), kinds)) {
    suppressWarnings(RNGkind(kinds[1L], kinds[2L], kinds[3L]))
  }
  set.seed(seed)
}

# Runs the code in a child scope of the caller. With a seed, set.seed() runs
# before the code and again on exit, error included, so a computation leaves
# the stream where a cache hit does (cache_fit() seeds a hit too). A hit never
# runs the code, so it always seeds under the caller's generator kinds; the exit
# handler first puts back the kinds the code found on entry, in case it changed
# them (an RNGkind("L'Ecuyer-CMRG") for parallel work, say). Nothing saves or
# restores .Random.seed in the global environment. Without a seed, compares
# .Random.seed before and after to detect random number use anywhere in the
# computation, including inside compiled package code.
.cache_run <- function(code, env, seed) {
  scope <- new.env(parent = env)
  if (!is.null(seed)) {
    kinds <- RNGkind()
    set.seed(seed)
    on.exit(.cache_reseed(seed, kinds), add = TRUE)
    value <- eval(code, envir = scope)
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

# Restore with a copy fallback so a platform-specific rename failure does not
# discard the only preserved bytes. If both operations fail, leave the backup
# in place rather than deleting the recoverable copy.
.cache_rename <- function(from, to) {
  file.rename(from, to)
}

.cache_restore_backup <- function(backup, target) {
  if (is.null(backup) || !file.exists(backup)) return(invisible(TRUE))
  restored <- suppressWarnings(.cache_rename(backup, target))
  if (!isTRUE(restored)) {
    restored <- suppressWarnings(file.copy(backup, target, overwrite = TRUE))
    if (isTRUE(restored)) unlink(backup)
  }
  invisible(isTRUE(restored))
}

.cache_warn_restore_failure <- function(backup, target) {
  warn <- getOption("warn")
  if (is.numeric(warn) && length(warn) == 1L && !is.na(warn) && warn >= 2L) {
    old <- options(warn = 1L)
    on.exit(options(old), add = TRUE)
  }
  warning("cache_fit(): could not restore ", target,
          "; the recoverable backup remains at ", backup, ".",
          call. = FALSE)
}

# Save beside the target, capture provenance, preserve the existing cache pair,
# move the completed cache into place, then publish the sidecar against those
# exact bytes. The prior sidecar is hidden before the new cache becomes visible
# so no observer can pair the new cache with stale provenance. An unwind for any
# reason attempts to restore the pair and warns where it retains any backup;
# this includes interrupts, not only errors.
.cache_write <- function(record, path, key, dir) {
  tmp <- tempfile(
    pattern = paste0(".", tools::file_path_sans_ext(basename(path)), "-"),
    tmpdir = dirname(path), fileext = ".rds.tmp"
  )
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  saveRDS(record, tmp)
  payload <- .cache_provenance(path, key, dir)

  sidecar <- if (is.null(payload)) NULL else provenance_path(path)
  if (!is.null(sidecar) && dir.exists(sidecar)) {
    stop("cache_fit(): provenance sidecar path is a directory: ", sidecar,
         call. = FALSE)
  }

  backup <- NULL
  sidecar_backup <- NULL
  cache_moved <- FALSE
  sidecar_moved <- FALSE
  cache_replaced <- FALSE
  sidecar_replacement_started <- FALSE
  committed <- FALSE
  on.exit({
    if (!committed) {
      restore_failures <- list()
      if (cache_replaced && file.exists(path) && !dir.exists(path)) unlink(path)
      if (sidecar_replacement_started && file.exists(sidecar) &&
            !dir.exists(sidecar)) {
        unlink(sidecar)
      }
      if (cache_moved && !isTRUE(.cache_restore_backup(backup, path))) {
        restore_failures[[length(restore_failures) + 1L]] <- list(
          backup = backup,
          target = path
        )
      }
      if (sidecar_moved &&
            !isTRUE(.cache_restore_backup(sidecar_backup, sidecar))) {
        restore_failures[[length(restore_failures) + 1L]] <- list(
          backup = sidecar_backup,
          target = sidecar
        )
      }
      for (failure in restore_failures) {
        .cache_warn_restore_failure(failure$backup, failure$target)
      }
    } else {
      if (cache_moved && file.exists(backup)) unlink(backup)
      if (sidecar_moved && file.exists(sidecar_backup)) {
        unlink(sidecar_backup)
      }
    }
  }, add = TRUE)

  if (!is.null(sidecar) && file.exists(sidecar)) {
    sidecar_backup <- tempfile(
      pattern = paste0(".", basename(sidecar), "-backup-"),
      tmpdir = dirname(sidecar), fileext = ".tmp"
    )
    sidecar_moved <- isTRUE(.cache_rename(sidecar, sidecar_backup))
    if (!sidecar_moved) {
      stop("cache_fit(): could not preserve the existing provenance sidecar at ",
           sidecar, call. = FALSE)
    }
  }
  if (file.exists(path) && !dir.exists(path)) {
    backup <- tempfile(
      pattern = paste0(".", basename(path), "-backup-"),
      tmpdir = dirname(path), fileext = ".tmp"
    )
    cache_moved <- isTRUE(.cache_rename(path, backup))
    if (!cache_moved) {
      stop("cache_fit(): could not preserve the existing cached object at ",
           path, call. = FALSE)
    }
  }
  cache_replaced <- isTRUE(.cache_rename(tmp, path))
  if (!cache_replaced) {
    stop("cache_fit(): could not move the cached object into place at ",
         path, call. = FALSE)
  }

  tryCatch({
    if (!is.null(payload)) {
      sidecar_replacement_started <- TRUE
      publish_provenance(path, payload)
    }
  }, error = function(e) {
    .cache_provenance_rethrow(e, path)
  })
  committed <- TRUE
  invisible(path)
}

# Re-raises `e` as the same condition, classes included, with the message
# prefixed so the failure is traceable to cache_fit() rather than discarded as
# an unattributed study_root()/study_config()/provenance error.
.cache_provenance_rethrow <- function(e, path) {
  cnd <- e
  cnd$message <- paste0(
    "cache_fit(): provenance could not be recorded for '",
    basename(path), "'; the computed result was NOT kept.\n",
    conditionMessage(e)
  )
  stop(cnd)
}

# Captures provenance when `dir` lies inside a study. Only "no _study.yml
# found" FROM study_root() means "not a study"; every other failure -
# including a study_config() or capture_provenance() error whose message
# happens to contain that same phrase - propagates as an error naming
# cache_fit(), and because this runs before the rename, a failure leaves
# nothing cached. The escape is scoped to the study_root() call alone so a
# later, genuine failure in study_config()/capture_provenance() can never be
# mistaken for "not a study" and silently swallowed. The text match on "no
# _study.yml found" is a coupling to study_config()'s own stop() in
# R/study_config.R, which study_root() calls internally (it raises a plain,
# unclassed condition); replace it if that ever gains a class.
.cache_provenance <- function(path, key, dir) {
  root <- tryCatch(study_root(dir), error = function(e) {
    if (grepl("no _study.yml found", conditionMessage(e), fixed = TRUE)) {
      return(NULL)
    }
    .cache_provenance_rethrow(e, path)
  })
  if (is.null(root)) return(invisible(NULL))

  tryCatch({
    # require_data = FALSE matches the leniency of study_root()'s own
    # detection above; study_config()'s default (require_data = TRUE) would
    # otherwise apply a stricter read here than what "is this a study" just
    # decided.
    cfg <- study_config(root, require_data = FALSE)
    capture_provenance(
      job = tools::file_path_sans_ext(basename(path)),
      data = list(),
      extra = list(cache_key = key),
      cfg = cfg
    )
  }, error = function(e) .cache_provenance_rethrow(e, path))
}
