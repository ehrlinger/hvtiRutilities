# hvtiRutilities 1.0.0.9004

## Bug fixes

- `read_clinical_data()`: files with no extension now produce a clear error
  ("Cannot determine file type: … has no extension") instead of the
  misleading `Unsupported file type: '..'` message. The unsupported-extension
  error also now includes the full file path for easier diagnosis.

## Tests

- `test-read_clinical_data.R`: strengthened the tibble-coercion assertion from
  `expect_true(is.data.frame(result))` (TRUE for tibbles) to
  `expect_equal(class(result), "data.frame")` so the test actually protects
  against `as.data.frame()` being removed or bypassed.

## Documentation

- `vignettes/reproducible-seeds.qmd`: section heading "Using the Seed with
  varpro" and narrative references to the package now use the correct CRAN
  casing `varPro`; function-name references (`varpro()`, `unsupv.varpro()`)
  remain lowercase as those are the exported function names.

# hvtiRutilities 1.0.0.9003

## Bug fixes

- Fixed `Suggests` entry for `varPro`: package name on CRAN is `varPro`
  (camelCase), not `varpro` (lowercase). The case mismatch caused `pak`
  lockfile resolution to fail with "Can't find package called varpro".
  Updated the corresponding `varPro::varpro()` call in
  `vignettes/reproducible-seeds.qmd` to match.

# hvtiRutilities 1.0.0.9002

## Documentation

- All vignettes migrated from R Markdown (`.Rmd`) to Quarto (`.qmd`). Added
  `quarto` to `Suggests`.

## Bug fixes

- `read_clinical_data()`: CSV files are now read with `check.names = FALSE` so
  column names containing spaces, hyphens, or special characters are preserved
  exactly as written, preventing silent name mangling that could break
  downstream label lookups.

# hvtiRutilities 1.0.0.9000

## Maintenance

* Start prerelease cycle at 1.0.0.9000.

# hvtiRutilities 0.4.1

## Maintenance

* Bumped package metadata for the upcoming release cycle.

# hvtiRutilities 0.1.4

## New Features

* Added `generate_survival_data()`: generates a synthetic cardiac surgery
  survival cohort with 22 clinical variables, Weibull-distributed survival
  times, reoperation outcome, and variable labels

## Bug Fixes

* Fixed `r_data_types()` silently corrupting Date, POSIXct, and POSIXlt
  columns that had exactly 2 unique values (they were converted to logical)
* Fixed `r_data_types()` incorrectly converting constant columns (1 unique
  value) to logical; binary detection now requires exactly 2 unique values
* Fixed `r_data_types()` producing a cryptic "missing value where TRUE/FALSE
  needed" error when `factor_size = NaN`
* Fixed `r_data_types()` giving a misleading "not found in dataset" error
  when `skip_vars` was not a character vector
* Fixed `generate_survival_data()` producing `NaN` in `iv_reop` for patients
  with very short follow-up times
* Fixed `generate_survival_data()` permanently altering the global RNG state;
  the session's RNG is now saved and restored on exit

## Improvements

* `r_data_types()` now validates all inputs before doing any work, so errors
  are raised immediately with clear messages
* `r_data_types()` input validation now explicitly checks that `dataset` is a
  data.frame, `skip_vars` is a character vector, and `factor_size` is not NaN
* `generate_survival_data()` now uses `labelled::var_label()` consistently
  to attach labels instead of `attr()` directly
* Removed leftover `if (interactive())` development block from
  `generate_survival_data.R`
* Added new vignette `survival-data` demonstrating `generate_survival_data()`
  and its integration with `r_data_types()` and `label_map()`

## Tests

* Added 27 tests for `generate_survival_data()` covering structure, column
  types, outcome validity, reproducibility, RNG side-effect safety, and
  variable labels
* Updated POSIXct test to verify preservation without `skip_vars` (the
  previous test only verified the `skip_vars` workaround)
* Strengthened idempotency test to assert full value equality across
  sequential conversions, not just column class equality
* Updated `skip_vars` type-error test to match the improved error message

# hvtiRutilities 0.1.3

## Bug Fixes

* Fixed critical bug in `r_data_types()` where `dplyr::na_if()` was called with a vector instead of scalar values
* Fixed bug where character columns with 2 unique values were incorrectly converted to logical (returning all NAs)
* Fixed bug in `sample_data()` where `sample.int()` parameters were reversed, causing errors for small sample sizes
* Fixed column order preservation bug in `r_data_types()` when using `skip_vars` - columns now maintain original order
* Fixed silent parameter mutation bug where `factor_size > 50` was changed to 20 without user consent - now errors instead

## Improvements

* Removed unused `lubridate` dependency that was never actually used in the package
* Removed inappropriate use of `invisible()` from `label_map()` and `r_data_types()` functions
* Implemented `hvtiRutilities.news()` function that was referenced but didn't exist
* Completely rewrote test suite with modern testthat 3 syntax (removed deprecated `context()` calls)
* Expanded test coverage from 24 tests to 75 comprehensive tests
* Added proper examples to `label_map()` documentation with `@examples` tag
* Improved error messages for better clarity and consistency
* Changed `== TRUE` comparisons to simpler boolean checks

## Documentation

* Complete rewrite of README.md with actual package description and usage examples
* Fixed `label_map()` documentation (was incomplete sentence, wrong return type)
* Improved `r_data_types()` documentation with clearer parameter descriptions
* Added comprehensive usage examples for all main functions

# hvtiRutilities 0.1.2

* Internal development version

# hvtiRutilities 0.1.1

* Internal development version

# hvtiRutilities 0.1.0

* Initial release
* Core functions: `r_data_types()`, `label_map()`, `sample_data()`
