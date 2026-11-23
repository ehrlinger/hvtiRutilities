* `update_manifest(file)` records an `.rds` without being given `n_rows`. By
  default it writes `<name>.parquet` and a `<name>.schema.csv` sidecar beside
  it and records the shape and schema hash, as `read_built()` does for a
  source; the new `as_parquet = FALSE` lists the `.rds` as it is, with row and
  column counts but no schema. It refuses an `.rds` that does not hold a data
  frame, and will not write a parquet another entry records (#316).
