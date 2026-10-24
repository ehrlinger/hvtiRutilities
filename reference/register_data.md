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

  Character(1). The dataset's name. Choose it only with
  `role = "named"`; `role = "study"` requires the default,
  `dataset = "study"`. A name starts with a lowercase letter and uses
  only lowercase letters, digits and underscores. `"study"` and
  `"built"` are reserved, `"built"` being a second name for the study
  dataset. Read the dataset back with `read_built(dataset = "<name>")`.

- role:

  Character(1). Takes one value, which picks the slot the dataset fills.
  `"study"`, the default when the argument is left out, registers the
  study's single main dataset. It is recorded under `built:` in
  `_study.yml` and read by
  [`read_built()`](https://ehrlinger.github.io/hvtiRutilities/reference/read_built.md)
  with no arguments. A study has exactly one, so registering it a second
  time stops with "already registered". `"named"` adds another dataset
  under the name given in `dataset`. It is recorded under
  `additional_datasets:` and read with `read_built(dataset = "<name>")`.

- population:

  Character(1) or `NULL`. Population description.

- source:

  Character(1) or `NULL`. Data-source description.

- extract_date:

  Character, `Date`, or `NULL`. Extraction date. The file modification
  date is used when omitted.

- catalog_dataset, release_id:

  **Deprecated.** Catalog releases are retired; use a build record
  sidecar and plain `register_data()`. Character(1) or `NULL`. Producer
  catalog dataset ID and exact published release ID. Supply both to make
  the study contract release-aware, or neither for a legacy
  registration. A dataset already registered as dated versions cannot be
  moved to a release this way: that would drop every registered version.

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
  later update to a parent marks this dataset out of date. `"built"` is
  a second name for `"study"`.

## Value

An object of class `"study_status"`, returned visibly.

## Where a subset goes

A subset of the study dataset has three homes, and which to pick depends
on who needs it.

- A `WHERE` condition in one job writes no file. The job's
  `hvtiRtemplates::read_job_data()` applies the condition and records
  it. Use this for a subset that only one job analyses.

- An analysis set from `hvtiRdatabuild::write_analysis_set()` is saved
  as `00_datasets/<name>.parquet` with `<name>.set.yml` beside it, and
  is derived from the study dataset only. A job reads it with
  `DATASET <- "built"` and `ANALYSIS_SET <- "<name>"`. Use this for a
  subset of the study dataset that several jobs share.

- A separately registered dataset, `role = "named"` with
  `kind = "subset"`, is for a subset built some other way, such as from
  a second source or by a script outside the study's build.

Exclusions that define the cohort itself belong in the build job
(`hvtiRtemplates::build_cohort()`), not in a subset.

## See also

[`study_setup`](https://ehrlinger.github.io/hvtiRutilities/reference/study_setup.md),
[`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md),
[`update_manifest`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)

## Examples

``` r
root <- file.path(tempdir(), "register-data-example")
invisible(study_setup(root, study = "Example", study_tracker_id = 1L, renv = FALSE))
utils::write.csv(data.frame(ccfid = 1:3, age = c(61, 70, 55)),
                 file.path(root, "00_datasets", "built.csv"),
                 row.names = FALSE)
register_data(root, built = "built.csv", key = "ccfid")
#> Study: /tmp/RtmpE17TJa/register-data-example
#> 
#> [x] _study.yml — study: Example
#> [ ] renv.lock — no renv.lock; run renv::init() in the study project
#> [x] manifest.yaml — 1 dataset entry verified by checksum
#> [x] dataset — built.csv, registered as built_20261024.parquet
#> [ ] provenance — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> 0 .R  |  0 .qmd/.Rmd  |  0 .sas  |  0 provenance sidecars
# The CSV is kept; the registered version is a dated Parquet file.
list.files(file.path(root, "00_datasets"))
#> [1] "built.csv"                 "built_20261024.parquet"   
#> [3] "built_20261024.schema.csv"
unlink(root, recursive = TRUE)

# An additional dataset is registered with role = "named", under a name of
# its own, and read back by that name.
root <- file.path(tempdir(), "register-data-named-example")
invisible(study_setup(root, study = "Example", study_tracker_id = 1L, renv = FALSE))
utils::write.csv(data.frame(ccfid = 1:3, age = c(61, 70, 55)),
                 file.path(root, "00_datasets", "built.csv"),
                 row.names = FALSE)
invisible(register_data(root, built = "built.csv", key = "ccfid"))
utils::write.csv(
  data.frame(ccfid = c(1, 1, 2), echo_date = c("2020-01-05", "2020-06-01", "2020-02-10"),
             lvef = c(55, 50, 60)),
  file.path(root, "00_datasets", "echo.csv"),
  row.names = FALSE
)
invisible(register_data(root, built = "echo.csv", dataset = "echo", role = "named",
                        kind = "ancillary", key = c("ccfid", "echo_date")))
read_built(study_config(root), dataset = "echo")
#>   ccfid  echo_date lvef
#> 1     1 2020-01-05   55
#> 2     1 2020-06-01   50
#> 3     2 2020-02-10   60
unlink(root, recursive = TRUE)
```
