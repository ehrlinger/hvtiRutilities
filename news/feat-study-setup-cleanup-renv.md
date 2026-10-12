* `study_setup()` gains `cleanup`, `renv` and `template_dir`, so one call,
  `study_setup(..., adopt = TRUE, cleanup = TRUE, renv = TRUE)`, leaves a
  legacy study ready to work in. `cleanup = TRUE` deletes the template copies
  a study was given when it was created: every `tp.*` file, every
  `binder.summaries.doc`, and every other file whose name and exact content
  match the template corpus at `template_dir` (default
  `/programs/development/template`). A study's own file that shares a name
  with a corpus file but differs from it is kept, as are `.renvignore` and
  `.gitignore`, and folders the deletions leave empty are removed. No backup
  is made; the corpus is the backup. `renv = TRUE` then initializes and
  snapshots the study's renv environment in a separate R process, keeping a
  complete environment and resuming one interrupted after initialization.
  Both default to `FALSE`, so existing calls behave as before.
