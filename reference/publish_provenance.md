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

## Examples

``` r
root <- file.path(tempdir(), "publish-provenance-example")
invisible(study_setup(root, study = "Example", study_tracker_id = 1L))
utils::write.csv(data.frame(ccfid = 1:3, age = c(61, 70, 55)),
                 file.path(root, "00_datasets", "built.csv"),
                 row.names = FALSE)
invisible(register_data(root, built = "built.csv"))
cfg <- study_config(root)

payload <- capture_provenance("death-hz-ac",
                              data = list(provenance_data(cfg = cfg)),
                              cfg = cfg)
# Publish only once the output exists.
out <- file.path(root, "40_graphs", "death-hz-ac.html")
writeLines("<p>report</p>", out)
invisible(publish_provenance(out, payload))
file.exists(provenance_path(out))
#> [1] TRUE
unlink(root, recursive = TRUE)
```
