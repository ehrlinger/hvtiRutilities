# Review a rebuilt study dataset before registering it

Compares the working dataset, as it stands in the study's datasets
folder, with its registered version, the dated parquet jobs read. It
reads both and writes nothing. Run it after a rebuild and before
[`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md),
which registers the rebuilt file as the next version. It describes how
the data changed; it does not certify that the new file is analytically
or clinically correct.

## Usage

``` r
review_built(cfg = study_config(), dataset = "study")
```

## Arguments

- cfg:

  List. A study manifest from
  [`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md).

- dataset:

  Character(1). Logical dataset name. Defaults to `"study"`. `"built"`
  is a second name for `"study"`.

## Value

An object of class `"built_review"` with

- dataset:

  The logical dataset name.

- registered:

  The current version record from `manifest.yaml`.

- working:

  A list with the source file's `sha256`, `n_rows` and `n_cols`.

- changed:

  `TRUE` when the source differs from the registered version.

- comparison:

  A
  [`compare_datasets`](https://ehrlinger.github.io/hvtiRutilities/reference/compare_datasets.md)
  result, or `NULL` when unchanged.

## See also

[`update_manifest`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md),
[`read_built`](https://ehrlinger.github.io/hvtiRutilities/reference/read_built.md)

## Examples

``` r
if (requireNamespace("arrow", quietly = TRUE)) {
  root <- file.path(tempdir(), "review-built-example")
  suppressMessages(study_setup(root, "Example", 1L))
  path <- file.path(study_dir("datasets", root), "example.csv")
  write.csv(data.frame(DEAD = c(1, 0, 0), IV_DEAD = 1:3), path, row.names = FALSE)
  suppressMessages(register_data(root, "example.csv"))
  write.csv(data.frame(DEAD = c(1, 0, 0, 1), IV_DEAD = 1:4), path, row.names = FALSE)
  review_built(study_config(root))
  unlink(root, recursive = TRUE)
}
```
