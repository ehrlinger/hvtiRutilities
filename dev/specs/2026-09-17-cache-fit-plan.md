# `cache_fit()` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `cache_fit()` to hvtiRutilities: a strict cache for expensive computations, keyed on the code, the values it reads, package versions and seed.

**Architecture:** Two source files. `R/cache_key.R` builds and compares keys without evaluating anything. `R/cache_fit.R` resolves the `code` argument, decides hit / miss / stale / unkeyed, runs the computation in a child environment (with optional seed), writes atomically, and records provenance when inside a study. The `.rds` holds a record `list(hvtiRutilities_cache = 1L, key, value)`; the returned value carries the key as attribute `hvtiRutilities_cache_key`.

**Tech Stack:** R (>= 4.1.0), digest (xxhash64), withr (`with_seed`), testthat 3e; existing `study_dir()`, `study_root()`, `study_config()`, `record_provenance()`.

**Spec:** `dev/specs/2026-09-17-cache-fit-design.md`

## Global Constraints

- Work on branch `feat/cache-fit` from `origin/main`, in a worktree: `git -C ~/Documents/GitHub/hvtiRutilities worktree add -b feat/cache-fit ../hvtiRutilities-feat-cache-fit origin/main`. Never commit to `main`.
- Exported API exactly: `cache_fit(name, code, seed = NULL, dir = study_dir("estimates"), refit = FALSE)`.
- Condition classes exactly: `hvtiRutilities_stale_cache`, `hvtiRutilities_unkeyed_cache` (errors), `hvtiRutilities_nonreproducible_fit` (warning).
- Key fields compared: `code`, `inputs`, `packages`, `seed`. Recorded but not compared: `reproducible`, `r_version`.
- Never call `set.seed()` on the global stream in package code; tests use `withr::local_seed()`.
- No `<<-` in package code.
- Tests run in `withr::local_tempdir()`; forests use `ntree <= 50`; set `rf.cores`/`mc.cores` to 1 in forest tests.
- Done means: `devtools::document()` output committed, `devtools::test()` passes, `devtools::check()` 0 errors / 0 warnings / 0 notes.
- Version: do **not** bump DESCRIPTION (a release branch is in flight); add the NEWS entry under `# hvtiRutilities (unreleased)`.
- No em dashes in prose written into the repo.

## Clarifications of the spec made while planning

These resolve ambiguities; they are consistent with the approved design.

1. **Attached packages.** The spec says the key includes "versions of attached packages (for bare function names)". Implemented precisely: for each bare function name called in the code, the package whose namespace defines it. Merely attaching an unrelated package does not change the key. Packages with `Priority: base` (base, stats, utils, ...) are excluded, like `r_version`, so an R patch upgrade does not force refits.
2. **Where the code runs.** The computation is evaluated in a new child environment of the caller, so names assigned inside a `{}` block do not leak. Otherwise a cache hit and a miss would leave different variables behind.
3. **Provenance timing and scope.** Provenance is written after the temporary file is saved and **before** it is renamed into place, so a provenance failure leaves nothing cached. It is attempted when `dir` lies inside a study (a `_study.yml` is found walking up). Only the "no `_study.yml` found" error means "not a study"; any other error from `study_root()`, `study_config()` or `record_provenance()` propagates.
4. **Formulas and language values** among the inputs are digested from their deparsed text with attributes removed, because a formula's environment does not serialise stably.
5. **A computation returning `NULL`** is an error: there is nothing to attach a key to.
6. An `expression()` object holding several expressions is treated as a `{}` block.

## File Structure

| File | Responsibility |
|---|---|
| Create `R/cache_key.R` | internal: code text, assigned names, call heads, input digests, package versions, key, key diff |
| Create `R/cache_fit.R` | exported `cache_fit()` + roxygen; internal: argument checks, code resolution, run with RNG handling, conditions, atomic write, provenance |
| Create `tests/testthat/test-cache_key.R` | key construction and comparison |
| Create `tests/testthat/test-cache_fit.R` | resolution, hit/miss/stale/unkeyed/refit, writes, chaining, RNG, provenance, real fits |
| Modify `DESCRIPTION` | `withr` Suggests to Imports; add `mice` to Suggests |
| Modify `_pkgdown.yml` | new reference section "Caching" |
| Modify `NEWS.md` | feature entry |
| Generated `NAMESPACE`, `man/cache_fit.Rd` | via `devtools::document()` |

---

### Task 1: Key construction and comparison (`R/cache_key.R`)

**Files:**
- Create: `R/cache_key.R`
- Test: `tests/testthat/test-cache_key.R`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces (all internal, used by Task 2):
  - `.cache_code_text(code) -> character(1)`
  - `.cache_assigned(code) -> character`
  - `.cache_heads(code) -> list(ns = character, ns_fn = character, bare = character)`
  - `.cache_digest(value) -> character(1)`
  - `.cache_inputs(code, env) -> named list of character(1)`
  - `.cache_packages(code, env) -> named list of character(1)`
  - `.cache_key(code, env, seed) -> list(code, inputs, packages, seed, reproducible = TRUE, r_version)`
  - `.cache_key_fields` (character: `c("code", "inputs", "packages", "seed")`)
  - `.cache_key_diff(old, new) -> character` (one line per differing entry; `character(0)` when equal)

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-cache_key.R`:

```r
test_that("code text ignores formatting and comments", {
  a <- parse(text = "{\n  # a comment\n  sum( x,y )\n}", keep.source = TRUE)[[1]]
  b <- quote({
    sum(x, y)
  })
  expect_identical(hvtiRutilities:::.cache_code_text(a),
                   hvtiRutilities:::.cache_code_text(b))
})

test_that("assigned names are found, including inside nested calls", {
  code <- quote({
    fml <- y ~ x
    dta = subset(d, x > 1)
    f(g(h <- 1), d[, 1])
  })
  expect_setequal(hvtiRutilities:::.cache_assigned(code), c("fml", "dta", "h"))
})

test_that("call heads separate namespaced and bare functions", {
  heads <- hvtiRutilities:::.cache_heads(quote(randomForestSRC::rfsrc(f(x), data = d)))
  expect_identical(heads$ns, "randomForestSRC")
  expect_identical(heads$ns_fn, "rfsrc")
  expect_true("f" %in% heads$bare)
})

test_that("inputs digest free variables and skip locals, functions and unknown names", {
  d <- data.frame(x = 1:3)
  helper <- function(z) z
  code <- quote({
    local_copy <- d
    helper(nrow(local_copy) + not_a_variable)
  })
  inputs <- hvtiRutilities:::.cache_inputs(code, environment())
  expect_identical(names(inputs), "d")
  expect_type(inputs$d, "character")
})

test_that("changing a value or a column type changes the input digest", {
  env <- new.env()
  env$d <- data.frame(x = 1:3)
  code <- quote(sum(d$x))
  k1 <- hvtiRutilities:::.cache_inputs(code, env)$d
  env$d$x[2] <- 9L
  k2 <- hvtiRutilities:::.cache_inputs(code, env)$d
  env$d$x <- as.numeric(env$d$x)
  k3 <- hvtiRutilities:::.cache_inputs(code, env)$d
  expect_false(identical(k1, k2))
  expect_false(identical(k2, k3))
})

test_that("a formula input digests the same whatever its environment", {
  e1 <- new.env(); e2 <- new.env()
  e1$fml <- local(y ~ x, envir = new.env())
  e2$fml <- local(y ~ x, envir = new.env())
  code <- quote(lm(fml))
  expect_identical(hvtiRutilities:::.cache_inputs(code, e1)$fml,
                   hvtiRutilities:::.cache_inputs(code, e2)$fml)
})

test_that("packages come from :: and from the namespace of bare functions, base excluded", {
  f <- digest::digest
  pk <- hvtiRutilities:::.cache_packages(quote(f(stats::median(x))), environment())
  expect_identical(names(pk), "digest")
  expect_identical(pk$digest, as.character(utils::packageVersion("digest")))

  pk2 <- hvtiRutilities:::.cache_packages(quote(jsonlite::toJSON(sum(x))), environment())
  expect_identical(names(pk2), "jsonlite")
})

test_that("identical inputs give identical keys; the seed is part of the key", {
  d <- 1:5
  k1 <- hvtiRutilities:::.cache_key(quote(sum(d)), environment(), NULL)
  k2 <- hvtiRutilities:::.cache_key(quote(sum(d)), environment(), NULL)
  k3 <- hvtiRutilities:::.cache_key(quote(sum(d)), environment(), 1L)
  expect_identical(k1, k2)
  expect_length(hvtiRutilities:::.cache_key_diff(k1, k2), 0L)
  expect_match(hvtiRutilities:::.cache_key_diff(k1, k3), "seed")
})

test_that("the diff names each changed input and package, and ignores r_version", {
  old <- list(code = "sum(d)", inputs = list(d = "aaa", e = "bbb"),
              packages = list(randomForestSRC = "3.4.5"), seed = NULL,
              reproducible = TRUE, r_version = "R 4.5.0")
  new <- old
  new$inputs$d <- "ccc"
  new$inputs$e <- NULL
  new$packages$randomForestSRC <- "3.5.0"
  new$r_version <- "R 4.5.1"
  diff <- hvtiRutilities:::.cache_key_diff(old, new)
  expect_length(diff, 3L)
  expect_match(diff, "inputs\\$d +aaa +-> +ccc", all = FALSE)
  expect_match(diff, "inputs\\$e +bbb +-> +\\(absent\\)", all = FALSE)
  expect_match(diff, "packages\\$randomForestSRC +3.4.5 +-> +3.5.0", all = FALSE)
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "cache_key")'`
Expected: FAIL, `object '.cache_code_text' not found` (and similar).

- [ ] **Step 3: Implement `R/cache_key.R`**

```r
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "cache_key")'`
Expected: PASS, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add R/cache_key.R tests/testthat/test-cache_key.R
git commit -m "feat(cache_fit): key construction and comparison" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: `cache_fit()` core (resolution, hit/miss/stale/unkeyed, writes, chaining)

**Files:**
- Create: `R/cache_fit.R`
- Modify: `DESCRIPTION` (move `withr` from Suggests to Imports)
- Test: `tests/testthat/test-cache_fit.R`

**Interfaces:**
- Consumes: `.cache_key()`, `.cache_key_diff()` from Task 1.
- Produces: exported `cache_fit(name, code, seed = NULL, dir = study_dir("estimates"), refit = FALSE)`; internal `.cache_run(code, env, seed) -> list(value, reproducible)` (Task 3 extends its RNG branch); internal `.cache_provenance(path, key, dir)` (a no-op stub here, filled in Task 4).

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-cache_fit.R`:

```r
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "cache_fit")'`
Expected: FAIL, `could not find function "cache_fit"`.

- [ ] **Step 3: Move `withr` to Imports**

In `DESCRIPTION`, delete the line `    withr,` from `Suggests:` and add it to `Imports:` so the block reads:

```
Imports:
    digest,
    dplyr,
    haven,
    jsonlite,
    labelled,
    readxl,
    tools,
    utils,
    withr,
    yaml
```

- [ ] **Step 4: Implement `R/cache_fit.R`**

```r
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
#' The code runs in a new environment whose parent is the caller's, so names
#' assigned inside a block do not appear in the caller.
#'
#' The key digests each free variable of the code: each name it reads, less
#' names it assigns. Values read indirectly (inside the body of a function it
#' calls, or through \code{get()}) are not seen; pass such values into the code
#' as arguments.
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
#' @param refit Logical(1). \code{TRUE} recomputes and overwrites a stale or
#'   unkeyed file.
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
  .cache_check_args(name, seed, refit)
  if (!is.null(seed)) seed <- as.integer(seed)
  code <- .cache_resolve(expr, env)

  if (!dir.exists(dir)) {
    stop("cache_fit(): directory does not exist: ", dir, call. = FALSE)
  }
  path <- file.path(dir, paste0(name, ".rds"))
  key  <- .cache_key(code, env, seed)

  if (file.exists(path)) {
    stored <- readRDS(path)
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

.cache_check_args <- function(name, seed, refit) {
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

# Runs the code in a child scope of the caller. Task 3 adds the seed and RNG
# detection; until then every run reports reproducible = TRUE.
.cache_run <- function(code, env, seed) {
  scope <- new.env(parent = env)
  list(value = eval(code, envir = scope), reproducible = TRUE)
}

.cache_abort <- function(kind, name, path, diff = character(0)) {
  msg <- if (identical(kind, "stale")) {
    paste0("Cached object '", name, "' is stale (", path, "):\n",
           paste(diff, collapse = "\n"),
           "\nRecompute with refit = TRUE, or restore the inputs it was ",
           "built from.")
  } else {
    paste0("Cached object '", name, "' has no cache key (", path, ").\n",
           "It was not written by cache_fit(), so it cannot be checked. ",
           "Recompute with refit = TRUE.")
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

# Filled in by Task 4.
.cache_provenance <- function(path, key, dir) {
  invisible(NULL)
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "cache_")'`
Expected: PASS, 0 failures (both `test-cache_key.R` and `test-cache_fit.R`).

- [ ] **Step 6: Commit**

```bash
git add DESCRIPTION NAMESPACE man/cache_fit.Rd R/cache_fit.R tests/testthat/test-cache_fit.R
git commit -m "feat(cache_fit): strict call-keyed cache with atomic writes" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Seeds and global RNG detection

**Files:**
- Modify: `R/cache_fit.R` (replace `.cache_run`)
- Test: `tests/testthat/test-cache_fit.R` (append)

**Interfaces:**
- Consumes: `cache_fit()`, `.cache_run(code, env, seed)` signature from Task 2.
- Produces: `.cache_run()` returning `reproducible = FALSE` when the global RNG state changed and `seed` is `NULL`.

- [ ] **Step 1: Append the failing tests**

```r
test_that("a seed reproduces the result and leaves the global stream alone", {
  dir <- withr::local_tempdir()
  withr::local_seed(1)
  n <- 5
  before <- get(".Random.seed", envir = globalenv())
  a <- cache_fit("r1", stats::runif(n), seed = 42, dir = dir)
  expect_identical(get(".Random.seed", envir = globalenv()), before)
  b <- cache_fit("r2", stats::runif(n), seed = 42, dir = dir)
  expect_identical(as.vector(a), as.vector(b))
  expect_true(attr(a, "hvtiRutilities_cache_key")$reproducible)
})

test_that("RNG use without a seed warns and is recorded as not reproducible", {
  dir <- withr::local_tempdir()
  withr::local_seed(1)
  n <- 5
  expect_warning(x <- cache_fit("r3", stats::runif(n), dir = dir),
                 class = "hvtiRutilities_nonreproducible_fit")
  expect_false(attr(x, "hvtiRutilities_cache_key")$reproducible)
  expect_false(readRDS(file.path(dir, "r3.rds"))$key$reproducible)
})

test_that("a computation that draws no random numbers does not warn", {
  dir <- withr::local_tempdir()
  withr::local_seed(1)
  expect_no_warning(cache_fit("r4", sum(1:3), dir = dir))
})

test_that("changing the seed makes the cache stale", {
  dir <- withr::local_tempdir()
  n <- 5
  cache_fit("r5", stats::runif(n), seed = 1, dir = dir)
  err <- expect_error(cache_fit("r5", stats::runif(n), seed = 2, dir = dir),
                      class = "hvtiRutilities_stale_cache")
  expect_match(conditionMessage(err), "seed")
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "cache_fit")'`
Expected: FAIL on "RNG use without a seed warns" (no warning raised) and "a seed reproduces" (global stream changed).

- [ ] **Step 3: Replace `.cache_run` in `R/cache_fit.R`**

```r
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "cache_")'`
Expected: PASS, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add R/cache_fit.R tests/testthat/test-cache_fit.R
git commit -m "feat(cache_fit): seed argument and global RNG detection" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Provenance, real fits, documentation, release checks

**Files:**
- Modify: `R/cache_fit.R` (replace `.cache_provenance`)
- Modify: `DESCRIPTION` (add `mice` to Suggests)
- Modify: `_pkgdown.yml`, `NEWS.md`
- Test: `tests/testthat/test-cache_fit.R` (append)

**Interfaces:**
- Consumes: `cache_fit()`, `.cache_write()` calling `.cache_provenance(path, key, dir)` before the rename (Task 2); `study_root()`, `study_config()`, `record_provenance()`, `make_study_fixture()` (existing, `tests/testthat/helper-study.R`).
- Produces: sidecar `<dir>/<name>.provenance.json` with field `cache_key`.

- [ ] **Step 1: Append the failing tests**

```r
test_that("inside a study the default dir is used and provenance carries the key", {
  root <- make_study_fixture(withr::local_tempdir())
  dir.create(file.path(root, "estimates"))
  withr::local_dir(root)
  d <- 1:10
  out <- cache_fit("s", sum(d))
  expect_true(file.exists(file.path(root, "estimates", "s.rds")))
  side <- file.path(root, "estimates", "s.provenance.json")
  expect_true(file.exists(side))
  rec <- jsonlite::read_json(side)
  expect_identical(rec$cache_key$inputs$d,
                   attr(out, "hvtiRutilities_cache_key")$inputs$d)
})

test_that("outside a study no sidecar is written", {
  dir <- withr::local_tempdir()
  cache_fit("s", sum(1:3), dir = dir)
  expect_identical(list.files(dir, all.files = TRUE, no.. = TRUE), "s.rds")
})

test_that("a provenance failure inside a study leaves nothing cached", {
  root <- make_study_fixture(withr::local_tempdir(), write_data = FALSE)
  dir.create(file.path(root, "estimates"))
  expect_error(cache_fit("s", sum(1:3), dir = file.path(root, "estimates")))
  expect_length(list.files(file.path(root, "estimates"), all.files = TRUE,
                           no.. = TRUE), 0L)
})

test_that("a survival forest round-trips and records its package version", {
  skip_if_not_installed("randomForestSRC")
  withr::local_options(rf.cores = 1L, mc.cores = 1L)
  dir <- withr::local_tempdir()
  utils::data("veteran", package = "randomForestSRC", envir = environment())
  fit <- cache_fit(
    "vet-rfs",
    randomForestSRC::rfsrc(Surv(time, status) ~ ., data = veteran,
                           ntree = 50, seed = -1L),
    dir = dir
  )
  direct <- randomForestSRC::rfsrc(Surv(time, status) ~ ., data = veteran,
                                   ntree = 50, seed = -1L)
  expect_equal(fit$predicted.oob, direct$predicted.oob)
  expect_message(
    again <- cache_fit(
      "vet-rfs",
      randomForestSRC::rfsrc(Surv(time, status) ~ ., data = veteran,
                             ntree = 50, seed = -1L),
      dir = dir
    ),
    "loaded"
  )
  expect_equal(again$predicted.oob, fit$predicted.oob)
  expect_identical(attr(fit, "hvtiRutilities_cache_key")$packages$randomForestSRC,
                   as.character(utils::packageVersion("randomForestSRC")))
})

test_that("a multiple imputation round-trips with a seed", {
  skip_if_not_installed("mice")
  dir <- withr::local_tempdir()
  aq <- datasets::airquality[1:40, 1:4]
  imp <- cache_fit("aq-mice", mice::mice(aq, m = 2, printFlag = FALSE),
                   seed = 7, dir = dir)
  expect_s3_class(imp, "mids")
  expect_message(
    again <- cache_fit("aq-mice", mice::mice(aq, m = 2, printFlag = FALSE),
                       seed = 7, dir = dir),
    "loaded"
  )
  expect_equal(mice::complete(again), mice::complete(imp))
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "cache_fit")'`
Expected: FAIL on "provenance carries the key" (no sidecar) and "a provenance failure ... leaves nothing cached" (no error). The provenance-failure test assumes `study_config(root)` (with `require_data = TRUE`) errors when the fixture has no built dataset; confirm that before implementing, and if it does not, make the fixture fail another way (for example `make_study_fixture(dir, omit = "cohort")`, which `record_provenance()` rejects). The forest and mice tests may already pass or skip.

- [ ] **Step 3: Replace `.cache_provenance` in `R/cache_fit.R`**

```r
# Records provenance when `dir` lies inside a study. Only "no _study.yml
# found" means "not a study"; every other failure propagates, and because this
# runs before the rename, a failure leaves nothing cached.
.cache_provenance <- function(path, key, dir) {
  root <- tryCatch(
    study_root(dir),
    error = function(e) {
      if (grepl("no _study.yml found", conditionMessage(e), fixed = TRUE)) {
        return(NULL)
      }
      stop(e)
    }
  )
  if (is.null(root)) return(invisible(NULL))
  record_provenance(path, extra = list(cache_key = key),
                    cfg = study_config(root))
}
```

- [ ] **Step 4: Add `mice` to Suggests**

In `DESCRIPTION` `Suggests:`, insert `    mice,` after `    knitr,` (alphabetical).

- [ ] **Step 5: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "cache_")'`
Expected: PASS, 0 failures; forest and mice tests pass (not skipped) where those packages are installed. Report any skips.

- [ ] **Step 6: Add the pkgdown section**

In `_pkgdown.yml`, directly after the `Provenance` section (after its `  - provenance_path` line), insert:

```yaml

- title: Caching
  desc: Compute expensive results once and reload them only while their inputs are unchanged
  contents:
  - cache_fit
```

- [ ] **Step 7: Add the NEWS entry**

In `NEWS.md`, directly under `## New features` (the first one, under `# hvtiRutilities (unreleased)`), insert:

```markdown
* **`cache_fit()` caches expensive computations strictly.** A random forest,
  varPro fit, imputation, hazard model or partial dependence grid runs once and
  is reloaded on later renders only while its code, every outside value it
  reads, its packages' versions and its seed are unchanged. Anything else stops
  with an error of class `hvtiRutilities_stale_cache` that lists what changed;
  `refit = TRUE` recomputes. Code is written inline, as a `{}` block, or passed
  as a quoted call. `seed =` runs the computation under `withr::with_seed()`;
  random number use without a seed is cached with a warning and recorded as not
  reproducible. Writes are atomic, and inside a study a provenance sidecar
  carries the key. `withr` moves from Suggests to Imports.

```

- [ ] **Step 8: Full verification**

Run: `Rscript -e 'devtools::document(); devtools::test()'`
Expected: all tests pass, no failures (report the skip count).

Run: `Rscript -e 'devtools::check(args = "--as-cran")'`
Expected: `0 errors ✔ | 0 warnings ✔ | 0 notes ✔`. If `r_dir_impurities()`-style or lint checks run in CI, run them locally too: `Rscript -e 'lintr::lint_package()'` and fix any findings in the new files only.

- [ ] **Step 9: Commit and open the PR**

```bash
git add DESCRIPTION NAMESPACE man/cache_fit.Rd R/cache_fit.R tests/testthat/test-cache_fit.R _pkgdown.yml NEWS.md
git commit -m "feat(cache_fit): provenance, docs and real-fit tests" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
git push -u origin feat/cache-fit
gh pr create --base main --title "feat: cache_fit(), a strict call-keyed cache for expensive computations" --body "Implements dev/specs/2026-09-17-cache-fit-design.md per dev/specs/2026-09-17-cache-fit-plan.md.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

Do not merge; John merges.
