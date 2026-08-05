# Describe a dataset's variables, in the style of SAS PROC CONTENTS

Reports the variable-level metadata that SAS `PROC CONTENTS` prints:
creation position, name, SAS type, format, and label, alongside the R
class and simple completeness counts.

## Usage

``` r
proc_contents(data, order = c("alpha", "varnum"))
```

## Arguments

- data:

  A data frame, tibble, or similar tabular object.

- order:

  Variable ordering. `"alpha"` (default) sorts case-insensitively by
  name, matching SAS's default *Alphabetic List of Variables and
  Attributes*; `"varnum"` keeps creation order. The `num` column always
  reports creation position regardless of sort.

## Value

An object of class `proc_contents`: a list with two elements.

- header:

  One-row data frame with `observations` (row count), `variables`
  (column count), and `label` (dataset label, or `NA`)

- variables:

  Data frame with one row per column and the columns `num` (creation
  position), `variable`, `type` (`"Num"`/`"Char"`), `format` (SAS
  format, or `NA`), `label`, `class` (R class), `n_unique` (distinct
  non-`NA` values), and `pct_missing` (0-100, 1 decimal place, or `NaN`
  when `data` has zero rows)

## Details

Reading a `.sas7bdat` through haven is lossy. Variable name, label,
`format.sas`, and creation order survive; SAS storage `LENGTH`, `POS`
(position within the observation), informat, and the dataset's
created/modified timestamps do not. Those fields are omitted rather than
inferred, because inferred values would look authoritative and would
disagree with the source dataset whenever its `LENGTH` statement
differed from the default.

The SAS `Type` column is two-valued, so the mapping from R is
deliberately lossy: `character` and `factor` become `"Char"`; everything
else, including `logical`, `Date`, and `POSIXct`, becomes `"Num"`. A SAS
date is a number carrying a date format, so `type` reports `"Num"` while
`class` reports `"Date"` — keeping the disagreement visible rather than
hiding it.

For a data frame with columns but zero rows — a fully filtered cohort,
say — `pct_missing` is `NaN` rather than a number in 0-100, because
`mean(is.na(x))` on an empty vector is `0/0`. The proportion of missing
values among no values is genuinely undefined, and reporting `0` would
assert that nothing is missing. Callers formatting this column for
display should handle `NaN` explicitly.

## See also

[`proc_means`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md)
for numeric summaries,
[`data_dictionary`](https://ehrlinger.github.io/hvtiRutilities/reference/data_dictionary.md)
for a flattened documentation table.

## Examples

``` r
dta <- sample_data(n = 50)
pc <- proc_contents(dta)
pc$header
#>   observations variables label
#> 1           50         7  <NA>
pc$variables
#>   num variable type format                label     class n_unique pct_missing
#> 1   2  boolean  Num   <NA>     Binary Indicator   integer        2           0
#> 2   6     char Char   <NA>               Gender character        2           0
#> 3   4   f_real  Num   <NA> Random Uniform Value   numeric        9           0
#> 4   7   factor Char   <NA>       Category Group    factor        5           0
#> 5   5    float  Num   <NA>  Random Normal Value   numeric       50           0
#> 6   1       id  Num   <NA>   Patient Identifier   integer       50           0
#> 7   3  logical Char   <NA>       Logical Status character        2           0

# Creation order rather than alphabetical
proc_contents(dta, order = "varnum")$variables
#>   num variable type format                label     class n_unique pct_missing
#> 1   1       id  Num   <NA>   Patient Identifier   integer       50           0
#> 2   2  boolean  Num   <NA>     Binary Indicator   integer        2           0
#> 3   3  logical Char   <NA>       Logical Status character        2           0
#> 4   4   f_real  Num   <NA> Random Uniform Value   numeric        9           0
#> 5   5    float  Num   <NA>  Random Normal Value   numeric       50           0
#> 6   6     char Char   <NA>               Gender character        2           0
#> 7   7   factor Char   <NA>       Category Group    factor        5           0
```
