* New `study_render_commit()` commits the study's allow-listed code snapshot,
  the one `study_checkpoint()` takes, to the branch `renders` of
  `.checkpoint/repo/` and returns the commit, so a render can print the
  commit of the code that drew each figure. An unchanged study reuses the
  last render commit. The commit is local: it is not tagged or pushed, and
  `main`, its tags and the checkpoint working tree are left alone.
