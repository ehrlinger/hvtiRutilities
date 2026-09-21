# Review one published dataset release

Verifies the pinned release and one exact, newer candidate, then
compares their structure and cohort counts. Review reads the source
files directly; it does not write caches or change either study
manifest. It describes data drift, but it does not certify that a
candidate is analytically or clinically correct.

## Usage

``` r
review_data_update(cfg = study_config(), dataset = "study", release_id)
```

## Arguments

- cfg:

  List. A study manifest from
  [`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md).

- dataset:

  Character(1). Logical dataset name. Defaults to `"study"`.

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

- cohort_old,cohort_new:

  Cohort counts, or `NULL` when the selected dataset has no cohort
  contract.

## See also

[`check_data_updates`](https://ehrlinger.github.io/hvtiRutilities/reference/check_data_updates.md),
[`adopt_data_update`](https://ehrlinger.github.io/hvtiRutilities/reference/adopt_data_update.md)

## Examples

``` r
if (FALSE) { # \dontrun{
review_data_update(
  study_config(),
  release_id = "surgery_cohort-20260921-r1"
)
} # }
```
