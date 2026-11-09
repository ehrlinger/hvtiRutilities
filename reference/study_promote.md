# Give an exploration its own Study Tracker ID

An exploration set up with `study_setup(derived_from = )` has a
`provisional_id` and no Study Tracker ID of its own. Once the Tracker
has registered it, `study_promote()` writes that ID into `_study.yml`
and removes `provisional_id`. `derived_from` and `workspace_id` stay, so
the lineage to the parent study is kept. Checkpoints held locally while
the study was provisional are pushed by the next
[`study_checkpoint_push`](https://ehrlinger.github.io/hvtiRutilities/reference/study_checkpoint_push.md);
their tags are unchanged. Checkpoint commits and tag messages made while
the study was provisional keep the provisional ID; they are pushed
unchanged.

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

The number of checkpoint entries rewritten, invisibly. A rerun after an
interrupted promotion rewrites the entries again, and the provisional ID
already recorded is kept. A study that is already promoted, or whose
`_study.yml` still has a legacy `st_id` key, is refused, as is one whose
checkpoint repository is not on `main`. A rerun with a different ID
rewrites every entry to it.

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
