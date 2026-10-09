* `study_setup()` no longer needs `root`. When it is omitted, the study that
  encloses the working directory is used, as `study_root()` finds it, or the
  working directory itself when no `_study.yml` lies above it; an empty
  working directory is set up as a new study. Run from a subfolder of an
  existing study, it therefore works on that study rather than creating one
  nested inside it. When the root already holds a `_study.yml` for the same
  Study Tracker ID, an interactive session is asked whether to adopt it
  instead of stopping with "use adopt = TRUE"; a batch session still stops,
  and a folder with other files but no `_study.yml` still needs
  `adopt = TRUE`.
