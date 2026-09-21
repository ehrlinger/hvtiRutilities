# Register a study dataset

Completes the default study data contract or adds one distinctly named
dataset. The function derives row and cohort counts from the file and
replaces `_study.yml` and `manifest.yaml` only after both updated files
have been prepared successfully.

## Usage

``` r
register_data(
  root = getwd(),
  built,
  event = NULL,
  time = NULL,
  dataset = "study",
  role = c("study", "named"),
  population = NULL,
  source = NULL,
  extract_date = NULL,
  catalog_dataset = NULL,
  release_id = NULL
)
```

## Arguments

- root:

  Character. Study root or a directory beneath it.

- built:

  Character(1). Dataset filename within the logical `datasets`
  directory, including its extension.

- event, time:

  Character(1) or `NULL`. Event and follow-up columns. Supply both or
  neither. The default study dataset requires both.

- dataset:

  Character(1). Logical dataset name. `"study"` is reserved for the
  default.

- role:

  Character. Either `"study"` or `"named"`.

- population:

  Character(1) or `NULL`. Population description.

- source:

  Character(1) or `NULL`. Data-source description.

- extract_date:

  Character, `Date`, or `NULL`. Extraction date. The file modification
  date is used when omitted.

- catalog_dataset, release_id:

  Character(1) or `NULL`. Producer catalog dataset ID and exact
  published release ID. Supply both to make the study contract
  release-aware, or neither for a legacy registration.

## Value

An object of class `"study_status"`, returned visibly.

## See also

[`study_setup`](https://ehrlinger.github.io/hvtiRutilities/reference/study_setup.md),
[`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md),
[`update_manifest`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)
