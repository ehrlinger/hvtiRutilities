# Capture an explicit job provenance payload

Freezes the study identity, executing R session, loaded packages,
lockfile, and explicit data and artifact records. Capture never resolves
a current dataset implicitly. Pass
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
