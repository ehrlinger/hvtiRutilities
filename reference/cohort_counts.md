# Count the analysable cohort

Counts rows for which both explicitly supplied event and time columns
are present, and the events among them.

The event column must be logical or numeric binary coding:
`FALSE`/`TRUE` or `0`/`1`. Rows missing either column are excluded from
the analysable cohort.

A zero or negative time is still counted, so the gate's numbers do not
move, but it warns:
[`followup_check()`](https://ehrlinger.github.io/hvtiRutilities/reference/followup_check.md)
flags the same rows for review, and the two should not disagree in
silence.

## Usage

``` r
cohort_counts(data, time_col, event_col)
```

## Arguments

- data:

  A data frame. Was `d` before 2026-11; `d =` still works for one
  release, with a warning.

- time_col:

  Character scalar naming the time column. Was `time` before 2026-11;
  `time =` still works for one release, with a warning.

- event_col:

  Character scalar naming the binary event column. Was `event` before
  2026-11; `event =` still works for one release, with a warning.

## Value

A list with integer elements `n`, `n_events` and `n_censored`.

## Argument order

`time_col, event_col`, as in
[`survival::Surv()`](https://rdrr.io/pkg/survival/man/Surv.html). Until
2026-11 the order was `event, time`, so a call passing both unnamed
means opposite things in the two orders and is an error, whether or not
`data` is named. Name them, `time_col =` and `event_col =`. One of the
two unnamed reads the same in either order.

## See also

[`assert_cohort()`](https://ehrlinger.github.io/hvtiRutilities/reference/assert_cohort.md)

## Examples

``` r
d <- data.frame(dead = c(1, 1, 0, 0, 0), iv_dead = 1:5)
cohort_counts(d, time_col = "iv_dead", event_col = "dead")
#> $n
#> [1] 5
#> 
#> $n_events
#> [1] 2
#> 
#> $n_censored
#> [1] 3
#> 
```
