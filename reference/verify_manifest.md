# Verify all datasets listed in a manifest

Reads a `manifest.yaml` produced by
[`update_manifest`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)
and, for every entry, confirms that (a) the file exists, (b) its SHA-256
checksum matches the recorded value, and (c) its row count matches.
Supported formats for automatic row-count verification: CSV (`.csv`),
SAS (`.sas7bdat`), and Excel (`.xlsx`, `.xls`). For other file types the
row-count check is skipped and only the SHA-256 is verified.

Re-deriving the row count of a SAS or Excel file means reading the whole
file, so it only happens under
`options(manifest.allow_heavy_rowcount = TRUE)`. Without that option the
row count is skipped rather than failed, and the entry passes on its
checksum, which is the stronger of the two checks. A check that could
not run is not a check that failed. A file that cannot be read at all is
a different matter and still fails.

An entry recording no SHA-256 fails, because the checksum is the whole
of what this function verifies and there is nothing to compare it
against. Manifests written by an md5-based writer are the case that
turns up in practice; the failure names the algorithm that was recorded
instead.

Three outcomes are therefore possible for an entry that passes, and the
report distinguishes them rather than reporting all three as simply
verified. The count was compared; the count is recorded but was not
re-derived; or the manifest records no count at all. The
`row_count_checked` column is `TRUE` only in the first case, and the
message names which of the three it was. A build-record row (see below)
sets `row_count_checked` to `TRUE` once its checksum is verified,
because a record has no row count.

For a dataset registered with
[`register_data`](https://ehrlinger.github.io/hvtiRutilities/reference/register_data.md),
every registered version (the current dated parquet and each earlier
one) is checked, and its row count is re-derived from the parquet footer
when the arrow package is available. A source file rebuilt since
registration is reported with status `"PENDING"` and never stops: jobs
keep reading the registered version until
[`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)
registers the new one.

Call this function at the top of every analysis script or Quarto
document to ensure data integrity before any results are generated.

## Usage

``` r
verify_manifest(
  manifest_path = .default_manifest_path(),
  data_dir = NULL,
  stop_on_error = TRUE,
  verbose = FALSE,
  strict = FALSE
)
```

## Arguments

- manifest_path:

  Character. Path to the manifest YAML file. Defaults to the study's
  `manifest.yaml` when run inside a study (a `_study.yml` here or
  above), and to `"manifest.yaml"` in the working directory otherwise.

- data_dir:

  Character. Directory holding the dataset files. When supplied, it is
  used exactly as given. When `NULL` (default), the manifest directory
  is inspected once. `00_datasets/` supports the numbered layout created
  by
  [`study_setup`](https://ehrlinger.github.io/hvtiRutilities/reference/study_setup.md),
  `datasets/` supports an adopted legacy layout, and a manifest with
  neither uses its own directory. Outside a study, an empty nested
  directory does not displace files beside the manifest. Both dataset
  directories together are a mixed layout and produce an error; entries
  never fall back between layouts.

- stop_on_error:

  Logical. If `TRUE` (default) the function calls
  [`stop()`](https://rdrr.io/r/base/stop.html) on the first failed
  check, preventing the analysis from proceeding. Set to `FALSE` to
  collect all errors and report them together as a warning.

- verbose:

  Logical. If `TRUE`, report each passing entry via
  [`message`](https://rdrr.io/r/base/message.html). Defaults to `FALSE`
  so that scripted or looped calls stay silent; the same information is
  always available in the returned data frame. Failures are reported
  through [`stop()`](https://rdrr.io/r/base/stop.html) or
  [`warning()`](https://rdrr.io/r/base/warning.html) regardless of this
  setting.

- strict:

  Logical. If `TRUE`, an entry whose row count could not be re-derived
  is reported as `"FAIL"` rather than passing on its checksum alone, and
  the message names which of the three causes applies: no count recorded
  in the manifest, a file type whose rows cannot be counted, or heavy
  row counting left disabled. Defaults to `FALSE`, which preserves the
  permissive behaviour described above.

  Use it where the question is "did every check actually run", not "is
  the data intact": a release gate, an archival gate, or a hand-off
  where a downstream reader will treat `"OK"` as meaning fully verified.
  Under the default, `"OK"` can mean "checksum verified, row count not
  examined", and the `row_count_checked` column is the only thing that
  distinguishes the two.

## Value

Invisibly returns a data frame with columns `file`, `status` (`"OK"` or
`"FAIL"`), `message`, and `row_count_checked` (logical; `TRUE` when the
row count was re-derived from the file and compared with the manifest;
also `TRUE` for a build-record row whose checksum was verified, since a
record has no row count).

## See also

[`update_manifest`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)

## Examples

``` r
dir <- file.path(tempdir(), "verify-manifest-example")
dir.create(dir)
csv <- file.path(dir, "cohort_20240115.csv")
utils::write.csv(data.frame(patient_id = 1:3, age = c(61, 70, 55)), csv,
                 row.names = FALSE)
manifest <- file.path(dir, "manifest.yaml")
update_manifest(csv, manifest_path = manifest, extract_date = "2024-01-15")

# Silent unless a check fails; verbose = TRUE reports each passing entry.
verify_manifest(manifest, verbose = TRUE)
#> cohort_20240115.csv — SHA-256 match (n = 3)

# The file changes after registration. Collect failures instead of
# stopping on the first.
utils::write.csv(data.frame(patient_id = 1:4, age = c(61, 70, 55, 48)), csv,
                 row.names = FALSE)
report <- suppressWarnings(verify_manifest(manifest, stop_on_error = FALSE))
report[, c("file", "status")]
#>                  file status
#> 1 cohort_20240115.csv   FAIL
unlink(dir, recursive = TRUE)
```
