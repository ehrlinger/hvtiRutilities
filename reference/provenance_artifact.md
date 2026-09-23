# Snapshot an input artifact for provenance

Records an existing artifact beneath the study root by canonical
study-relative path, role, byte count, modification time, and SHA-256
hash.

## Usage

``` r
provenance_artifact(path, role = "input", cfg = study_config())
```

## Arguments

- path:

  Character(1). Existing artifact path, absolute or relative to the
  study root.

- role:

  Character(1). The artifact's role in this job.

- cfg:

  List. A study manifest from
  [`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md).

## Value

A plain list containing one immutable-by-convention artifact record.

## See also

[`provenance_data`](https://ehrlinger.github.io/hvtiRutilities/reference/provenance_data.md),
[`capture_provenance`](https://ehrlinger.github.io/hvtiRutilities/reference/capture_provenance.md)
