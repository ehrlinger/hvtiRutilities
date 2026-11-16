* `r_data_types()` documents its numeric threshold as the code applies it: more than 2 and fewer than `factor_size` distinct values, so the default of 10 converts 3 to 9. Character columns are not subject to `factor_size`; one that becomes a factor with more than 50 levels (an identifier or free text) now warns, naming the column. Its argument errors no longer carry the call, and an unknown `skip_vars` name is named.

* `read_clinical_data()` refuses arguments in `...` it cannot honour. They reach `r_data_types()` only, so a reader option such as `sheet = 2` or `na = "."` was dropped without a word when `convert_types = FALSE`, and failed as "unused argument" when `TRUE`. Unnamed dots, any dots with `convert_types = FALSE`, and a name `r_data_types()` does not take are now errors. The help documents the column types each format returns: a date is `Date` from SAS, `POSIXct` from Excel and character from CSV.

* `study_status()` reports closure as `UNKNOWN` when git fails, rather than reading the failure as an open study.

* `compare_datasets()` also compares the levels of shared factor columns (new `level_changes` element), and its printed summary says that values were not compared, rather than "No differences detected" for two datasets whose values may differ.

* `verify_manifest()` and the other functions defaulting to the study manifest pass on a malformed `_study.yml` instead of quietly checking `manifest.yaml` in the working directory. Only a missing `_study.yml` means "not in a study".

* `add_labels()` on a data frame, and so `apply_label_overrides()` on a data frame, warns about names not present in the data instead of dropping them silently.

* `study_dir()` resolves a root that has neither layout's folders to the numbered spelling new studies use, so `study_dir("estimates")` in a fresh study is `90_estimates`, not a bare `estimates`.

* `cohort_counts()` and `assert_cohort()` warn when analysable rows have a zero or negative time, which `followup_check()` flags for review. The counts are unchanged.

* `covariates_to_numeric()` warns about names in `vars` that are not columns of the data instead of skipping them silently.

* `apply_value_labels()` leaves a factor column as read and names it in a warning, instead of stopping with labelled's "Value labels cannot be applied to factors".

* Checkpoints: `occurred_at`, `closed_at` and `reopened_at` must be one `Date`, date-time or `"YYYY-MM-DD"` string; `"01/02/2026"` was logged as year 1. A checkpoint of a kind whose live `trigger` is not `manual` or `auto` is an error rather than an automatic kind; other kinds are unaffected. An empty or non-scalar `checkpoint: remote:` is a configuration error rather than "remote unreachable". An unusable `.checkpoint/repo` reports git's own message and the `safe.directory` fix before advising a delete.
