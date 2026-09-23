# Assert the cohort matches a job-level expectation

Compares
[`cohort_counts`](https://ehrlinger.github.io/hvtiRutilities/reference/cohort_counts.md)
against explicitly supplied expected counts and errors on any
disagreement. Call it before any analysis that would otherwise run
happily on an unreconciled cohort.

## Usage

``` r
assert_cohort(d, expected, event, time)
```

## Arguments

- d:

  A data frame.

- expected:

  List containing nonnegative integer `n`, `n_events` and `n_censored`.

- event:

  Character scalar naming the binary event column.

- time:

  Character scalar naming the time column.

## Value

`invisible(TRUE)` on success; otherwise an error.

## See also

[`cohort_counts`](https://ehrlinger.github.io/hvtiRutilities/reference/cohort_counts.md)

## Examples

``` r
d <- data.frame(dead = c(1, 1, 0, 0, 0), iv_dead = 1:5)
expected <- list(n = 5L, n_events = 2L, n_censored = 3L)
assert_cohort(d, expected, event = "dead", time = "iv_dead")
```
