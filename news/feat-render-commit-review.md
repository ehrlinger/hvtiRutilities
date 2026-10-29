* `study_checkpoint()`, `study_close()` and `study_reopen()` stop when
  `.checkpoint/repo` is not on `main`, before reconciliation or the sync with
  the remote can write, rather than tagging or resetting another branch.
