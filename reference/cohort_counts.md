# Count the analysable cohort

Counts rows for which both explicitly supplied event and time columns
are present, and the events among them.

The event column must be logical or numeric binary coding:
`FALSE`/`TRUE` or `0`/`1`. Rows missing either column are excluded from
the analysable cohort.

## Usage

``` r
cohort_counts(d, event, time)
```

## Arguments

- d:

  A data frame.

- event:

  Character scalar naming the binary event column.

- time:

  Character scalar naming the time column.

## Value

A list with integer elements `n`, `n_events` and `n_censored`.

## See also

[`assert_cohort`](https://ehrlinger.github.io/hvtiRutilities/reference/assert_cohort.md)

## Examples

``` r
d <- data.frame(dead = c(1, 1, 0, 0, 0), iv_dead = 1:5)
cohort_counts(d, event = "dead", time = "iv_dead")
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
