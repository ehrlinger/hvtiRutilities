# Look up labels for multiple variables at once

A vectorized companion to
[`get_label`](https://ehrlinger.github.io/hvtiRutilities/reference/get_label.md).
Returns a named character vector of labels for one or more variable
names, making it convenient to label axes, table columns, or multi-panel
plots in a single call.

Variables not found in the label map cause an error (just like
`get_label`), so typos are caught immediately.

## Usage

``` r
get_labels(label_map_df, variables)
```

## Arguments

- label_map_df:

  A data frame with `key` and `label` columns, as returned by
  [`label_map`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md).

- variables:

  A character vector of variable names to look up.

## Value

A named character vector with names equal to `variables` and values
equal to the corresponding labels.

## See also

[`get_label`](https://ehrlinger.github.io/hvtiRutilities/reference/get_label.md)
for single-variable lookup,
[`label_map`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)
to extract a label map from data.

## Examples

``` r
dta <- generate_survival_data(n = 50, seed = 42)
lmap <- label_map(dta)

# Look up several labels at once
get_labels(lmap, c("age", "bmi", "hgb_bs"))
#>                          age                          bmi 
#>     "Age at surgery (years)"    "Body mass index (kg/m2)" 
#>                       hgb_bs 
#> "Baseline hemoglobin (g/dL)" 

# Useful for table column headers
vars <- c("age", "bmi", "lvefvs_b")
headers <- get_labels(lmap, vars)
print(headers)
#>                                 age                                 bmi 
#>            "Age at surgery (years)"           "Body mass index (kg/m2)" 
#>                            lvefvs_b 
#> "Baseline LV ejection fraction (%)" 
```
