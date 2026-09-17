# Keys for cache_fit(). A key describes a computation without running it: the
# code, a digest of every outside value the code reads, the versions of the
# packages its functions come from, and the seed. Two keys that agree on
# .cache_key_fields describe the same computation.

.cache_key_fields <- c("code", "inputs", "packages", "seed")

# Deparsed code. Deparsing the parsed call normalises whitespace; leaving out
# "showAttributes" drops srcrefs, so comments and layout never reach the key.
.cache_code_text <- function(code) {
  paste(deparse(code, width.cutoff = 500L,
                control = c("keepNA", "keepInteger", "niceNames")),
        collapse = "\n")
}

# TRUE for the empty symbol that stands in for a missing argument, as in
# d[, 1]. It must be tested inline: binding it to a variable and reading the
# variable is an error.
.cache_is_empty_arg <- function(code, i) {
  is.symbol(code[[i]]) && !nzchar(as.character(code[[i]]))
}

# Names assigned inside the code. They are derived from the free variables,
# which are digested, so they are not digested themselves.
.cache_assigned <- function(code) {
  if (!is.call(code)) return(character(0))
  head <- code[[1L]]
  here <- character(0)
  if (is.symbol(head) && as.character(head) %in% c("<-", "=", "<<-") &&
        length(code) >= 2L && is.symbol(code[[2L]])) {
    here <- as.character(code[[2L]])
  }
  kids <- character(0)
  for (i in seq_along(code)[-1L]) {
    if (.cache_is_empty_arg(code, i)) next
    kids <- c(kids, .cache_assigned(code[[i]]))
  }
  unique(c(here, kids))
}

# Function names in call position: pkg::fn heads (package and function) and
# bare heads.
.cache_heads <- function(code) {
  out <- list(ns = character(0), ns_fn = character(0), bare = character(0))
  if (!is.call(code)) return(out)
  head <- code[[1L]]
  if (is.call(head) && is.symbol(head[[1L]]) &&
        as.character(head[[1L]]) %in% c("::", ":::")) {
    out$ns    <- as.character(head[[2L]])
    out$ns_fn <- as.character(head[[3L]])
  } else if (is.symbol(head)) {
    out$bare <- as.character(head)
  }
  for (i in seq_along(code)) {
    if (.cache_is_empty_arg(code, i)) next
    sub <- .cache_heads(code[[i]])
    out$ns    <- c(out$ns, sub$ns)
    out$ns_fn <- c(out$ns_fn, sub$ns_fn)
    out$bare  <- c(out$bare, sub$bare)
  }
  lapply(out, unique)
}

# Digest of one input. A formula carries its environment, which does not
# serialise stably, so formulas and other language objects are digested from
# their text.
.cache_digest <- function(value) {
  if (inherits(value, "formula") || is.language(value)) {
    attributes(value) <- NULL
    value <- .cache_code_text(value)
  }
  digest::digest(value, algo = "xxhash64")
}

# Digests of the free variables: every name the code reads, less names it
# assigns and names that are part of pkg::fn. Names that do not resolve
# (column names under non-standard evaluation) and functions (covered by
# .cache_packages) are skipped.
.cache_inputs <- function(code, env) {
  heads <- .cache_heads(code)
  vars  <- setdiff(all.vars(code),
                   c(.cache_assigned(code), heads$ns, heads$ns_fn))
  out <- list()
  for (v in sort(vars)) {
    if (!exists(v, envir = env, inherits = TRUE)) next
    value <- get(v, envir = env, inherits = TRUE)
    if (is.function(value)) next
    out[[v]] <- .cache_digest(value)
  }
  out
}

.cache_is_base_package <- function(pkg) {
  desc <- suppressWarnings(
    tryCatch(utils::packageDescription(pkg), error = function(e) NULL)
  )
  is.list(desc) && identical(desc$Priority, "base")
}

# Versions of the packages the code's functions come from: every pkg:: in the
# code, and for each bare function name the namespace that defines it.
# Base-priority packages are left out; R's own version is recorded separately
# and not compared.
.cache_packages <- function(code, env) {
  heads <- .cache_heads(code)
  from_bare <- character(0)
  for (fn in heads$bare) {
    f <- get0(fn, envir = env, mode = "function", inherits = TRUE)
    if (is.null(f) || is.null(environment(f))) next
    nm <- environmentName(topenv(environment(f)))
    if (nzchar(nm) && !identical(nm, "R_GlobalEnv")) {
      from_bare <- c(from_bare, nm)
    }
  }
  pkgs <- sort(unique(c(heads$ns, from_bare)))
  pkgs <- pkgs[!vapply(pkgs, .cache_is_base_package, logical(1))]
  out <- list()
  for (p in pkgs) {
    out[[p]] <- tryCatch(as.character(utils::packageVersion(p)),
                         error = function(e) NA_character_)
  }
  out
}

.cache_key <- function(code, env, seed) {
  list(
    code         = .cache_code_text(code),
    inputs       = .cache_inputs(code, env),
    packages     = .cache_packages(code, env),
    seed         = seed,
    reproducible = TRUE,
    r_version    = R.version.string
  )
}

.cache_show <- function(x) {
  if (is.null(x)) return("NULL")
  s <- paste(x, collapse = " ")
  if (nchar(s) > 60L) paste0(substr(s, 1L, 57L), "...") else s
}

# One line per differing entry of the compared fields. List fields (inputs,
# packages) are compared entry by entry, so the message names the variable or
# package that changed.
.cache_key_diff <- function(old, new) {
  lines <- character(0)
  for (f in .cache_key_fields) {
    o <- old[[f]]
    n <- new[[f]]
    if (identical(o, n)) next
    if (f %in% c("inputs", "packages")) {
      for (k in sort(union(names(o), names(n)))) {
        ov <- if (k %in% names(o)) as.character(o[[k]]) else "(absent)"
        nv <- if (k %in% names(n)) as.character(n[[k]]) else "(absent)"
        if (!identical(ov, nv)) {
          lines <- c(lines, sprintf("  %s$%s  %s  ->  %s", f, k, ov, nv))
        }
      }
    } else if (identical(f, "code")) {
      lines <- c(lines, "  code  (changed)")
    } else {
      lines <- c(lines, sprintf("  %s  %s  ->  %s", f,
                                .cache_show(o), .cache_show(n)))
    }
  }
  lines
}
