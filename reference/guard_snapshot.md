# Refuse a renv snapshot taken from the wrong R

Stops before
[`renv::snapshot()`](https://rstudio.github.io/renv/reference/snapshot.html)
when the R running this session has a different major.minor version than
the R recorded in the study's `renv.lock`. A snapshot from the wrong R
rewrites the lockfile's R version and drops every locked package the
session's library lacks. On 2026-10-22, R 4.6.1 snapshotted a study
locked to R 4.5.3, and boostmtree and ggBoostedTrees fell out of its
lockfile.

A patch difference (4.5.1 against 4.5.3) passes, as does a study with no
`renv.lock`.

Use `r_upgrade = TRUE` only when you are deliberately moving the study
to a new R. The guard then still stops if any package in the lockfile is
not installed in this session's library, because the snapshot would drop
it; restore those first with
[`renv::restore()`](https://rstudio.github.io/renv/reference/restore.html).

[`study_need`](https://ehrlinger.github.io/hvtiRutilities/reference/study_need.md)
and
[`study_setup`](https://ehrlinger.github.io/hvtiRutilities/reference/study_setup.md)
call this before they snapshot, so you need to call it yourself only
before a snapshot of your own.

## Usage

``` r
guard_snapshot(
  root,
  r_upgrade = FALSE,
  session = .session_r(),
  installed = .installed_version
)
```

## Arguments

- root:

  Character(1). The study root, holding `renv.lock`.

- r_upgrade:

  Logical(1). The study is being moved to this session's R on purpose.

- session:

  The R version of this session, a
  [`numeric_version`](https://rdrr.io/r/base/numeric_version.html).
  Defaults to the running R; set it only to test the guard.

- installed:

  A function taking a package name and returning its installed version,
  or `NA_character_` when it is not installed. Defaults to a lookup in
  this session's library; set it only to test the guard.

## Value

`TRUE`, invisibly, when the snapshot may go ahead. Otherwise an error
that names both R versions and the R to start.

## Examples

``` r
root <- tempfile("study")
dir.create(root)
# A study with no renv.lock has nothing to protect:
guard_snapshot(root)

# A lock written by R 4.5.3, checked from a session running R 4.6.1:
writeLines('{"R": {"Version": "4.5.3"}, "Packages": {}}',
           file.path(root, "renv.lock"))
try(guard_snapshot(root, session = numeric_version("4.6.1")))
#> Error : renv.lock records R 4.5.3 but this is R 4.6.1. A snapshot now would record the wrong R and drop packages this R's library lacks. Start R 4.5.3 (/opt/R/4.5.3/bin/R), or pass r_upgrade = TRUE to move the study to R 4.6.1 on purpose.
unlink(root, recursive = TRUE)
```
