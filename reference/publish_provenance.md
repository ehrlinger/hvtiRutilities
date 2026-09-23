# Publish captured provenance beside a completed output

Requires an existing regular output, binds its byte count and SHA-256
hash to a previously captured payload, and writes the JSON sidecar
through a same-directory temporary file and rename. Capture-session
facts are not recomputed during publication.

## Usage

``` r
publish_provenance(path, payload)
```

## Arguments

- path:

  Character(1). Existing completed output path.

- payload:

  A payload returned by
  [`capture_provenance`](https://ehrlinger.github.io/hvtiRutilities/reference/capture_provenance.md).

## Value

Invisibly, the published record as a list.

## See also

[`capture_provenance`](https://ehrlinger.github.io/hvtiRutilities/reference/capture_provenance.md),
[`record_provenance`](https://ehrlinger.github.io/hvtiRutilities/reference/record_provenance.md),
[`provenance_path`](https://ehrlinger.github.io/hvtiRutilities/reference/provenance_path.md)
