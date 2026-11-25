* `arrow` moves from Imports to Suggests, so hvtiRutilities installs on a
  server that cannot build `arrow` (the LRI servers under R 4.6). Registering
  or reading parquet data still requires it: those functions ask for `arrow`
  through `study_need()`, now including a read of a promoted dataset, which
  previously fell through to the retired source.
