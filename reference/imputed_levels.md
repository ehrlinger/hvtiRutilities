# Levels of a column that are not clean integers

On a mean-imputed column these are the imputed value, which is the
signature that imputation happened at all: a genuine 0/1 indicator has
no such level.

## Usage

``` r
imputed_levels(x)
```

## Arguments

- x:

  A vector or factor.

## Value

A character vector of the offending levels, possibly empty.

## See also

[`covariate_audit`](https://ehrlinger.github.io/hvtiRutilities/reference/covariate_audit.md)

## Examples

``` r
imputed_levels(c(0, 1, 0.714047, 1))
#> [1] "0.714047"
```
