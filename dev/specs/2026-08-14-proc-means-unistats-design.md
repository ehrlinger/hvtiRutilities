# Extending `proc_means()` to the `unistats` Statistic Vocabulary

**Date:** 2026-08-14
**Status:** Approved design, pending implementation plan
**Package:** `hvtiRutilities`
**Predecessor:** `dev/specs/2026-08-05-proc-contents-means-design.md`

## Context

`proc_means()` shipped in 1.0.2 as a port of SAS `PROC MEANS`. Phase 0 of the
macro canonicalization program (`dev/specs/2026-07-10-sas-macro-canonicalization-design.md`)
has since inventoried the legacy macro library, and the inventory surfaced
`unistats` — a 208-line `PROC UNIVARIATE` wrapper that had been invisible to the
earlier file discovery because it carries no file extension.

`unistats` matters here because it is the closest thing in the corpus to a
specification for `proc_means()`. It is already parameterised the same way
(`DATA=`, `VARS=`, `WHERE=`, `BY=`, `STATS=`, `OUT=`, `PRINT=`), and its `STATS`
keyword list is the union vocabulary the CORR group actually asks for:

```
N NOBS NMISS SUM MEDIAN MEAN VAR STD CV MIN MAX Q1 Q3 P1 P5 P10 P90 P95 P99
NORMAL PROBN T PROBT MSIGN PROBM SIGNRANK PROBS STDMEAN USS CSS SKEWNESS
KURTOSIS SUMWGT RANGE QRANGE MODE
```

`proc_means()` currently supports `n`, `nmiss`, `mean`, `std`, `min`, `max`,
`sum`, `range`, `stderr`, `cv`, `median`, `q1`, `q3`, and any `pNN`. SAS
`STDMEAN` is the existing `stderr`, and `pNN` covers `P1` through `P99`, so the
gap is seventeen keywords, splitting into nine descriptive and eight inference.

## Scope

**In scope — nine descriptive statistics:**
`nobs`, `var`, `uss`, `css`, `skewness`, `kurtosis`, `sumwgt`, `qrange`, `mode`.

**In scope — weighting.** A `weights` argument, because `sumwgt` is meaningless
without one and because weighting recurs across the porting work (`std_dif_wt.sas`
is a weighted variant of `std_dif`). Adding it later would silently change the
meaning of statistics shipped in the meantime.

**Out of scope — the eight inference statistics** (`normal`, `probn`, `t`,
`probt`, `msign`, `probm`, `signrank`, `probs`). These return test statistics
and p-values, which would turn `proc_means()` from a summary function into a
hypothesis-testing one. `NORMAL`, `MSIGN` and `SIGNRANK` are `PROC UNIVARIATE`
statistics in any case; real `PROC MEANS` offers only `T`/`PROBT`.

This scope boundary carries a consequence worth recording: **`unistats` maps to a
future `proc_univariate()`, not to `proc_means()`.** This change closes the
descriptive half of that gap. The inference half should be specified separately,
informed by how `unistats` is actually called in the template corpus.

**Out of scope — `WHERE=` and `BY=`.** `unistats` has both. `BY=` overlaps the
existing `class` argument and `WHERE=` is `subset()` at the call site; neither is
needed to close the statistic vocabulary, and folding them in would mix two
changes.

## Architecture

A registry replaces the flat `known` vector in `.validate_stats()`:

```r
.STATS <- list(
  n      = list(fun = ..., weighted = FALSE, integer = TRUE),
  mean   = list(fun = ..., weighted = TRUE,  integer = FALSE),
  median = list(fun = ..., weighted = FALSE, integer = FALSE),
  ...
)
```

Three consumers read from it:

- `.validate_stats()` — valid keywords are `names(.STATS)` plus the `pNN`
  pattern, which stays a regex because it is an open family, not a fixed list.
- `.compute_stat(x, stat, w = NULL)` — looks up the entry and calls its `fun`.
  The `w = NULL` default preserves `data_dictionary()`'s three positional calls
  (`R/data_dictionary.R:88-90`) unchanged.
- `.empty_means()` — reads `integer` to type zero-row columns, replacing the
  hardcoded `s %in% c("n", "nmiss")`.

`median`, `q1`, `q3` and `pNN` continue to route to `.quantile_stat()` unchanged,
retaining `type = 2` for SAS `QNTLDEF=5`.

The registry exists for one specific reason. The central rule of this change —
which statistics respond to weights — is exactly the kind of rule that rots when
it lives implicitly across nine function bodies and one paragraph of prose. As
data, it is assertable in a test. `.compute_stat()` passes `w` to a statistic's
`fun` only when that statistic's `weighted` flag is `TRUE`, so a statistic cannot
become weighted by someone editing its body.

The registry stays in `R/proc_means.R`. Extracting a `R/stat_engine.R` is worth
doing when `proc_univariate()` gives it a second consumer, not on speculation.

Existing behaviour is unchanged: same defaults (`n`, `mean`, `std`, `min`,
`max`), same output shape, same `class` stratification path.

## The nine statistics

| Keyword | SAS definition | Weighted | `NA` when |
|---|---|---|---|
| `nobs` | count of all observations, missing included (`n + nmiss`) | no | never |
| `var` | sample variance, `VARDEF=DF` → divisor `n - 1` | yes | `n < 2` |
| `uss` | uncorrected sum of squares, `sum(x^2)` | yes | `n = 0` |
| `css` | corrected sum of squares, `sum((x - xbar)^2)` | yes | `n = 0` |
| `skewness` | `n/((n-1)(n-2)) * sum(((x-xbar)/s)^3)` | yes | `n < 3` or `s = 0` |
| `kurtosis` | `n(n+1)/((n-1)(n-2)(n-3)) * sum(((x-xbar)/s)^4) - 3(n-1)^2/((n-2)(n-3))` | yes | `n < 4` or `s = 0` |
| `sumwgt` | `sum(w)` over non-missing; equals `n` when `weights` is `NULL` | yes | `n = 0` |
| `qrange` | `q3 - q1` at `QNTLDEF=5` (R `type = 2`) | no | `n = 0` |
| `mode` | most frequent value; **smallest** when tied | no | no value repeats |

Weighted forms use the weighted mean `xbar_w = sum(w*x)/sum(w)`:
`uss = sum(w*x^2)`, `css = sum(w*(x - xbar_w)^2)`, `var = css/(n - 1)` under
`VARDEF=DF`, where `n` is the count of non-missing observations, not `sum(w)`.

Two notes.

**`mode` is the only one without a formula.** `PROC UNIVARIATE` returns the
smallest of the tied modes, and returns missing when every value is distinct —
not the first value encountered, and not an arbitrary one. Both edges get a test.

**`skewness` and `kurtosis` are the adjusted Fisher-Pearson forms**, which are
SAS's, not R's naive moment ratios. The `s = 0` guard is load-bearing: a constant
column yields `0/0`, and SAS returns missing rather than `NaN`.

## The `weights` argument

```r
proc_means(data, vars = NULL, class = NULL,
           stats = c("n", "mean", "std", "min", "max"),
           weights = NULL)
```

`weights` is appended last, so existing positional calls are unaffected — the
convention `verbose` followed in `update_manifest()`/`verify_manifest()` for
1.0.1.

**It names a column, not a vector:** `weights = "wt"`, mirroring the SAS `WEIGHT`
statement. This makes length mismatches structurally impossible and keeps the
weight aligned through `class` stratification without the caller re-subsetting.

**Weights apply within each `class` level**, computed on that level's rows, as
SAS does.

**Unweighted statistics stay unweighted.** Requesting `median` alongside
`weights` returns the unweighted median. This is `PROC MEANS` behaviour — `PROC
MEANS` does not compute weighted quantiles at all; that is `PROC UNIVARIATE`. It
is documented explicitly in `@details`, because it is the most likely thing for a
reader to assume wrongly. The full unweighted set under `weights`: `n`, `nmiss`,
`nobs`, `min`, `max`, `range`, `mode`, `median`, `q1`, `q3`, `pNN`, `qrange`.

**Validation.** `weights` must name a single column that exists in `data` and is
numeric; anything else errors immediately, consistent with how `vars` and `class`
validate today.

**Non-positive weights error, deliberately.** SAS's documented handling is
inconsistent across procedures and versions — variously "negative treated as
zero", "non-positive excluded", and "excluded from N but not NOBS". Rather than
encode a guess and call it parity:

- **missing** weight → observation excluded, as a missing analysis value is
- **zero or negative** weight → error, naming the offending rows

This is stricter than any SAS variant. It fails loudly on input whose SAS-side
meaning cannot be pinned, instead of silently producing a number that may not
match. When the Phase 1 oracle exists this can be relaxed to whatever SAS
actually does, and because the current behaviour is an error rather than a value,
no existing result will silently change when it is.

## Validation strategy

SAS runs on a separate system and the Phase 1 oracle does not yet exist, so
correctness is established against an independent implementation where one is
available.

`e1071::skewness(type = 2)` and `e1071::kurtosis(type = 2)` implement exactly the
SAS/SPSS definitions. `e1071` is added to `Suggests` and tests assert agreement
under `skip_if_not_installed("e1071")`. The remaining statistics are checked
against independent expressions rather than restatements of the implementation:
`var` against `stats::var`, `uss` against `sum(x^2)`, `css` against
`sum((x - mean(x))^2)`, `qrange` against `q3 - q1`.

**Known gap.** `e1071` takes no weights, so **weighted `skewness` and `kurtosis`
have no independent oracle available today**. They are implemented per the SAS
formula, pinned with hand-worked fixtures showing the arithmetic, and marked in
the test file as awaiting confirmation from the Phase 1 SAS oracle. This is the
one place in this change where a formula is asserted from documentation rather
than demonstrated against a second implementation. Weighted `var`, `uss`, `css`
and `sumwgt` do not have this problem — their weighted forms are simple enough to
hand-verify convincingly.

## Testing

**Registry contract.** The weighting decision asserted as data:

```r
expect_setequal(names(Filter(function(s) s$weighted, .STATS)),
                c("mean","std","var","cv","stderr","sum",
                  "uss","css","skewness","kurtosis","sumwgt"))
```

Plus: every registry name is accepted by `.validate_stats()`; the integer-typed
set is exactly `n`, `nmiss`, `nobs`. A statistic added later without its flags
set correctly fails these.

**Unweighted values.** `skewness`/`kurtosis` against `e1071`; the rest against
the independent expressions above.

**Edge cases**, one test each: `var` at `n < 2`; `skewness` at `n < 3`;
`kurtosis` at `n < 4`; both at `s = 0` returning `NA` rather than `NaN`;
`uss`/`css` at `n = 0`; `mode` returning the smallest of tied values; `mode`
returning `NA` when nothing repeats.

**Weighted path.** `sumwgt` sums the column. Weighted `mean`/`var`/`css`/`uss`
pinned on a small example with the arithmetic worked in comments. Weighted
`skewness`/`kurtosis` hand-pinned with an explicit comment marking them as
awaiting oracle confirmation, so the soft spot is visible in the test file and
not only in this document. The contract test that matters most: with `weights`
supplied, `median`, `min`, `max` and `n` return exactly what they return without
it.

**Validation and regression.** Errors for a missing column, a non-numeric column,
and zero or negative weights naming the offending rows; a missing weight excludes
the row. Regression: existing defaults and output shape unchanged;
`data_dictionary()`'s three positional `.compute_stat()` calls unchanged; the
zero-row path typing columns correctly through the registry's `integer` flag.

All fixtures are small, so the `R CMD check` time budget is unaffected.

## Documentation

`@param weights` describes the column-name form and the non-positive-weight
error. `@param stats` lists the full keyword vocabulary. `@details` states the
weighted/unweighted split explicitly, names `PROC MEANS` as the reason quantiles
are unweighted, and records that the inference statistics are deliberately absent
and belong to a future `proc_univariate()`.

## Success criteria

1. `devtools::test()` passes, with the registry contract, per-statistic value,
   edge-case, weighted, validation and regression groups above.
2. `R CMD check --as-cran` from a clean `git archive` export, with the manual:
   0 errors, 0 warnings, and no NOTE beyond the standing "New submission".
3. Overall check time remains well inside the 10-minute gate.
4. `data_dictionary()` output is unchanged, held by the characterization tests
   added in 1.0.2 before its refactor onto the shared statistic engine.
