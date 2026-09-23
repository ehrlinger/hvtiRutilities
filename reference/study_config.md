# Read the study manifest

Walks up from `start` until a `_study.yml` is found, parses it,
validates the requested identity or data contract, and returns the
result with the study root attached.

A study without a manifest must not render, so an absent `_study.yml` is
an error rather than a set of defaults. The directories walked are named
in the error, because the usual cause is starting from outside the study
tree.

Study identity always requires `study`. With `require_data = TRUE`,
`built` is also required. It must carry its file extension, because the
reader dispatches on the extension.

## Usage

``` r
study_config(start = getwd(), require_data = TRUE)
```

## Arguments

- start:

  Character. Directory to start the upward walk from. Defaults to
  [`getwd()`](https://rdrr.io/r/base/getwd.html).

- require_data:

  Logical. If `TRUE`, require the default dataset and registered file.
  Use `FALSE` when only study identity is needed.

## Value

The manifest as a list, with `root` and `file` attached. Additive
identity and named-dataset fields are retained.

## See also

[`study_root`](https://ehrlinger.github.io/hvtiRutilities/reference/study_root.md),
[`record_provenance`](https://ehrlinger.github.io/hvtiRutilities/reference/record_provenance.md)

## Examples

``` r
root <- file.path(tempdir(), "study-example")
dir.create(root, showWarnings = FALSE)
yaml::write_yaml(
  list(study = "Example", built = "example.sas7bdat"),
  file.path(root, "_study.yml")
)
cfg <- study_config(root)
cfg$study
#> [1] "Example"
unlink(root, recursive = TRUE)
```
