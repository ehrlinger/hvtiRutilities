# Render a study audit as a markdown checklist

Turns a
[`study_status`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md)
result into markdown: one checkbox per check, ticked where the check
passed and left open otherwise, with the detail alongside. File counts
follow.

## Usage

``` r
study_checklist(status, path = NULL)
```

## Arguments

- status:

  An object of class `"study_status"`, from
  [`study_status`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md)
  or
  [`study_init`](https://ehrlinger.github.io/hvtiRutilities/reference/study_init.md).

- path:

  Character(1) or `NULL`. Where to write the markdown. When `NULL`
  (default) the lines are returned instead of written.

## Value

When `path` is `NULL`, a character vector of markdown lines. Otherwise
`path`, invisibly, after writing.

## See also

[`study_status`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md),
[`study_init`](https://ehrlinger.github.io/hvtiRutilities/reference/study_init.md)

## Examples

``` r
root <- file.path(tempdir(), "study-checklist-example")
dir.create(root, showWarnings = FALSE)
cat(study_checklist(study_status(root)), sep = "\n")
#> # Study readiness
#> 
#> Study root: `/tmp/RtmptLwp6O/study-checklist-example`
#> 
#> ## Checks
#> 
#> - [ ] **_study.yml** — no _study.yml at this root; run study_init()
#> - [ ] **renv.lock** — no renv.lock; run renv::init() in the study project
#> - [ ] **manifest.yaml** — no manifest.yaml; study_init() seeds one
#> - [ ] **dataset** — requires a valid _study.yml
#> - [ ] **cohort** — requires a valid _study.yml
#> - [ ] **provenance** — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> ## Counts
#> 
#> - `.R` files: 0
#> - `.qmd`/`.Rmd` sources: 0
#> - `.sas` jobs: 0
#> - provenance sidecars: 0
unlink(root, recursive = TRUE)
```
