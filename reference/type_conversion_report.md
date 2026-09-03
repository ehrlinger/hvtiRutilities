# Read the per-column type-conversion report

Returns the record
[`r_data_types`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
attaches to its result: one row per column, naming the rule that fired
and where the levels came from.

## Usage

``` r
type_conversion_report(x)
```

## Arguments

- x:

  An object returned by
  [`r_data_types`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md).

## Value

A data frame with columns `variable`, `storage_in`, `rule`,
`level_source`, `n_levels` and `storage_out`, one row per column of the
converted dataset, in column order.

## Details

A column that became a factor because it was *declared* one, and a
column that became a factor because it happened to have seven distinct
values, are otherwise the same object. This is how a caller tells them
apart.

The columns are:

- `variable` – the column name.

- `storage_in` – its class as received, before conversion.

- `rule` – one of `"value_labels"`, `"binary_logical"`,
  `"binary_factor"`, `"character_factor"`, `"n_distinct_factor"`,
  `"unchanged"` or `"skipped"`. `"unchanged"` means every rule was
  tested and none fired; `"skipped"` means the column was named in
  `skip_vars` and no rule was tested.

- `level_source` – `"value labels"` where the levels came from the
  column's own value labels, `"inference"` where they came from counting
  distinct values, and `NA` where no levels were made.

- `n_levels` – levels produced, or `NA` for a non-factor.

- `storage_out` – the class of the returned column.

The report is an attribute of the returned object. Operations that
rebuild a data frame – most dplyr verbs among them – drop it. Read it
directly from the
[`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
result.

## See also

[`r_data_types`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)

## Examples

``` r
converted <- r_data_types(datasets::mtcars, use_value_labels = FALSE)
type_conversion_report(converted)
#>    variable storage_in              rule level_source n_levels storage_out
#> 1       mpg    numeric         unchanged         <NA>       NA     numeric
#> 2       cyl    numeric n_distinct_factor    inference        3      factor
#> 3      disp    numeric         unchanged         <NA>       NA     numeric
#> 4        hp    numeric         unchanged         <NA>       NA     numeric
#> 5      drat    numeric         unchanged         <NA>       NA     numeric
#> 6        wt    numeric         unchanged         <NA>       NA     numeric
#> 7      qsec    numeric         unchanged         <NA>       NA     numeric
#> 8        vs    numeric    binary_logical         <NA>       NA     logical
#> 9        am    numeric    binary_logical         <NA>       NA     logical
#> 10     gear    numeric n_distinct_factor    inference        3      factor
#> 11     carb    numeric n_distinct_factor    inference        6      factor
```
