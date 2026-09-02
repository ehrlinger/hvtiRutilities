# Path to the study's built dataset

Resolves `<study root>/datasets/<built>`, where `built` is the filename
declared in `_study.yml`. The path is not checked for existence.

## Usage

``` r
built_path(cfg = study_config())
```

## Arguments

- cfg:

  List. A study manifest from
  [`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md).

## Value

Character(1). The path to the built dataset.

## See also

[`built_manifest`](https://ehrlinger.github.io/hvtiRutilities/reference/built_manifest.md),
[`read_built`](https://ehrlinger.github.io/hvtiRutilities/reference/read_built.md)

## Examples

``` r
root <- file.path(tempdir(), "built-path-example")
dir.create(file.path(root, "datasets"), recursive = TRUE,
           showWarnings = FALSE)
yaml::write_yaml(
  list(study = "Example", built = "example.sas7bdat",
       cohort = list(n = 10L, n_events = 4L, n_censored = 6L,
                     event = "dead", time = "iv_dead")),
  file.path(root, "_study.yml")
)
built_path(study_config(root))
#> [1] "/tmp/RtmpGXT8BZ/built-path-example/datasets/example.sas7bdat"
unlink(root, recursive = TRUE)
```
