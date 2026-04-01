# Compare two versions of a dataset

Summarises the differences between two data pulls of the same dataset:
added or dropped columns, row count changes, type changes, and label
changes. This is useful for auditing data drift when a new extract
arrives, and pairs naturally with the manifest system.

## Usage

``` r
compare_datasets(old, new)
```

## Arguments

- old:

  A data frame representing the previous version of the dataset.

- new:

  A data frame representing the current version of the dataset.

## Value

A list with the following elements:

- rows_old:

  Number of rows in `old`

- rows_new:

  Number of rows in `new`

- cols_added:

  Character vector of column names present in `new` but not `old`

- cols_dropped:

  Character vector of column names present in `old` but not `new`

- type_changes:

  Data frame with columns `variable`, `old_class`, `new_class` for
  shared columns whose primary class changed

- label_changes:

  Data frame with columns `variable`, `old_label`, `new_label` for
  shared columns whose label changed

## See also

[`update_manifest`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md),
[`verify_manifest`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)

## Examples

``` r
# Simulate two data pulls
v1 <- generate_survival_data(n = 100, seed = 1)
v2 <- generate_survival_data(n = 120, seed = 2)

# Add a column to v2 and drop one
v2$new_var <- rnorm(120)
v2$dead <- NULL

diff <- compare_datasets(v1, v2)
diff$rows_old
#> [1] 100
diff$rows_new
#> [1] 120
diff$cols_added
#> [1] "new_var"
diff$cols_dropped
#> [1] "dead"
```
