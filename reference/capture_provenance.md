# Capture an explicit job provenance payload

Freezes the study identity, executing R session, loaded packages,
lockfile, and explicit data and artifact records. Each loaded package is
recorded with its version and source, and a package installed from a git
remote also records the commit it was built from (`sha`), because one
version number can cover more than one build. Capture never resolves a
current dataset implicitly. Pass
[`list()`](https://rdrr.io/r/base/list.html) deliberately when a job has
no known direct data input.

Capture does not write a sidecar or inspect a rendered output. Use
[`publish_provenance`](https://ehrlinger.github.io/hvtiRutilities/reference/publish_provenance.md)
only after the completed output exists.

## Usage

``` r
capture_provenance(
  job,
  data,
  artifacts = list(),
  extra = list(),
  cfg = study_config()
)
```

## Arguments

- job:

  Character(1). Stable job identity.

- data:

  List of records returned by
  [`provenance_data`](https://ehrlinger.github.io/hvtiRutilities/reference/provenance_data.md).

- artifacts:

  List of records returned by
  [`provenance_artifact`](https://ehrlinger.github.io/hvtiRutilities/reference/provenance_artifact.md).

- extra:

  Named list of job-specific fields. Reserved capture and publication
  fields cannot be displaced.

- cfg:

  List. A study manifest from
  [`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md).

## Value

A captured provenance payload as a plain list.

## See also

[`publish_provenance`](https://ehrlinger.github.io/hvtiRutilities/reference/publish_provenance.md),
[`record_provenance`](https://ehrlinger.github.io/hvtiRutilities/reference/record_provenance.md)

## Examples

``` r
root <- file.path(tempdir(), "capture-provenance-example")
invisible(study_setup(root, study = "Example", study_tracker_id = 1L, renv = FALSE))
utils::write.csv(data.frame(ccfid = 1:3, age = c(61, 70, 55)),
                 file.path(root, "00_datasets", "built.csv"),
                 row.names = FALSE)
invisible(register_data(root, built = "built.csv"))
cfg <- study_config(root)

payload <- capture_provenance("death-hz-ac",
                              data = list(provenance_data(cfg = cfg)),
                              cfg = cfg)
names(payload)
#> [1] "job"       "rendered"  "study"     "r"         "packages"  "renv_lock"
#> [7] "data"      "artifacts"
unlink(root, recursive = TRUE)
```
