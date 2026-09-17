# Porting SAS `PROC FREQ` to `proc_freq()`

**Date:** 2026-09-16
**Status:** Approved design, pending implementation plan
**Package:** `hvtiRutilities`
**Predecessors:** `dev/specs/2026-08-05-proc-contents-means-design.md`,
`dev/specs/2026-08-14-proc-means-unistats-design.md`

## Context

A job's opening data checks are typically

```sas
proc freq data = built;
  table dead / missing list;
  table arch_bvd * dead / missing list;
run;
```

followed by `PROC UNIVARIATE`. The package ports `PROC CONTENTS` and
`PROC MEANS` but not `PROC FREQ`, so analysts translate it by hand with
`dplyr::count()`. Those hand translations agree with SAS on the counts and
disagree on the details: NA sorts last instead of first (moving every
cumulative column), a grouped `count()` leaves groups attached so a later
percentage is 100 in every row, and the n-way crosstab denominator differs
from the `LIST` denominator. None of these errors raises a warning.

`proc_freq()` is the first of two ports. `proc_univariate()` is the second, a
separate spec, and remains the open item recorded in the vault.

## Scope

**In scope.** One-way and n-way frequency tables; the `MISSING` and `LIST`
options; cell, row and column percentages; cumulative columns; `WEIGHT`.

**Out of scope.** `CHISQ`, `FISHER`, `MEASURES`, `AGREE`, `TREND`, `EXACT`,
and every other test or measure of association. This follows `proc_means()`,
which excludes inference so that the function stays a summary one. Also out:
`ORDER=FREQ|DATA|FORMATTED`, `SPARSE`, `ZEROS`, `OUT=` options beyond the
returned data frame, and the SAS `a*(b c)` table grouping syntax.

## Interface

```r
proc_freq(data, tables, missing = FALSE, list = FALSE, weights = NULL)
```

One table per call. A SAS step with several `TABLES` statements is several
calls. One-way and two-way results have different columns and would not
stack, so a single-data-frame return is kept simple rather than wrapped in a
list.

| argument | meaning |
|---|---|
| `data` | a data frame |
| `tables` | character vector of one or more column names. The last is the column variable, the one before it the row variable, and any earlier names are strata, as in SAS `a*b*c` |
| `missing` | `FALSE` (SAS default) or `TRUE`, SAS `/ MISSING` |
| `list` | `FALSE` (SAS default) or `TRUE`, SAS `/ LIST` |
| `weights` | `NULL` or the name of one numeric column, SAS `WEIGHT` |

## Result

Always a long data frame: one row per observed level combination, leading
with one column per `tables` variable in the order given, followed by the
statistic columns. Which statistic columns appear, and what each percentage
is out of, depends on the case:

| case | statistic columns | denominators |
|---|---|---|
| one-way | `Frequency`, `Percent`, `Cum_Frequency`, `Cum_Percent` | table total |
| n-way, `list = TRUE` | `Frequency`, `Percent`, `Cum_Frequency`, `Cum_Percent` | grand total; cumulated in row order |
| n-way, `list = FALSE` | `Frequency`, `Percent`, `Row_Percent`, `Col_Percent` | `Percent` within stratum; `Row_Percent` within stratum and row; `Col_Percent` within stratum and column |

For a two-way table the "stratum" is the whole table, so `Percent` is of the
total in both modes. The modes give different `Percent` values only from
three variables on, where a SAS crosstab prints one row-by-column table per
stratum level and percentages it within that table. This is the design's
central parity trap and has its own test.

`list = TRUE` on a one-way table is accepted and has no effect, as in SAS.

Percentages are **not rounded**. SAS rounds for display only, and a rounded
result would fail `compare_parity()` against SAS output at any tight
tolerance.

### Missing values

- `missing = FALSE`: rows with NA in any `tables` variable are excluded from
  the result and from every denominator. Their count (weighted, when
  `weights` is given) is stored as `attr(result, "frequency_missing")`,
  mirroring SAS's printed `Frequency Missing = k`. The attribute is `0` when
  nothing was missing, never absent.
- `missing = TRUE`: NA is a level and contributes to every denominator.
  `frequency_missing` is `0`.
- **What is missing.** As in SAS, a blank or whitespace-only character value
  is missing (`haven` gives it as `""`), and `NaN` is recoded to plain NA so
  the two form one level. Factors are not recoded.
- **Special missing values.** `haven::tagged_na()` values (SAS `.A` to `.Z`,
  `._`) are separate levels under `missing = TRUE`, ordered `._`, `.`, `.A`
  ... `.Z`, all before non-missing values, and the result keeps the tag.
  Under `missing = FALSE` they are excluded and counted like any NA.

### Weights

With `weights`, `Frequency` is the sum of weights rather than a row count, and
every percentage uses weighted denominators. Weights are validated by the
existing `.validate_weights()`, so non-positive and NA weights are an error,
consistent with `proc_means()`. A `weights` column that also appears in
`tables` is an error.

## Row order

Rows follow SAS `ORDER=INTERNAL`, sorted by the `tables` variables left to
right:

- factors in declared level order (the same rule `proc_means()` applies to
  `class`), which keeps ordinal clinical scales in clinical sequence;
- numeric by value, character alphabetically;
- **NA first.** SAS treats missing as the smallest value. `dplyr::count()`
  places NA last, and cumulative columns depend on this order.

## Labels

- **Value labels.** SAS forms levels from formatted values, so a
  `haven_labelled` variable is grouped on its value label: stored codes
  sharing a label form one row, shown and ordered as the smallest of those
  codes. A value with no label keeps its own value and row. A `<var>_label`
  character column, holding the value label (NA where a value has none),
  follows that variable's column. Variables without value labels get no extra
  column. A `tables` name that equals an output column (a statistic, or the
  `<var>_label` of a value-labelled variable) is an error.
- **Variable labels.** The result's leading columns carry the source
  variables' `var_label`. Row subsetting strips the `label` attribute, which
  once silently dropped every label in weighted `proc_means()` calls; labels
  are therefore read before any filtering and reapplied at the end.

## Errors

All errors use `call. = FALSE` and name the offending input.

- `data` is not a data frame.
- `tables` is not a non-empty character vector, contains duplicates, or names
  a column absent from `data` (via `.check_columns()`).
- `missing` or `list` is not a single `TRUE`/`FALSE`.
- `weights` fails `.validate_weights()` or appears in `tables`.

A table that is empty after `missing = FALSE` drops rows is **not** an error.
It returns a zero-row data frame with the correct columns and
`frequency_missing` set, so a loop over subsets does not abort on one that is
entirely missing.

## Testing

Test files split by theme, following the `proc_means` tests:
`test-proc_freq_shape.R`, `test-proc_freq_values.R`,
`test-proc_freq_missing.R`, `test-proc_freq_weights.R`,
`test-proc_freq_errors.R`.

- **Hand-computed oracles.** Small fixtures whose expected `Frequency` and
  percentages are frozen literals, never recomputed with `dplyr` inside the
  test, so a formula change cannot move the expectation with it.
- **Denominator trap.** A three-way fixture on which `list = TRUE` and
  `list = FALSE` give different `Percent`, each checked against literals.
- **Missing.** NA sorts first; `frequency_missing` is correct weighted and
  unweighted; percentages sum to 100 excluding NA under `missing = FALSE` and
  including it under `missing = TRUE`.
- **Order.** Factor level order is kept, including an unused level (dropped,
  as SAS omits zero-count levels without `SPARSE`).
- **Labels.** `<var>_label` columns for `haven_labelled` input; `var_label`
  survives both the NA filter and weighting.
- **Edge cases.** Zero-row result; a single-level table; every error path.
- **SAS oracle.** No SAS listing exists for these fixtures yet. The tests say
  so, in the same way as the weighted `skewness`/`kurtosis` tests awaiting the
  Phase 1 oracle.

## Documentation and delivery

- Roxygen in **Rd markup**, not markdown (`\code{}`, `\itemize{}`). `\value`
  lists the statistic columns per case and the `frequency_missing` attribute.
  `@details` states the denominator difference and the NA-first ordering.
- `_pkgdown.yml`: add `proc_freq` beside `proc_means` in the SAS procedures
  section; the site build errors without it.
- `vignettes/sas-procedures.qmd`: a `proc_freq()` section built around the
  denominator trap, parallel to the quartile trap section for `proc_means()`.
- `NEWS.md`: entry under `# hvtiRutilities (unreleased)`; no version bump in
  the PR.
- Branch `feat/proc-freq`. Done means `devtools::document()`,
  `devtools::test()` and `devtools::check()` at 0/0/0, then a PR.

## Revisions after final review (2026-09-16)

- **F1.** A `tables` name clashing with an output column is an error; it
  previously overwrote the key column silently.
- **F2.** Blank character values are missing, as in SAS.
- **F3.** `NaN` is recoded to NA; tagged NAs are separate missing levels in
  SAS order and keep their tags in the result.
- **F4.** Value-labelled variables group on the label (codes sharing a label
  form one row, at the smallest code), not on the stored value. Unlabelled
  doubles stay grouped on exact values, a stated divergence from SAS's
  printed-value grouping.

## Follow-up

- `proc_univariate()`: its own spec, carrying the `unistats` inference
  statistics (`normal`, `probt`, `signrank`, `clm`) and weighted quantiles.
- A SAS-run oracle for the `proc_freq()` fixtures.
