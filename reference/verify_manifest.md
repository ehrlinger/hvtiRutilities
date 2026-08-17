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
not run is not a check that failed. The `row_count_checked` column says
which entries were counted, so you can tell the two apart. A file that
cannot be read at all is a different matter and still fails.

Call this function at the top of every analysis script or Quarto
document to ensure data integrity before any results are generated.

## Usage

``` r
verify_manifest(
  manifest_path = "manifest.yaml",
  data_dir = NULL,
  stop_on_error = TRUE,
  verbose = FALSE
)
```

## Arguments

- manifest_path:

  Character. Path to the manifest YAML file. Defaults to
  `"manifest.yaml"` in the current working directory.

- data_dir:

  Character. Directory in which to look for the dataset files. When
  `NULL` (default) the directory containing `manifest_path` is used.

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

## Value

Invisibly returns a data frame with columns `file`, `status` (`"OK"` or
`"FAIL"`), `message`, and `row_count_checked` (logical; `TRUE` when the
row count was re-derived from the file and compared with the manifest).

## See also

[`update_manifest`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# --- Typical usage: top of every analysis script or .qmd -----------
# Silent unless a check fails.
hvtiRutilities::verify_manifest(here::here("manifest.yaml"))

# --- Interactive use: report each passing entry ---------------------
hvtiRutilities::verify_manifest(here::here("manifest.yaml"), verbose = TRUE)
# cohort_20240115.csv    — SHA-256 match (n = 831)
# labs_20240115.sas7bdat — SHA-256 match (n = 1204); row count not re-derived
# adjudication_20240115.xlsx — SHA-256 match (n = 47); row count not re-derived

# --- Collect all failures instead of stopping on the first ---------
report <- verify_manifest(
  here::here("manifest.yaml"),
  stop_on_error = FALSE
)
report[report$status == "FAIL", ]
} # }
```
