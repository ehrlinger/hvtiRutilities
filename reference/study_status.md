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

A `_study.yml` whose identity was entered by hand and not yet confirmed
against Study Tracker (`identity_verified: false`) is reported
`"UNVERIFIED"`. A manifest without the field is a Tracker identity and
is reported `"OK"`.

A study that has been checkpointed (it has a `.checkpoint/` directory)
adds a `checkpoints` row: `"OK"` when every checkpoint, closure and
reopening has reached the remote, or `"PENDING"` when some are saved
locally and not yet pushed. Its detail counts the recorded events, names
the last tag, and counts those not yet pushed or not yet in ST. A closed
study then adds a `closure` row with status `"CLOSED"` and the outcome
and date of the latest closure; see
[`study_close`](https://ehrlinger.github.io/hvtiRutilities/reference/study_close.md).
This function never contacts the remote, so when one is configured that
row adds *as of the last fetch*. When a closure or reopening tag in this
copy is not on its `main`, the state cannot be determined and the row
has status `"UNKNOWN"`.

The `manifest.yaml` row is `"PENDING"` when a dataset registered as a
dated parquet has had its source file rebuilt since registration. Jobs
keep reading the registered version; the detail names the datasets and
[`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md),
which registers the rebuild.

Release-aware datasets add an `update:<dataset>` row with status
`"CURRENT"`, `"UPDATE AVAILABLE"`, `"UPDATE STATUS UNKNOWN"`, or
`"FAIL"`. Legacy studies retain the five base rows and their existing
dataset rows.

A combined dataset built from parents that have since been updated adds
an `out_of_date:<dataset>` row with status `"OUT OF DATE"`. Its detail
names the parents' recorded and current versions and the commands that
bring the combined data up to date. A combined dataset with no recorded
parent versions is reported the same way, with the parent versions shown
as `unrecorded`. If that check itself cannot run, for example because
`manifest.yaml` cannot be parsed, the row has status `"FAIL"` and the
error as its detail.

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
data frame of `item`, `status` – `"OK"`, `"MISSING"`, `"FAIL"`,
`"UNVERIFIED"`, `"CURRENT"`, `"UPDATE AVAILABLE"`,
`"UPDATE STATUS UNKNOWN"`, `"OUT OF DATE"`, `"PENDING"`, `"CLOSED"`, or
`"UNKNOWN"` – and `detail`). The five base rows are followed by
release-aware update rows, by dataset and update rows for each named
dataset, and by the `checkpoints` and `closure` rows when they apply.
`counts` lists `r_files`, `qmd`, `sas_jobs` and `sidecars`.

## See also

[`study_setup`](https://ehrlinger.github.io/hvtiRutilities/reference/study_setup.md),
[`study_checklist`](https://ehrlinger.github.io/hvtiRutilities/reference/study_checklist.md)

## Examples

``` r
root <- file.path(tempdir(), "study-status-example")
dir.create(root, showWarnings = FALSE)
study_status(root)
#> Study: /tmp/RtmpeCLyfX/study-status-example
#> 
#> [ ] _study.yml — no _study.yml at this root; recovery may be available with study-setup --recover; if its Tracker ID cannot be inferred, run study-setup 42 --recover
#> [ ] renv.lock — no renv.lock; run renv::init() in the study project
#> [ ] manifest.yaml — no manifest.yaml; register_data() creates it
#> [ ] dataset — requires a valid _study.yml
#> [ ] provenance — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> 0 .R  |  0 .qmd/.Rmd  |  0 .sas  |  0 provenance sidecars
unlink(root, recursive = TRUE)
```
