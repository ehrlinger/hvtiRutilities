# Audit the analysis environment before running an analysis

Reports the version of every package a hazard-family analysis depends
on. Run it on the machine that will do the work, before anything else.

## Usage

``` r
preflight_report(extra = character(0))
```

## Arguments

- extra:

  Character vector of additional package names to report.

## Value

A data frame with columns `component`, `found`, `version` and `notes`.

## Details

`numDeriv` is only a *Suggests* of `TemporalHazard`, so
`install_github()` does not pull it. Its absence silently costs standard
errors on any interval- or left-censored multiphase fit: the analytic
multiphase Hessian declines for those statuses by design and the
optimizer falls back to `numDeriv`; with it missing there is no third
option, and [`vcov()`](https://rdrr.io/r/stats/vcov.html) returns a bare
logical while `rcond` and `pd` come back `NA` with nothing naming the
cause.

`R` itself is reported from `R.version`, not from
[`packageVersion()`](https://rdrr.io/r/utils/packageDescription.html),
so it is dropped from the package list: a caller who names it in `extra`
would otherwise get a second `R` row reporting it as not found.

## Examples

``` r
preflight_report()
#>         component found version
#> 1               R  TRUE   4.6.1
#> 2  TemporalHazard FALSE        
#> 3  hvtiRutilities  TRUE   1.1.2
#> 4           haven  TRUE   2.5.5
#> 5        survival  TRUE   3.8.6
#> 6       hvtiPlotR FALSE        
#> 7        testthat  TRUE   3.3.2
#> 8          quarto  TRUE   1.5.1
#> 9         ggplot2  TRUE   4.0.3
#> 10       numDeriv FALSE        
#>                                                                                                                      notes
#> 1                                                                                                                         
#> 2                                                                                                                         
#> 3                                                                                                                         
#> 4                                                                                                                         
#> 5                                                                                                                         
#> 6                                                                                                                         
#> 7                                                                                                                         
#> 8                                                                                                                         
#> 9                                                                                                                         
#> 10 Suggests-only for TemporalHazard; absence silently costs standard errors on interval- or left-censored multiphase fits.
```
