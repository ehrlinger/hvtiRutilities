* Help-page examples for `register_data()`, the provenance functions
  (`provenance_data()`, `provenance_artifact()`, `capture_provenance()`,
  `publish_provenance()`, `record_provenance()`), `study_checkpoint_push()` and
  the pool conventions (`POOL_AFFIXES` and friends). Each runs on a throwaway
  study under `tempdir()` and removes it; the ones that register data run only
  when arrow is installed.
