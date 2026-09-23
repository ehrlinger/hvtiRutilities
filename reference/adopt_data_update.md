# Adopt one published dataset release

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

  Character(1). Logical dataset name. Defaults to `"study"`.

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
if (FALSE) { # \dontrun{
adopt_data_update(
  study_config(),
  release_id = "surgery_cohort-20260921-r1"
)
} # }
```
