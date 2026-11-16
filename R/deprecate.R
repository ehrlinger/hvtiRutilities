# The family conventions from the hvtiR API rubric (2026-11-16) that need code:
# quiet mode, and renames that ship as one-release deprecations.

# Quiet mode. Every informational message() goes through it; warnings and
# errors never do. A function's own `verbose` argument, given explicitly, wins
# over the option, so callers test it before calling this.
.hvti_inform <- function(...) {
  if (!isTRUE(getOption("hvti.quiet"))) message(...)
  invisible()
}

# A deprecation notice, once per session per key. The class carries the
# package's own name for callers to catch, and deprecatedWarning, which
# .Deprecated() uses and which the notices here carried before 2026-11.
.hvti_deprecation <- function(message) {
  structure(
    class = c("hvtiRutilities_deprecated", "deprecatedWarning", "warning", "condition"),
    list(message = message, call = NULL)
  )
}

.hvti_deprecate <- function(key, ...) {
  if (isTRUE(.hvti_deprecated[[key]])) return(invisible())
  assign(key, TRUE, envir = .hvti_deprecated)
  warning(.hvti_deprecation(paste0(...)))
}

# The arguments of `cl` as written, with any `...` expanded from `env`.
.hvti_call_args <- function(cl, env) {
  args <- as.list(match.call(function(...) NULL, cl, expand.dots = TRUE, envir = env))[-1L]
  if (is.null(names(args))) names(args) <- rep("", length(args))
  args
}

# A renamed argument given under both names: reading either one would drop
# the other without a word, so the call is refused.
.hvti_refuse_both <- function(caller, old, new) {
  stop(caller, "(): `", old, " =` and `", new, " =` are the same argument, under its old and new names. ",
       "Give only `", new, " =`.", call. = FALSE)
}

# Whether a call names an argument that was renamed.
.hvti_old_call <- function(cl, env, renamed) {
  any(names(.hvti_call_args(cl, env)) %in% renamed)
}

# The formals of `fn` that the call's unnamed arguments bind to, in formal
# order, found by matching the call with a marker in place of each unnamed
# argument. Nothing is evaluated.
.hvti_positional_formals <- function(cl, env, fn) {
  args <- .hvti_call_args(cl, env)
  pos <- which(!nzchar(names(args)))
  if (!length(pos)) return(character())
  marks <- paste0(".hvti_positional_", pos)
  args[pos] <- lapply(marks, as.name)
  matched <- tryCatch(as.list(match.call(fn, as.call(c(cl[[1L]], args))))[-1L],
                      error = function(e) list())
  hit <- vapply(matched, function(a) is.name(a) && as.character(a) %in% marks, logical(1))
  names(matched)[hit]
}

# The survival interval arguments were (event, time) until 2026-11 and are now
# (time, event). Two unnamed arguments mean opposite things in the two orders,
# whether or not the data is named, so such a call is refused on every call
# rather than read in either order: a cohort gate must not count the wrong
# column without saying so.
.hvti_refuse_ambiguous_order <- function(cl, env, fn, caller, signature, pair = c("time_col", "event_col")) {
  if (all(pair %in% .hvti_positional_formals(cl, env, fn))) {
    stop(caller, "(): pass `", pair[[1L]], " =` and `", pair[[2L]], " =` by name. The arguments are now ", signature,
         ", as in survival::Surv(), and were event before time until 2026-11, so two unnamed ",
         "arguments cannot be read safely.", call. = FALSE)
  }
}

# Re-issue an old-signature call through the new one: match it against `old`,
# a function with the previous formals, rename what was renamed, substitute
# any argument already evaluated (`forced`, by old formal name) so it is not
# evaluated again, and call `fn` with every argument named so the new order
# cannot misread it. With `old = NULL` the arguments stay as written, in
# place, with only the renamed names changed, so unnamed ones bind against
# `fn`'s own order: for a rename that kept its position.
.hvti_recall <- function(cl, env, old, fn, rename = character(), forced = list()) {
  args <- if (is.null(old)) .hvti_call_args(cl, env) else as.list(match.call(old, cl, expand.dots = TRUE, envir = env))[-1L]
  args[names(forced)] <- forced
  hit <- names(args) %in% names(rename)
  names(args)[hit] <- rename[names(args)[hit]]
  eval(as.call(c(list(fn), args)), env)
}

# register_data() and declare_data() took `root` first until 2026-11. A call
# whose FIRST argument is unnamed and an existing directory, and which does not
# name `root`, was written in that order: a data file is never a directory,
# and the old order put `root` first, as hvtiRdatabuild and hvtiRtemplates
# still write `register_data(root, file = ...)`. A call that opens with a named
# argument, such as `register_data(file = "x.csv", "valve")`, is read in the
# new order, so an unnamed `dataset` or `key_cols` that happens to name a
# directory is never taken for the root.
# The argument is read by forcing the formal of `fn` it bound to, in `fenv`
# (the caller's own frame), so it is evaluated exactly once however the call
# is then read: a stateful root expression cannot name one study here and
# another in the write. Returns the root, or NULL for a new-order call.
.hvti_root_first <- function(cl, env, fn, fenv) {
  if ("root" %in% names(.hvti_call_args(cl, env))) return(NULL)
  bound <- .hvti_positional_formals(cl, env, fn)
  if (!length(bound) || nzchar(names(.hvti_call_args(cl, env))[[1L]])) return(NULL)
  value <- get(bound[[1L]], envir = fenv)
  if (is.character(value) && length(value) == 1L && !is.na(value) && dir.exists(value)) value else NULL
}
