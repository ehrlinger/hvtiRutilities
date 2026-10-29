# Commit the study's code before a render

Commits the same allow-listed snapshot
[`study_checkpoint`](https://ehrlinger.github.io/hvtiRutilities/reference/study_checkpoint.md)
takes (code, identity and reproducibility files; never data or outputs)
to this copy's render source ref in the private repository
`.checkpoint/repo/`, and returns the commit. A render calls it before
the job runs, so each figure can print the commit of the code that drew
it.

## Usage

``` r
study_render_commit(job, root = study_root())
```

## Arguments

- job:

  Character(1). The job being rendered, relative to the study root.

- root:

  Character(1). The study root. Default
  [`study_root()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_root.md).

## Value

Invisibly, the 40-character commit ID.

## Details

The job must be in the commit, as the bytes on disk: a job the
allow-list leaves out (a symbolic link, a file under a data or estimates
folder or one over 50 MB) stops the call rather than returning a commit
from which the job cannot be recovered, and so does a job that is not a
code file. A file that changes, or is replaced by a symbolic link, while
the snapshot is taken stops the call before the ref moves. The check
runs after hashing, since base R cannot open a file without following a
link: a swap undone before it, to a target of exactly the same size, is
not detected. Files are committed byte for byte, without line-ending
conversion, and an executable file keeps its executable bit.

A study whose snapshot is unchanged since the last render commit gets
that commit back, so re-rendering adds no history and an unchanged job
always prints the same commit. The ref is `refs/renders/<id>/source`,
outside `refs/heads/`; records go to a separate ref (see
[`study_render_record`](https://ehrlinger.github.io/hvtiRutilities/reference/study_render_record.md)).
The ID belongs to this copy of the study at this path on this host: a
study copied or moved elsewhere gets a new one, and keeps the refs it
brought with it. Nothing is tagged or pushed, and `main`, its tags,
`HEAD` and the checkpoint working tree are never touched. The call takes
the checkpoint lock, so it stops while a checkpoint or another render
holds it.

The commit only proves what the job was when the render began. A render
that publishes outputs must also show that the code it executed matches
the commit, and record what it published with
[`study_render_record`](https://ehrlinger.github.io/hvtiRutilities/reference/study_render_record.md).

## See also

[`study_render_record`](https://ehrlinger.github.io/hvtiRutilities/reference/study_render_record.md),
[`study_checkpoint`](https://ehrlinger.github.io/hvtiRutilities/reference/study_checkpoint.md)

## Examples

``` r
# \donttest{
if (nzchar(Sys.which("git"))) {
  root <- file.path(tempdir(), "render-commit-example")
  study_setup(root, "Render commit example", 1L, renv = FALSE)
  writeLines("fit <- 1", file.path(root, "30_analyses", "fit.R"))
  # A commit needs an author; a real study uses the analyst's git config.
  withr::with_envvar(c(
    GIT_AUTHOR_NAME = "Example", GIT_AUTHOR_EMAIL = "example@example.org",
    GIT_COMMITTER_NAME = "Example", GIT_COMMITTER_EMAIL = "example@example.org"
  ), {
    sha <- study_render_commit("30_analyses/fit.R", root = root)
    print(substr(sha, 1, 7))
  })
  unlink(root, recursive = TRUE)
}
#> [1] "4f657c3"
# }
```
