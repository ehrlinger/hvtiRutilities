# Register a study dataset

Completes the default study data contract or adds one distinctly named
dataset. The function derives row and column counts from the file and
replaces `_study.yml` and `manifest.yaml` only after both updated files
have been prepared successfully.

Registration converts the file once to a dated parquet in the same
folder, `<name>_YYYYMMDD.parquet`, with its column record beside it as
`<name>_YYYYMMDD.schema.csv`. That parquet is what
[`read_built`](https://ehrlinger.github.io/hvtiRutilities/reference/read_built.md)
and the job templates read, so the source file may be rebuilt freely;
run
[`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)
to register a rebuilt file as a new version. The date is the file's
modification date unless `extract_date` is given. Conversion needs the
arrow package. A release-aware registration (`catalog_dataset` and
`release_id`) records the catalog's file as it is and converts nothing.

A dataset is registered once: registering it again stops with "already
registered". So a study whose datasets are already registered adds
`kind`, `key` or `parents` by editing that dataset's entry in
`_study.yml`, then running
[`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md).
The key is checked when the next version is registered. A combined
dataset records its parents' versions only once its source has been
rebuilt, and reads as out of date until then. A release-aware dataset is
skipped by
[`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md):
its parents' versions are recorded when a release is adopted with
[`adopt_data_update()`](https://ehrlinger.github.io/hvtiRutilities/reference/adopt_data_update.md),
and its key is checked only at registration.

## Usage

``` r
register_data(
  root = getwd(),
  built,
  dataset = "study",
  role = c("study", "named"),
  population = NULL,
  source = NULL,
  extract_date = NULL,
  catalog_dataset = NULL,
  release_id = NULL,
  kind = NULL,
  key = NULL,
  parents = NULL
)
```

## Arguments

- root:

  Character. Study root or a directory beneath it.

- built:

  Character(1). Dataset filename within the logical `datasets`
  directory, including its extension.

- dataset:

  Character(1). Logical dataset name. `"study"` is reserved for the
  default, and `"built"` is a second name for it.

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

- kind:

  Character(1) or `NULL`. What the dataset is: `"built"` (the study
  dataset), `"subset"`, `"ancillary"` (many rows per patient, such as
  echoes or labs, joined to the cohort by a job) or `"combined"` (built
  by joining others).

- key:

  Character or `NULL`. The columns that make each row unique, such as
  `c("ccfid", "echo_date")`. Checked at registration, which stops if any
  row repeats on it. Jobs use it unless they set their own.

- parents:

  Character or `NULL`. For `kind = "combined"` only: the registered
  datasets it was built from. Their current versions are recorded, so a
  later update to a parent marks this dataset out of date.

## Value

An object of class `"study_status"`, returned visibly.

## See also

[`study_setup`](https://ehrlinger.github.io/hvtiRutilities/reference/study_setup.md),
[`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md),
[`update_manifest`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)
