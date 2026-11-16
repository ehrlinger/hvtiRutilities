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
  cfg = study_config(),
  seed = NA_integer_
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

- seed:

  The job's seed, one whole number, or `NA` (the default) when the job
  sets none. Recorded as the common `seed` field, where `NA` means "does
  not apply"; pass a seeded job's `SEED`.

## Value

A captured provenance payload as a plain list. It opens with the seven
fields every hvtiR package's provenance record shares: `package`
(`"hvtiRutilities"`), `version`, `sha` (the installed commit, or `NA`),
`method` (here the `job`), `seed` (the `seed` argument, `NA` unless the
job is seeded), `rng_kind`
([`RNGkind()`](https://rdrr.io/r/base/Random.html)) and `time` (when it
was captured, `POSIXct`). The render-specific fields follow. An `extra`
element with one of these seven names is an error. In the published JSON
an unknown `sha` is `null` and `time` is UTC in the form `rendered`
uses.

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
invisible(register_data(file = "built.csv", root = root))
cfg <- study_config(root)

payload <- capture_provenance("death-hz-ac",
                              data = list(provenance_data(cfg = cfg)),
                              cfg = cfg)
names(payload)
#>  [1] "package"   "version"   "sha"       "method"    "seed"      "rng_kind" 
#>  [7] "time"      "job"       "rendered"  "study"     "r"         "packages" 
#> [13] "renv_lock" "data"      "artifacts"
unlink(root, recursive = TRUE)
```
