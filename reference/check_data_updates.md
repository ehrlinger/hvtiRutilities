# Check a study for published dataset updates

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
if (FALSE) { # \dontrun{
cfg <- study_config()
check_data_updates(cfg)
check_data_updates(cfg, dataset = "complete_cases")
} # }
```
