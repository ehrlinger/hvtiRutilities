# Spend the once-per-session deprecation notices before any test runs.
#
# read_clinical_data() warns once when 'convert_types' is omitted, and
# r_data_types() warns once when 'use_value_labels' is omitted. Each notice is
# gated by a flag in .hvti_deprecated, so in a full run it fires in whichever
# test happens to be the first of 79 call sites to omit the argument. That test
# is asserting something else, and the stray warning moves to the next site the
# moment the first one is changed.
#
# The notices themselves are covered where they belong: the "warns once" tests
# in test-read_clinical_data.R and test-r_data_types-value-labels.R clear the
# flag, assert the warning, and restore the prior value. Marking both flags
# spent here leaves those tests intact and keeps every other test from
# depending on file order.
local({
  env <- asNamespace("hvtiRutilities")$.hvti_deprecated
  flags <- c("convert_types", "use_value_labels", "release_contract", "cohort_counts_args", "assert_cohort_args",
             "followup_check_args", "r_data_types_dataset", "parity_headline_df", "register_data_root",
             "declare_data_root")
  for (flag in flags) {
    assign(flag, TRUE, envir = env)
  }
  withr::defer(
    rm(list = flags, envir = env),
    envir = testthat::teardown_env()
  )
})
