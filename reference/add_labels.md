# Add or update labels in a label map

Registers new labels in an existing label map, or applies labels
directly to a data frame's variable attributes. This is the recommended
way to label derived variables (e.g., ratios, binned groups, computed
indices) that were not present in the original imported dataset.

When `label_map_df` is a label map (a data frame with `key` and `label`
columns), the map is updated and returned. When `label_map_df` is a
regular data frame (any data frame without the label map structure),
labels are applied directly to the data using
[`labelled::var_label()`](https://larmarange.github.io/labelled/reference/var_label.html),
which is the preferred approach because labels travel with the data
through `dplyr` operations.

## Usage

``` r
add_labels(label_map_df, new_labels)
```

## Arguments

- label_map_df:

  A data frame with `key` and `label` columns (as returned by
  [`label_map`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)),
  **or** any data frame to which labels should be applied directly.

- new_labels:

  A named character vector where names are variable names and values are
  descriptive labels.

## Value

When given a label map: the updated label map data frame. When given a
data frame: the data frame with labels applied via
[`labelled::var_label()`](https://larmarange.github.io/labelled/reference/var_label.html).

## See also

[`label_map`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)
to extract a label map from data,
[`apply_label_overrides`](https://ehrlinger.github.io/hvtiRutilities/reference/apply_label_overrides.md)
for bulk overrides from YAML.

## Examples

``` r
# --- Method 1: Update a label map (for reporting) ---
dta <- generate_survival_data(n = 50, seed = 42)
lmap <- label_map(dta)

# Add labels for derived variables
lmap <- add_labels(lmap, c(
  age_group  = "Age Group (<40, 40-60, >60)",
  bsa_ratio  = "BSA Ratio",
  risk_score = "Composite Risk Score"
))
tail(lmap, 4)
#>                       key                       label
#> hypertension hypertension                Hypertension
#> 1               age_group Age Group (<40, 40-60, >60)
#> 2               bsa_ratio                   BSA Ratio
#> 3              risk_score        Composite Risk Score

# --- Method 2: Label a data frame directly (preferred) ---
dta$age_group <- cut(dta$age, breaks = c(0, 40, 60, Inf),
                     labels = c("<40", "40-60", ">60"))
dta <- add_labels(dta, c(age_group = "Age Group (<40, 40-60, >60)"))
labelled::var_label(dta$age_group)
#> [1] "Age Group (<40, 40-60, >60)"
```
