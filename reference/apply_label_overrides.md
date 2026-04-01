# Apply label overrides from a YAML file

Reads label overrides from a YAML file and applies them to a label map
**or** directly to a data frame. This allows study-specific label
replacements (e.g., abbreviations, corrections) to be configured
externally rather than hard-coded in analysis scripts.

The YAML file should contain a simple mapping of variable names to
labels. If the file does not exist, the input is returned unchanged —
making it safe to call unconditionally in shared code.

When `data` is a label map (a data frame with `key` and `label`
columns), the overrides are applied to the map. When `data` is any other
data frame, labels are applied directly to the data via
[`add_labels`](https://ehrlinger.github.io/hvtiRutilities/reference/add_labels.md),
which is the preferred data-first workflow.

## Usage

``` r
apply_label_overrides(data, overrides_file = "labels_overrides.yml")
```

## Arguments

- data:

  A data frame: either a label map (with `key` and `label` columns, as
  returned by
  [`label_map`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)),
  or any data frame whose columns should be labeled directly.

- overrides_file:

  Path to a YAML file containing label overrides. Defaults to
  `"labels_overrides.yml"` in the current working directory.

## Value

When given a label map: the updated label map data frame. When given a
data frame: the data frame with labels applied via
[`labelled::var_label()`](https://larmarange.github.io/labelled/reference/var_label.html).
In both cases, variables not mentioned in the YAML file are left
unchanged.

## Details

The YAML file format is a simple mapping of variable names to labels:

    age_binned: "Age Group"
    bsa_ratio: "BSA Ratio"
    cavv_area: "Common AVV Area"

This design keeps study-specific label customizations in configuration
rather than code. Each study gets its own `labels_overrides.yml`
alongside its `config.yml`, and shared helper functions never contain
hard-coded replacements.

## See also

[`add_labels`](https://ehrlinger.github.io/hvtiRutilities/reference/add_labels.md)
for programmatic label updates,
[`label_map`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)
for extracting labels from data.

## Examples

``` r
# Create a temporary YAML overrides file
tmp <- tempfile(fileext = ".yml")
writeLines(c(
  "age: 'Patient Age (years)'",
  "bsa_ratio: 'Body Surface Area Ratio'"
), tmp)

# --- On a label map ---
dta <- generate_survival_data(n = 50, seed = 42)
lmap <- label_map(dta)
lmap <- apply_label_overrides(lmap, overrides_file = tmp)
lmap[lmap$key == "age", ]
#>     key               label
#> age age Patient Age (years)

# --- Directly on data (preferred) ---
dta <- apply_label_overrides(dta, overrides_file = tmp)
labelled::var_label(dta$age)
#> [1] "Patient Age (years)"

unlink(tmp)
```
