* `study_status()` no longer tells a study without `renv.lock` to run `renv::init()`, which starts the study's
  library over without the family. It names `hvtiR::setup()` instead, with the study's title, Study Tracker ID and
  root filled in from `_study.yml`, and says that adopting deletes `tp.*` files.
