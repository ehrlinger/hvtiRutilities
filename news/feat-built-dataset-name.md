* `"built"` is now a second name for the study dataset. Every function that
  takes a `dataset` accepts it, and everything recorded (manifests,
  provenance, status) still says `"study"`, so records made under either name
  compare equal. `"built"` is reserved: a named dataset may not use it, and a
  study that already registered an additional dataset called `built` is asked
  to rename it.

* `update_manifest()` with no file reported "found none" for any error reading
  `_study.yml`, so a study that exists but needs fixing was told it had no
  study. It now says that only when no `_study.yml` is found, and passes any
  other error on unchanged.
