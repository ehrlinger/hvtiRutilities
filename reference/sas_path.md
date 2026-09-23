# Build a path under the study root

Joins its arguments onto the study root. A first component naming a
logical study directory is resolved through the study's numbered or
legacy layout. Other components are passed through unchanged. Use this
instead of any literal path: the same study is mounted at different
absolute paths on the analysis server and on a laptop.

## Usage

``` r
sas_path(..., start = getwd())
```

## Arguments

- ...:

  Character. Path components, passed to
  [`file.path()`](https://rdrr.io/r/base/file.path.html).

- start:

  Character. Directory to start the upward walk from. Defaults to
  [`getwd()`](https://rdrr.io/r/base/getwd.html).

## Value

Character(1). The joined path. It is not checked for existence.

## See also

[`study_root`](https://ehrlinger.github.io/hvtiRutilities/reference/study_root.md)

## Examples

``` r
root <- file.path(tempdir(), "sas-path-example")
dir.create(file.path(root, "datasets"), recursive = TRUE,
           showWarnings = FALSE)
yaml::write_yaml(
  list(study = "Example", built = "example.sas7bdat"),
  file.path(root, "_study.yml")
)
sas_path("datasets", start = root)
#> [1] "/tmp/RtmpinUoTN/sas-path-example/datasets"
unlink(root, recursive = TRUE)
```
