# Apply label overrides from a YAML file (deprecated)

**Deprecated.** Use
[`apply_label_overrides()`](https://ehrlinger.github.io/hvtiRutilities/reference/apply_label_overrides.md)
instead. `clean_labels()` has been renamed for clarity. This function is
kept as an alias for backward compatibility.

## Usage

``` r
clean_labels(label_map_df, overrides_file = "labels_overrides.yml")
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

## Examples

``` r
# Use apply_label_overrides() instead
tmp <- tempfile(fileext = ".yml")
writeLines("age: 'Patient Age (years)'", tmp)

library(labelled)
dta <- data.frame(age = c(25, 30, 35))
var_label(dta$age) <- "Patient Age"
lmap <- label_map(dta)

lmap <- clean_labels(lmap, overrides_file = tmp)
#> Warning: clean_labels() is deprecated; use apply_label_overrides() instead.
unlink(tmp)
```
