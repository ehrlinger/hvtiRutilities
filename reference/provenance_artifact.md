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

## Examples

``` r
root <- file.path(tempdir(), "provenance-artifact-example")
invisible(study_setup(root, study = "Example", study_tracker_id = 1L))
utils::write.csv(data.frame(ccfid = 1:3, age = c(61, 70, 55)),
                 file.path(root, "00_datasets", "built.csv"),
                 row.names = FALSE)
invisible(register_data(root, built = "built.csv"))
cfg <- study_config(root)

writeLines("x <- 1", file.path(root, "30_analyses", "fit.R"))
str(provenance_artifact("30_analyses/fit.R", role = "code", cfg = cfg))
#> List of 5
#>  $ path  : chr "30_analyses/fit.R"
#>  $ role  : chr "code"
#>  $ bytes : num 7
#>  $ mtime : chr "2026-10-15T20:51:10Z"
#>  $ sha256: chr "66b7dd2c95677966d7e30532fe17ac4642554f6ca9c4165274d8438fd9c5a283"
unlink(root, recursive = TRUE)
```
