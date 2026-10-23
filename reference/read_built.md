# Read the study's built dataset

Reads the dataset named in `_study.yml` and normalises its types so that
both available read paths deliver the same frame.

For a dataset registered with
[`register_data`](https://ehrlinger.github.io/hvtiRutilities/reference/register_data.md),
the registered version (a dated parquet) is read, after its checksum is
checked. If the source file has been rebuilt since, the registered
version is still read and a message of class
`hvtiRutilities_source_changed` says so and names
[`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md).

A combined dataset (see
[`register_data`](https://ehrlinger.github.io/hvtiRutilities/reference/register_data.md))
is still read when a dataset it was built from has been updated since. A
message of class `hvtiRutilities_parent_changed`, which inherits
`hvtiRutilities_out_of_date`, names the parents' recorded and current
versions and the commands that update it. A combined dataset with no
recorded parent versions is reported the same way, as `unrecorded`,
until it is rebuilt and registered again.

Only a dated version is registered data. Any other read is a working
read: it is allowed in the interactive console and in a draft render of
a job in any stage folder of the study. It is refused in a final render
(see below), in a script run with `Rscript`, and for a job at the study
root or outside the study. A permitted working read signals a message of
class `hvtiRutilities_working_read`. Review a rebuilt source with
[`review_built()`](https://ehrlinger.github.io/hvtiRutilities/reference/review_built.md)
and register it with
[`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md).
The release branch below is deprecated.

For a release-aware contract, the pinned release is verified before
cache access. A later valid release emits a message of class
`hvtiRutilities_update_available`; an unavailable catalog or invalid
candidate emits `hvtiRutilities_update_status_unknown` and the pinned
data are still read. A changed pinned release errors with class
`hvtiRutilities_release_integrity`. A withdrawn pin errors with class
`hvtiRutilities_withdrawn_release` unless `allow_withdrawn` is `TRUE`.

The normalisation is not cosmetic.
[`read_clinical_data`](https://ehrlinger.github.io/hvtiRutilities/reference/read_clinical_data.md)
converts SAS 0/1 numerics to logical while
[`haven::read_sas()`](https://haven.tidyverse.org/reference/read_sas.html)
leaves them numeric, and downstream modelling code rejects a logical
status vector outright — so without this the same document would run
under one read path and fail under the other. Labelled vectors are
likewise reduced to plain vectors, keeping the SAS variable label as an
attribute because listings print labels rather than names.

A render counts as final when the environment variable
`HVTI_TEMPLATE_STRICT` is set to anything but empty, `0`, `false` or
`no`, as hvtiRtemplates' `render_job(final = TRUE)` sets it. A final
render, and a script run with `Rscript`, read registered data only. A
draft render of a job in any stage folder may read the working file.

## Usage

``` r
read_built(
  cfg = study_config(),
  refresh = FALSE,
  dataset = "study",
  allow_withdrawn = FALSE,
  working = .hvti_working_default()
)
```

## Arguments

- cfg:

  List. A study manifest from
  [`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md).

- refresh:

  Logical. If `TRUE`, force a re-read from the source and a reconversion
  regardless of the manifest's role or cached stamp. "The source
  changed" is not always something a timestamp can express – a rebuild
  that preserves `mtime`, a restored backup, a correction applied out of
  band. Errors if the manifest entry has `role: "primary"`: that role
  means the source has been retired and the parquet is authoritative, so
  there is nothing to refresh from. It also errors for a dataset
  registered as a dated parquet, and names
  [`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md),
  which registers a rebuilt source.

- dataset:

  Character(1). Logical dataset name. Defaults to `"study"`. `"built"`
  is a second name for `"study"`.

- allow_withdrawn:

  **Deprecated.** A dated version is never withdrawn, so there is
  nothing to allow. Logical. If `TRUE`, allow a deliberately pinned
  withdrawn release to be read for revision work. The default is
  `FALSE`.

- working:

  Logical. If `TRUE`, read the working dataset as it stands rather than
  its registered version, writing nothing. Defaults to `TRUE` when the
  environment variable `HVTI_DATA` is `"working"`. Any read that is not
  of a dated version is a working read: it is allowed in the interactive
  console and in a draft render of a job in any stage folder of the
  study. It is refused in a final render, where `HVTI_TEMPLATE_STRICT`
  is set to anything but empty, `0`, `false` or `no`, as
  `render_job(final = TRUE)` sets it. It is also refused in a script run
  with `Rscript`, and for a job at the study root or outside the study.
  A permitted working read signals a message of class
  `hvtiRutilities_working_read`.

## Value

A data frame with lower-cased names, no logical columns and no
`haven_labelled` columns.

## See also

[`built_manifest`](https://ehrlinger.github.io/hvtiRutilities/reference/built_manifest.md),
[`assert_cohort`](https://ehrlinger.github.io/hvtiRutilities/reference/assert_cohort.md)

## Examples

``` r
if (requireNamespace("arrow", quietly = TRUE)) {
  root <- file.path(tempdir(), "read-built-example")
  suppressMessages(study_setup(root, "Example", 1L, renv = FALSE))
  write.csv(data.frame(DEAD = c(1, 0, 0), IV_DEAD = 1:3),
            file.path(study_dir("datasets", root), "example.csv"), row.names = FALSE)
  suppressMessages(register_data(root, "example.csv"))
  names(read_built(study_config(root)))
  unlink(root, recursive = TRUE)
}
```
