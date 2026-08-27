# Prune a candidate pool to one form per concept

Prune a candidate pool to one form per concept

## Usage

``` r
prune_to_one_form(pool, ...)
```

## Arguments

- pool:

  Character vector of candidate names.

- ...:

  Passed to
  [`concept_map`](https://ehrlinger.github.io/hvtiRutilities/reference/concept_map.md).

## Value

The kept names, in the pool's original order, so the scope handed to a
screen stays stable across runs.

## See also

[`concept_map`](https://ehrlinger.github.io/hvtiRutilities/reference/concept_map.md),
[`pool_collinear_pairs`](https://ehrlinger.github.io/hvtiRutilities/reference/pool_collinear_pairs.md)

## Examples

``` r
prune_to_one_form(c("age", "ln_age", "age2", "bsa"))
#> [1] "age" "bsa"
```
