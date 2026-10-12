# Capture and publish provenance for an existing output

Convenience wrapper for an output that already exists. It captures an
explicit provenance payload and immediately publishes it beside the
output.

## Usage

``` r
record_provenance(
  path,
  data,
  artifacts = list(),
  extra = list(),
  cfg = study_config()
)
```

## Arguments

- path:

  Character(1). Existing completed output path.

- data:

  List of records returned by
  [`provenance_data`](https://ehrlinger.github.io/hvtiRutilities/reference/provenance_data.md).

- artifacts:

  List of records returned by
  [`provenance_artifact`](https://ehrlinger.github.io/hvtiRutilities/reference/provenance_artifact.md).

- extra:

  Named list of job-specific fields. Reserved fields cannot be
  displaced.

- cfg:

  List. A study manifest from
  [`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md).

## Value

Invisibly, the published record as a list.

## See also

[`capture_provenance`](https://ehrlinger.github.io/hvtiRutilities/reference/capture_provenance.md),
[`publish_provenance`](https://ehrlinger.github.io/hvtiRutilities/reference/publish_provenance.md),
[`provenance_path`](https://ehrlinger.github.io/hvtiRutilities/reference/provenance_path.md)
