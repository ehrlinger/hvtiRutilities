# The Pediatric Heart Network z-score coefficients

Returns the coefficients
[`phn_zscore()`](https://ehrlinger.github.io/hvtiRutilities/reference/phn_zscore.md)
uses, exactly as published in Table 2 of Lopez et al. (2017): for each
structure, its unit, the BSA exponent `alpha`, and the mean and standard
deviation of the indexed value `measurement / BSA^alpha`.

## Usage

``` r
phn_zscore_table()
```

## Value

A `data.frame` with one row per structure (34 rows) and columns
`structure` (the paper's abbreviation), `label` (the paper's
definition), `unit` (the unit the mean and SD are in), `alpha`, `mean`
and `sd`.

## References

Lopez L, Colan S, Stylianou M, et al. Relationship of echocardiographic
Z scores adjusted for body surface area to age, sex, race, and
ethnicity: the Pediatric Heart Network Normal Echocardiogram Database.
*Circ Cardiovasc Imaging*. 2017;10(11):e006979, Table 2.
[doi:10.1161/CIRCIMAGING.117.006979](https://doi.org/10.1161/CIRCIMAGING.117.006979)

## See also

[`phn_zscore()`](https://ehrlinger.github.io/hvtiRutilities/reference/phn_zscore.md)

## Examples

``` r
subset(phn_zscore_table(), structure %in% c("ANN", "ROOT", "STJ", "AAO"))
#>    structure                     label unit alpha mean   sd
#> 7        ANN   Aortic annular diameter   cm   0.5 1.48 0.14
#> 8       ROOT      Aortic root diameter   cm   0.5 2.06 0.18
#> 9        STJ      Sinotubular junction   cm   0.5 1.69 0.16
#> 10       AAO Ascending aortic diameter   cm   0.5 1.79 0.18
```
