* The working-read gate stops any job outside the datasets and descriptive folders: a job in any
  other stage folder, a job at the study root, a script outside the study, and a non-interactive
  session with no job file, such as `Rscript -e`, targets or callr. `HVTI_DATA` must be unset or
  `"working"`; any other value stops every `read_built()` and `provenance_data()`. A dataset with
  no dated version stops those jobs and the message names `update_manifest()`, the only way out
  once `_study.yml` names the dataset. A job directly in the study root is named as outside any
  stage folder.
* `provenance_data(working = )` is new. It records the working source file, as
  `read_built(working = TRUE)` reads it, and is validated the same way.
* `update_manifest()` registers a version with its build record. It renames `<stem>.build.yml` beside
  the version, and stops on a malformed record with `schema: 1` or one that says
  `derived_after_overlay: false`, or whose `job` is an absolute path or climbs out of the study. A
  record without `schema: 1`, such as the one hvtiRtemplates' `bd.qmd` writes, is left where it is
  and the version is recorded as legacy, so removing a retired `release:` block does not stop
  `update_manifest()`.
* `update_manifest()` migrates a promoted entry (`role: primary`, no `parquet:`) whose source was
  retired, by renaming its parquet to a dated version, and returns a new action, `"missing"`, for a
  dataset whose source and registered version are both gone. A promoted entry whose source is still
  on disk is compared through `source_sha256`: an unchanged source registers the promoted parquet
  itself, and a rebuilt one keeps it as the earlier version. Neither is reported as overwritten,
  and a combined dataset is no longer recorded as rebuilt when only its format changed.
* `update_manifest()` prints its reminder to commit `manifest.yaml` after a rewrite that only
  re-recorded a source stamp, and its documentation says that a key violation on one dataset stops
  the whole run and leaves every dataset as it was.
* `study_status()` adds a `dated_version:<dataset>` row, `PENDING`, for each dataset with no dated
  version, so a study no longer reads as all `OK` while every analysis job stops.
* The message that says a source changed since registration names `review_built()`, which compares
  the rebuild with the registered version, before `update_manifest()`.
