* `update_manifest(file)` looks for a relative name in the study's datasets
  folder when it is not found from the working directory, as `register_data()`
  does, so `update_manifest("x.csv")` works from a job folder. An `.rds` given
  without `n_rows` now points at `register_data()`, which records the schema,
  instead of asking for a row count (#316).
