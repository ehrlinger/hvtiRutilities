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

# Whether a call was written against a previous signature: it names a renamed
# argument, or passes at least `positional` arguments unnamed, which the old
# order would read differently.
.hvti_old_call <- function(cl, env, renamed = character(), positional = Inf) {
  nm <- names(.hvti_call_args(cl, env))
  any(nm %in% renamed) || sum(!nzchar(nm)) >= positional
}

# Re-issue an old-signature call through the new one: match it against `old`,
# a function with the previous formals, rename what was renamed, and call `fn`
# with every argument named so the new order cannot misread it.
.hvti_recall <- function(cl, env, old, fn, rename = character()) {
  args <- as.list(match.call(old, cl, expand.dots = TRUE, envir = env))[-1L]
  hit <- names(args) %in% names(rename)
  names(args)[hit] <- rename[names(args)[hit]]
  eval(as.call(c(list(fn), args)), env)
}

# register_data() and declare_data() took `root` first until 2026-11. A call
# whose first unnamed argument is an existing directory, and which does not
# name `root`, was written in that order: a data file is never a directory.
.hvti_root_first <- function(cl, env) {
  args <- .hvti_call_args(cl, env)
  nm <- names(args)
  if ("root" %in% nm) return(FALSE)
  first <- which(!nzchar(nm))[1L]
  if (is.na(first)) return(FALSE)
  value <- tryCatch(eval(args[[first]], env), error = function(e) NULL)
  is.character(value) && length(value) == 1L && !is.na(value) && dir.exists(value)
}
