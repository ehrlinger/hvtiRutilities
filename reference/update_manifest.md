# Create or update a dataset manifest file

**In a study**, run with no arguments after rebuilding a registered
dataset: `update_manifest()`. It finds the study from the working
directory, converts every registered dataset whose source file has
changed to a new dated parquet (`<name>_YYYYMMDD.parquet`, or `_r2`,
`_r3` for another version on the same date), keeps every earlier
version, records the change in `manifest.yaml`, and prints one line per
dataset. Jobs read the new version from then on. Unchanged datasets are
left alone. Name one with `dataset`. Release-aware datasets are skipped;
use
[`review_data_update`](https://ehrlinger.github.io/hvtiRutilities/reference/review_data_update.md)
and
[`adopt_data_update`](https://ehrlinger.github.io/hvtiRutilities/reference/adopt_data_update.md).
Needs the arrow package.

**A single file**: `update_manifest(file, ...)` records a SHA-256
checksum, row count, extract date and optional provenance fields for one
file in a `manifest.yaml`. If the manifest already contains an entry for
the named file it is updated in place; otherwise a new entry is
appended. The manifest is intended to be committed to version control
while the data files themselves are not. It refuses a file a study
registers as dated versions, whose entry it would flatten; use the
no-argument form for those.

Row counts are detected automatically for **CSV** (`.csv`) files. For
**SAS** (`.sas7bdat`) and **Excel** (`.xlsx`, `.xls`) files, automatic
row counting is considered "heavy" because it loads the entire
dataset/workbook into memory; it is therefore disabled by default and
only performed when `options(manifest.allow_heavy_rowcount = TRUE)` is
set. For any other format, or when heavy counting is disabled, supply
`n_rows` explicitly.

## Usage

``` r
update_manifest(
  file,
  manifest_path = "manifest.yaml",
  extract_date = Sys.Date(),
  n_rows = NULL,
  n_cols = NULL,
  source = NULL,
  sort_key = NULL,
  schema_sha256 = NULL,
  role = c("source", "primary"),
  reader = NULL,
  verbose = FALSE,
  dataset = NULL
)
```

## Arguments

- file:

  Character. Path to the dataset file. Omit it inside a study to
  register every changed dataset; see the description.

- manifest_path:

  Character. Path to the manifest YAML file. Created if it does not
  exist. Defaults to `"manifest.yaml"` in the current working directory.

- extract_date:

  Character or `Date`. The date the data were pulled from the source
  system. Stored as `"YYYY-MM-DD"`. Defaults to today's date. With no
  `file`, the date of the new version; defaults to the source file's
  modification date.

- n_rows:

  Integer. Number of data rows. When `NULL` (default) the row count is
  detected automatically from CSV files, and from SAS/Excel files only
  when `options(manifest.allow_heavy_rowcount = TRUE)` is set. all other
  file types supply this value explicitly.

- n_cols:

  Integer. Column count. Pass it from a frame already read; a row count
  alone cannot detect a dropped column.

- source:

  Character. Free-text description of the data source (e.g.
  `"Epic EMR, query v4.2, ICD mapping v3.2"`).

- sort_key:

  Character. Column name(s) that define the canonical sort order of the
  dataset.

- schema_sha256:

  Character. SHA-256 of this dataset's schema sidecar, making the
  manifest-to-sidecar link tamper-evident.

- role:

  Character, always `"source"`. This function only ever writes
  `role = "source"` entries; a `role = "primary"` (promoted) entry's
  `sha256` must describe its **parquet**, not the source this function
  hashes, so calling it on a promoted entry would write a manifest that
  can never verify. No exported function performs promotion yet — the
  internal `.update_promoted_entry()` is what maintains a promoted entry
  once one exists. See the *Promotion* section of the read-layer design
  spec.

- reader:

  Character. The package and version that produced this derived file
  (e.g. `"haven 2.5.5"`). Under `role = "primary"` the parquet is the
  data, so the reader that produced it is part of its provenance: a
  reader defect found later is otherwise unfindable once the source is
  retired. `NULL` (default) omits the field.

- verbose:

  Logical. If `TRUE`, report which manifest entry was added or updated
  via [`message`](https://rdrr.io/r/base/message.html). Defaults to
  `FALSE` so that scripted or looped calls stay silent.

- dataset:

  Character(1) or `NULL`. With no `file`: the one registered dataset to
  update; `NULL` updates every one that changed. Ignored when `file` is
  given.

## Value

With `file`, invisibly returns the updated manifest as a named list.
With no `file`, invisibly returns a data frame with one row per dataset
and columns `dataset`, `action` (`"registered"`, `"migrated"`,
`"unchanged"` or `"skipped"`) and `detail`.

## See also

[`verify_manifest`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# --- In a study, after rebuilding built.sas7bdat --------------------
update_manifest()

# --- CSV ------------------------------------------------------------
update_manifest(
  file         = here::here("datasets", "cohort_20240115.csv"),
  extract_date = "2024-01-15",
  source       = "Epic EMR, query v4.2, ICD mapping v3.2",
  sort_key     = "patient_id"
)

# --- SAS ------------------------------------------------------------
# .sas7bdat files exported from SAS or pulled via SASConnect
update_manifest(
  file         = here::here("datasets", "labs_20240115.sas7bdat"),
  extract_date = "2024-01-15",
  source       = "SAS dataset from CORR registry, labs module v2.1",
  sort_key     = "pat_id"
)

# --- Excel ----------------------------------------------------------
update_manifest(
  file         = here::here("datasets", "adjudication_20240115.xlsx"),
  extract_date = "2024-01-15",
  source       = "Clinical events committee adjudication log"
)

# --- Verify all three at once ---------------------------------------
verify_manifest(here::here("manifest.yaml"))
} # }
```
