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

## Examples

``` r
root <- file.path(tempdir(), "record-provenance-example")
invisible(study_setup(root, study = "Example", study_tracker_id = 1L))
utils::write.csv(data.frame(ccfid = 1:3, age = c(61, 70, 55)),
                 file.path(root, "00_datasets", "built.csv"),
                 row.names = FALSE)
invisible(register_data(root, built = "built.csv"))
cfg <- study_config(root)

out <- file.path(root, "40_graphs", "death-hz-ac.html")
writeLines("<p>report</p>", out)
rec <- record_provenance(out, data = list(provenance_data(cfg = cfg)),
                         cfg = cfg)
rec$output$file
#> [1] "death-hz-ac.html"
file.exists(provenance_path(out))
#> [1] TRUE
unlink(root, recursive = TRUE)
```
