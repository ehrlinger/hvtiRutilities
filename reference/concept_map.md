# Map a candidate pool to concepts

One row per candidate: which concept it belongs to, and whether it is
that concept's representative. Returned rather than applied, so a caller
can put the map in its report **before** anything is discarded.

## Usage

``` r
concept_map(pool, prefer = character(0), aliases = character(0), ...)
```

## Arguments

- pool:

  Character vector of candidate names.

- prefer:

  Named character vector `c(concept = variable)`.

- aliases:

  Named character vector, as for
  [`concept_of`](https://ehrlinger.github.io/hvtiRutilities/reference/concept_of.md).

- ...:

  Passed to
  [`concept_of`](https://ehrlinger.github.io/hvtiRutilities/reference/concept_of.md).

## Value

A data frame with columns `variable`, `concept` and `representative`,
ordered by concept with the representative first.

## Details

`prefer` overrides which form represents a concept, as
`c(concept = variable)`. **The default is a modelling assumption, not a
neutral choice:** keeping the plain form asserts the effect is linear in
it. Measured on one study, `ln_crcl` selected in 43.8% of replicates
against 18.0% for `crcl_pr`, so defaulting to the plain form would have
*lowered* a genuine risk factor's frequency. Override where the study
has a view; the map goes into the report either way, so the choice is
visible rather than implied.

## See also

[`concept_of`](https://ehrlinger.github.io/hvtiRutilities/reference/concept_of.md),
[`prune_to_one_form`](https://ehrlinger.github.io/hvtiRutilities/reference/prune_to_one_form.md)

## Examples

``` r
concept_map(c("age", "ln_age", "age2", "agee"))
#>   variable concept representative
#> 1      age     age           TRUE
#> 3     age2     age          FALSE
#> 2   ln_age     age          FALSE
#> 4     agee    agee           TRUE
```
