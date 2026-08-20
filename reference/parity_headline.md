# Summarise a parity table as one reviewer-facing claim

The headline, not the badge, is the claim to report. It is falsifiable
and independent of whatever thresholds were chosen. A maximum relative
discrepancy of exactly zero across many quantities is not a triumph – it
means nothing was really compared – so it is flagged rather than
celebrated.

## Usage

``` r
parity_headline(df)
```

## Arguments

- df:

  A data frame of
  [`compare_parity`](https://ehrlinger.github.io/hvtiRutilities/reference/compare_parity.md)
  rows.

## Value

A single string.

## Examples

``` r
parity_headline(compare_parity("a", 1.0001, 1, class = "mle_printed"))
#> [1] "Across 1 compared quantities, the largest relative discrepancy was 1.00e-04."
```
