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

- **Not on main** (a log write was lost after a replay). This one
  usually repairs itself. Delivery finds the entry's replayed commit in
  one of three ways, in order: another entry in the log already records
  the same old commit as its `replayed_from`; exactly one commit on
  `main` carries the entry's own id (`checkpoint_id` or `closure_id`);
  or exactly one commit on `main` carries the id in the old commit's own
  message. The last way covers a reopening, whose `reopening_id` is only
  in its tag: it tags an existing commit, a closure's or that of a
  checkpoint taken while the study was closed. Delivery then points the
  entry at that commit, keeps the old value as `replayed_from`, and
  delivers as normal. Only when none of these finds exactly one commit
  does the entry stay pending with a warning. Then repair it by hand:
  look the id up with
  `git -C .checkpoint/repo log --fixed-strings --grep=<id> --format=%H main`,
  choose the right commit, set the entry's `git_commit` in
  `.checkpoint/log.yml` to it, and set its `replayed_from` to the old
  `git_commit`. Then run `study_checkpoint_push()` again. Do not skip
  `replayed_from`: a later entry that names the same old commit, such as
  a reopening, heals from it. If no such commit exists, set the entry's
  `state` to `"abandoned"` instead; an abandoned entry is never
  delivered.

- **Unnumbered tag clash** (two copies of the study each recorded the
  same unnumbered tag, for example `workspace_created`). The two copies
  have diverged. Keep one copy's `.checkpoint/` directory, normally the
  one whose history is already on the remote, move the other copy's
  `.checkpoint/` aside, and run `study_checkpoint_push()` again from the
  kept copy.

## See also

[`study_checkpoint`](https://ehrlinger.github.io/hvtiRutilities/reference/study_checkpoint.md)
