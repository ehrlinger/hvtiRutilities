* `read_clinical_data()`, and so `register_data()` and `read_built()`, read
  `.rda` and `.RData` files. The file must hold exactly one data frame, which
  is the dataset; other objects saved with it, such as a list of labels, are
  ignored, and a file with none or several stops with their names.
  `update_manifest(file)` converts one to parquet as it does an `.rds`, or
  lists it as it is with `as_parquet = FALSE` (#316).
* `register_data()`'s help says which formats its `file` may be, that
  registration converts each to parquet, and that parquet is preferred to an
  R data file when R writes the file (#316).
