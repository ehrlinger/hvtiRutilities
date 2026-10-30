# Name a study's working dataset without registering it

Writes the study dataset's contract, `built:` and `key:`, to
`_study.yml`, and an empty `manifest.yaml` when the study has none. It
registers no version. The dataset is then known but has no registered
version, so every read of it is a working read: allowed in the console
and in a draft render, refused in a final one. Register it with
[`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)
when it is ready.

## Usage

``` r
declare_data(root = study_root(), built, key = NULL)
```

## Arguments

- root:

  The study root, or a directory beneath it. Defaults to the study that
  contains the working directory, found by its `_study.yml`; outside a
  study the function stops and writes nothing.

- built:

  The working file's name in the datasets folder, with its extension.

- key:

  Columns that make a row unique, or `NULL` to leave `key:` unset.

## Value

`TRUE`, invisibly, when the contract was written, or a `key` was added
to a declaration that had none; `FALSE`, invisibly, when `built` was
already declared. Stops when the study already declares a different file
or a different key.

## Details

A new study's first build needs this before any job can read it, because
[`read_built()`](https://ehrlinger.github.io/hvtiRutilities/reference/read_built.md)
finds the file through the contract. The empty manifest is there because
the templates call
[`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)
before reading data, and that stops on a missing file. An existing
manifest is left untouched. The `bd` template calls this on its first
render with `REGISTER = FALSE`.

## Examples

``` r
root <- file.path(tempdir(), "declare-example")
suppressMessages(study_setup(root, "Example", 1L, renv = FALSE))
#> Study: /tmp/RtmpQ0wEa6/declare-example
#> 
#> [x] _study.yml — study: Example
#> [ ] renv.lock — no renv.lock; run renv::init() in the study project
#> [ ] manifest.yaml — no manifest.yaml; register_data() creates it
#> [ ] dataset — no default dataset registered; run register_data()
#> [ ] provenance — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> 0 .R  |  0 .qmd/.Rmd  |  0 .sas  |  0 provenance sidecars
saveRDS(data.frame(ccfid = 1:3), file.path(study_dir("datasets", root), "study_cohort.rds"))
declare_data(root, built = "study_cohort.rds", key = "ccfid")
unlink(root, recursive = TRUE)
```
