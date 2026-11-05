* `duplicate_keys()` matches keys as `duplicated()` matches them: `NA` and `NaN`
  are different keys, and doubles compare exactly. It had merged rows whose key
  held `NA` in one and `NaN` in the other into one repeated key (#278 review).

* `register_data()` and `declare_data()` refuse `file = NULL` given beside
  `built =`, as they refuse any `file =` beside it, rather than reading the call
  as `built =` alone (#278 review).

* `declare_data()` accepts a path into the study's data folder for `file`, such
  as `"00_datasets/study_cohort.rds"`, as `register_data()` does since #272, and
  records the file name alone (#276 review).
