# Compare one R quantity against its SAS reference

Errors – never warns, never skips – when the quantity is absent on
either side. A comparison that cannot fail is worse than no comparison.

## Usage

``` r
compare_parity(quantity, r, sas, class, source = "lst", digits = NA_integer_)
```

## Arguments

- quantity:

  Name of the quantity, used in the report.

- r:

  Value computed in R.

- sas:

  Value from the SAS reference.

- class:

  Tolerance class; see
  [`parity_tolerance`](https://ehrlinger.github.io/hvtiRutilities/reference/parity_tolerance.md).

- source:

  Where the SAS value came from – `"lst"` or `"outhaz"`.

- digits:

  For `class = "printed"`, the number of decimal places the reference
  was printed to, as a single non-negative whole number. The tolerance
  becomes half of the last place.

## Value

A one-row data frame.

## Details

The outcome is three-state. `R_BETTER` fires only for a log-likelihood
that exceeds SAS's beyond tolerance: a multi-start optimizer regularly
beats a single-start one, and recording that as a failure would train
the reader to distrust a real improvement.

## Relative discrepancy at a zero reference

When the SAS value is zero there is no relative scale. The reported
`rel_diff` is `0` if the two agree exactly and `Inf` otherwise – never
`NA`, which
[`parity_headline`](https://ehrlinger.github.io/hvtiRutilities/reference/parity_headline.md)
would drop, reporting a real failure as no discrepancy at all.

## Examples

``` r
compare_parity("log_likelihood", r = -239.1941, sas = -239.194,
               class = "loglik")
#>         quantity         r      sas source abs_diff     rel_diff rtol  atol
#> 1 log_likelihood -239.1941 -239.194    lst    1e-04 4.180707e-07    0 5e-04
#>   outcome
#> 1    PASS
```
