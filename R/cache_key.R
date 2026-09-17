# Keys for cache_fit(). A key describes a computation without running it: the
# code, a digest of every outside value the code reads, the versions of the
# packages its functions come from, and the seed. Two keys that agree on
# .cache_key_fields describe the same computation.

.cache_key_fields <- c("code", "inputs", "packages", "seed")

# Deparsed code. Deparsing the parsed call normalises whitespace; leaving out
# "useSource" (and "showAttributes") means srcrefs are not used, so comments and
# layout never reach the key.
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

# Lexical free-variable walk used by .cache_inputs(): a name is free only at
# occurrences not covered by an enclosing binding of that name. This replaces
# a naive "assigned anywhere in the whole expression" filter, which wrongly
# hid a name from every occurrence once it was bound ANYWHERE - a lambda
# formal, a for-loop index, an assignment target - even where a particular
# occurrence was a genuine, unrelated free variable (e.g.
# `sapply(1:2, function(d) d) + sum(d)`: the lambda's `d` is bound, but the
# `sum(d)` afterwards is a real input). .cache_free_heads() below applies the
# same lexical rule to bare call heads.
#
# `bound` is the set of names currently in lexical scope. A function's
# formals are bound only inside its own body; a formal's DEFAULT expression
# is still evaluated in the enclosing scope, so its free variables are inputs
# of the enclosing scope, not shielded by the formal it defaults. A `for`
# index is bound only inside the loop body (not in the sequence expression,
# and not after the loop - a deliberate simplification of R's real
# semantics, for cache-key purposes). `<-`/`=`/`<<-` with a symbol target
# binds that name only for occurrences textually after the assignment within
# the same block (see .cache_bound_after()); a read before the assignment, in
# the same block, is a genuine free variable/input.
.cache_free_vars <- function(code, bound = character(0)) {
  if (!is.call(code)) {
    if (is.symbol(code)) {
      nm <- as.character(code)
      if (nzchar(nm) && !(nm %in% bound)) return(nm)
    }
    return(character(0))
  }

  head <- code[[1L]]

  if (is.symbol(head)) {
    hd <- as.character(head)

    if (identical(hd, "{")) {
      out <- character(0)
      cur <- bound
      for (i in seq_along(code)[-1L]) {
        stmt <- code[[i]]
        out <- c(out, .cache_free_vars(stmt, cur))
        cur <- union(cur, .cache_bound_after(stmt))
      }
      return(unique(out))
    }

    if (identical(hd, "for") && length(code) >= 4L && is.symbol(code[[2L]])) {
      idx <- as.character(code[[2L]])
      out <- .cache_free_vars(code[[3L]], bound)
      out <- c(out, .cache_free_vars(code[[4L]], union(bound, idx)))
      return(unique(out))
    }

    if (identical(hd, "function") && length(code) >= 3L) {
      fmls <- code[[2L]]
      out <- character(0)
      for (i in seq_along(fmls)) {
        if (.cache_is_empty_arg(fmls, i)) next
        if (is.language(fmls[[i]])) {
          out <- c(out, .cache_free_vars(fmls[[i]], bound))
        }
      }
      out <- c(out, .cache_free_vars(code[[3L]], union(bound, names(fmls))))
      return(unique(out))
    }

    if (hd %in% c("<-", "=", "<<-") && length(code) >= 3L &&
          is.symbol(code[[2L]]) && nzchar(as.character(code[[2L]]))) {
      return(unique(.cache_free_vars(code[[3L]], bound)))
    }

    # pkg::fn / pkg:::fn: neither symbol is a data read (the package name is
    # covered by .cache_packages(), the function name is not a variable at
    # all), so this stops here regardless of where the call appears - not
    # only when it is a call head (see .cache_heads() for that case).
    if (hd %in% c("::", ":::")) return(character(0))

    # df$col / obj@slot: only the left side is a data read. The right side is
    # a name, not a variable reference (mirrors all.vars(), which does not
    # descend into it either).
    if (hd %in% c("$", "@") && length(code) >= 2L) {
      return(unique(.cache_free_vars(code[[2L]], bound)))
    }

    # Any other bare call head (f(...)): the head names a function, not a
    # data read, so it is never itself a free variable (mirrors all.vars(),
    # which likewise excludes a call head). Bare heads are separately
    # collected by .cache_heads() for the global-helper/package checks.
    out <- character(0)
    for (i in seq_along(code)[-1L]) {
      if (.cache_is_empty_arg(code, i)) next
      out <- c(out, .cache_free_vars(code[[i]], bound))
    }
    return(unique(out))
  }

  # A call-valued head: pkg::fn(...) (skip the :: call's own symbols) or
  # f(x)(y) (the head is itself a call and is walked like any other value).
  out <- character(0)
  skip_head <- is.call(head) && is.symbol(head[[1L]]) &&
    as.character(head[[1L]]) %in% c("::", ":::")
  if (!skip_head) out <- c(out, .cache_free_vars(head, bound))
  for (i in seq_along(code)[-1L]) {
    if (.cache_is_empty_arg(code, i)) next
    out <- c(out, .cache_free_vars(code[[i]], bound))
  }
  unique(out)
}

# Names a statement adds to the ENCLOSING scope once it has run, used to
# thread bindings through a `{}` block. Only `<-`/`=`/`<<-` with a symbol
# target does this; a `for`'s index and a `function`'s formals are scoped to
# their own body/formals and never leak out (see .cache_free_vars()). A
# nested `{}` block's own bindings do leak to what follows it in the same
# enclosing block, since `{` introduces no scope of its own.
.cache_bound_after <- function(code) {
  if (!is.call(code)) return(character(0))
  head <- code[[1L]]
  if (!is.symbol(head)) return(character(0))
  hd <- as.character(head)
  if (hd %in% c("<-", "=", "<<-") && length(code) >= 3L &&
        is.symbol(code[[2L]]) && nzchar(as.character(code[[2L]]))) {
    return(as.character(code[[2L]]))
  }
  if (identical(hd, "{")) {
    return(unique(unlist(lapply(as.list(code)[-1L], .cache_bound_after))))
  }
  character(0)
}

# Lexical free-call-head walk, the head analogue of .cache_free_vars(): a bare
# call head (e.g. `prep` in `prep(z)`) is free only at occurrences not covered
# by an enclosing binding of that name - the same `bound` threading as
# .cache_free_vars(), so a name bound by a lambda formal, a for index, or an
# earlier assignment in the same block shadows only the occurrences it
# actually covers, not every occurrence in the expression. Used by
# .cache_inputs() to decide which global helpers to digest; pkg::fn and
# df$col/obj@slot are excluded the same way .cache_free_vars() excludes them,
# since neither names a bare call head.
.cache_free_heads <- function(code, bound = character(0)) {
  if (!is.call(code)) return(character(0))

  head <- code[[1L]]

  if (is.symbol(head)) {
    hd <- as.character(head)

    if (identical(hd, "{")) {
      out <- character(0)
      cur <- bound
      for (i in seq_along(code)[-1L]) {
        stmt <- code[[i]]
        out <- c(out, .cache_free_heads(stmt, cur))
        cur <- union(cur, .cache_bound_after(stmt))
      }
      return(unique(out))
    }

    if (identical(hd, "for") && length(code) >= 4L && is.symbol(code[[2L]])) {
      idx <- as.character(code[[2L]])
      out <- .cache_free_heads(code[[3L]], bound)
      out <- c(out, .cache_free_heads(code[[4L]], union(bound, idx)))
      return(unique(out))
    }

    if (identical(hd, "function") && length(code) >= 3L) {
      fmls <- code[[2L]]
      out <- character(0)
      for (i in seq_along(fmls)) {
        if (.cache_is_empty_arg(fmls, i)) next
        if (is.language(fmls[[i]])) {
          out <- c(out, .cache_free_heads(fmls[[i]], bound))
        }
      }
      out <- c(out, .cache_free_heads(code[[3L]], union(bound, names(fmls))))
      return(unique(out))
    }

    if (hd %in% c("<-", "=", "<<-") && length(code) >= 3L &&
          is.symbol(code[[2L]]) && nzchar(as.character(code[[2L]]))) {
      return(unique(.cache_free_heads(code[[3L]], bound)))
    }

    if (hd %in% c("::", ":::")) return(character(0))

    if (hd %in% c("$", "@") && length(code) >= 2L) {
      return(unique(.cache_free_heads(code[[2L]], bound)))
    }

    out <- if (hd %in% bound) character(0) else hd
    for (i in seq_along(code)[-1L]) {
      if (.cache_is_empty_arg(code, i)) next
      out <- c(out, .cache_free_heads(code[[i]], bound))
    }
    return(unique(out))
  }

  # A call-valued head: pkg::fn(...) (skip the :: call's own symbols) or
  # f(x)(y) (the head is itself a call and is walked like any other value).
  out <- character(0)
  skip_head <- is.call(head) && is.symbol(head[[1L]]) &&
    as.character(head[[1L]]) %in% c("::", ":::")
  if (!skip_head) out <- c(out, .cache_free_heads(head, bound))
  for (i in seq_along(code)[-1L]) {
    if (.cache_is_empty_arg(code, i)) next
    out <- c(out, .cache_free_heads(code[[i]], bound))
  }
  unique(out)
}

# Function names in call position: pkg::fn heads (package and function) and
# bare heads.
.cache_heads <- function(code) {
  out <- list(ns = character(0), ns_fn = character(0), bare = character(0))
  if (!is.call(code)) return(out)
  head <- code[[1L]]
  handled_ns_call <- FALSE
  if (is.call(head) && is.symbol(head[[1L]]) &&
        as.character(head[[1L]]) %in% c("::", ":::")) {
    out$ns    <- as.character(head[[2L]])
    out$ns_fn <- as.character(head[[3L]])
    handled_ns_call <- TRUE
  } else if (is.symbol(head)) {
    out$bare <- as.character(head)
  }
  # Recurse into arguments. If head was a :: call, skip index 1 (don't
  # recurse into it again); for other call-valued heads like f(x)(y), recurse
  # into index 1.
  indices <- if (handled_ns_call) seq_along(code)[-1L] else seq_along(code)
  for (i in indices) {
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
# their text. serializeVersion is pinned so a session-level `serializeVersion`
# option (digest:::.getSerializeVersion() consults it) cannot change every key.
.cache_digest <- function(value) {
  if (inherits(value, "formula") || is.language(value)) {
    attributes(value) <- NULL
    value <- .cache_code_text(value)
  }
  digest::digest(value, algo = "xxhash64", serializeVersion = 2L)
}

# Deparsed body+formals of a closure defined in the global environment (the
# _common.R shape), attributes (incl. srcref) stripped so layout and comments
# do not reach the key. NULL for a package function, which .cache_packages()
# already covers by version.
.cache_global_closure_text <- function(fn) {
  if (!identical(environmentName(topenv(environment(fn))), "R_GlobalEnv")) {
    return(NULL)
  }
  attributes(fn) <- NULL
  paste(deparse(fn, width.cutoff = 500L,
                control = c("keepNA", "keepInteger", "niceNames")),
        collapse = "\n")
}

# Digests of the free variables: every name the code reads free of any
# enclosing binding (see .cache_free_vars()), less names that are part of
# pkg::fn (already excluded by the walk itself). Names that do not resolve
# (column names under non-standard evaluation) are skipped. A value carrying
# a cache key (attribute "hvtiRutilities_cache_key", attached by cache_fit())
# is digested by that key's compared fields (.cache_key_fields) instead of
# the whole key or the value itself: the key is stable by construction, so a
# downstream key does not go stale between a live upstream object and the
# detached copy readRDS() returns on a later cache hit, and does not go stale
# across an R version bump either, since r_version/reproducible (deliberately
# excluded from .cache_key_fields, see .cache_key()) are excluded here too. A
# function is digested by its body when it is user-defined (global); a
# package function is skipped here and covered by .cache_packages() instead.
.cache_inputs <- function(code, env) {
  vars <- sort(unique(.cache_free_vars(code)))
  out <- list()
  for (v in vars) {
    if (!exists(v, envir = env, inherits = TRUE)) next
    value <- get(v, envir = env, inherits = TRUE)
    if (is.function(value)) {
      txt <- .cache_global_closure_text(value)
      if (!is.null(txt)) out[[v]] <- .cache_digest(txt)
      next
    }
    cache_key <- attr(value, "hvtiRutilities_cache_key")
    out[[v]] <- if (!is.null(cache_key)) {
      .cache_digest(cache_key[.cache_key_fields])
    } else {
      .cache_digest(value)
    }
  }
  # Bare call heads (e.g. prep(z)) never appear in all.vars(), which excludes
  # function names in call position; a global helper called this way would
  # otherwise never be seen at all, by this function or by .cache_packages().
  # .cache_free_heads() does the same lexical scoping as .cache_free_vars()
  # above, so a head shadowed by a lambda formal, a for index, or an earlier
  # assignment in the same block is excluded only where that binding actually
  # covers it, not wherever else the same name is bound in the expression.
  for (fn in setdiff(.cache_free_heads(code), names(out))) {
    if (!exists(fn, envir = env, inherits = TRUE)) next
    f <- get0(fn, envir = env, mode = "function", inherits = TRUE)
    if (is.null(f)) next
    txt <- .cache_global_closure_text(f)
    if (!is.null(txt)) out[[fn]] <- .cache_digest(txt)
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
