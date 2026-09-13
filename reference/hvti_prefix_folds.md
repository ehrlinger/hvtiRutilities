# Legacy prefixes folded into a taxonomy prefix

A legacy prefix that names the same job as a prefix in
[`hvti_taxonomy`](https://ehrlinger.github.io/hvtiRutilities/reference/hvti_taxonomy.md),
so a census counts its files under that prefix. `pm` folds into `lm`: a
review of the job catalog on 2026-09-11 found that the propensity work
filed as `pm` belongs with the logistic models in `lm`.

## Usage

``` r
hvti_prefix_folds()
```

## Value

A named character vector, `c(legacy = prefix)`.

## Details

The map is stored, never derived. A fold is a judgement about what a
legacy name means, and a rule that inferred it from spelling would also
fold names that merely look alike. Every name is absent from
[`hvti_taxonomy()`](https://ehrlinger.github.io/hvtiRutilities/reference/hvti_taxonomy.md)
and every value is present in it; the tests pin both.

## See also

[`job_files`](https://ehrlinger.github.io/hvtiRutilities/reference/job_files.md),
which applies it.

## Examples

``` r
hvti_prefix_folds()
#>   pm 
#> "lm" 
```
