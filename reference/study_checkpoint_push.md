# Push pending study checkpoints

Retries delivery of every checkpoint, closure and reopening in
`.checkpoint/log.yml` that has not reached the remote yet.
[`study_checkpoint`](https://ehrlinger.github.io/hvtiRutilities/reference/study_checkpoint.md)
does this on every call; use this function after a network outage, or
once `study-setup --verify` has verified a manually entered identity.

## Usage

``` r
study_checkpoint_push(root = study_root())
```

## Arguments

- root:

  Character. Study root. Defaults to
  [`study_root()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_root.md).

## Value

A data frame, returned invisibly, with one row per logged event and
columns `type`, `tag`, `state`, `git`, `st` and `reason`.

## Details

An entry that a crash left half-written is settled first: completed when
its tag exists, otherwise marked `abandoned`. Abandoned entries are
never pushed.

## Repairing a stuck delivery

Two failures leave an entry pending in a way that retrying
`study_checkpoint_push()` cannot fix by itself. Each is reported as a
warning that names the tag and points back here.

- **Not on main** (a log write was lost after a replay). Find the commit
  on `main` whose message carries the entry's id (`checkpoint_id` for a
  checkpoint, `closure_id` for a closure, `reopening_id` for a
  reopening):
  `git -C .checkpoint/repo log --fixed-strings --grep=<id> --format=%H main`.
  If a commit is found, set the entry's `git_commit` in
  `.checkpoint/log.yml` to that commit, keep the old value as
  `replayed_from`, then run `study_checkpoint_push()` again. If no such
  commit exists, set the entry's `state` to `"abandoned"` instead; an
  abandoned entry is never delivered.

- **Unnumbered tag clash** (two copies of the study each recorded the
  same unnumbered tag, for example `workspace_created`). The two copies
  have diverged. Keep one copy's `.checkpoint/` directory, normally the
  one whose history is already on the remote, move the other copy's
  `.checkpoint/` aside, and run `study_checkpoint_push()` again from the
  kept copy.

## See also

[`study_checkpoint`](https://ehrlinger.github.io/hvtiRutilities/reference/study_checkpoint.md)
