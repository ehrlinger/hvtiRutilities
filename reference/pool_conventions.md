# Affix conventions for grouping a SAS candidate pool into concepts

Defaults for
[`concept_of`](https://ehrlinger.github.io/hvtiRutilities/reference/concept_of.md),
[`concept_map`](https://ehrlinger.github.io/hvtiRutilities/reference/concept_map.md)
and friends, describing the naming conventions a legacy `vars.sas` uses:
`ln_` (log), `in_` (inverse), `in2` (inverse squared) and a trailing `2`
(squared).

`POOL_PLAIN_SUFFIX` is the suffix untransformed measurements carry
(`crcl_pr`, `bun_pr`, `hct_pr`). `POOL_MIN_STEM` guards the prefix rule:
two characters would match half a pool by accident.

These are **defaults, not constants** – pass your study's own
conventions through the `affixes`, `plain_suffix` and `min_stem`
arguments where they differ, rather than editing a copy of this package.

## Usage

``` r
POOL_AFFIXES

POOL_PLAIN_SUFFIX

POOL_MIN_STEM
```

## Format

Character vectors, and an integer for `POOL_MIN_STEM`.

## Examples

``` r
POOL_AFFIXES
#> [1] "^ln_" "^in2" "^in_" "2$"  
pool <- c("age", "age2", "crcl_pr", "ln_crcl_pr")
concept_map(pool)
#>     variable concept representative
#> 1        age     age           TRUE
#> 2       age2     age          FALSE
#> 3    crcl_pr crcl_pr           TRUE
#> 4 ln_crcl_pr crcl_pr          FALSE
# A study whose trailing 2 does not mean "squared" drops that affix.
concept_map(pool, affixes = setdiff(POOL_AFFIXES, "2$"))
#>     variable concept representative
#> 1        age     age           TRUE
#> 2       age2    age2           TRUE
#> 3    crcl_pr crcl_pr           TRUE
#> 4 ln_crcl_pr crcl_pr          FALSE
```
