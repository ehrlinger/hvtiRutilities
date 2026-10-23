# Would cache_fit() compute, or load?

Answers, without computing anything, whether
[`cache_fit`](https://ehrlinger.github.io/hvtiRutilities/reference/cache_fit.md)
called with the same arguments would run its computation. A job uses it
to guard a resource, memory or cores, only when a fit will actually run,
rather than refusing a session for a fit it would simply load from the
cache.

## Usage

``` r
cache_would_fit(
  name,
  code,
  seed = NULL,
  dir = study_dir("estimates"),
  refit = FALSE,
  packages = NULL
)
```

## Arguments

- name:

  Character(1). File stem; the result is stored at
  `file.path(dir, paste0(name, ".rds"))`.

- code:

  The computation: an inline call or
  [`{}`](https://rdrr.io/r/base/Paren.html) block, or a variable holding
  a quoted call.

- seed:

  `NULL` or a single whole number.

- dir:

  Character(1). An existing directory. Defaults to the study's estimates
  folder.

- refit:

  Logical(1). `TRUE` recomputes and overwrites the file only when it is
  stale or unkeyed; a valid cache is still loaded, not recomputed,
  regardless of `refit`.

- packages:

  `NULL` or a character vector of package names whose versions are added
  to the key. Use it for a package that does the work beneath a wrapper
  and so never appears in `code` itself; see Details.

## Value

`TRUE` if
[`cache_fit()`](https://ehrlinger.github.io/hvtiRutilities/reference/cache_fit.md)
with the same arguments would run `code`, `FALSE` if it would load the
cached result or stop on a stale or unkeyed file without computing.

## Details

The arguments are
[`cache_fit()`](https://ehrlinger.github.io/hvtiRutilities/reference/cache_fit.md)'s,
with the same names, order and defaults, and none is dropped: `name` and
`dir` locate the file, `code`, `seed` and `packages` make the key, and
`refit` decides what a stale or unkeyed file does. Write the call
exactly as the
[`cache_fit()`](https://ehrlinger.github.io/hvtiRutilities/reference/cache_fit.md)
call it guards, for example
`cache_would_fit("forest", rfsrc(f, data = d), seed = 1)` before
`cache_fit("forest", rfsrc(f, data = d), seed = 1)`. `code` is captured
as
[`cache_fit()`](https://ehrlinger.github.io/hvtiRutilities/reference/cache_fit.md)
captures it, by substitution, and is never evaluated: inline code and a
variable holding a [`quote`](https://rdrr.io/r/base/substitute.html)d
call both work, and an already-computed object is refused as it is
there. The same rule about wrappers applies; see
[`cache_fit`](https://ehrlinger.github.io/hvtiRutilities/reference/cache_fit.md).

The answer comes from the same internal decision
[`cache_fit()`](https://ehrlinger.github.io/hvtiRutilities/reference/cache_fit.md)
makes, not from a copy of it, so the two cannot drift apart:

- no file: `TRUE`;

- a file whose key matches: `FALSE`, whatever `refit` is, because a
  valid cache is loaded even under `refit = TRUE`;

- a stale file (the code, an input, the seed or a package version
  changed) or an unkeyed or unreadable file: `TRUE` with `refit = TRUE`,
  and `FALSE` without it.

The last case is deliberate. Without `refit`,
[`cache_fit()`](https://ehrlinger.github.io/hvtiRutilities/reference/cache_fit.md)
stops on a stale or unkeyed file before it computes anything, so nothing
will run and there is nothing to guard; the error that follows is
[`cache_fit()`](https://ehrlinger.github.io/hvtiRutilities/reference/cache_fit.md)'s
to raise, with the list of what changed. For the same reason, an
existing file under `refit = FALSE` is not read at all, since every
outcome there computes nothing.

Arguments are checked as
[`cache_fit()`](https://ehrlinger.github.io/hvtiRutilities/reference/cache_fit.md)
checks them, and a bad one raises the same error, naming
[`cache_fit()`](https://ehrlinger.github.io/hvtiRutilities/reference/cache_fit.md),
including a `dir` that does not exist. Under `refit = TRUE` an existing
file is read to compare its key, so a matching fit is read here and
again by
[`cache_fit()`](https://ehrlinger.github.io/hvtiRutilities/reference/cache_fit.md).

## See also

[`cache_fit`](https://ehrlinger.github.io/hvtiRutilities/reference/cache_fit.md)

## Examples

``` r
dir <- file.path(tempdir(), "cache-would-fit-example")
dir.create(dir, showWarnings = FALSE)
x <- c(3, 1, 2)
cache_would_fit("sorted", sort(x), dir = dir)
#> [1] TRUE
fit <- cache_fit("sorted", sort(x), dir = dir)
cache_would_fit("sorted", sort(x), dir = dir)
#> [1] FALSE
x <- c(4, 1, 2)
cache_would_fit("sorted", sort(x), dir = dir)
#> [1] FALSE
cache_would_fit("sorted", sort(x), dir = dir, refit = TRUE)
#> [1] TRUE
unlink(dir, recursive = TRUE)
```
