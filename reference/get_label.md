# Look up the label for a single variable

Returns the descriptive label for one variable name from a label map.
This is a safer alternative to the manual
[`match()`](https://rdrr.io/r/base/match.html) pattern, providing clear
errors on typos and missing variables.

## Usage

``` r
get_label(label_map_df, variable)
```

## Arguments

- label_map_df:

  A data frame with `key` and `label` columns, as returned by
  [`label_map`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md).

- variable:

  A single character string: the variable name to look up.

## Value

A single character string: the label for the requested variable.

## Examples

``` r
dta <- generate_survival_data(n = 50, seed = 42)
lmap <- label_map(dta)

get_label(lmap, "age")
#> [1] "Age at surgery (years)"
get_label(lmap, "hgb_bs")
#> [1] "Baseline hemoglobin (g/dL)"

# Use in plot titles
var <- "lvefvs_b"
plot(dta[[var]], main = get_label(lmap, var), ylab = get_label(lmap, var))
```
