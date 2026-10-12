# Read the study manifest

Walks up from `start` until a `_study.yml` is found, parses it,
validates that every required key is present, and returns the result
with the study root attached.

A study without a manifest must not render, so an absent or incomplete
`_study.yml` is an error rather than a set of defaults. The directories
walked are named in the error, because the usual cause is starting from
outside the study tree.

Required keys are `study`, `built`, and a `cohort` block holding `n`,
`n_events`, `n_censored`, `event` and `time`. `population` and
`citation` are optional. `built` must carry its file extension, because
the reader dispatches on it.

## Usage

``` r
study_config(start = getwd())
```

## Arguments

- start:

  Character. Directory to start the upward walk from. Defaults to
  [`getwd()`](https://rdrr.io/r/base/getwd.html).

## Value

A list with elements `root`, `file`, `study`, `population`, `built`,
`citation`, and `cohort` (a list of `n`, `n_events`, `n_censored`,
`event`, `time`).

## See also

[`study_root`](https://ehrlinger.github.io/hvtiRutilities/reference/study_root.md),
[`record_provenance`](https://ehrlinger.github.io/hvtiRutilities/reference/record_provenance.md)

## Examples

``` r
root <- file.path(tempdir(), "study-example")
dir.create(root, showWarnings = FALSE)
yaml::write_yaml(
  list(study = "Example", built = "example.sas7bdat",
       cohort = list(n = 10L, n_events = 4L, n_censored = 6L,
                     event = "dead", time = "iv_dead")),
  file.path(root, "_study.yml")
)
cfg <- study_config(root)
cfg$study
#> [1] "Example"
unlink(root, recursive = TRUE)
```
