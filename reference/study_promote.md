# Give an exploration its own Study Tracker ID

An exploration set up with `study_setup(derived_from = )` has a
`provisional_id` and no Study Tracker ID of its own. Once the Tracker
has registered it, `study_promote()` writes that ID into `_study.yml`
and removes `provisional_id`. `derived_from` and `workspace_id` stay, so
the lineage to the parent study is kept. When the study has a checkpoint
repository and a remote, the checkpoints held locally while the study
was provisional are delivered at once, with the `study_promoted`
checkpoint described below, and
[`study_checkpoint_push`](https://ehrlinger.github.io/hvtiRutilities/reference/study_checkpoint_push.md)
retries anything still pending; their tags are unchanged. Checkpoint
commits and tag messages made while the study was provisional keep the
provisional ID; they are pushed unchanged.

## Usage

``` r
study_promote(study_tracker_id, start = ".")
```

## Arguments

- study_tracker_id:

  The study's new Study Tracker ID, one positive integer.

- start:

  A directory in the study. The study is found as by
  [`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md).

## Value

The number of checkpoint entries rewritten, invisibly; the
`study_promoted` checkpoint is not counted. A rerun after an interrupted
promotion rewrites the entries again, and the provisional ID already
recorded is kept. A study that is already promoted, or whose
`_study.yml` still has a legacy `st_id` key, is refused, as is one whose
checkpoint repository is not on `main`. A rerun with a different ID
rewrites every entry to it.

## Details

When the study has a checkpoint repository, `study_promote()` then
records a `study_promoted` checkpoint: a snapshot of the promoted study,
tagged `study_promoted`, and delivers it with the held checkpoints,
printing the usual delivery messages, so the promoted `_study.yml`
reaches the remote and a second copy of the study reads it as promoted.
Without a remote it stays pending until
[`study_checkpoint_push`](https://ehrlinger.github.io/hvtiRutilities/reference/study_checkpoint_push.md).
A study with no checkpoint repository yet takes no snapshot; its first
checkpoint carries the promoted manifest. With a repository, git must be
available and the `study_promoted` kind must not be retired; both are
checked before anything is written. The `study_promoted` snapshot is
taken whatever trigger or numbering the live vocabulary gives the kind;
only retirement refuses it.

If the snapshot fails, `_study.yml` and the outbox stay promoted and
`study_promote()` stops with the error. A rerun is refused, because the
study is already promoted; record the checkpoint by hand instead, with
`study_checkpoint("study_promoted")`, which is refused too if the kind
has been retired.

If two copies of a study both promote, their unnumbered `study_promoted`
tags clash on push and the second stays pending, as `workspace_created`
does.

## See also

[`study_setup`](https://ehrlinger.github.io/hvtiRutilities/reference/study_setup.md),
[`study_update_identity`](https://ehrlinger.github.io/hvtiRutilities/reference/study_update_identity.md)

## Examples

``` r
root <- file.path(tempdir(), "promote-example")
invisible(study_setup(root, study = "Example exploration",
                      derived_from = 1L, renv = FALSE))
study_promote(2L, start = root)
unlink(root, recursive = TRUE)
```
