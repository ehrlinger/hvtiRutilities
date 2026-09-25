# Record a study checkpoint

Commits an allow-listed snapshot of the study (code, identity and
reproducibility files) to a private git repository in
`.checkpoint/repo/`, tags it with the checkpoint kind and a sequence
number, records it in the outbox `.checkpoint/log.yml`, and pushes it
when `_study.yml` names a remote. Known data formats, credentials and
symbolic links are never committed, even through `include:` patterns,
and neither is anything under `00_datasets/` or `90_estimates/` or an
output file type. Files in `50_documents/` other than `.qmd` and `.bib`
sources are not committed; `CHECKPOINT.yml` records their size and
checksum.

## Usage

``` r
study_checkpoint(
  kind,
  note = NULL,
  attributes = NULL,
  occurred_at = Sys.Date(),
  root = study_root()
)
```

## Arguments

- kind:

  Character(1). A checkpoint kind.

- note:

  Optional character(1), stored with the checkpoint.

- attributes:

  Optional named list of kind-specific details, each a single value, for
  example `list(journal = "JTCVS")`.

- occurred_at:

  Date the event happened. Defaults to today.

- root:

  Character. Study root. Defaults to
  [`study_root()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_root.md).

## Value

An object of class `"study_checkpoint"`, returned invisibly, with the
tag, commit, file count, skipped files and delivery states.

## Details

The kind comes from the StudyTracker checkpoint vocabulary, for example
`"abstract_submitted"` or `"manuscript_submitted"`. Automatic kinds such
as `"data_received"` are logged without a snapshot. A checkpoint is
committed locally before anything is pushed, so an unreachable remote
never loses one;
[`study_checkpoint_push`](https://ehrlinger.github.io/hvtiRutilities/reference/study_checkpoint_push.md)
retries later.

One session at a time: this function,
[`study_checkpoint_push`](https://ehrlinger.github.io/hvtiRutilities/reference/study_checkpoint_push.md),
[`study_close`](https://ehrlinger.github.io/hvtiRutilities/reference/study_close.md)
and
[`study_reopen()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_close.md)
hold the lock `.checkpoint/lock` while they run. A call that finds it
held by another session stops, naming the holder; retry once that
session has finished. The holder refreshes the lock between phases
(selection, the snapshot's `CHECKPOINT.yml`, the commit and tag,
delivery), so a lock not refreshed for 6 hours was left by a crashed
session and is taken over with a warning.

`note` and `attributes` are written to the snapshot, the tag and the
outbox, so they leave the study folder. A message says so whenever
either is given: they must not contain patient information.

## See also

[`study_checkpoint_push`](https://ehrlinger.github.io/hvtiRutilities/reference/study_checkpoint_push.md),
[`study_close`](https://ehrlinger.github.io/hvtiRutilities/reference/study_close.md),
[`study_status`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md)

## Examples

``` r
# \donttest{
if (nzchar(Sys.which("git"))) {
  root <- file.path(tempdir(), "checkpoint-example")
  study_setup(root, "Checkpoint example", 1267L)
  writeLines("x <- 1", file.path(root, "30_analyses", "fit.R"))
  # A throwaway identity, so the example commits on a machine with no
  # git user configured.
  withr::with_envvar(c(GIT_AUTHOR_NAME = "Example",
                       GIT_AUTHOR_EMAIL = "example@example.org",
                       GIT_COMMITTER_NAME = "Example",
                       GIT_COMMITTER_EMAIL = "example@example.org"), {
    cp <- study_checkpoint("abstract_submitted", root = root)
    print(cp$tag)
  })
  unlink(root, recursive = TRUE)
}
#> [1] "abstract_submitted-1"
# }
```
