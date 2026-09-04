# Report what stripping a code prefix would do to a dataset's levels

One row per level of each discrete variable, giving the text as stored
and the text that would be displayed once a leading code prefix is
removed. Like
[`strip_level_prefix`](https://ehrlinger.github.io/hvtiRutilities/reference/strip_level_prefix.md)
it reports; it changes nothing.

## Usage

``` r
level_map(data, vars = NULL, max_levels = 20L)
```

## Arguments

- data:

  A data frame.

- vars:

  Optional character vector of column names to report. Defaults to every
  discrete column - factor, value-labelled, or character. Naming a
  column that is not in `data` is an error.

- max_levels:

  Maximum distinct values a column may have before it is skipped. A
  single positive whole number, finite; defaults to 20. To report every
  column, pass a number at least as large as the widest one - `Inf` is
  refused, because a threshold that never fires reads as a cap that is
  working.

## Value

A data frame with one row per reported level and the columns

- key:

  The variable name

- code:

  The code the level maps to, as character, or `NA`

- level:

  The text to display, with a prefix stripped where the rule in
  [`strip_level_prefix`](https://ehrlinger.github.io/hvtiRutilities/reference/strip_level_prefix.md)
  allows it

- level_full:

  The level text as stored, never modified

- stripped:

  Logical: `TRUE` where `level` differs from `level_full`

Zero rows, with those columns, when nothing is reportable.

## Details

The shape deliberately mirrors
[`label_map`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)
one level down: `level`, `level_full` and `stripped` read the same way
as `label`, `label_full` and `truncated`. So
`subset(level_map(data), stripped)` answers "which levels will print
differently", exactly as `subset(label_map(data), truncated)` answers
the question for labels.

Where the codes come from depends on what the column carries:

- a column with value labels - from `value_labels.yml` via
  [`apply_value_labels`](https://ehrlinger.github.io/hvtiRutilities/reference/apply_value_labels.md),
  or from a SAS format catalog - gives the declared codes;

- a factor gives its integer level positions, which is what the column
  actually stores;

- a character column has no codes, and `code` is `NA`.

Plain numeric and logical columns contribute no rows: they have no level
text for a prefix to sit in front of.

**High-cardinality columns are skipped, not expanded.** A character
column of identifiers would otherwise contribute thousands of rows to a
report meant to be read. Columns with more than `max_levels` distinct
values are omitted and named in a warning, so a skip is never silent.

## See also

[`strip_level_prefix`](https://ehrlinger.github.io/hvtiRutilities/reference/strip_level_prefix.md)
for the rule itself,
[`label_map`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)
for the same idea applied to variable labels,
[`apply_value_labels`](https://ehrlinger.github.io/hvtiRutilities/reference/apply_value_labels.md)
for declaring level text outright.

## Examples

``` r
dta <- data.frame(
  disp = factor(c("1. Home", "2. Rehab", "1. Home")),
  vess = factor(c("1 vessel", "2 vessel", "1 vessel"))
)
level_map(dta)
#>    key code    level level_full stripped
#> 1 disp    1     Home    1. Home     TRUE
#> 2 disp    2    Rehab   2. Rehab     TRUE
#> 3 vess    1 1 vessel   1 vessel    FALSE
#> 4 vess    2 2 vessel   2 vessel    FALSE

# Which levels will print differently
subset(level_map(dta), stripped)
#>    key code level level_full stripped
#> 1 disp    1  Home    1. Home     TRUE
#> 2 disp    2 Rehab   2. Rehab     TRUE
```
