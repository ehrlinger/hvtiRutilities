# Cache an expensive computation, strictly

Runs an expensive computation (a random forest, a varPro fit, an
imputation, a hazard model, a partial dependence grid) once, saves the
result, and on later calls loads it instead of recomputing. The saved
result is used only if nothing it was built from has changed: the code,
every outside value the code reads, the versions of the packages its
functions come from, and the seed. If anything changed, `cache_fit()`
stops and lists what changed. It never returns a stale result.

## Usage

``` r
cache_fit(name, code, seed = NULL, dir = study_dir("estimates"), refit = FALSE)
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

## Value

The result of `code`, computed or loaded, with its key attached as
attribute `hvtiRutilities_cache_key`.

## Details

`code` is not evaluated on a cache hit. It can be written inline, as a
single call or a [`{}`](https://rdrr.io/r/base/Paren.html) block of
several steps, or passed as a variable holding a
[`quote`](https://rdrr.io/r/base/substitute.html)d call built
beforehand. Both forms give the same key for the same computation.
Passing an object that has already been computed is an error, because
the cache could never skip it.

`code` must be written in the call to `cache_fit()` itself. A wrapper
function that forwards its own argument, e.g.
`function(nm, expr) cache_fit(nm, expr)`, forces that argument's promise
when it resolves `code`, so the value is already computed and the call
is refused as already-computed. A wrapper should instead build and pass
a quoted call, for example `cache_fit(nm, bquote(...))` or by passing
`quote(...)` through.

The code runs in a new environment whose parent is the caller's, so
names assigned inside a block do not appear in the caller.

The key digests each free variable of the code: a name bound by an
assignment, a `function` formal, or a `for` index is local within that
binding's scope, so a name that is also read free elsewhere in the code
still counts as an input. Values read indirectly (inside the body of a
function it calls, or through
[`get()`](https://rdrr.io/r/base/get.html)) are not seen; pass such
values into the code as arguments. The exception is a function defined
in the global environment (as in a shared `_common.R`): its own body is
part of the key, so editing it invalidates a cache that calls it, even
though values it in turn reads indirectly are still not seen. This
reaches only one level deep: a global helper is part of the key only
through its own body, not through the bodies of further helpers it in
turn calls, so editing a callee of a helper does not invalidate a cache
that calls the helper. For example, if `hA <- function(z) hB(z)` is
defined globally and `hB`'s body is later edited, the key computed for
code that calls `hA` is unchanged.

The result is returned with its key attached as an attribute, and that
attached key, not the object's own content, is what a downstream
`cache_fit()` digests when this result is passed to it as an input.
Mutating the returned object afterwards, for example
`fit$coefficients <- ...`, is invisible to that downstream cache,
because the attached key does not change to reflect the mutation. If a
cached object is modified in place, strip its `hvtiRutilities_cache_key`
attribute or re-wrap the result so a downstream cache is not fooled into
treating it as unchanged.

The attached-key short cut above applies only to a cached object passed
directly as an input. A cached object wrapped inside a list, or a model
object built outside `cache_fit()`, carries no such key and is digested
whole instead; such objects can digest differently across sessions or
platforms even when nothing meaningful about them changed. This shows up
as a loud, classed `hvtiRutilities_stale_cache` error rather than a
silently wrong cache hit, which is the safer failure mode, but is worth
knowing about when a downstream cache goes stale for no apparent reason.

The computation must return a value; a result of `NULL` is an error,
because there would be nothing to cache.

When `seed` is given, the code runs inside
[`with_seed`](https://withr.r-lib.org/reference/with_seed.html), which
leaves the global random number stream as it was. When `seed` is `NULL`
and the code consumes random numbers, the result is still saved, with a
warning of class `hvtiRutilities_nonreproducible_fit`, and the key
records `reproducible = FALSE`.

A stale file stops with an error of class `hvtiRutilities_stale_cache`;
a file not written by `cache_fit()` stops with class
`hvtiRutilities_unkeyed_cache`. Both are recomputed with `refit = TRUE`.

The result is written to a temporary file and renamed into place, so an
interrupted run never leaves a partial file. When `dir` lies inside a
study, a provenance sidecar carrying the key is written with
[`record_provenance`](https://ehrlinger.github.io/hvtiRutilities/reference/record_provenance.md).

## See also

[`record_provenance`](https://ehrlinger.github.io/hvtiRutilities/reference/record_provenance.md),
[`study_dir`](https://ehrlinger.github.io/hvtiRutilities/reference/study_dir.md)

## Examples

``` r
dir <- file.path(tempdir(), "cache-fit-example")
dir.create(dir, showWarnings = FALSE)
x <- c(3, 1, 2)
first <- cache_fit("sorted", sort(x), dir = dir)
again <- cache_fit("sorted", sort(x), dir = dir)
#> cache_fit(): loaded 'sorted' from cache
identical(first, again)
#> [1] TRUE
unlink(dir, recursive = TRUE)
```
