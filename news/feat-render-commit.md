* New `study_render_commit()` commits the study's allow-listed code snapshot,
  the one `study_checkpoint()` takes, before a render and returns the commit,
  so each figure can print the commit of the code that drew it. The job must
  be in the commit as the bytes on disk, or the call stops before anything is
  committed. Files are committed byte for byte, with no line-ending
  conversion, and keep their executable bit. Commits go to
  `refs/renders/<id>/source` in `.checkpoint/repo/`, which holds only source
  snapshots, so an unchanged study always gets the same commit back. `<id>`
  belongs to this copy of the study at this path on this host: a copied or
  moved study gets a new one and keeps the refs it brought. Nothing touches
  `main`, its tags, `HEAD` or the working tree, and nothing is tagged or
  pushed yet.

* New `study_render_record()` records what a render published: each output's
  path and sha256 against the commit it prints, in
  `.hvti-renders/<render_id>.json` on a separate append-only ref,
  `refs/renders/<id>/records`. Records accumulate, so a figure copied into a
  manuscript still traces after its job renders again. The commit must be a
  source commit of this copy that holds the job; outputs must be regular files
  inside the study, hashed stably; and a `render_id` already recorded stops
  the call rather than replacing the record.
