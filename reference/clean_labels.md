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

  A data frame (label map or dataset) passed to
  [`apply_label_overrides`](https://ehrlinger.github.io/hvtiRutilities/reference/apply_label_overrides.md).

- overrides_file:

  Path to a YAML file containing label overrides. Defaults to
  `"labels_overrides.yml"`.

## Value

When given a label map: the updated label map data frame. When given a
data frame: the data frame with labels applied via
[`labelled::var_label()`](https://larmarange.github.io/labelled/reference/var_label.html).
In both cases, variables not mentioned in the YAML file are left
unchanged.

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
