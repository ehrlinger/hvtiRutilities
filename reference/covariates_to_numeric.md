# Apply what covariate_audit() reports

Factors whose levels are all numeric become numeric, so they enter a
model linearly the way the SAS job specifies.

A factor with a genuinely non-numeric level is **left alone** and will
be dummy-coded – the right outcome for a real categorical, and the wrong
one for a mean-imputed binary.
[`covariate_audit`](https://ehrlinger.github.io/hvtiRutilities/reference/covariate_audit.md)'s
`action` column is where a reader sees which of the two happened; check
it before reading any coefficient.

## Usage

``` r
covariates_to_numeric(data, vars)
```

## Arguments

- data:

  A data frame.

- vars:

  Character vector of covariate names.

## Value

`data`, with the convertible columns coerced to numeric.

## See also

[`covariate_audit`](https://ehrlinger.github.io/hvtiRutilities/reference/covariate_audit.md)

## Examples

``` r
d <- data.frame(hx_htn = factor(c("0", "1", "0.714047")))
str(covariates_to_numeric(d, "hx_htn"))
#> 'data.frame':    3 obs. of  1 variable:
#>  $ hx_htn: num  0 1 0.714
```
