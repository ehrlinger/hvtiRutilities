# Tolerance classes for SAS parity comparison

Tolerances are derived from what limits agreement for each quantity, not
tuned until things pass. Three regimes:

## Usage

``` r
parity_tolerance(class)
```

## Arguments

- class:

  One of `"count"`, `"printed"`, `"loglik"`, `"mle_stored"`,
  `"mle_printed"`, `"vcov_stored"`, `"curvature"`.

## Value

A list with `rtol` and `atol`.

## Details

- **Printed references are intervals, not numbers.** When SAS prints
  `-239.194`, the value that produced it lies in
  `[-239.1945, -239.1935)`. Half a unit in the last printed place is a
  floor that is derived.

- **Stored references carry machine precision**, so that floor does not
  apply. What remains is that two implementations run different
  optimizers on the same likelihood and converge to different points.

- **Counts are exact, or there is a bug.**

## Examples

``` r
parity_tolerance("loglik")
#> $rtol
#> [1] 0
#> 
#> $atol
#> [1] 5e-04
#> 
```
