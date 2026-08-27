# Concepts represented more than once among selected covariates

[`concept_map`](https://ehrlinger.github.io/hvtiRutilities/reference/concept_map.md)
and
[`prune_to_one_form`](https://ehrlinger.github.io/hvtiRutilities/reference/prune_to_one_form.md)
act on a candidate pool **before** a screen. This is the after-the-fact
view, and it is the only one available for a job run without pruning –
which is the case for any faithful reproduction of a SAS `%macro model`,
since SAS had no notion of a concept.

## Usage

``` r
selection_crowding(selected, aliases = character(0), ...)
```

## Arguments

- selected:

  Character vector of phase-qualified selected parameter names.

- aliases:

  Named character vector, as for
  [`concept_of`](https://ehrlinger.github.io/hvtiRutilities/reference/concept_of.md).
  Only those whose target was selected in a given phase are forwarded,
  because
  [`concept_map`](https://ehrlinger.github.io/hvtiRutilities/reference/concept_map.md)
  refuses an alias pointing outside its pool – right for a *candidate*
  pool, wrong here, where a parent form may legitimately be absent
  (`in_arin` can be selected while `area_int` is not).

- ...:

  Passed to
  [`concept_map`](https://ehrlinger.github.io/hvtiRutilities/reference/concept_map.md).

## Value

A data frame with columns `phase`, `concept`, `n_forms` and `forms`,
ordered by phase then decreasing `n_forms`. Empty when nothing is
crowded.

## Details

**Why it is worth reporting.** A step budget is shared: `max_steps` caps
total steps across both phases. So a slot spent on a second form of a
concept already in the model is a slot no other variable could have.
When the selection also stopped *on* the cap, the two facts together say
the model is not merely budget-limited but budget-limited **by
redundancy** – and neither fact is visible in a coefficient table.

Grouping is
[`concept_map`](https://ehrlinger.github.io/hvtiRutilities/reference/concept_map.md)'s,
so it is conservative by construction. Under-grouping only understates
crowding; over-grouping would assert two clinical concepts are one. This
errs the safe way, and the result is a **floor**: a concept nobody
listed is still counted as separate variables.

`selected` is phase-qualified, as
`setdiff(names(coef(sel)), names(coef(base)))` returns it: `"late.age"`,
`"early.zexp2"`. Phases are counted separately – one form of age in each
phase is two slots but not a crowded concept.

## See also

[`concept_map`](https://ehrlinger.github.io/hvtiRutilities/reference/concept_map.md),
[`prune_to_one_form`](https://ehrlinger.github.io/hvtiRutilities/reference/prune_to_one_form.md)

## Examples

``` r
selection_crowding(c("early.age", "early.ln_age", "late.bsa"))
#>   phase concept n_forms       forms
#> 1 early     age       2 age, ln_age
```
