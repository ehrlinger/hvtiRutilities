# Close or reopen a study

`study_close()` records how a study ended: it takes a final checkpoint
snapshot, tags it `closed-<outcome>-<n>` and records a closure in the
outbox. It does not make the study read-only: the folder stays writable,
and a checkpoint taken on a closed study is still recorded, with a
warning. The closure tag is what fixes the code as it stood at closure.
`study_reopen()` records a reopening and tags the current snapshot
`reopened-<n>`; the next checkpoint snapshots as usual. A study may be
closed and reopened any number of times, and every cycle is kept.

## Usage

``` r
study_close(
  outcome,
  reason = NULL,
  publication = NULL,
  superseded_by = NULL,
  closed_at = Sys.Date(),
  root = study_root()
)

study_reopen(
  reason,
  new_lead = NULL,
  reopened_at = Sys.Date(),
  root = study_root()
)
```

## Arguments

- outcome:

  Character(1). One of `"published"`, `"not_published"`, `"superseded"`
  or `"abandoned"`.

- reason:

  Optional character(1). For `study_reopen()`, required.

- publication:

  Named list of publication details; required for `"published"`.

- superseded_by:

  One whole positive number, the ST number, given as an integer, a
  double or a string; required for `"superseded"`.

- closed_at, reopened_at:

  Date of the event. Defaults to today.

- root:

  Character. Study root. Defaults to
  [`study_root()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_root.md).

- new_lead:

  Optional character(1), the username of a new study lead.

## Value

An object of class `"study_checkpoint"`, returned invisibly.

## Details

The outcomes follow the StudyTracker closure rules:

- `"published"` needs `publication` (`title`, `journal`, `accepted_on`,
  `published_on`, and at least one of `doi` and `pmid`) and an earlier
  `"manuscript_published"` checkpoint.

- `"superseded"` needs `superseded_by`, the ST number of the study that
  replaced it.

- `"not_published"` and `"abandoned"` need nothing further.

These rules are checked before anything is written, so a close made
offline fails at once rather than when the outbox is delivered.

`reason` is written to the snapshot, the tag and the outbox, so it
leaves the study folder. A message says so whenever it is given: it must
not contain patient information.

## See also

[`study_checkpoint`](https://ehrlinger.github.io/hvtiRutilities/reference/study_checkpoint.md),
[`study_status`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md)

## Examples

``` r
# \donttest{
if (nzchar(Sys.which("git"))) {
  root <- file.path(tempdir(), "close-example")
  study_setup(root, "Close example", 1267L)
  # A throwaway identity, so the example commits on a machine with no
  # git user configured.
  withr::with_envvar(c(GIT_AUTHOR_NAME = "Example",
                       GIT_AUTHOR_EMAIL = "example@example.org",
                       GIT_COMMITTER_NAME = "Example",
                       GIT_COMMITTER_EMAIL = "example@example.org"), {
    study_close("abandoned", reason = "PI left", root = root)
    study_reopen("new PI", root = root)
  })
  unlink(root, recursive = TRUE)
}
#> note/reason/attributes leave the study folder (git and ST); they must not contain patient information.
#> note/reason/attributes leave the study folder (git and ST); they must not contain patient information.
# }
```
