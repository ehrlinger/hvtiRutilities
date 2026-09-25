# Check recorded follow-up before a time-related analysis

Summarises an event indicator and its follow-up intervals the way the
`dc-gfup` template reports them: counts for the whole cohort and its
event and censored subsets, the missing, negative and zero intervals, a
[`proc_means`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md)
table for each subset, and the rows worth a second look. It checks
recorded follow-up; it does not establish completeness against a close
date.

## Usage

``` r
followup_check(data, event, followup, identifier = NULL, max_rows = 25L)
```

## Arguments

- data:

  A data frame, one row per patient.

- event:

  Name of the event indicator: 1 or `TRUE` for an event, 0 or `FALSE`
  for censored. Missing values are allowed and counted.

- followup:

  Names of one or more follow-up interval columns, in years.

- identifier:

  `NULL` (the default), or the name of one column to show in `review`.

- max_rows:

  The most suspicious rows to return in `review`, in data order. Default
  25.

## Value

An object of class `followup_check`, a list of four components, three
data frames and a list of three:

- `cohort`:

  One row: `full`, `event`, `censored` and `missing_event` counts.

- `intervals`:

  One row per interval: `missing`, `negative` and `zero` counts, then
  `min`, `q1`, `median`, `q3`, `mean`, `sd` and `max` of the observed
  values.

- `means`:

  A named list, `full`, `event` and `censored`, of
  [`proc_means`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md)
  tables over the intervals.

- `review`:

  Up to `max_rows` suspicious rows, with the event, the intervals and
  any `identifier`.

## Details

Every argument is checked before anything is computed, and every column
that is not in `data` is named in one error, so a job with three
misspellings says so once.

A row with a missing event is counted in `missing_event` and belongs to
neither the event nor the censored subset. A row is *suspicious* when
its event is missing or any of its intervals is missing, negative or
zero.

The quartiles in `intervals` use R's default interpolated quantiles
(`type = 7`), while
[`proc_means`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md)
uses the SAS `QNTLDEF=5` estimator, so the two tables can disagree on a
small subset. The difference is deliberate: `intervals` is a quick
screen, and `means` is the table to compare against SAS.

Identifiers are never included unless named in `identifier`. Check the
result before sharing a report that shows `review` with one.

## See also

[`proc_means`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md),
[`cohort_counts`](https://ehrlinger.github.io/hvtiRutilities/reference/cohort_counts.md),
which counts the analysable cohort rather than checking follow-up.

## Examples

``` r
d <- data.frame(dead = c(1, 0, 0, NA, 1), iv_dead = c(2.5, 4, 0, 1.2, NA))
fc <- followup_check(d, event = "dead", followup = "iv_dead")
fc
#> <followup_check> event `dead`, interval(s) `iv_dead`
#>   Cohort     : 5 (2 event, 2 censored, 1 missing event)
#>   Suspicious : 3 row(s), 3 shown in $review
fc$cohort
#>   full event censored missing_event
#> 1    5     2        2             1
fc$review
#>   dead iv_dead
#> 1    0     0.0
#> 2   NA     1.2
#> 3    1      NA
```
