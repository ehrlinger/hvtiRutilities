# Write the provenance record for a rendered output

Writes `<output>.provenance.json` beside a rendered result, recording
what produced it: the study manifest and its checksum, the R version and
platform, every loaded package and its version, the `renv.lock` checksum
if there is one, the built dataset's checksum, and the cohort.

This closes a loop that is otherwise impossible. Revisiting a study
becomes: read the sidecar off the filed output, `renv::restore()` to
that lock, re-render, confirm the filed numbers reproduce, and only then
wind forward.

Failure to write the sidecar is an error rather than a warning. Every
other failure in this design is recoverable; a silently unrecorded
result is not.

## Usage

``` r
record_provenance(path, extra = list(), cfg = study_config())
```

## Arguments

- path:

  Character(1). Path to the rendered output the record belongs to. The
  file itself need not exist; only its name and directory are used.

- extra:

  List. Additional named fields merged into the record - for example a
  `template` block naming the template and its version. Required keys
  cannot be displaced.

- cfg:

  List. A study manifest from
  [`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md).

## Value

Invisibly, the record that was written, as a list.

## See also

[`provenance_path`](https://ehrlinger.github.io/hvtiRutilities/reference/provenance_path.md),
[`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md),
[`built_manifest`](https://ehrlinger.github.io/hvtiRutilities/reference/built_manifest.md)

## Examples

``` r
root <- file.path(tempdir(), "provenance-example")
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
out <- file.path(root, "example.html")
writeLines("<html></html>", out)
rec <- record_provenance(out, cfg = study_config(root))
rec$job
#> [1] "example"
unlink(root, recursive = TRUE)
```
