# Record what a render published

Adds a render record to this copy's render ref, tying every output a
render published to the commit its figures print. Records accumulate, so
a figure copied into a manuscript can be traced after its job is
rendered again.

## Usage

``` r
study_render_record(
  render_id,
  commit,
  job,
  outputs,
  extra = list(),
  root = study_root()
)
```

## Arguments

- render_id:

  Character(1). The render's identifier; names the record.

- commit:

  Character(1). The commit from
  [`study_render_commit`](https://ehrlinger.github.io/hvtiRutilities/reference/study_render_commit.md)
  that the outputs print.

- job:

  Character(1). The job rendered, relative to the study root.

- outputs:

  Character. Paths of the published files, absolute or relative to the
  study root; each must exist.

- extra:

  List. Further fields for the record. Default
  [`list()`](https://rdrr.io/r/base/list.html).

- root:

  Character(1). The study root. Default
  [`study_root()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_root.md).

## Value

Invisibly, the record as a list.

## Details

The record is written as `.hvti-renders/<render_id>.json` in a new
commit on the render ref, and every later render commit carries it, so
the ref's tip holds every record. It names `commit`, `job`, the time,
`extra` (typically the render's provenance) and, for each file in
`outputs`, its path relative to the study root and its sha256. A render
that fails should publish nothing and record nothing.

## See also

[`study_render_commit`](https://ehrlinger.github.io/hvtiRutilities/reference/study_render_commit.md)

## Examples

``` r
# \donttest{
if (nzchar(Sys.which("git"))) {
  root <- file.path(tempdir(), "render-record-example")
  study_setup(root, "Render record example", 1L, renv = FALSE)
  writeLines("fit <- 1", file.path(root, "30_analyses", "fit.R"))
  writeLines("figure", file.path(root, "30_analyses", "fit.png"))
  withr::with_envvar(c(
    GIT_AUTHOR_NAME = "Example", GIT_AUTHOR_EMAIL = "example@example.org",
    GIT_COMMITTER_NAME = "Example", GIT_COMMITTER_EMAIL = "example@example.org"
  ), {
    sha <- study_render_commit("30_analyses/fit.R", root = root)
    rec <- study_render_record("r1", sha, "30_analyses/fit.R",
                               "30_analyses/fit.png", root = root)
    print(rec$outputs)
  })
  unlink(root, recursive = TRUE)
}
#> [[1]]
#> [[1]]$path
#> [1] "30_analyses/fit.png"
#> 
#> [[1]]$sha256
#> [1] "e952f88f5e35916f10eb0b1495710c1dec05ddd468e23d22afedcb934e2e46cb"
#> 
#> 
# }
```
