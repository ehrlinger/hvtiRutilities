# Dataset Version Tracking with manifest.yaml

## The Problem: Datasets Drift

A dataset pulled from Epic today is **not** the same file you will get
if you pull it again tomorrow — even when no one intentionally changed
anything. Backfilled lab results, corrected ICD codes, and updated
patient status all mean that re-running an extraction silently changes
the underlying numbers.

The standard defence is a three-step protocol:

1.  **Name every dataset by its extract date** — `cohort_20240115.csv`,
    `labs_20240801.sas7bdat`. Never overwrite an existing dated file; a
    new pull gets a new filename.
2.  **Record a SHA-256 checksum** the moment a file lands on disk. A
    single changed byte produces a completely different hash.
3.  **Verify the checksums before every analysis run** so that any drift
    is caught immediately, before results are generated.

`hvtiRutilities` provides two functions that implement this protocol:

| Function                                                                                       | Purpose                                                     |
|------------------------------------------------------------------------------------------------|-------------------------------------------------------------|
| [`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md) | Register a dataset (or update its entry) in `manifest.yaml` |
| [`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md) | Check every registered dataset before an analysis runs      |

## Setup

``` r
if (requireNamespace("hvtiRutilities", quietly = TRUE)) {
  library("hvtiRutilities")
} else {
  pkgload::load_all(export_all = FALSE, helpers = FALSE, quiet = TRUE)
}
#> 
#>  hvtiRutilities 1.0.0.9000 
#>  
#>  Type hvtiRutilities.news() to see new features, changes, and bug fixes. 
#> 
```

For this vignette we work in a temporary directory that mimics a real
project’s `datasets/` folder.

``` r
datasets_dir <- file.path(tempdir(), "datasets")
dir.create(datasets_dir, showWarnings = FALSE)
manifest_path <- file.path(tempdir(), "manifest.yaml")
```

## Registering Datasets

### CSV — automatic row count

Generate a synthetic cohort (using
[`generate_survival_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/generate_survival_data.md))
and write it as a date-stamped CSV.

``` r
set.seed(42)
cohort <- generate_survival_data(n = 200, seed = 42)

cohort_file <- file.path(datasets_dir, "cohort_20240115.csv")
write.csv(cohort, cohort_file, row.names = FALSE)
```

Register it in the manifest. Row count is detected automatically from
the CSV header; only the SHA-256 is computed from the raw bytes.

``` r
update_manifest(
  file         = cohort_file,
  manifest_path = manifest_path,
  extract_date = "2024-01-15",
  source       = "Epic EMR, query v4.2, ICD mapping v3.2",
  sort_key     = "ccfid"
)
#> Manifest entry added: cohort_20240115.csv
```

Add a second file — a simulated labs extract pulled on the same date.

``` r
set.seed(7)
labs <- data.frame(
  ccfid   = cohort$ccfid,
  hgb     = round(rnorm(200, mean = 13.5, sd = 1.8), 1),
  egfr    = round(rnorm(200, mean = 72,   sd = 18),   0),
  bnp     = round(exp(rnorm(200, mean = 4.8, sd = 0.9)), 0)
)

labs_file <- file.path(datasets_dir, "labs_20240115.csv")
write.csv(labs, labs_file, row.names = FALSE)

update_manifest(
  file          = labs_file,
  manifest_path = manifest_path,
  extract_date  = "2024-01-15",
  source        = "Epic EMR, labs module — Hgb, eGFR, BNP",
  sort_key      = "ccfid"
)
#> Manifest entry added: labs_20240115.csv
```

### Inspecting the manifest

The manifest is a plain YAML file committed to version control alongside
your analysis scripts (but **not** alongside the data files, which stay
out of git).

``` r
cat(paste(readLines(manifest_path), collapse = "\n"))
#> datasets:
#> - file: cohort_20240115.csv
#>   extract_date: '2024-01-15'
#>   n_rows: 200
#>   sha256: f3db9dd8a47765003a2509c54068f8736b0fd8c2f0b0425808422cc11f0bdfcd
#>   source: Epic EMR, query v4.2, ICD mapping v3.2
#>   sort_key: ccfid
#> - file: labs_20240115.csv
#>   extract_date: '2024-01-15'
#>   n_rows: 200
#>   sha256: 035acf2e981692554ba8e2c07f8b61f9d6ceb834343612d50d5487aed062b380
#>   source: Epic EMR, labs module — Hgb, eGFR, BNP
#>   sort_key: ccfid
```

Each entry records exactly what is needed to re-verify the file later:
`extract_date`, `n_rows`, `sha256`, and any provenance notes you supply.

### SAS datasets — automatic row count

Files exported directly from SAS (`.sas7bdat`) are handled the same way.
[`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)
calls
[`haven::read_sas()`](https://haven.tidyverse.org/reference/read_sas.html)
internally to count rows; the checksum is always computed from the raw
file bytes.

``` r
update_manifest(
  file          = here::here("datasets", "cohort_20240115.sas7bdat"),
  manifest_path = here::here("manifest.yaml"),
  extract_date  = "2024-01-15",
  source        = "SAS CORR registry extract, query v3.1",
  sort_key      = "pat_id"
)
```

### Excel workbooks — automatic row count

Adjudication logs, crosswalk tables, and other curator-maintained
datasets often arrive as `.xlsx` files.
[`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)
calls
[`readxl::read_excel()`](https://readxl.tidyverse.org/reference/read_excel.html)
to count rows.

``` r
update_manifest(
  file          = here::here("datasets", "adjudication_20240115.xlsx"),
  manifest_path = here::here("manifest.yaml"),
  extract_date  = "2024-01-15",
  source        = "Clinical Events Committee adjudication log, v2"
)
```

### Other formats — supply `n_rows` explicitly

For RDS, Feather, Parquet, or any format not listed above, pass `n_rows`
directly. The SHA-256 is still computed from the raw bytes.

``` r
update_manifest(
  file          = here::here("datasets", "cohort_20240115.rds"),
  manifest_path = here::here("manifest.yaml"),
  extract_date  = "2024-01-15",
  n_rows        = nrow(readRDS(here::here("datasets", "cohort_20240115.rds"))),
  source        = "RDS cached from Epic pull"
)
```

## Verifying Before Every Analysis

Place
[`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)
at the very top of every analysis script and Quarto document — before
any data are loaded and before any results are produced.

``` r
verify_manifest(
  manifest_path = manifest_path,
  data_dir      = datasets_dir
)
#> cohort_20240115.csv — SHA-256 match (n = 200)
#> labs_20240115.csv — SHA-256 match (n = 200)
```

The function prints one confirmation line per file and returns
invisibly. If everything is clean, your script continues.

### Typical script header

``` r
library(hvtiRutilities)
library(here)

# Abort immediately if any registered dataset has changed
verify_manifest(here("manifest.yaml"))

# Only reached if all checksums pass
cohort <- read.csv(here("datasets", "cohort_20240115.csv"))
labs   <- read.csv(here("datasets", "labs_20240115.csv"))
```

## What Happens When Data Changes

Suppose the data warehouse silently updates `cohort_20240115.csv`
overnight.
[`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)
catches it the moment the next analysis run starts.

``` r
# Simulate a silent dataset change
cohort_modified <- cohort
cohort_modified$age[1] <- cohort_modified$age[1] + 1L
write.csv(cohort_modified, cohort_file, row.names = FALSE)

# verify_manifest stops immediately
verify_manifest(
  manifest_path = manifest_path,
  data_dir      = datasets_dir
)
#> labs_20240115.csv — SHA-256 match (n = 200)
#> Error:
#> ! STOP: manifest verification failed for:
#>    cohort_20240115.csv: SHA-256 mismatch
#>   expected: f3db9dd8a47765003a2509c54068f8736b0fd8c2f0b0425808422cc11f0bdfcd
#>   actual:   5557af305fedf53ed5ee74c6a0aace29e4974a549a2a44fc5ff8c173d40a4e1a
```

The error message names the affected file and shows both the expected
and actual SHA-256 values, giving you an unambiguous audit trail.

### Collecting all failures at once

During development it can be useful to see every problem before fixing
any of them. Set `stop_on_error = FALSE` to collect warnings instead of
stopping.

``` r
report <- verify_manifest(
  manifest_path = manifest_path,
  data_dir      = datasets_dir,
  stop_on_error = FALSE
)
#> labs_20240115.csv — SHA-256 match (n = 200)
#> Warning: STOP: manifest verification failed for:
#>    cohort_20240115.csv: SHA-256 mismatch
#>   expected: f3db9dd8a47765003a2509c54068f8736b0fd8c2f0b0425808422cc11f0bdfcd
#>   actual:   5557af305fedf53ed5ee74c6a0aace29e4974a549a2a44fc5ff8c173d40a4e1a

report[report$status == "FAIL", c("file", "message")]
#>                  file
#> 1 cohort_20240115.csv
#>                                                                                                                                                                        message
#> 1 SHA-256 mismatch\n  expected: f3db9dd8a47765003a2509c54068f8736b0fd8c2f0b0425808422cc11f0bdfcd\n  actual:   5557af305fedf53ed5ee74c6a0aace29e4974a549a2a44fc5ff8c173d40a4e1a
```

### Updating the manifest after a legitimate re-pull

If a new extract is intentional — a corrected pull, an updated query —
call
[`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)
again with the same filename. The existing entry is replaced in place
and the new checksum is recorded.

``` r
# Re-register after the legitimate change
update_manifest(
  file          = cohort_file,
  manifest_path = manifest_path,
  extract_date  = "2024-01-15",
  source        = "Epic EMR, query v4.2, ICD mapping v3.2 — corrected age for pt 1"
)
#> Manifest updated: cohort_20240115.csv

# Verification now passes again
verify_manifest(
  manifest_path = manifest_path,
  data_dir      = datasets_dir
)
#> cohort_20240115.csv — SHA-256 match (n = 200)
#> labs_20240115.csv — SHA-256 match (n = 200)
```

## A New Pull for a Different Project

When the same registry is pulled again months later for a different
analysis, it gets a **new filename** — never overwriting the original.

``` r
set.seed(99)
cohort_aug <- generate_survival_data(n = 315, seed = 99)

cohort_aug_file <- file.path(datasets_dir, "cohort_20240801.csv")
write.csv(cohort_aug, cohort_aug_file, row.names = FALSE)

update_manifest(
  file          = cohort_aug_file,
  manifest_path = manifest_path,
  extract_date  = "2024-08-01",
  source        = "Epic EMR, query v4.2, ICD mapping v3.3 — LVAD sub-study cohort",
  sort_key      = "ccfid"
)
#> Manifest entry added: cohort_20240801.csv
```

The manifest now tracks all three files independently.

``` r
m <- yaml::read_yaml(manifest_path)
do.call(rbind, lapply(m$datasets, function(e)
  data.frame(file = e$file, extract_date = e$extract_date,
             n_rows = e$n_rows, stringsAsFactors = FALSE)
))
#>                  file extract_date n_rows
#> 1 cohort_20240115.csv   2024-01-15    200
#> 2   labs_20240115.csv   2024-01-15    200
#> 3 cohort_20240801.csv   2024-08-01    315
```

Verification covers all of them in a single call.

``` r
verify_manifest(
  manifest_path = manifest_path,
  data_dir      = datasets_dir
)
#> cohort_20240115.csv — SHA-256 match (n = 200)
#> labs_20240115.csv — SHA-256 match (n = 200)
#> cohort_20240801.csv — SHA-256 match (n = 315)
```

## Policy Recommendations

| Stage                            | Action                                                                                                                                           |
|----------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------|
| **On every data pull**           | Run [`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md) immediately and commit `manifest.yaml` to git |
| **Top of every analysis script** | Call [`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md) — before loading any data                    |
| **At manuscript submission**     | Tag the git commit; freeze `manifest.yaml`; do not re-pull data                                                                                  |
| **For a new project or re-pull** | Use a new date-stamped filename; add a new [`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md) entry  |
| **`.gitignore`**                 | Add `datasets/` — commit the manifest, not the data                                                                                              |

## Summary

- [`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)
  records the SHA-256 checksum, row count, extract date, and optional
  provenance fields for CSV, SAS, Excel, or any file type.
- [`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)
  checks every registered dataset before results are produced; one
  changed byte triggers an immediate, informative error.
- The combination makes dataset drift **detectable** and the audit trail
  **reproducible** from first pull to manuscript submission.

## Session Information

``` r
sessionInfo()
#> R version 4.5.3 (2026-03-11)
#> Platform: x86_64-pc-linux-gnu
#> Running under: Ubuntu 24.04.3 LTS
#> 
#> Matrix products: default
#> BLAS:   /usr/lib/x86_64-linux-gnu/openblas-pthread/libblas.so.3 
#> LAPACK: /usr/lib/x86_64-linux-gnu/openblas-pthread/libopenblasp-r0.3.26.so;  LAPACK version 3.12.0
#> 
#> locale:
#>  [1] LC_CTYPE=C.UTF-8       LC_NUMERIC=C           LC_TIME=C.UTF-8       
#>  [4] LC_COLLATE=C.UTF-8     LC_MONETARY=C.UTF-8    LC_MESSAGES=C.UTF-8   
#>  [7] LC_PAPER=C.UTF-8       LC_NAME=C              LC_ADDRESS=C          
#> [10] LC_TELEPHONE=C         LC_MEASUREMENT=C.UTF-8 LC_IDENTIFICATION=C   
#> 
#> time zone: UTC
#> tzcode source: system (glibc)
#> 
#> attached base packages:
#> [1] stats     graphics  grDevices utils     datasets  methods   base     
#> 
#> other attached packages:
#> [1] hvtiRutilities_1.0.0.9000
#> 
#> loaded via a namespace (and not attached):
#>  [1] vctrs_0.7.1       cli_3.6.5         knitr_1.51        rlang_1.1.7      
#>  [5] xfun_0.56         forcats_1.0.1     otel_0.2.0        haven_2.5.5      
#>  [9] generics_0.1.4    textshaping_1.0.5 jsonlite_2.0.0    glue_1.8.0       
#> [13] htmltools_0.5.9   ragg_1.5.1        sass_0.4.10       hms_1.1.4        
#> [17] rmarkdown_2.30    tibble_3.3.1      evaluate_1.0.5    jquerylib_0.1.4  
#> [21] fastmap_1.2.0     yaml_2.3.12       lifecycle_1.0.5   compiler_4.5.3   
#> [25] dplyr_1.2.0       fs_1.6.7          pkgconfig_2.0.3   htmlwidgets_1.6.4
#> [29] labelled_2.16.0   systemfonts_1.3.2 digest_0.6.39     R6_2.6.1         
#> [33] tidyselect_1.2.1  pillar_1.11.1     magrittr_2.0.4    bslib_0.10.0     
#> [37] tools_4.5.3       pkgdown_2.2.0     cachem_1.1.0      desc_1.4.3
```
