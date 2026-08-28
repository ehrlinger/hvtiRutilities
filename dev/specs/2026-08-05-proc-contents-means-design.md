# Port of SAS `PROC CONTENTS` and `PROC MEANS`

**Date:** 2026-08-05
**Status:** Approved design, pending implementation plan
**Package:** `hvtiRutilities`
**Base:** `main` @ 1.0.1

## Context

The CORR EDA step currently runs in SAS. On the whiteboard sketch of the
pipeline, `proc contents` and `proc means` are bracketed together and annotated
`hvtiRutilities` — they are the two metadata/summary primitives that sit
between the SAS data build and the Quarto EDA document, and they are the piece
that has to move into R first, because everything downstream reads their output.

The goal is that the EDA step *feels unchanged* to an analyst after the
migration: the same fields, the same statistics, the same table orientation
they already read off a SAS listing. This is a fidelity requirement about
content and structure, not about console typography.

`data_dictionary()` already exists in this package and covers roughly 60% of
`PROC CONTENTS`: variable, label, class, `n_unique`, `pct_missing`, and a
`summary` string. What it lacks is precisely the SAS-side metadata an analyst
opens `PROC CONTENTS` for — variable position, SAS type, and format. And its
`summary` column collapses min/median/max into a *string*, which is fine for a
document table and useless as a summary primitive.

That overlap is the reason this spec restructures rather than merely adds:
`data_dictionary()`'s `summary` column always was "contents plus a slice of
means", so the two new functions are the primitives it should have been built
on.

## Decisions

| Question | Decision |
|---|---|
| What "port" means | Reproduce the SAS output in R — same fields, same statistics, same orientation |
| Fidelity | SAS-shaped data frames with R-native rendering; no ASCII-listing emulation |
| `proc_means()` statistics | SAS keyword list via `stats =`, defaulting to SAS's own five |
| Stratification | `CLASS` only; `BY` is not ported |
| `proc_contents()` scope | Variables table plus dataset header; unrecoverable fields omitted, never inferred |
| Relationship to `data_dictionary()` | `data_dictionary()` becomes a thin wrapper over both primitives |

## What `haven` can and cannot recover

Reading a `.sas7bdat` through `haven` is lossy, and the design is shaped by
exactly where the losses fall.

**Recoverable:** variable name, variable label, `format.sas`, creation order.

**Not recoverable:** informat, SAS storage `LENGTH`, `POS` (position within the
observation), and the dataset header's created/modified timestamps and engine.

`Len` and `Pos` are the tempting fields, because they *can* be fabricated — 8
for numerics, `max(nchar())` for character, cumulative offsets for position.
Those values would look authoritative and would disagree with the real dataset
whenever the SAS `LENGTH` statement differed from the default, which is common.
They are omitted, and their absence is documented in `@details`.

## Architecture

Three files, one dependency direction, no new package dependencies:

```
R/proc_contents.R     proc_contents()      <- primitive
R/proc_means.R        proc_means()         <- primitive
R/data_dictionary.R   data_dictionary()    <- thin wrapper over both
```

`stats` is already imported and `labelled` is already a dependency, so
`Imports:` is unchanged.

## `proc_contents(data, order = c("alpha", "varnum"))`

Returns a list of class `proc_contents` with two elements.

### `$header`

One-row data frame:

| column | source |
|---|---|
| `observations` | `nrow(data)` |
| `variables` | `ncol(data)` |
| `label` | dataset label attribute, `NA` when absent |

### `$variables`

One row per column:

| column | source |
|---|---|
| `num` | creation order (position in `data`) — SAS's `#` |
| `variable` | `names(data)` |
| `type` | `"Num"` / `"Char"`, derived |
| `format` | `attr(x, "format.sas")`, `NA` when absent |
| `label` | `labelled::var_label()`, falling back to the variable name |
| `class` | primary R class |
| `n_unique` | count of distinct non-`NA` values |
| `pct_missing` | percentage `NA`, rounded to 1 dp |

### Ordering

`order` defaults to `"alpha"`, matching SAS's own default heading *Alphabetic
List of Variables and Attributes*. `"varnum"` gives creation order. The `num`
column always reports creation position regardless of sort, as SAS does.

### Type mapping

The SAS `Type` column is two-valued, so the mapping from R is deliberately
lossy: `factor`, `character`, and character `haven_labelled` become `Char`;
`numeric`, `integer`, labelled numerics, `Date`, and `POSIXct` become `Num`.

Dates are the case that needs stating: a SAS date is a number carrying a
`DATE9.` format, so `type` is `Num` — but `haven` may already have converted it
to an R `Date`, leaving `format.sas` as the only surviving evidence. Reporting
`Num` in `type` while `class` shows `Date` keeps that disagreement visible
rather than hiding it behind one column.

### Printing

A minimal `print.proc_contents` writes the two header lines, then the variables
data frame. This exists so that a bare two-element list does not print badly.
It is explicitly *not* SAS console emulation: no centered titles, dashed rules,
or column banners.

## `proc_means(data, vars = NULL, class = NULL, stats = c("n", "mean", "std", "min", "max"))`

### Arguments

**`vars`** — `NULL` means all numeric columns, matching SAS's behaviour when the
`VAR` statement is omitted. Class variables are excluded from the analysis set
even when numeric.

**`class`** — character vector of grouping columns, prepended to the output as
leading columns. Rows where any class variable is `NA` are dropped, matching
SAS's default. (SAS's `MISSING` option, which retains them, is deferred until
someone needs it.)

**`stats`** — SAS statistic keywords. Output column order follows the order
requested, as SAS does.

### Statistics

| keyword | definition |
|---|---|
| `n` | count of non-missing |
| `nmiss` | count of missing |
| `mean`, `min`, `max`, `sum`, `range` | computed on non-missing values |
| `std` | sample standard deviation, denominator *n*−1 — agrees with `sd()` |
| `stderr` | `std / sqrt(n)` |
| `cv` | `100 * std / mean` |
| `median`, `q1`, `q3`, `p1`…`p99` | `stats::quantile(type = 2)` |

Percentile keywords are parsed generically: any `pNN` for integer *NN* from 1
to 99 is accepted, so the whiteboard's 15th-percentile need is simply
`stats = c("n", "mean", "median", "p15")`. `median`, `q1`, and `q3` are
accepted as aliases of `p50`, `p25`, and `p75`.

### Which columns count as numeric

`vars = NULL` selects columns for which `is.numeric()` is `TRUE`. Two cases
need stating because this package creates them:

- **Logical columns.** `r_data_types()` converts binary 0/1 variables to
  logical, and `is.numeric(TRUE)` is `FALSE` in R, so those columns are *not*
  in the default analysis set even though SAS would treat them as numeric.
  Naming one explicitly in `vars` coerces it to 0/1 and summarises it, which
  makes `mean` a proportion, as `PROC MEANS` would give.
- **Labelled numerics.** `haven_labelled` over a numeric base is numeric and is
  included; the underlying codes are summarised, not the value labels.

### Quantile definition

This is the sharpest parity trap in the port and the reason the quantile type
is pinned rather than left to R's default.

SAS defaults to `QNTLDEF=5`; R's `quantile()` defaults to `type = 7`. These are
different estimators, and they disagree on exactly the small and
even-numbered samples that clinical subgroups produce. `QNTLDEF=5` corresponds
to R `type = 2`.

Concretely, for `c(1, 2, 3, 4)`: Q1 is `1.75` under R's default and `1.5` in
SAS. The median agrees, which is why the bug hides — it surfaces only in
Q1/Q3/P15, the statistics nobody eyeballs.

The type is fixed at `2` and documented as the `QNTLDEF=5` equivalent.
Exposing a `qntldef` argument is deferred until a non-default SAS call needs
reproducing.

### Return value

A plain data frame, one row per variable per class combination:

```
[class columns...], variable, label, <one column per requested statistic>
```

Rows sort by `variable` in `vars` order (varying slowest), then by class levels
ascending — the SAS row order.

### Not included

`MAXDEC=` is not ported. Rounding is a display concern, and the chosen
rendering is R-native, so it belongs in `knitr::kable(digits = )` rather than
baked into the returned numbers.

## `data_dictionary()` after the refactor

The signature and all six output columns stay byte-identical; only the
implementation changes.

- `variable`, `label`, `class`, `n_unique`, `pct_missing` come from
  `proc_contents()`.
- The `summary` string for numeric columns is built from
  `proc_means(stats = c("min", "median", "max"))`.
- The factor, character, logical, and all-`NA` branches of
  `.summarise_column()` stay as they are — those are not `PROC MEANS`
  territory.

The numeric `summary` string will now take its median from
`proc_means()`'s `type = 2` quantile rather than `stats::median()`. These are
the same estimator at *p* = 0.5 for both odd and even *n* — `median()` averages
the two central order statistics on even *n*, and `type = 2` does likewise — so
the pinned output is unchanged. This is noted only so the substitution is not
mistaken for a silent behaviour change during review.

## Error handling

Following the conventions already used by `data_dictionary()` and
`compare_datasets()` — `stop(..., call. = FALSE)`, and zero-column input
returning a correctly-typed zero-row frame rather than erroring:

- non-data-frame input → stop
- `class` or `vars` naming columns absent from `data` → stop, listing the offenders
- unrecognised `stats` keyword → stop, listing the valid keywords
- no numeric columns available to analyse → warn and return a zero-row frame;
  silence here would be indistinguishable from success

## Testing

The order matters — the characterization test is written before the refactor,
not after.

1. **Pin `data_dictionary()` before touching it.** Capture current output on
   `generate_survival_data(n = 100, seed = 42)` and on the zero-column edge
   case. The refactor is correct only if this passes unchanged.
2. **Statistic-by-statistic unit tests** against hand-computed values,
   including all-`NA` columns, single-value columns, and single-row input.
3. **Quantile parity test** on `c(1, 2, 3, 4)`, asserting Q1 is `1.5` and not
   `1.75`. This is the regression guard against a later "simplification" to
   `quantile()`'s default.
4. **`CLASS` tests** — grouping columns prepended, `NA`-class rows dropped, row
   ordering as specified, class variables excluded from the analysis set.
5. **`proc_contents()` tests** — `format.sas` surfaced, labels resolved,
   `"alpha"` versus `"varnum"` ordering, `Date` reported as `Num` with `class`
   showing `Date`, and an explicit assertion that no `len` or `pos` columns
   exist.

## Files touched

**New:** `R/proc_contents.R`, `R/proc_means.R`,
`tests/testthat/test-proc_contents.R`, `tests/testthat/test-proc_means.R`

**Modified:** `R/data_dictionary.R` (rewritten as a wrapper),
`tests/testthat/test-data_dictionary.R` (characterization tests added),
`NAMESPACE` (regenerated), `README.md` (Main Functions entries), `NEWS.md` and
`DESCRIPTION` (1.0.1 → 1.0.2)

## Out of scope

- **Descriptives / Table 1** (`de.tables.sas` on the whiteboard: overall
  mean/median/15th percentile/n, stratified significance tests, chi-square,
  Wilcoxon, Kruskal-Wallis, standardized mean difference). Drawn as a separate
  item, and it is a separate spec.
- **`BY` group processing** and the `_TYPE_`/`_FREQ_` columns SAS emits.
- **`PROC SUMMARY`**, which is `PROC MEANS` without printing and therefore
  needs nothing additional here.
- **`MAXDEC=`**, the `MISSING` class option, and a `qntldef` argument — all
  deferred, all cheap to add later if a real SAS call needs them.
