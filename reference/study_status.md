# Audit a study's reproducibility readiness

Reports, without writing anything, whether a study has the four things a
later result needs in order to be re-derivable: a valid `_study.yml`, an
`renv.lock`, a `manifest.yaml` whose checksums still match the data, and
a provenance sidecar for every `.qmd` or `.Rmd` source.

Every finding is reported rather than raised. A study with no
`_study.yml` is the thing this function exists to describe, so it must
not error on one. Checks that cannot run because an earlier one failed
are reported `"MISSING"`, never `"FAIL"` – a check that could not run is
not a check that failed, and conflating the two makes the audit
unreadable on exactly the legacy studies it is most needed for.

Unlike
[`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md),
this function does **not** walk up the directory tree. It asks whether
`root` itself is a study root, so that a subdirectory of a study is
never mistaken for one.

The provenance check matches sidecars to sources **by file name**,
because
[`record_provenance`](https://ehrlinger.github.io/hvtiRutilities/reference/record_provenance.md)
writes the sidecar beside the rendered output and Quarto's output
directory is usually not the source's directory. Two sources sharing a
name therefore cannot be distinguished; the repeated names are reported
in the check's detail so the gap is visible rather than silent.

## Usage

``` r
study_status(root = getwd())
```

## Arguments

- root:

  Character. The study root to audit. Defaults to
  [`getwd()`](https://rdrr.io/r/base/getwd.html).

## Value

An object of class `"study_status"`: a list with `root`, `checks` (a
data frame of `item`, `status` – `"OK"`, `"MISSING"` or `"FAIL"` – and
`detail`, six rows), and `counts` (a list of `r_files`, `qmd`,
`sas_jobs` and `sidecars`).

## See also

[`study_init`](https://ehrlinger.github.io/hvtiRutilities/reference/study_init.md),
[`study_checklist`](https://ehrlinger.github.io/hvtiRutilities/reference/study_checklist.md)

## Examples

``` r
root <- file.path(tempdir(), "study-status-example")
dir.create(root, showWarnings = FALSE)
study_status(root)
#> Study: /tmp/RtmptEPWF3/study-status-example
#> 
#> [ ] _study.yml — no _study.yml at this root; run study_init()
#> [ ] renv.lock — no renv.lock; run renv::init() in the study project
#> [ ] manifest.yaml — no manifest.yaml; study_init() seeds one
#> [ ] dataset — requires a valid _study.yml
#> [ ] cohort — requires a valid _study.yml
#> [ ] provenance — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> 0 .R  |  0 .qmd/.Rmd  |  0 .sas  |  0 provenance sidecars
unlink(root, recursive = TRUE)
```
