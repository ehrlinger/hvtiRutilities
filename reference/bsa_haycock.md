# Body surface area by the Haycock formula

Computes body surface area (BSA) from height and weight with the formula
of Haycock, Schwartz and Wisotsky (1978):
`BSA (m^2) = 0.024265 * weight(kg)^0.5378 * height(cm)^0.3964`. This is
the formula the Pediatric Heart Network used for its echocardiographic
z-scores, so it is the one
[`phn_zscore()`](https://ehrlinger.github.io/hvtiRutilities/reference/phn_zscore.md)
uses.

Give the height and weight measured at the echocardiogram, not at birth.

## Usage

``` r
bsa_haycock(height_cm, weight_kg)
```

## Arguments

- height_cm:

  Numeric vector of heights (lengths, for infants) in cm.

- weight_kg:

  Numeric vector of weights in kg, the same length as `height_cm` or
  length 1.

## Value

A numeric vector of BSA in m^2, `NA` where either input is `NA`.

## References

Haycock GB, Schwartz GJ, Wisotsky DH. Geometric method for measuring
body surface area: a height-weight formula validated in infants,
children, and adults. *J Pediatr*. 1978;93(1):62-66.
[doi:10.1016/s0022-3476(78)80601-5](https://doi.org/10.1016/s0022-3476%2878%2980601-5)

## See also

[`phn_zscore()`](https://ehrlinger.github.io/hvtiRutilities/reference/phn_zscore.md)

## Examples

``` r
bsa_haycock(height_cm = 50, weight_kg = 3.5)
#> [1] 0.224415
```
