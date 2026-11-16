# Assert the cohort matches a job-level expectation

Compares
[`cohort_counts`](https://ehrlinger.github.io/hvtiRutilities/reference/cohort_counts.md)
against explicitly supplied expected counts and errors on any
disagreement. Call it before any analysis that would otherwise run
happily on an unreconciled cohort.

## Usage

``` r
assert_cohort(data, expected, time_col, event_col)
```

## Arguments

- data:

  A data frame. Was `d` before 2026-11; `d =` still works for one
  release, with a warning.

- expected:

  List containing nonnegative integer `n`, `n_events` and `n_censored`.

- time_col:

  Character scalar naming the time column. Was `time` before 2026-11;
  `time =` still works for one release, with a warning.

- event_col:

  Character scalar naming the binary event column. Was `event` before
  2026-11; `event =` still works for one release, with a warning.

## Value

`invisible(TRUE)` on success; otherwise an error.

## Argument order

`time_col, event_col`, as in
[`survival::Surv()`](https://rdrr.io/pkg/survival/man/Surv.html); it was
`event, time` until 2026-11. A call passing both unnamed is an error,
since the two orders read it oppositely; name `time_col =` and
`event_col =`.

## See also

[`cohort_counts`](https://ehrlinger.github.io/hvtiRutilities/reference/cohort_counts.md)

## Examples

``` r
d <- data.frame(dead = c(1, 1, 0, 0, 0), iv_dead = 1:5)
expected <- list(n = 5L, n_events = 2L, n_censored = 3L)
assert_cohort(d, expected, time_col = "iv_dead", event_col = "dead")
```
