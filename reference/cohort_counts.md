# Count the analysable cohort

Counts rows for which both the event and the time column declared in
`_study.yml` are present, and the events among them.

**The missingness filter may be vacuous on a given study.** Where the
upstream build has already filtered the cohort, both columns have no
missing values and this reduces to `nrow(d)` and the event total. The
filter is kept because it is the correct definition of analysable and it
stops a future dataset with genuine missingness from being miscounted -
but a passing cohort gate is not evidence that the filtering works.

The event column may arrive logical or numeric depending on the read
path, so the comparison is against `1`, which is correct for both. Do
not simplify it to `sum(d[[event]])`.

## Usage

``` r
cohort_counts(d, cfg = study_config())
```

## Arguments

- d:

  A data frame, typically from
  [`read_built`](https://ehrlinger.github.io/hvtiRutilities/reference/read_built.md).

- cfg:

  List. A study manifest from
  [`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md);
  supplies `cohort$event` and `cohort$time`.

## Value

A list with integer elements `n`, `n_events` and `n_censored`.

## See also

[`assert_cohort`](https://ehrlinger.github.io/hvtiRutilities/reference/assert_cohort.md)

## Examples

``` r
cfg <- list(cohort = list(event = "dead", time = "iv_dead"))
d <- data.frame(dead = c(1, 1, 0, 0, 0), iv_dead = 1:5)
cohort_counts(d, cfg)
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
