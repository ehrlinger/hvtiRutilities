# Adopt one published dataset release

**Deprecated.** Catalog releases are retired; use
[`update_manifest`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md).

Repeats the candidate review and replaces `_study.yml` and
`manifest.yaml` as one recoverable pair. The old dated release and its
cache files remain on disk. Adoption does not make a Git commit.

The candidate must be named by its exact release ID. The value
`"latest"` is never accepted, because the reviewed release and the
adopted release must be the same object.

## Usage

``` r
adopt_data_update(cfg = study_config(), dataset = "study", release_id)
```

## Arguments

- cfg:

  List. A study manifest from
  [`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md).

- dataset:

  Character(1). Logical dataset name. Defaults to `"study"`. `"built"`
  is a second name for `"study"`.

- release_id:

  Character(1). Exact, newer, published candidate release ID.

## Value

The updated
[`study_status`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md)
object, returned visibly.

## See also

[`check_data_updates`](https://ehrlinger.github.io/hvtiRutilities/reference/check_data_updates.md),
[`review_data_update`](https://ehrlinger.github.io/hvtiRutilities/reference/review_data_update.md),
[`register_data`](https://ehrlinger.github.io/hvtiRutilities/reference/register_data.md)

## Examples

``` r
root <- file.path(tempdir(), "adopt-data-update-example")
invisible(study_setup(root, study = "Example", study_tracker_id = 1L, renv = FALSE))
utils::write.csv(data.frame(ccfid = 1:3, age = c(61, 70, 55)),
                 file.path(root, "00_datasets", "built.csv"),
                 row.names = FALSE)
invisible(register_data(root, built = "built.csv"))
cfg <- study_config(root)

# Deprecated: it warns and names update_manifest() instead, then stops,
# because this study is not pinned to a catalog release.
try(adopt_data_update(cfg, release_id = "surgery_cohort-20260921-r1"))
#> Warning: adopt_data_update() is deprecated: catalog releases are retired. Use update_manifest(), which promotes a rebuilt dataset to a new dated version.
#> Error : review_data_update(): dataset 'study' is not registered to a catalog release
unlink(root, recursive = TRUE)
```
