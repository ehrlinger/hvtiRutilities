# Record the state of the built dataset

Returns a one-row data frame identifying the built dataset by name,
size, modification time and SHA-256. This is the record that lets a
later reader tell whether two results were produced from the same data.

## Usage

``` r
built_manifest(cfg = study_config())
```

## Arguments

- cfg:

  List. A study manifest from
  [`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md).

## Value

A one-row data frame with columns `file`, `size_bytes`, `mtime` and
`sha256`.

## See also

[`built_path`](https://ehrlinger.github.io/hvtiRutilities/reference/built_path.md),
[`record_provenance`](https://ehrlinger.github.io/hvtiRutilities/reference/record_provenance.md)

## Examples

``` r
root <- file.path(tempdir(), "built-manifest-example")
dir.create(file.path(root, "datasets"), recursive = TRUE,
           showWarnings = FALSE)
yaml::write_yaml(
  list(study = "Example", built = "example.csv",
       cohort = list(n = 3L, n_events = 1L, n_censored = 2L,
                     event = "dead", time = "iv_dead")),
  file.path(root, "_study.yml")
)
write.csv(data.frame(dead = c(1, 0, 0), iv_dead = 1:3),
          file.path(root, "datasets", "example.csv"), row.names = FALSE)
built_manifest(study_config(root))
#>          file size_bytes               mtime
#> 1 example.csv         29 2026-09-04 17:00:35
#>                                                             sha256
#> 1 ff053e4e2cbfceda40422125c091a5cd1171909ccaffcd7154e900f5cbf69b4f
unlink(root, recursive = TRUE)
```
