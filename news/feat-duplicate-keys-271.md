* New `duplicate_keys()` lists the rows that repeat a key, such as two
  operations on the same day under `c("ccfid", "dt_surg")`. Given `order_by`,
  it marks the first row of each repeated key to keep, as the SAS jobs do
  (the first operation kept, the second treated as a complication), and stops
  on a tie or a missing value rather than pick one. It never changes the data,
  and leaves key values out of its report unless `show_key = TRUE` (#271).
