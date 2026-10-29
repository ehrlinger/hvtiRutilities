* New `study_render_commit()` commits the study's allow-listed code snapshot,
  the one `study_checkpoint()` takes, before a render and returns the commit,
  so each figure can print the commit of the code that drew it. The job must
  be in the commit as the bytes on disk, or the call stops. Commits go to a
  ref of this copy's own, `refs/renders/<id>` in `.checkpoint/repo/`, built
  without touching `main`, its tags, `HEAD` or the working tree; an
  unchanged study reuses the last commit. Nothing is tagged or pushed yet.

* New `study_render_record()` records what a render published: each output's
  path and sha256 against the commit it prints, in
  `.hvti-renders/<render_id>.json` on the render ref. Records accumulate, so a
  figure copied into a manuscript still traces after its job renders again.

* `study_checkpoint()`, `study_close()` and `study_reopen()` stop before
  writing when `.checkpoint/repo` is not on `main`, rather than tagging
  another branch.
