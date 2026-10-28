# Check a study for published dataset updates

**Deprecated.** Catalog releases are retired; use
[`study_status`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md)
or
[`verify_manifest`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md).

Compares each release-aware dataset contract with its producer-owned
catalog. The check verifies the pinned release and every later published
candidate without changing `_study.yml`, `manifest.yaml`, or any cache
file. Legacy dataset contracts have no update rows.

## Usage

``` r
check_data_updates(cfg = study_config(), dataset = NULL)
```

## Arguments

- cfg:

  List. A study manifest from
  [`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md).

- dataset:

  Character(1) or `NULL`. Logical dataset name. When omitted, check
  every release-aware dataset in the study.

## Value

An object of class `"data_update_report"`: a data frame with columns
`dataset`, `scope`, `pinned_release_id`, `candidate_release_id`,
`sequence`, `file`, `status`, `is_latest`, and `detail`. Status is one
of `"CURRENT"`, `"UPDATE AVAILABLE"`, `"UPDATE STATUS UNKNOWN"`,
`"WITHDRAWN"`, or `"FAIL"`.

## See also

[`review_data_update`](https://ehrlinger.github.io/hvtiRutilities/reference/review_data_update.md),
[`adopt_data_update`](https://ehrlinger.github.io/hvtiRutilities/reference/adopt_data_update.md),
[`read_built`](https://ehrlinger.github.io/hvtiRutilities/reference/read_built.md)

## Examples

``` r
root <- file.path(tempdir(), "check-data-updates-example")
invisible(study_setup(root, study = "Example", study_tracker_id = 1L, renv = FALSE))
utils::write.csv(data.frame(ccfid = 1:3, age = c(61, 70, 55)),
                 file.path(root, "00_datasets", "built.csv"),
                 row.names = FALSE)
invisible(register_data(root, built = "built.csv"))
cfg <- study_config(root)

# Deprecated: it warns and names study_status() instead. A study registered
# without a catalog release has nothing to report.
check_data_updates(cfg)
#> Warning: check_data_updates() is deprecated: catalog releases are retired. Use study_status() or verify_manifest(), whose PENDING rows report a rebuilt dataset.
#> [1] dataset              scope                pinned_release_id   
#> [4] candidate_release_id sequence             file                
#> [7] status               is_latest            detail              
#> <0 rows> (or 0-length row.names)
study_status(root)
#> Study: /tmp/Rtmp3MgToa/check-data-updates-example
#> 
#> [x] _study.yml — study: Example
#> [ ] renv.lock — no renv.lock; run renv::init() in the study project
#> [x] manifest.yaml — 1 dataset entry verified by checksum
#> [x] dataset — built.csv, registered as built_20261028.parquet
#> [ ] provenance — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> 0 .R  |  0 .qmd/.Rmd  |  0 .sas  |  0 provenance sidecars
unlink(root, recursive = TRUE)
```
