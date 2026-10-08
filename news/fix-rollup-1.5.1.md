- A `manifest.yaml` that records a registered dated version now starts its
  `datasets:` list with a line that makes hvtiRutilities 1.4.x, and 1.5.0,
  stop with an error instead of reading it. 1.4.x read such an entry as a
  promoted dataset, reconverted the rebuilt source and overwrote the entry, so
  a study pinned to 1.4.x was served unregistered data and 1.5 then reported
  the intact registered version as edited. A manifest written by 1.5.0 is read
  as it is and gains the line the next time `update_manifest()` runs. Code
  that reads `manifest.yaml` directly must skip the line: it is a character
  string, not an entry.
- `register_data(catalog_dataset = , release_id = )` refuses a dataset
  registered as dated versions, as `update_manifest(file)` already did. It
  replaced the entry with a flat one, dropping every registered version from
  the manifest and leaving their parquets unchecked.
- A combined dataset registered on a parent that predates dated versions no
  longer reads as out of date once `update_manifest()` converts that parent
  without a change to its data. The parent's checksum, recorded at
  registration, is recognised as the version it was converted to.
- `register_data(parents = )` and `_study.yml` accept `"built"` for the study
  dataset, as every other argument naming a dataset does, and record it as
  `"study"`. A parent that is not a registered dataset is now named in the
  error, which names `register_data()` rather than `study_config()` and comes
  before the dataset is converted to parquet.
- `update_manifest(file)` refuses a file that is another entry's registered
  version, current or earlier, or its schema sidecar. Recording it replaced
  nothing on disk but hid that its caller had just written over registered
  data; every job then failed the checksum with no hint of why.
- `update_manifest()` re-records the size and modification time of a
  registered dataset's source that was rewritten with the same contents.
  Until then every read, `verify_manifest()` and `study_status()` hashed the
  source again to find it unchanged. On a file system that records whole
  seconds only, such as a network share, a hash is still needed on each read,
  as it is for the read cache.
