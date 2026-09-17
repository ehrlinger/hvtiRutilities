# Frequency tables, in the style of SAS PROC FREQ

Produces the table SAS `PROC FREQ` prints for a `TABLES` statement: one
row per observed combination of levels, with frequencies and
percentages. One call is one table; a SAS step with several `TABLES`
statements is several calls.

## Usage

``` r
proc_freq(data, tables, missing = FALSE, list = FALSE, weights = NULL)
```

## Arguments

- data:

  A data frame.

- tables:

  Character vector of one or more column names defining the table.

- missing:

  Logical. `FALSE` (the SAS default) excludes rows with a missing value
  in any `tables` variable from the table and from every denominator,
  and reports their count in the `frequency_missing` attribute. `TRUE`,
  SAS `/ MISSING`, treats missing as a level, with each SAS special
  missing value a level of its own.

- list:

  Logical. `TRUE`, SAS `/ LIST`, gives cumulative columns and
  percentages of the grand total for an n-way table. It has no effect on
  a one-way table.

- weights:

  Character or `NULL`. Name of a single numeric column of weights, SAS
  `WEIGHT`. `Frequency` becomes the sum of weights. Rows with a missing
  weight are excluded entirely; non-positive weights are an error, as in
  [`proc_means`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md).

## Value

A data frame with one column per `tables` variable (each followed by a
`<var>_label` column when the variable carries value labels), then:

- for a one-way table, or `list = TRUE`: `Frequency`, `Percent`,
  `Cum_Frequency`, `Cum_Percent`;

- for an n-way crosstab: `Frequency`, `Percent` (within stratum),
  `Row_Percent`, `Col_Percent`.

`Frequency` is integer when unweighted and double when weighted. The
attribute `frequency_missing` holds the count (or weight) of excluded
missing rows, and is `0` when none were excluded. A table with no
remaining rows is returned with zero rows, not an error.

## Details

The last name in `tables` is the column variable, the one before it the
row variable, and any earlier names are strata, as in SAS
`TABLES a*b*c`.

**Percentages depend on `list`, not only the columns shown.** For a
crosstab of three or more variables, SAS prints one row-by-column table
per stratum and computes `Percent` within that stratum. With
`list = TRUE`, `Percent` is of the grand total. The two agree for one-
and two-way tables and disagree from three variables on.

**Missing values sort first.** SAS treats missing as the smallest value,
so under `missing = TRUE` the missing level heads the table and the
cumulative columns count it first.
[`dplyr::count()`](https://dplyr.tidyverse.org/reference/count.html)
places `NA` last, which moves every cumulative value.

Rows follow SAS `ORDER=INTERNAL`: factors in declared level order,
numbers by value, character values by byte value (the C locale, so `"B"`
sorts before `"a"`). Unused factor levels are omitted, as SAS omits
zero-count levels without `SPARSE`.

A `haven_labelled` variable is grouped on its value label, as SAS forms
levels from formatted values: stored codes sharing a label form one row,
shown as the smallest of those codes, and a `<var>_label` column holding
the label follows it. A value with no label is its own row. Variable
labels on the `tables` columns are kept.

**What counts as missing.** As in SAS, a blank or whitespace-only
character value is missing, and so is `NaN`. SAS special missing values,
read by `haven` as
[`tagged_na`](https://haven.tidyverse.org/reference/tagged_na.html), are
separate missing levels in SAS order: `._`, then `.`, then `.A` to `.Z`.

**Where this differs from SAS.** Unlabelled doubles are grouped on their
exact values, whereas SAS groups on the printed (`BEST12.`) value, so
values that differ past about 12 significant digits stay separate rows
here. Non-positive weights are an error, whereas SAS drops zero weights
and ignores negative ones;
[`proc_means`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md)
makes the same deliberate choice.

Percentages are not rounded. SAS rounds only for display, and a rounded
result would fail
[`compare_parity`](https://ehrlinger.github.io/hvtiRutilities/reference/compare_parity.md)
against SAS output.

Tests of association (`CHISQ`, `FISHER`, `MEASURES` and the rest) are
deliberately absent, for the same reason
[`proc_means`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md)
has no inference statistics.

## See also

[`proc_means`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md),
[`proc_contents`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_contents.md)

## Examples

``` r
dta <- generate_survival_data(n = 200, seed = 42)

# proc freq; table dead / missing;
proc_freq(dta, "dead", missing = TRUE)
#>   dead Frequency Percent Cum_Frequency Cum_Percent
#> 1    0        92      46            92          46
#> 2    1       108      54           200         100

# proc freq; table sex * dead;
proc_freq(dta, c("sex", "dead"))
#>      sex dead Frequency Percent Row_Percent Col_Percent
#> 1 Female    0        34    17.0    44.15584    36.95652
#> 2 Female    1        43    21.5    55.84416    39.81481
#> 3   Male    0        58    29.0    47.15447    63.04348
#> 4   Male    1        65    32.5    52.84553    60.18519

# proc freq; table sex * dead / list;
proc_freq(dta, c("sex", "dead"), list = TRUE)
#>      sex dead Frequency Percent Cum_Frequency Cum_Percent
#> 1 Female    0        34    17.0            34        17.0
#> 2 Female    1        43    21.5            77        38.5
#> 3   Male    0        58    29.0           135        67.5
#> 4   Male    1        65    32.5           200       100.0
```
