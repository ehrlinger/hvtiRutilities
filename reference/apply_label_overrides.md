# Apply label overrides from a YAML file

Reads label overrides from a YAML file and applies them to a label map.
This allows study-specific label replacements (e.g., abbreviations,
corrections) to be configured externally rather than hard-coded in
analysis scripts.

The YAML file should contain a simple mapping of variable names to
labels. If the file does not exist, the label map is returned unchanged
— making it safe to call unconditionally in shared code.

## Usage

``` r
apply_label_overrides(label_map_df, overrides_file = "labels_overrides.yml")
```

## Arguments

- label_map_df:

  A data frame with `key` and `label` columns, as returned by
  [`label_map`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md).

- overrides_file:

  Path to a YAML file containing label overrides. Defaults to
  `"labels_overrides.yml"` in the current working directory.

## Value

The label map with overrides applied. Variables not mentioned in the
YAML file are left unchanged. Variables in the YAML file that are not in
the label map are appended.

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

dta <- generate_survival_data(n = 50, seed = 42)
lmap <- label_map(dta)

# Apply study-specific overrides
lmap <- apply_label_overrides(lmap, overrides_file = tmp)
lmap[lmap$key == "age", ]
#>     key               label
#> age age Patient Age (years)
unlink(tmp)
```
