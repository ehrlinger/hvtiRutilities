# Record a verified study identity

Writes a Study Tracker identity into an existing `_study.yml` and marks
it verified: `identity_source: tracker` and `identity_verified: true`.
Every other key, including the data contract (`built`, `cohort`,
`additional_datasets`, `population`, `citation`), keeps its value.

## Usage

``` r
study_update_identity(identity, start = getwd())
```

## Arguments

- identity:

  A named list from the Study Tracker record. It must hold
  `study_tracker_id`, equal to the manifest's, and `study`; it may hold
  `umbrella`, `owner`, `irb_number`, `cvir_no` and
  `study_creation_date`.

- start:

  A directory inside the study; the study is found as
  [`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md)
  finds it.

## Value

The names of the keys whose values changed, invisibly.

## Details

This is the write step of verifying a manual identity. It does not read
Study Tracker or compare the record with the typed identity; the caller
does both, and passes the record only when they match. A field the
record leaves `NULL` keeps its current value.

The file is rewritten whole and atomically, as
[`register_data`](https://ehrlinger.github.io/hvtiRutilities/reference/register_data.md)
rewrites it, so comments in `_study.yml` are not kept.

## See also

[`study_setup`](https://ehrlinger.github.io/hvtiRutilities/reference/study_setup.md),
[`study_status`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md).

## Examples

``` r
root <- file.path(tempdir(), "update-identity-example")
study_setup(root, "Typed title", 42L, identity_source = "manual",
            renv = FALSE)
#> Study: /tmp/RtmpKtctbE/update-identity-example
#> 
#> [~] _study.yml — study: Typed title; identity entered by hand, confirm it with study-setup --verify
#> [ ] renv.lock — no renv.lock; run renv::init() in the study project
#> [ ] manifest.yaml — no manifest.yaml; register_data() creates it
#> [ ] dataset — no default dataset registered; run register_data()
#> [ ] provenance — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> 0 .R  |  0 .qmd/.Rmd  |  0 .sas  |  0 provenance sidecars
study_update_identity(
  list(study_tracker_id = 42L, study = "Typed title", owner = "Analyst"),
  start = root
)
study_config(root, require_data = FALSE)$identity_verified
#> [1] TRUE
unlink(root, recursive = TRUE)
```
