# Assert the cohort matches the study manifest

Compares
[`cohort_counts`](https://ehrlinger.github.io/hvtiRutilities/reference/cohort_counts.md)
against the `cohort` block of `_study.yml` and errors on any
disagreement. Call it before any analysis that would otherwise run
happily on an unreconciled cohort.

## Usage

``` r
assert_cohort(d, cfg = study_config())
```

## Arguments

- d:

  A data frame, typically from
  [`read_built`](https://ehrlinger.github.io/hvtiRutilities/reference/read_built.md).

- cfg:

  List. A study manifest from
  [`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md).

## Value

`invisible(TRUE)` on success; otherwise an error.

## See also

[`cohort_counts`](https://ehrlinger.github.io/hvtiRutilities/reference/cohort_counts.md)

## Examples

``` r
cfg <- list(cohort = list(n = 5L, n_events = 2L, n_censored = 3L,
                          event = "dead", time = "iv_dead"))
d <- data.frame(dead = c(1, 1, 0, 0, 0), iv_dead = 1:5)
assert_cohort(d, cfg)
```
