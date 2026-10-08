- A `manifest.yaml` that records a registered dated version now starts its
  `datasets:` list with a line that makes hvtiRutilities 1.4.x, and 1.5.0,
  stop with an error instead of reading it. 1.4.x read such an entry as a
  promoted dataset, reconverted the rebuilt source and overwrote the entry, so
  a study pinned to 1.4.x was served unregistered data and 1.5 then reported
  the intact registered version as edited. A manifest written by 1.5.0 is read
  as it is and gains the line the next time `update_manifest()` runs. Code
  that reads `manifest.yaml` directly must skip the line: it is a character
  string, not an entry.
