# Read the study's built dataset

Reads the dataset named in `_study.yml` and normalises its types so that
both available read paths deliver the same frame.

The normalisation is not cosmetic.
[`read_clinical_data`](https://ehrlinger.github.io/hvtiRutilities/reference/read_clinical_data.md)
converts SAS 0/1 numerics to logical while
[`haven::read_sas()`](https://haven.tidyverse.org/reference/read_sas.html)
leaves them numeric, and downstream modelling code rejects a logical
status vector outright — so without this the same document would run
under one read path and fail under the other. Labelled vectors are
likewise reduced to plain vectors, keeping the SAS variable label as an
attribute because listings print labels rather than names.

## Usage

``` r
read_built(cfg = study_config())
```

## Arguments

- cfg:

  List. A study manifest from
  [`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md).

## Value

A data frame with lower-cased names, no logical columns and no
`haven_labelled` columns.

## See also

[`built_manifest`](https://ehrlinger.github.io/hvtiRutilities/reference/built_manifest.md),
[`assert_cohort`](https://ehrlinger.github.io/hvtiRutilities/reference/assert_cohort.md)

## Examples

``` r
root <- file.path(tempdir(), "read-built-example")
dir.create(file.path(root, "datasets"), recursive = TRUE,
           showWarnings = FALSE)
yaml::write_yaml(
  list(study = "Example", built = "example.csv",
       cohort = list(n = 3L, n_events = 1L, n_censored = 2L,
                     event = "dead", time = "iv_dead")),
  file.path(root, "_study.yml")
)
write.csv(data.frame(DEAD = c(1, 0, 0), IV_DEAD = 1:3),
          file.path(root, "datasets", "example.csv"), row.names = FALSE)
names(read_built(study_config(root)))
#> [1] "dead"    "iv_dead"
unlink(root, recursive = TRUE)
```
