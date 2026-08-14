# hvtiRutilities 1.0.3

## Documentation

- New vignette, *PROC CONTENTS and PROC MEANS in R*, written for readers who
  run both languages. It walks `proc_contents()` and `proc_means()` beside the
  procedures they replace, covers the `QNTLDEF=5` quantile difference that
  changes quartiles without changing the median, and lists every behaviour
  where the R version departs from the SAS original.

- `compare_datasets()` is now demonstrated in *Dataset Version Tracking*
  rather than only named in its index table. The example covers the four kinds
  of drift it reports and why a label change is the one to watch.

# hvtiRutilities 1.0.2

## New features

- `proc_contents()`: a port of SAS `PROC CONTENTS`. Returns a dataset header
  (observations, variables, label) and a variables table carrying creation
  position, name, SAS type, format, label, R class, distinct-value count, and
  percent missing. `Len`, `Pos`, and `Informat` are deliberately omitted —
  `haven` cannot recover them from a `.sas7bdat`, and inferred values would
  disagree with the source dataset whenever its `LENGTH` statement differed
  from the default.

- `proc_means()`: a port of SAS `PROC MEANS`. Takes SAS statistic keywords
  (`n`, `nmiss`, `mean`, `std`, `min`, `max`, `sum`, `range`, `stderr`, `cv`,
  `median`, `q1`, `q3`, and any `pNN`), defaulting to SAS's own five, and
  supports `CLASS` stratification with SAS's default handling of missing class
  levels. Quantiles use `type = 2`, the R equivalent of SAS `QNTLDEF=5`;
  R's default `type = 7` disagrees with SAS on small and even-numbered samples.

## Documentation

- `proc_contents()` now documents that `pct_missing` is `NaN`, not a value in
  0-100, when the input has columns but zero rows: the proportion of missing
  values among no values is undefined, and reporting `0` would assert that
  nothing is missing. Behaviour is unchanged and is inherited from
  `data_dictionary()`; only the documented contract is now accurate, and a test
  pins it.

## Internal changes

- `data_dictionary()` is now a thin wrapper over `proc_contents()` and the
  shared statistic engine. Its signature and output are unchanged, pinned by
  characterization tests added before the refactor.

# hvtiRutilities 1.0.1

## Breaking changes

- `update_manifest()` and `verify_manifest()` are now **silent by default**.
  Both gained a `verbose` argument (default `FALSE`) that gates all
  informational `message()` output: "Manifest entry added / updated" in
  `update_manifest()`, and the per-entry "— SHA-256 match (n = N)" and
  "Manifest contains no dataset entries." lines in `verify_manifest()`.
  Pass `verbose = TRUE` to restore the previous console output.

  This removes unconditional chatter from packages that call these functions
  in a loop (for example `hvtiRdatasets::snapshot_oracle()`, which called
  `update_manifest()` once per study), and brings the package in line with
  the CRAN policy against chatty `message()`/`cat()` in function bodies.

  Failures are unaffected: a SHA-256 mismatch, a missing file, or a row-count
  mismatch still raises `stop()` (or `warning()` when
  `stop_on_error = FALSE`) regardless of `verbose`. The per-entry status text
  is also still returned in the `message` column of `verify_manifest()`'s
  data frame, so silencing the console loses no information.

  `verbose` is appended last in both signatures, so existing positional calls
  are unaffected.

## Maintenance

- Maintainer contact is now `john.ehrlinger@gmail.com`. The redundant
  `Maintainer:` field was removed from DESCRIPTION — with `Authors@R` present
  the maintainer is derived from the `cre` role, and having both declared
  different addresses.
- README: the repostatus badge now uses `https://` (the `http://` form
  301-redirected, failing `urlchecker::url_check()`).
- DESCRIPTION `Date:` refreshed to the 1.0.1 release date.

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
