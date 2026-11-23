* `update_manifest(file)` looks for a relative name in the study's datasets
  folder when it is not found from the working directory, as `register_data()`
  does, so `update_manifest("x.csv")` works from a job folder (#316).
