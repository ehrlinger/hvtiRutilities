# Changelog

## hvtiRutilities 1.0.8

### New features

- [`study_init()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_init.md)
  initializes a study for reproducible analysis: it writes the
  `_study.yml` identity manifest that
  [`study_config()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md)
  reads, and seeds a `manifest.yaml` pinning the built dataset’s
  SHA-256. The cohort counts are derived from the dataset rather than
  supplied, because a hand-typed count is a count that can disagree with
  the data. `citation` is written as an explicit null, so a study that
  is later published has an obvious place to record its reference.

- [`study_status()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md)
  audits a study without writing anything, reporting whether it has a
  valid `_study.yml`, an `renv.lock`, a `manifest.yaml` whose checksums
  still match, and a provenance sidecar for every `.qmd` or `.Rmd`
  source. It never errors on an absent or malformed manifest — that is
  the finding, not a failure — and it distinguishes a check that could
  not run (`MISSING`) from one that ran and failed (`FAIL`).

- [`study_checklist()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_checklist.md)
  renders a
  [`study_status()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md)
  result as a markdown checklist, ticked where the study already
  complies.

### Bug fixes

- [`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)
  no longer reports `FAIL` for a `.sas7bdat` or Excel entry whose
  SHA-256 matches. Re-deriving the row count of those formats needs
  `options(manifest.allow_heavy_rowcount = TRUE)`, and without it the
  attempt errored and the error was reported as a failed entry. At the
  default `stop_on_error = TRUE` that halted analyses whose data was
  intact. The count is now skipped when it cannot be re-derived and the
  entry passes on its checksum; a file that cannot be read at all is
  still `FAIL`.

- [`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)
  gains a `row_count_checked` column, `TRUE` when the row count was
  re-derived from the file and compared with the manifest. The entry’s
  message notes a count that was not re-derived.

### Notes

- No new dependencies.
- [`study_init()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_init.md)
  does not run `renv::init()`. A missing `renv.lock` is reported as an
  open item instead: creating one restarts the R session and rewrites
  `.Rprofile`, which a function that writes two YAML files has no
  business doing.
- [`study_status()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md)
  reports a `manifest.yaml` entry as verified when its SHA-256 matches
  but its row count could not be re-derived, and says how many counts
  were skipped. For a `.sas7bdat` that is the normal case.

## hvtiRutilities 1.0.7

### New features

- [`study_config()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md)
  reads a study’s `_study.yml` manifest, found by walking up from a
  starting directory. It validates that every required key is present
  and errors otherwise, naming the key: a study without a complete
  manifest must not render, and a partial default would be a silent
  wrong answer.

- [`record_provenance()`](https://ehrlinger.github.io/hvtiRutilities/reference/record_provenance.md)
  writes a JSON sidecar beside a rendered output, recording the study
  manifest checksum, the R version and platform, every loaded package
  and its version, the `renv.lock` checksum, the input dataset’s
  SHA-256, and the cohort. `renv.lock` alone cannot say what produced a
  particular result — it is project-scoped and re-snapshotted through a
  study’s life — so the record is job-scoped and lives with the result.
  Failure to write it is an error, not a warning.

- The study data contract moves in from the per-study `R/` directories:
  [`study_root()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_root.md),
  [`sas_path()`](https://ehrlinger.github.io/hvtiRutilities/reference/sas_path.md),
  [`built_path()`](https://ehrlinger.github.io/hvtiRutilities/reference/built_path.md),
  [`built_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/built_manifest.md),
  [`read_built()`](https://ehrlinger.github.io/hvtiRutilities/reference/read_built.md),
  [`cohort_counts()`](https://ehrlinger.github.io/hvtiRutilities/reference/cohort_counts.md)
  and
  [`assert_cohort()`](https://ehrlinger.github.io/hvtiRutilities/reference/assert_cohort.md).
  All of them read study-specific values from `_study.yml` rather than
  from constants, so no study path, title, dataset name or cohort count
  appears in package code.

- [`r_dir_impurities()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_dir_impurities.md)
  reports top-level executable code in a directory that is sourced
  wholesale, where a stray call would run on every render.

### Notes

- New dependency: `jsonlite`, for the provenance sidecar.
- [`built_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/built_manifest.md)
  records `sha256` rather than the `md5` used by the earlier per-study
  version, matching the provenance record. One hash algorithm across the
  design, not two.

## hvtiRutilities 1.0.6

### Bug fixes

- [`sas_triage()`](https://ehrlinger.github.io/hvtiRutilities/reference/sas_triage.md):
  the excluded-subdirectory counts no longer include dot-directories. A
  local clone carries `.git`, whose loose-object files carry no
  extension and so matched none of the non-source suffixes, reporting 31
  files of “excluded SAS source” that were git internals. These counts
  exist to tell a human what triage did not look at, and `.git` is never
  that decision. `CVS/` is still reported: it is a legacy artifact
  committed into the corpus itself, not infrastructure of the clone.

## hvtiRutilities 1.0.5

### New features

- [`proc_means()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md)
  gains nine statistics from the SAS `unistats` vocabulary: `nobs`,
  `var`, `uss`, `css`, `skewness`, `kurtosis`, `sumwgt`, `qrange` and
  `mode`. `skewness` and `kurtosis` are the adjusted Fisher-Pearson
  forms SAS uses, cross-validated in the test suite against `e1071` with
  `type = 2`. `mode` returns the smallest of tied modes and `NA` when no
  value repeats, matching SAS.

- [`proc_means()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md)
  gains a `weights` argument naming a numeric column, mirroring the SAS
  `WEIGHT` statement. Weights apply within each `class` level.

  Weighting is not uniform, following `PROC MEANS`: `mean`, `std`,
  `var`, `cv`, `stderr`, `sum`, `uss`, `css`, `skewness`, `kurtosis` and
  `sumwgt` respond to weights; `n`, `nmiss`, `nobs`, `min`, `max`,
  `range`, `mode` and every quantile do not. `PROC MEANS` computes no
  weighted quantiles; that is `PROC UNIVARIATE`.

  A zero or negative weight raises an error naming the offending rows.
  SAS’s own handling of non-positive weights differs across procedures
  and versions, so this fails loudly rather than encode a guess.

  The `PROC UNIVARIATE` inference statistics remain out of scope. See
  `specs/2026-08-14-proc-means-unistats-design.md`.

### Bug fixes

- [`proc_means()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md):
  `cv` now returns `NA` when the mean is zero, matching SAS. R’s
  arithmetic gives `Inf`, which asserts an infinite coefficient of
  variation where SAS reports the value as undefined.

### Internal changes

- [`proc_means()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md)
  statistics are dispatched through a `.STATS` registry that declares,
  per statistic, whether it responds to weights and whether it is
  integer-typed. The weighted set is asserted directly in the test
  suite.

## hvtiRutilities 1.0.4

### New features

- Phase 0 of the SAS macro canonicalization program:
  [`sas_triage()`](https://ehrlinger.github.io/hvtiRutilities/reference/sas_triage.md),
  [`sas_macro_defs()`](https://ehrlinger.github.io/hvtiRutilities/reference/sas_macro_defs.md),
  [`sas_macro_signature()`](https://ehrlinger.github.io/hvtiRutilities/reference/sas_macro_signature.md),
  [`write_macro_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/write_macro_manifest.md)
  and
  [`write_collision_report()`](https://ehrlinger.github.io/hvtiRutilities/reference/write_collision_report.md).
  Together they inventory a legacy SAS macro library, classify each
  definition public or private, and report the name collisions that make
  `%include` order-dependent. Pure R – no SAS dependency, so the
  inventory runs on the development workstation.

  Two design points are worth recording, because the obvious
  implementations of both are wrong for this corpus.

  **File discovery excludes known non-source suffixes rather than
  matching `.sas`.** The library uses dots as word separators in
  filenames – `deciles.hazard`, `lm.cprobs` and `kaplan.int` are names,
  not stems with extensions – and many macro files carry no extension at
  all. An extension-anchored pattern omits both populations silently,
  including `unistats`, whose statistic vocabulary is the closest
  analogue in the corpus to
  [`proc_means()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md).

  **Validity checking uses a stateful scanner, not pattern matching.**
  It tracks comment state (`/* */`, `* ... ;`), string state (`'...'`,
  `"..."`) and macro quoting (`%'`), so comments and literals spanning
  lines, apostrophes inside double-quoted strings, and the `%STR(%')`
  transpose idiom are not mistaken for syntax errors. Every rule reads
  the scanned source, so a `%macro` written inside a comment or a string
  literal is not counted as a definition. The check reports a file that
  ends inside a string literal *or* inside a comment, naming the line
  where it opened – an unclosed `/*` is the more destructive of the two,
  because every statement after it is inert while the file still looks
  like usable source. There is deliberately no do/end balance check:
  textual balance is not a validity property of macro source, since
  `%do`-guarded blocks emit DO and END from separate branches.

  **A macro redefined inside one file is resolved, not escalated.** SAS
  compiles definitions in order and the later one replaces the earlier,
  so the last definition in a file is what any `%include` of it actually
  gets. Rule 3 keeps that one and drops the rest, each carrying the line
  that supersedes it. This is deliberately not a name collision:
  [`write_collision_report()`](https://ehrlinger.github.io/hvtiRutilities/reference/write_collision_report.md)
  lists names found in more than one *file*, because those are the ones
  whose behaviour depends on `%include` order. On the reference corpus
  158 of the 816 definitions are shadowed this way, leaving 658 live.

  On the reference corpus of 336 files this inventories 816 macro
  definitions across 307 distinct names, rejecting 5 as genuinely
  defective: `bl_ord.norm.ci.sas`, `CR_compare_CP_test_AT.sas`,
  `rem.original`, `rem.uab` and `repeated.sas`.

  Those figures replace an earlier measurement of 866 definitions across
  250 names. The difference is not a change of policy but a correction:
  the earlier run counted `%macro` statements that the scanner had
  already established were comment or string content. The rejected set
  is the same size and different in membership – `xmacro.sas` leaves it,
  having been failed for an imbalance whose second definition is
  commented out, and `bl_ord.norm.ci.sas` enters it, whose
  `* NOT COMPLETE` header carries no semicolon and therefore swallows
  the `%MACRO BLORD` statement on the line below. The file says as much
  itself.

## hvtiRutilities 1.0.3

### Documentation

- New vignette, *PROC CONTENTS and PROC MEANS in R*, written for readers
  who run both languages. It walks
  [`proc_contents()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_contents.md)
  and
  [`proc_means()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md)
  beside the procedures they replace, covers the `QNTLDEF=5` quantile
  difference that changes quartiles without changing the median, and
  lists every behaviour where the R version departs from the SAS
  original.

- [`compare_datasets()`](https://ehrlinger.github.io/hvtiRutilities/reference/compare_datasets.md)
  is now demonstrated in *Dataset Version Tracking* rather than only
  named in its index table. The example covers the four kinds of drift
  it reports and why a label change is the one to watch.

## hvtiRutilities 1.0.2

### New features

- [`proc_contents()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_contents.md):
  a port of SAS `PROC CONTENTS`. Returns a dataset header (observations,
  variables, label) and a variables table carrying creation position,
  name, SAS type, format, label, R class, distinct-value count, and
  percent missing. `Len`, `Pos`, and `Informat` are deliberately omitted
  — `haven` cannot recover them from a `.sas7bdat`, and inferred values
  would disagree with the source dataset whenever its `LENGTH` statement
  differed from the default.

- [`proc_means()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md):
  a port of SAS `PROC MEANS`. Takes SAS statistic keywords (`n`,
  `nmiss`, `mean`, `std`, `min`, `max`, `sum`, `range`, `stderr`, `cv`,
  `median`, `q1`, `q3`, and any `pNN`), defaulting to SAS’s own five,
  and supports `CLASS` stratification with SAS’s default handling of
  missing class levels. Quantiles use `type = 2`, the R equivalent of
  SAS `QNTLDEF=5`; R’s default `type = 7` disagrees with SAS on small
  and even-numbered samples.

### Documentation

- [`proc_contents()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_contents.md)
  now documents that `pct_missing` is `NaN`, not a value in 0-100, when
  the input has columns but zero rows: the proportion of missing values
  among no values is undefined, and reporting `0` would assert that
  nothing is missing. Behaviour is unchanged and is inherited from
  [`data_dictionary()`](https://ehrlinger.github.io/hvtiRutilities/reference/data_dictionary.md);
  only the documented contract is now accurate, and a test pins it.

### Internal changes

- [`data_dictionary()`](https://ehrlinger.github.io/hvtiRutilities/reference/data_dictionary.md)
  is now a thin wrapper over
  [`proc_contents()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_contents.md)
  and the shared statistic engine. Its signature and output are
  unchanged, pinned by characterization tests added before the refactor.

## hvtiRutilities 1.0.1

### Breaking changes

- [`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)
  and
  [`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)
  are now **silent by default**. Both gained a `verbose` argument
  (default `FALSE`) that gates all informational
  [`message()`](https://rdrr.io/r/base/message.html) output: “Manifest
  entry added / updated” in
  [`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md),
  and the per-entry “— SHA-256 match (n = N)” and “Manifest contains no
  dataset entries.” lines in
  [`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md).
  Pass `verbose = TRUE` to restore the previous console output.

  This removes unconditional chatter from packages that call these
  functions in a loop (for example `hvtiRdatasets::snapshot_oracle()`,
  which called
  [`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)
  once per study), and brings the package in line with the CRAN policy
  against chatty
  [`message()`](https://rdrr.io/r/base/message.html)/[`cat()`](https://rdrr.io/r/base/cat.html)
  in function bodies.

  Failures are unaffected: a SHA-256 mismatch, a missing file, or a
  row-count mismatch still raises
  [`stop()`](https://rdrr.io/r/base/stop.html) (or
  [`warning()`](https://rdrr.io/r/base/warning.html) when
  `stop_on_error = FALSE`) regardless of `verbose`. The per-entry status
  text is also still returned in the `message` column of
  [`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)’s
  data frame, so silencing the console loses no information.

  `verbose` is appended last in both signatures, so existing positional
  calls are unaffected.

### Maintenance

- Maintainer contact is now `john.ehrlinger@gmail.com`. The redundant
  `Maintainer:` field was removed from DESCRIPTION — with `Authors@R`
  present the maintainer is derived from the `cre` role, and having both
  declared different addresses.
- README: the repostatus badge now uses `https://` (the `http://` form
  301-redirected, failing
  [`urlchecker::url_check()`](https://urlchecker.r-lib.org/reference/url_check.html)).
- DESCRIPTION `Date:` refreshed to the 1.0.1 release date.

### Bug fixes

- [`read_clinical_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/read_clinical_data.md):
  files with no extension now produce a clear error (“Cannot determine
  file type: … has no extension”) instead of the misleading
  `Unsupported file type: '..'` message. The unsupported-extension error
  also now includes the full file path for easier diagnosis.

### Tests

- `test-read_clinical_data.R`: strengthened the tibble-coercion
  assertion from `expect_true(is.data.frame(result))` (TRUE for tibbles)
  to `expect_equal(class(result), "data.frame")` so the test actually
  protects against
  [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) being
  removed or bypassed.

### Documentation

- `vignettes/reproducible-seeds.qmd`: section heading “Using the Seed
  with varpro” and narrative references to the package now use the
  correct CRAN casing `varPro`; function-name references (`varpro()`,
  `unsupv.varpro()`) remain lowercase as those are the exported function
  names.

## hvtiRutilities 1.0.0.9003

### Bug fixes

- Fixed `Suggests` entry for `varPro`: package name on CRAN is `varPro`
  (camelCase), not `varpro` (lowercase). The case mismatch caused `pak`
  lockfile resolution to fail with “Can’t find package called varpro”.
  Updated the corresponding
  [`varPro::varpro()`](https://www.randomforestsrc.org/reference/varpro.html)
  call in `vignettes/reproducible-seeds.qmd` to match.

## hvtiRutilities 1.0.0.9002

### Documentation

- All vignettes migrated from R Markdown (`.Rmd`) to Quarto (`.qmd`).
  Added `quarto` to `Suggests`.

### Bug fixes

- [`read_clinical_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/read_clinical_data.md):
  CSV files are now read with `check.names = FALSE` so column names
  containing spaces, hyphens, or special characters are preserved
  exactly as written, preventing silent name mangling that could break
  downstream label lookups.

## hvtiRutilities 1.0.0.9000

### Maintenance

- Start prerelease cycle at 1.0.0.9000.

## hvtiRutilities 0.4.1

### Maintenance

- Bumped package metadata for the upcoming release cycle.

## hvtiRutilities 0.1.4

### New Features

- Added
  [`generate_survival_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/generate_survival_data.md):
  generates a synthetic cardiac surgery survival cohort with 22 clinical
  variables, Weibull-distributed survival times, reoperation outcome,
  and variable labels

### Bug Fixes

- Fixed
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  silently corrupting Date, POSIXct, and POSIXlt columns that had
  exactly 2 unique values (they were converted to logical)
- Fixed
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  incorrectly converting constant columns (1 unique value) to logical;
  binary detection now requires exactly 2 unique values
- Fixed
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  producing a cryptic “missing value where TRUE/FALSE needed” error when
  `factor_size = NaN`
- Fixed
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  giving a misleading “not found in dataset” error when `skip_vars` was
  not a character vector
- Fixed
  [`generate_survival_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/generate_survival_data.md)
  producing `NaN` in `iv_reop` for patients with very short follow-up
  times
- Fixed
  [`generate_survival_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/generate_survival_data.md)
  permanently altering the global RNG state; the session’s RNG is now
  saved and restored on exit

### Improvements

- [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  now validates all inputs before doing any work, so errors are raised
  immediately with clear messages
- [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  input validation now explicitly checks that `dataset` is a data.frame,
  `skip_vars` is a character vector, and `factor_size` is not NaN
- [`generate_survival_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/generate_survival_data.md)
  now uses
  [`labelled::var_label()`](https://larmarange.github.io/labelled/reference/var_label.html)
  consistently to attach labels instead of
  [`attr()`](https://rdrr.io/r/base/attr.html) directly
- Removed leftover `if (interactive())` development block from
  `generate_survival_data.R`
- Added new vignette `survival-data` demonstrating
  [`generate_survival_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/generate_survival_data.md)
  and its integration with
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  and
  [`label_map()`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)

### Tests

- Added 27 tests for
  [`generate_survival_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/generate_survival_data.md)
  covering structure, column types, outcome validity, reproducibility,
  RNG side-effect safety, and variable labels
- Updated POSIXct test to verify preservation without `skip_vars` (the
  previous test only verified the `skip_vars` workaround)
- Strengthened idempotency test to assert full value equality across
  sequential conversions, not just column class equality
- Updated `skip_vars` type-error test to match the improved error
  message

## hvtiRutilities 0.1.3

### Bug Fixes

- Fixed critical bug in
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  where
  [`dplyr::na_if()`](https://dplyr.tidyverse.org/reference/na_if.html)
  was called with a vector instead of scalar values
- Fixed bug where character columns with 2 unique values were
  incorrectly converted to logical (returning all NAs)
- Fixed bug in
  [`sample_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/sample_data.md)
  where [`sample.int()`](https://rdrr.io/r/base/sample.html) parameters
  were reversed, causing errors for small sample sizes
- Fixed column order preservation bug in
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  when using `skip_vars` - columns now maintain original order
- Fixed silent parameter mutation bug where `factor_size > 50` was
  changed to 20 without user consent - now errors instead

### Improvements

- Removed unused `lubridate` dependency that was never actually used in
  the package
- Removed inappropriate use of
  [`invisible()`](https://rdrr.io/r/base/invisible.html) from
  [`label_map()`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)
  and
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  functions
- Implemented
  [`hvtiRutilities.news()`](https://ehrlinger.github.io/hvtiRutilities/reference/hvtiRutilities.news.md)
  function that was referenced but didn’t exist
- Completely rewrote test suite with modern testthat 3 syntax (removed
  deprecated `context()` calls)
- Expanded test coverage from 24 tests to 75 comprehensive tests
- Added proper examples to
  [`label_map()`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)
  documentation with `@examples` tag
- Improved error messages for better clarity and consistency
- Changed `== TRUE` comparisons to simpler boolean checks

### Documentation

- Complete rewrite of README.md with actual package description and
  usage examples
- Fixed
  [`label_map()`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)
  documentation (was incomplete sentence, wrong return type)
- Improved
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  documentation with clearer parameter descriptions
- Added comprehensive usage examples for all main functions

## hvtiRutilities 0.1.2

- Internal development version

## hvtiRutilities 0.1.1

- Internal development version

## hvtiRutilities 0.1.0

- Initial release
- Core functions:
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md),
  [`label_map()`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md),
  [`sample_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/sample_data.md)
