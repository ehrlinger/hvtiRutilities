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
  release_id = NULL
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
