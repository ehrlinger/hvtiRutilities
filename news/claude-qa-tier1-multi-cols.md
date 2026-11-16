* The arguments that take one or more columns now end in `_cols`, per the family API rubric. Each old name works for one more release with a once-per-session warning of class `hvtiRutilities_deprecated`, and each new name keeps the old one's position, so positional calls bind as before:
  * `vars` is now `var_cols` in `covariate_audit()`, `covariates_to_numeric()`, `level_map()`, `proc_means()` and `proc_univariate()`.
  * `class` is now `class_cols` in `proc_means()` and `proc_univariate()`.
  * `tables` is now `table_cols` in `proc_freq()`.
  * `var` is now `var_cols` in `proc_print()`.
  * `skip_vars` is now `skip_cols` in `r_data_types()`, and through it in `read_clinical_data(...)`.
  * `sort_key` is now `sort_key_cols` in `update_manifest()`. The field it writes in `manifest.yaml` is still `sort_key`.
