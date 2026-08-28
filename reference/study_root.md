# Locate the study root

Returns the absolute path of the directory holding `_study.yml`, found
by walking up from `start`. Errors if there is none, naming the
directories walked.

## Usage

``` r
study_root(start = getwd())
```

## Arguments

- start:

  Character. Directory to start the upward walk from. Defaults to
  [`getwd()`](https://rdrr.io/r/base/getwd.html).

## Value

Character(1). The absolute path of the study root.

## See also

[`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md),
[`sas_path`](https://ehrlinger.github.io/hvtiRutilities/reference/sas_path.md)

## Examples

``` r
root <- file.path(tempdir(), "study-root-example")
dir.create(root, showWarnings = FALSE)
yaml::write_yaml(
  list(study = "Example", built = "example.sas7bdat",
       cohort = list(n = 10L, n_events = 4L, n_censored = 6L,
                     event = "dead", time = "iv_dead")),
  file.path(root, "_study.yml")
)
study_root(root)
#> [1] "/tmp/Rtmp0vRjL6/study-root-example"
unlink(root, recursive = TRUE)
```
