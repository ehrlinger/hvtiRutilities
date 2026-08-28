# Inventory the job files under one or more corpus roots

Walks each root and returns one row per file. This is a filename-only
sweep: no file is opened, nothing is parsed, and there is no
`TemporalHazard` dependency.

## Usage

``` r
job_files(roots)
```

## Arguments

- roots:

  Character. One or more directories to sweep. A root is a directory
  that *contains* studies, not a study itself: the study is read as the
  path from the root down to the taxonomy folder's parent, so a root
  that is itself a study leaves nothing to name it and every prefix
  collapses to one study called `"."` (warned about). Each root must
  exist and be a directory, or this errors. A duplicate root is dropped;
  a root nested inside another warns and the inner one is dropped, since
  its files would otherwise be counted twice under two study labels.

## Value

A data frame with one row per file and the columns `path`, `study`,
`folder`, `status`, `depth`, `naming`, `prefix`, `is_template`, `stem`,
`ext`, `prefix_class`, `folder_expected` and `folder_ok`. Zero rows if
the roots hold no files.

## Details

**Nothing is filtered out.** Placement and classification are columns,
not reasons to drop a row, so a file this sweep cannot classify stays
findable. A sweep that reports only what it kept makes a missing job
indistinguishable from a job that does not exist.

There is deliberately no extension allowlist. See `vignette`-adjacent
design note `dev/specs/2026-08-26-job-type-inventory-design.md`, section
4.4: a plausible default tuned on the hazard prefixes would have dropped
every R-side job in the corpus.

`folder_ok` is `folder == folder_expected`, and is therefore `NA` – not
`FALSE` – whenever either side is unknown. An unplaced file has no
folder and an unparsed name has no expected folder; neither is a
misfiled job, and `!folder_ok` must not select them.

**Run this server-side.** It stats every file beneath `roots`, which is
metadata-latency-bound over an SMB mount – a 40-file scan has timed out
at two minutes over the share.

## See also

[`job_census`](https://ehrlinger.github.io/hvtiRutilities/reference/job_census.md),
[`hvti_taxonomy`](https://ehrlinger.github.io/hvtiRutilities/reference/hvti_taxonomy.md)

## Examples

``` r
d <- file.path(tempdir(), "job-files-example")
dir.create(file.path(d, "alpha", "distributions"), recursive = TRUE)
file.create(file.path(d, "alpha", "distributions", "hz.dead.lst"))
#> [1] TRUE
job_files(d)[, c("study", "folder", "prefix", "status")]
#>   study        folder prefix status
#> 1 alpha distributions     hz placed
unlink(d, recursive = TRUE)
```
