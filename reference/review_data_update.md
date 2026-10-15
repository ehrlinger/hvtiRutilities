# Review one published dataset release

**Deprecated.** Catalog releases are retired; use
[`review_built`](https://ehrlinger.github.io/hvtiRutilities/reference/review_built.md).

Verifies the pinned release and one exact, newer candidate, then
compares their structure. Review reads the source files directly; it
does not write caches or change either study manifest. It describes data
drift, but it does not certify that a candidate is analytically or
clinically correct.

## Usage

``` r
review_data_update(cfg = study_config(), dataset = "study", release_id)
```

## Arguments

- cfg:

  List. A study manifest from
  [`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md).

- dataset:

  Character(1). Logical dataset name. Defaults to `"study"`. `"built"`
  is a second name for `"study"`.

- release_id:

  Character(1). Exact candidate release ID. The value `"latest"` is not
  accepted as an alias.

## Value

An object of class `"data_update_review"` with

- dataset:

  The logical study dataset name.

- pinned,candidate:

  The catalog records for both releases.

- comparison:

  A
  [`compare_datasets`](https://ehrlinger.github.io/hvtiRutilities/reference/compare_datasets.md)
  result.

## See also

[`check_data_updates`](https://ehrlinger.github.io/hvtiRutilities/reference/check_data_updates.md),
[`adopt_data_update`](https://ehrlinger.github.io/hvtiRutilities/reference/adopt_data_update.md)

## Examples

``` r
root <- file.path(tempdir(), "review-data-update-example")
invisible(study_setup(root, study = "Example", study_tracker_id = 1L))
utils::write.csv(data.frame(ccfid = 1:3, age = c(61, 70, 55)),
                 file.path(root, "00_datasets", "built.csv"),
                 row.names = FALSE)
invisible(register_data(root, built = "built.csv"))
cfg <- study_config(root)

# Deprecated: it warns and names review_built() instead, then stops,
# because this study is not pinned to a catalog release.
try(review_data_update(cfg, release_id = "surgery_cohort-20260921-r1"))
#> Warning: review_data_update() is deprecated: catalog releases are retired. Use review_built(), which compares a rebuilt dataset with its registered version.
#> Error : review_data_update(): dataset 'study' is not registered to a catalog release
unlink(root, recursive = TRUE)
```
