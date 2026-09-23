# Snapshot a registered data file for provenance

Records the authoritative physical file selected by `dataset`. For a
manifest entry with `role: "primary"`, this is the promoted Parquet file
rather than the retired source. The returned plain list contains the
logical dataset name, a canonical study-relative path, its role, byte
count, modification time, and SHA-256 hash.

## Usage

``` r
provenance_data(dataset = "study", cfg = study_config(), role = "analysis")
```

## Arguments

- dataset:

  Character(1). Logical registered dataset name.

- cfg:

  List. A study manifest from
  [`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md).

- role:

  Character(1). The file's role in this job.

## Value

A plain list containing one immutable-by-convention data record.

## See also

[`provenance_artifact`](https://ehrlinger.github.io/hvtiRutilities/reference/provenance_artifact.md),
[`capture_provenance`](https://ehrlinger.github.io/hvtiRutilities/reference/capture_provenance.md)
