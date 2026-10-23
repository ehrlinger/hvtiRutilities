# Snapshot a registered data file for provenance

Records the authoritative physical file selected by `dataset`. For a
manifest entry with `role: "primary"`, this is the promoted Parquet file
rather than the retired source, and for a dataset registered with
[`register_data`](https://ehrlinger.github.io/hvtiRutilities/reference/register_data.md)
it is the registered version, the dated Parquet file, rather than the
source it was converted from. The returned plain list contains the
logical dataset name, a canonical study-relative path, its role, byte
count, modification time, and SHA-256 hash.

## Usage

``` r
provenance_data(
  dataset = "study",
  cfg = study_config(),
  role = "analysis",
  working = .hvti_working_default()
)
```

## Arguments

- dataset:

  Character(1). Logical registered dataset name. `"built"` is a second
  name for `"study"`.

- cfg:

  List. A study manifest from
  [`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md).

- role:

  Character(1). The file's role in this job.

- working:

  Logical. If `TRUE`, record the working source file, as
  [`read_built`](https://ehrlinger.github.io/hvtiRutilities/reference/read_built.md)`(working = TRUE)`
  reads it.

## Value

A plain list containing one immutable-by-convention data record.

## See also

[`provenance_artifact`](https://ehrlinger.github.io/hvtiRutilities/reference/provenance_artifact.md),
[`capture_provenance`](https://ehrlinger.github.io/hvtiRutilities/reference/capture_provenance.md)

## Examples

``` r
root <- file.path(tempdir(), "provenance-data-example")
invisible(study_setup(root, study = "Example", study_tracker_id = 1L, renv = FALSE))
utils::write.csv(data.frame(ccfid = 1:3, age = c(61, 70, 55)),
                 file.path(root, "00_datasets", "built.csv"),
                 row.names = FALSE)
invisible(register_data(root, built = "built.csv"))
cfg <- study_config(root)

# The registered Parquet file, not the CSV it was converted from.
str(provenance_data("study", cfg = cfg))
#> List of 6
#>  $ dataset: chr "study"
#>  $ path   : chr "00_datasets/built_20261023.parquet"
#>  $ role   : chr "analysis"
#>  $ bytes  : num 1162
#>  $ mtime  : chr "2026-10-23T18:36:17Z"
#>  $ sha256 : chr "1e75d28bc8dd10e5d237dfef32334987a04322b3d6c6ec12c80a7810158a508a"
unlink(root, recursive = TRUE)
```
