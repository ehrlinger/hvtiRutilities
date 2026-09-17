# A strict, call-keyed cache for expensive fits: `cache_fit()`

**Date:** 2026-09-17
**Status:** Approved design; implemented on `feat/cache-fit` (plan: `2026-09-17-cache-fit-plan.md`); revised 2026-09-17 after review
**Package:** `hvtiRutilities`
**Related:** `hvtiRtemplates/dev/specs/2026-08-29-template-conversion-roadmap-design.md`
(§3.4, the ML family: `rfs`/`rfc`/`rfr`/`sid`/`vt`)

## Context

Study analyses save expensive intermediate objects (forests, varPro fits,
imputations, partial dependence grids) as `.rds` files and reload them on the
next render. Two existing studies show the two failure modes this spec removes:

- **Load if the file exists, no check.** The first SID clustering notebook
  hand-names a dated estimates folder and pastes package versions into file
  names. Nothing detects that the data or settings changed.
- **Hash a chosen subset of config, warn on mismatch.** The virtual twins
  Quarto book stores an 8-character hash of selected config fields and only
  **warns** when it differs, then returns the stale object anyway. The hash
  omits the data itself and package versions.

This is sub-project 1 of the ML family work. The decisions that shaped it
(2026-09-17, John Ehrlinger):

1. **Dependency direction.** `hvtiR*` packages depend on the public packages
   (TemporalHazard, ggRandomForests, ggBoostedTrees), never the reverse.
   Method code for SID and virtual twins goes to a new internal package,
   `hvtiRforests`, which may also depend on `hvtiR*` packages. Nothing
   study-specific goes into ggRandomForests.
2. **No per-method wrappers.** An earlier draft had `fit_rfsrc()`,
   `fit_varpro()` and `fit_partials()`. They were dropped: they duplicate the
   argument surface of the functions they wrap and do not scale to
   `sidClustering()`, PAM, isolation forests, TemporalHazard, boostmtree or
   imputation. One generic function keyed on the code replaces them.
3. **Home.** Because nothing left is forest-specific, the cache lives in
   `hvtiRutilities` beside `record_provenance()`, and every family reuses it:
   random forests, TemporalHazard, hvtiBoostmtree, hvtiRbootstrap, imputation.
   `hvtiRforests` is created later (sub-project 3) with real method content.

Build order: (1) `cache_fit()` here, (2) `rf*` templates, (3) `sid` (creates
`hvtiRforests`), (4) `vt`.

## Goals

- Skip an expensive computation when, and only when, its code and every input
  it reads are unchanged.
- **Stop** on a stale cache and say exactly what changed. Never return a stale
  object.
- One function for any expensive step: model fits, imputation, resampling,
  partial dependence, clustering.
- Keep stable, predictable file names so downstream jobs can read upstream
  outputs by name.

## Non-goals

- A pipeline or dependency graph tool (`targets` covers that; this is one
  cached step inside a Quarto job).
- Cache eviction, size limits, or remote storage.
- Trusting pre-existing `.rds` files that carry no key.

## API

```r
cache_fit(name, code, seed = NULL, dir = study_dir("estimates"), refit = FALSE)
```

| Argument | Meaning |
|---|---|
| `name` | Character(1). File stem; the object is stored at `file.path(dir, paste0(name, ".rds"))`. Must be a valid file stem: a single non-empty string containing neither `/` nor `\\`, so a name checked on one platform cannot escape `dir` on another. |
| `code` | The computation, in one of two forms (below). Not evaluated unless the cache misses. |
| `seed` | `NULL` or integer(1). If given, `code` runs inside `withr::with_seed(seed, ...)` and the seed is part of the key. |
| `dir` | Existing directory. Defaults to the study's estimates folder. |
| `refit` | Logical(1). `TRUE` recomputes and overwrites a stale or unkeyed file. |

Returns the computed or loaded object, with the key attached as attribute
`hvtiRutilities_cache_key`.

### The two forms of `code`

**Inline expression or block.** What is written is the code:

```r
biv_rfs <- cache_fit("biv-rfs", {
  fml <- Surv(time, dead) ~ .
  dta <- biv[biv$repair == "Biventricular", ]
  randomForestSRC::rfsrc(fml, data = dta, ntree = 5000, seed = -1024)
})
```

**A variable holding a quoted call.** Built first, possibly over several
lines:

```r
rff <- quote(
  randomForestSRC::rfsrc(Surv(time, dead) ~ ., data = biv, ntree = 5000, seed = -1024)
)
biv_rfs <- cache_fit("biv-rfs", rff)
```

**Resolution rule.** `cache_fit()` captures `code` unevaluated. If the captured
expression is a single symbol whose value in the caller's environment is a
call or expression object (`is.call()` / `is.expression()`), that value is the
code. Otherwise the captured expression itself is the code. An already-fitted
object passed as `code` (a symbol bound to a non-call value) is an error: it
would defeat the cache, so it is refused rather than stored.

### Other expensive operations

The same function covers every family. Examples the tests and documentation
carry:

```r
imp <- cache_fit("biv-mice", mice::mice(biv_sub, m = 5, printFlag = FALSE), seed = 1024)
vp  <- cache_fit("biv-varpro", varPro::varpro(Surv(time, dead) ~ ., data = biv))
hz  <- cache_fit("dead-hz", TemporalHazard::hazard(fml, data = dta), seed = 1024)
bmt <- cache_fit("reop-bmt", hvtiBoostmtree::boostmtree(x, tm, id, y), seed = 1024)
pd  <- cache_fit("biv-rfs-partial", ggRandomForests::gg_partial_rfsrc(biv_rfs, xvar.names = xv))
```

`mice()` accepts its own `seed` argument; either that or `cache_fit(seed =)`
makes the key reproducible. The partial dependence example chains
automatically: `biv_rfs` is a free variable of the code, so it is digested,
and refitting the forest makes the partials stale.

## The key

A named list, built without evaluating `code`:

| Field | Content |
|---|---|
| `code` | `deparse()` of the code with whitespace normalised, so reformatting does not invalidate. |
| `inputs` | For each free variable of the code, resolved in the caller's environment with `get()` and digested with `digest::digest(value, algo = "xxhash64", serializeVersion = 2L)`. Free variables are found lexically: a name bound by an assignment, a `function` formal or a `for` index is local only within that binding's scope, so a name that is also read free elsewhere still counts. Covers data frames, parent models, config values. Names that do not resolve (column names used in non-standard evaluation) are skipped. A value that is itself a `cache_fit()` result (it carries `hvtiRutilities_cache_key`) is digested by its key's compared fields rather than by the object, which is stable across sessions and makes chains transitive. A function defined by the user in the global environment is digested by its own deparsed body; package functions are skipped and covered by `packages`. |
| `packages` | Versions of every package named with `pkg::` in the code, plus, for each bare function name called, the package whose namespace defines it. Base-priority packages are excluded. |
| `seed` | The `seed` argument, or `NULL`. |
| `reproducible` | `TRUE` unless the computation used the global RNG without a `seed` (see below). |
| `r_version` | `R.version.string`. |

Keys compare field by field, excluding `reproducible` and `r_version`. **Any**
R upgrade, not only a patch one, leaves a cache valid: serialized results stay
readable across R versions, every result is rebuilt anyway once its inputs
change, and `renv.lock` plus the provenance sidecar are where the runtime is
pinned and recorded. Comparing the R version would invalidate every cached
forest on a minor upgrade, which is the refit this exclusion exists to
prevent.

⚠️ **Known limits**, all documented on the function:

- Values read indirectly (inside a called function's body, or through `get()`
  or `eval()`) are not seen. Pass them as explicit arguments in the code.
- A global helper contributes its own body, but not the bodies of further
  helpers it calls.
- A cached result edited in place keeps its key attribute, so the edit is
  invisible downstream.
- The key short circuit applies to a cached object passed directly. One
  wrapped in a list, or a model fitted outside `cache_fit()`, is digested
  whole, and such objects can digest differently between sessions. That shows
  up as a loud stale error, never as a wrong result.

## Behaviour

```
key  <- build key (no evaluation)
path <- dir/name.rds

file missing          -> compute -> save -> provenance -> return
file exists, key same -> readRDS -> message "loaded <name> from cache" -> return
file exists, differs  -> refit ? compute and overwrite (message) : stop(stale)
file exists, no key   -> refit ? compute and overwrite           : stop(unkeyed)
```

**Global RNG detection.** When `seed` is `NULL`, `cache_fit()` reads
`.Random.seed` from the global environment before and after the computation
with `get0(..., inherits = FALSE)`, which returns `NULL` when the binding does
not exist yet, as in a fresh session. Absent and present are therefore
distinct states and neither errors: a computation that draws no random numbers
compares `NULL` with `NULL`, and one that draws them compares `NULL` with a
seed vector. If it changed, the result is
still saved (it was expensive), a warning names the job and advises `seed =`,
and the key and provenance record `reproducible: false`. randomForestSRC's
`seed =` argument is part of the code and so already in the key; TemporalHazard,
hvtiBoostmtree, `cluster::pam()`, `sidClustering()` and hvtiRbootstrap draw
on the global RNG and need `cache_fit(seed =)`. The function never calls
`set.seed()` on the global stream.

**Stop message.** A classed condition, `hvtiRutilities_stale_cache` (and
`hvtiRutilities_unkeyed_cache`), listing only the differing fields:

```
Cached object 'biv-rfs' is stale (estimates/biv-rfs.rds):
  inputs$biv       3f9a1c...  ->  b21c07...
  packages$randomForestSRC  3.4.5  ->  3.5.0
Recompute with refit = TRUE, or restore the inputs it was built from.
```

**Writes.** `saveRDS()` to a temporary file in `dir`, then provenance, then
`file.rename()` to promote it. On Windows R's `file.rename()` replaces an
existing target (`MoveFileEx` with `MOVEFILE_REPLACE_EXISTING`), which the
`refit = TRUE` tests exercise on every platform CI runs; if the Windows job
ever shows otherwise, the fallback is `unlink()` then rename, which trades
atomicity for replacement and must say so. An interrupted render never leaves a partial
`.rds` that later loads as valid. A failing computation writes nothing and its
condition propagates unchanged.

**Provenance.** `record_provenance(path, extra = list(cache_key = key))`, so
the sidecar format is the package's existing one. It runs **after the
temporary file is written and before the rename**, which makes the pair
transactional in the direction that matters: a provenance failure leaves
nothing cached, so a cached `.rds` never exists without its sidecar. The
failure stays loud, and the message says the computed result was not kept.
Provenance is attempted only when `dir` lies inside a study, and the study is
read leniently (`require_data = FALSE`), matching how the study is detected.

**One writer per cache file.** Promotion is atomic for readers: a reader sees
either the old file or the new one, never a partial one, and the key stored is
always the key of the object stored. It does **not** serialise writers. Two
processes computing the same `name` at once both compute, and the later rename
wins, so a slower job started with older inputs can end up on disk. That
result is not silently trusted: its key is its own, so the next call compares
it against the current inputs and stops as stale. Locking is out of scope; the
contract is one writer per cache file, which is what a study render is.

**Errors on arguments.** Missing `dir` stops (it is not created silently);
`name` with a path separator stops; `refit` and `seed` are type-checked.

## Dependencies

- `digest` is already imported.
- Add `withr` to Imports (`with_seed()`).
- No modelling package is imported; they are reached only through `code`.

## Testing

All tests run in `withr::local_tempdir()`. Tests that exercise provenance use
the package's own study fixture, which writes `_study.yml` **and** the built
dataset, because `record_provenance()` requires a cohort contract and a built
manifest; a bare `_study.yml` would make the first cache miss fail after
computing. Forests use `ntree <= 50`;
target suite time under 30 s.

| Area | Cases |
|---|---|
| Key | identical inputs give identical keys; reformatting the code does not change it; changing one data value, a column type, a config value, a seed, or a package version changes the named field; locally assigned names are not digested; unresolvable NSE names are skipped |
| Resolution | inline expression, `{}` block, and a symbol bound to `quote()` all work; a symbol bound to a fitted object errors |
| Hit / miss | a counting mock computation proves a cache hit does not evaluate `code`; miss writes; stale raises `hvtiRutilities_stale_cache` naming the fields; unkeyed raises `hvtiRutilities_unkeyed_cache`; `refit = TRUE` overwrites both |
| RNG | with `seed`, two cold runs are identical and the global RNG state is untouched; without `seed`, an RNG-consuming computation warns and records `reproducible: false`; a non-RNG computation does not warn |
| Writes | a computation that errors leaves no file; no temporary file remains after success |
| Chaining | a downstream `cache_fit()` whose code reads an upstream cached object goes stale when the upstream is refit |
| Provenance | the sidecar exists and carries `cache_key` |
| Real fits | `skip_if_not_installed()` round trips for `randomForestSRC::rfsrc` (survival, `ntree = 50`) and `mice::mice` |

## Release

- NEWS entry under the unreleased section; version bump is the patch digit
  only, per the family versioning rule.
- Downstream, after release: the `rf*` template spec (sub-project 2,
  `hvtiRtemplates`) adopts `cache_fit()` for every fitting chunk. The hvtiR
  `jobs.json` rows for `sid` and `vt` are repointed from ggRandomForests to
  `hvtiRforests` once that package exists (sub-project 3).

## Open questions

- None blocking. Migration of existing unkeyed `.rds` files is by design one
  deliberate `refit = TRUE` per job.
