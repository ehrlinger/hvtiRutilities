# Dataset Release Consumer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a study pin one published dataset release, discover newer
catalog releases without following them, review a named candidate, and adopt
it through an atomic study-contract update.

**Architecture:** A focused catalog reader validates the version-1 publisher
contract and resolves release records. Release-aware study contracts feed
three exported operations: discovery, review, and adoption. `read_built()`
keeps serving the pinned file, but verifies published bytes before the cache
can refresh its manifest and emits a once-per-session update condition.

**Tech Stack:** R 4.1+, testthat edition 3, yaml, digest, haven, labelled,
devtools, roxygen2, Quarto.

**Spec:** `dev/specs/2026-09-21-dataset-release-contract-design.md`

## Global Constraints

- This plan implements the `hvtiRutilities` consumer only. Implement
  `publish_dataset()` and catalog locking in `hvtiRdatabuild` under its own
  plan and pull request first.
- Treat `dataset-catalog.yml` in the logical datasets directory as the only
  release catalog. Catalog filenames are basenames and may not escape that
  directory.
- Keep every existing study without a `release` block working exactly as it
  does now.
- Never choose a release implicitly during adoption. The caller supplies an
  exact `release_id`; the string `"latest"` is invalid.
- A newer release is informational. It never changes the file read by
  `read_built()` and never makes the current study contract invalid.
- Verify a release-aware pinned file before `.cache_read()` runs. Otherwise a
  changed source can enter the cache-miss path and rewrite `manifest.yaml`,
  silently blessing an in-place mutation.
- Derive cohort counts from the candidate data. Never accept replacement
  counts from the caller.
- Replace `_study.yml` and `manifest.yaml` through `.replace_study_pair()`;
  do not add a second transaction mechanism.
- Use Rd markup, not markdown, in roxygen. Keep lines at no more than 135
  characters and preserve the package's lint-clean state.
- Add every new export to `_pkgdown.yml`, run `devtools::document()`, and
  commit generated `man/`, `NAMESPACE`, and `DESCRIPTION` changes.
- Add an entry beneath `# hvtiRutilities (unreleased)` in `NEWS.md`. Do not
  bump `Version:`.
- Do not write paths, credentials, patient identifiers, or real study data to
  fixtures, conditions, snapshots, or documentation.

## Review Focus

- A filename reused under two logical dataset IDs must invalidate the catalog;
  test the cross-dataset duplicate, not only duplicates within one release
  list (Task 1).
- Same-day corrections must be ordered by `sequence`, even when lexical
  filename order disagrees (Task 3).
- A missing catalog must report `UPDATE STATUS UNKNOWN` while a valid pinned
  read still succeeds (Task 4).
- A checksum-invalid candidate must fail discovery without blocking the valid
  pinned read (Task 4).
- A candidate changed after review but before adoption must fail adoption and
  leave both study files byte-identical (Task 6).

---

## File Map

| file | action | responsibility |
|---|---|---|
| `R/dataset_catalog.R` | create | validate the version-1 catalog and resolve release records and files |
| `R/data_updates.R` | create | discovery, conditions, review, printing, and atomic adoption |
| `R/study_config.R` | modify | validate and preserve default and named `release` blocks |
| `R/study_data.R` | modify | expose release metadata through `.study_dataset()` and guard/notify reads |
| `R/register_data.R` | modify | attach a verified published release during initial registration |
| `R/study_status.R` | modify | report current, available, unknown, withdrawn, and failed update states |
| `tests/testthat/helper-release.R` | create | build synthetic catalogs and release-aware studies |
| `tests/testthat/fixtures/dataset-catalog-v1.yml` | create | shared version-1 contract fixture for both packages |
| `tests/testthat/test-dataset_catalog.R` | create | catalog schema and file-integrity tests |
| `tests/testthat/test-data_updates.R` | create | discovery, review, conditions, and adoption tests |
| `tests/testthat/test-study_config.R` | modify | release-block validation and legacy compatibility |
| `tests/testthat/test-register_data.R` | modify | catalog-backed initial registration |
| `tests/testthat/test-study_status.R` | modify | update-status rows and print markers |
| `tests/testthat/test-parquet_cache.R` | modify | immutable-release guard before cache refresh |
| `vignettes/dataset-versioning.qmd` | modify | replace overwrite-and-rehash advice with publish/review/adopt workflow |
| `NEWS.md` | modify | document the new release-aware study contract |
| `_pkgdown.yml` | modify | index the three new exports |
| `man/*.Rd`, `NAMESPACE`, `DESCRIPTION` | generate | roxygen output required by the repository gate |

### Task 1: Validate and resolve the version-1 catalog

**Files:**
- Create: `R/dataset_catalog.R`
- Create: `tests/testthat/helper-release.R`
- Create: `tests/testthat/fixtures/dataset-catalog-v1.yml`
- Create: `tests/testthat/test-dataset_catalog.R`

**Interfaces:**
- Produces: `.catalog_path(cfg) -> character(1)`.
- Produces: `.read_dataset_catalog(path) -> validated list`.
- Produces: `.catalog_release(catalog, dataset_id, release_id) -> list`.
- Produces: `.catalog_file(release, data_dir) -> character(1)`.
- Produces: `.verify_catalog_file(release, data_dir) -> character(1)` path,
  or an error of class `hvtiRutilities_release_integrity`.
- Produces test helper:
  `write_release_fixture(root, releases, dataset_id = "surgery_cohort")`.

- [ ] **Step 1: Write the shared valid fixture and helper**

Create `tests/testthat/fixtures/dataset-catalog-v1.yml` with two synthetic
releases. Use complete 64-character lowercase checksums in the committed
contract fixture; the helper rewrites those checksums after it writes test
CSV files.

```yaml
format_version: 1
datasets:
  surgery_cohort:
    releases:
      - release_id: surgery_cohort-20260920-r1
        sequence: 1
        file: cohort_20260920.csv
        extract_date: '2026-09-20'
        revision: 1
        published_at: '2026-09-20T16:00:00-04:00'
        sha256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
        n_rows: 3
        n_cols: 3
        status: published
      - release_id: surgery_cohort-20260921-r1
        sequence: 2
        file: cohort_20260921.csv
        extract_date: '2026-09-21'
        revision: 1
        published_at: '2026-09-21T16:00:00-04:00'
        sha256: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
        n_rows: 4
        n_cols: 3
        status: published
```

In `helper-release.R`, copy the fixture into the study's logical datasets
directory, write synthetic `id`, `dead`, and `iv_dead` CSVs, then replace each
fixture checksum with `digest::digest(path, algo = "sha256", file = TRUE)`.
Return a list containing `root`, `catalog_path`, `catalog`, and `data_dir`.
The `releases` argument defaults to the two records in the committed fixture;
tests may pass a complete replacement release list.

- [ ] **Step 2: Write failing catalog schema tests**

```r
test_that("catalog v1 validates and resolves a release", {
  fx <- write_release_fixture(withr::local_tempdir())
  catalog <- .read_dataset_catalog(fx$catalog_path)
  rel <- .catalog_release(
    catalog,
    "surgery_cohort",
    "surgery_cohort-20260921-r1"
  )

  expect_identical(rel$sequence, 2L)
  expect_identical(rel$revision, 1L)
  expect_identical(.verify_catalog_file(rel, fx$data_dir),
                   file.path(fx$data_dir, rel$file))
})

test_that("catalog rejects a file reused by different datasets", {
  fx <- write_release_fixture(withr::local_tempdir())
  catalog <- yaml::read_yaml(fx$catalog_path)
  catalog$datasets$imaging <- catalog$datasets$surgery_cohort
  catalog$datasets$imaging$releases[[1L]]$release_id <- "imaging-1"
  catalog$datasets$imaging$releases[[1L]]$sequence <- 1L
  catalog$datasets$imaging$releases <-
    catalog$datasets$imaging$releases[1L]
  yaml::write_yaml(catalog, fx$catalog_path)

  expect_error(.read_dataset_catalog(fx$catalog_path),
               "listed more than once")
})

test_that("catalog rejects paths that escape the datasets directory", {
  fx <- write_release_fixture(withr::local_tempdir())
  catalog <- yaml::read_yaml(fx$catalog_path)
  catalog$datasets$surgery_cohort$releases[[1L]]$file <- "../cohort.csv"
  yaml::write_yaml(catalog, fx$catalog_path)

  expect_error(.read_dataset_catalog(fx$catalog_path), "basename")
})
```

Add table-driven cases for an unknown `format_version`, unnamed `datasets`,
missing required fields, invalid SHA-256, impossible `extract_date`, invalid
`published_at`, zero or fractional `sequence`, non-increasing sequence order,
duplicate release ID, duplicate sequence, invalid status, a withdrawn release
without `withdrawal_reason`, and a missing replacement release ID.

- [ ] **Step 3: Run the tests to verify failure**

Run:

```bash
Rscript -e 'devtools::test(filter = "dataset_catalog")'
```

Expected: FAIL because `.read_dataset_catalog()` and the resolver helpers do
not exist.

- [ ] **Step 4: Implement scalar and catalog validation**

Create `R/dataset_catalog.R` with narrowly scoped helpers. Normalize integers
only after proving the original value is a scalar whole number.

```r
.catalog_abort <- function(message) {
  stop("dataset catalog: ", message, call. = FALSE)
}

.catalog_scalar <- function(x, name, type = "character") {
  valid <- length(x) == 1L && !is.na(x)
  if (identical(type, "character")) {
    valid <- valid && is.character(x) && nzchar(x)
  } else {
    valid <- valid && is.numeric(x) && is.finite(x) && x == as.integer(x)
  }
  if (!valid) .catalog_abort(paste0(name, " is invalid"))
  if (identical(type, "integer")) as.integer(x) else x
}

.catalog_path <- function(cfg) {
  file.path(study_dir("datasets", cfg$root), "dataset-catalog.yml")
}

.catalog_file <- function(release, data_dir) {
  file.path(data_dir, release$file)
}
```

Implement `.read_dataset_catalog()` so it validates every required field and
then validates the collection-wide invariants. Use these exact predicates:

```r
is_sha256 <- function(x) grepl("^[0-9a-f]{64}$", x)
is_dataset_id <- function(x) grepl("^[a-z][a-z0-9_]*$", x)
is_release_id <- function(x) grepl("^[a-z0-9][a-z0-9_-]*$", x)
is_file <- function(x) identical(basename(x), x) &&
  nzchar(tools::file_ext(x))
is_date <- function(x) {
  parsed <- suppressWarnings(as.Date(x, format = "%Y-%m-%d"))
  !is.na(parsed) && identical(format(parsed, "%Y-%m-%d"), x)
}
is_timestamp <- function(x) {
  shape <- grepl(
    "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(Z|[+-][0-9]{2}:[0-9]{2})$",
    x
  )
  compact <- sub("Z$", "+0000", x)
  compact <- sub("([+-][0-9]{2}):([0-9]{2})$", "\\1\\2", compact)
  parsed <- suppressWarnings(strptime(compact, "%Y-%m-%dT%H:%M:%S%z"))
  shape && !is.na(parsed)
}
```

Require `n_rows >= 0L`, `n_cols >= 1L`, `revision >= 1L`, and
`sequence >= 1L`. Require sequences to appear in strictly increasing order.
After all datasets are parsed, reject duplicated `file` values across the
flattened release collection and validate every `replacement_release_id`
against the release IDs in its logical dataset.

- [ ] **Step 5: Implement release lookup and byte verification**

```r
.catalog_release <- function(catalog, dataset_id, release_id) {
  dataset <- catalog$datasets[[dataset_id]]
  if (is.null(dataset)) {
    .catalog_abort(paste0("unknown dataset_id '", dataset_id, "'"))
  }
  hit <- vapply(dataset$releases, function(x) {
    identical(x$release_id, release_id)
  }, logical(1))
  if (sum(hit) != 1L) {
    .catalog_abort(paste0("unknown release_id '", release_id,
                          "' for '", dataset_id, "'"))
  }
  dataset$releases[[which(hit)]]
}

.verify_catalog_file <- function(release, data_dir) {
  path <- .catalog_file(release, data_dir)
  actual <- if (file.exists(path)) {
    digest::digest(path, algo = "sha256", file = TRUE)
  } else {
    NA_character_
  }
  if (is.na(actual) || !identical(actual, release$sha256)) {
    msg <- if (is.na(actual)) {
      paste0("published release is missing: ", path)
    } else {
      paste0("published release changed in place: ", release$file,
             "\n  expected: ", release$sha256,
             "\n  actual:   ", actual)
    }
    stop(structure(
      list(message = msg, call = NULL, release = release),
      class = c("hvtiRutilities_release_integrity", "error", "condition")
    ))
  }
  path
}
```

- [ ] **Step 6: Run focused tests and commit**

Run:

```bash
Rscript -e 'devtools::test(filter = "dataset_catalog")'
```

Expected: PASS.

Commit:

```bash
git add R/dataset_catalog.R tests/testthat/helper-release.R \
  tests/testthat/fixtures/dataset-catalog-v1.yml \
  tests/testthat/test-dataset_catalog.R
git commit -m "feat: validate dataset release catalogs"
```

### Task 2: Attach published releases to study contracts

**Files:**
- Modify: `R/study_config.R`
- Modify: `R/study_data.R`
- Modify: `R/register_data.R`
- Modify: `tests/testthat/helper-release.R`
- Modify: `tests/testthat/test-study_config.R`
- Modify: `tests/testthat/test-register_data.R`

**Interfaces:**
- Consumes: Task 1 catalog helpers.
- Changes: `.study_dataset(cfg, dataset)` returns a `release` member.
- Changes: `register_data(..., catalog_dataset = NULL, release_id = NULL)`;
  both new arguments are appended after `extract_date`.
- Produces: release blocks with exactly `dataset_id` and `release_id` required;
  additive fields remain preserved for forward compatibility.
- Produces test helper:
  `make_release_aware_study(dir, pinned_sequence = 1L, named = FALSE)`.

- [ ] **Step 1: Write failing study-contract tests**

```r
test_that("study_config preserves a valid default release block", {
  root <- make_study_fixture(withr::local_tempdir())
  raw <- yaml::read_yaml(file.path(root, "_study.yml"))
  raw$release <- list(
    dataset_id = "surgery_cohort",
    release_id = "surgery_cohort-20260920-r1"
  )
  yaml::write_yaml(raw, file.path(root, "_study.yml"))

  cfg <- study_config(root)
  expect_identical(cfg$release, raw$release)
  expect_identical(.study_dataset(cfg)$release, raw$release)
})

test_that("study_config rejects incomplete named release metadata", {
  root <- make_registered_study(withr::local_tempdir())
  raw <- yaml::read_yaml(file.path(root, "_study.yml"))
  raw$additional_datasets$complete_cases$release <- list(
    dataset_id = "complete_cases"
  )
  yaml::write_yaml(raw, file.path(root, "_study.yml"))

  expect_error(study_config(root), "release_id")
})
```

Also test a non-list release block, empty values, invalid dataset IDs, release
IDs containing `/`, and a legacy study with no release block.

- [ ] **Step 2: Write failing catalog-backed registration tests**

```r
test_that("register_data attaches a verified published release", {
  root <- registration_study()
  fx <- write_release_fixture(root)

  register_data(
    root,
    "cohort_20260920.csv",
    "dead",
    "iv_dead",
    catalog_dataset = "surgery_cohort",
    release_id = "surgery_cohort-20260920-r1"
  )

  cfg <- study_config(root)
  expect_identical(cfg$release, list(
    dataset_id = "surgery_cohort",
    release_id = "surgery_cohort-20260920-r1"
  ))
  manifest <- yaml::read_yaml(file.path(root, "manifest.yaml"))
  expect_identical(manifest$datasets[[1L]]$sha256,
                   fx$catalog$datasets$surgery_cohort$releases[[1L]]$sha256)
})

test_that("release registration refuses a filename mismatch without writes", {
  root <- registration_study()
  write_release_fixture(root)
  before <- readLines(file.path(root, "_study.yml"))

  expect_error(
    register_data(
      root,
      "cohort_20260921.csv",
      "dead",
      "iv_dead",
      catalog_dataset = "surgery_cohort",
      release_id = "surgery_cohort-20260920-r1"
    ),
    "does not name"
  )
  expect_identical(readLines(file.path(root, "_study.yml")), before)
  expect_false(file.exists(file.path(root, "manifest.yaml")))
})
```

Add cases requiring `catalog_dataset` and `release_id` together, rejecting a
withdrawn release, rejecting catalog/file checksum disagreement, and rejecting
caller-supplied `extract_date` or `source` when it disagrees with catalog
metadata. Matching explicit values remain legal.

Add a migration test for a legacy registered study. Register
`cohort_20260920.csv` without release metadata, then call `register_data()`
again with the same `built`, event/time columns, `catalog_dataset`, and
`release_id`. Assert that the release block is attached, the existing
population is preserved, and the manifest still contains exactly one entry
for that file. Calling again after the release block exists must retain the
current `"already registered"` error.

- [ ] **Step 3: Run tests to verify failure**

Run:

```bash
Rscript -e 'devtools::test(filter = "study_config|register_data")'
```

Expected: FAIL because release blocks and registration arguments are not
validated or written.

- [ ] **Step 4: Validate release blocks and project them through `.study_dataset()`**

Add `.study_validate_release(value, found, dataset)` in `study_config.R`.
Return `NULL` unchanged. Otherwise require a list containing non-empty scalar
`dataset_id` and `release_id`, validate them with the Task 1 identifier rules,
and return the original list so future additive keys survive.

Call it for `raw$release` and for every
`raw$additional_datasets[[name]]$release`. Extend the default projection in
`study_data.R`:

```r
return(list(
  dataset = dataset,
  built = cfg$built,
  population = cfg$population,
  cohort = cfg$cohort,
  release = cfg$release
))
```

- [ ] **Step 5: Verify catalog metadata before registration writes**

Append `catalog_dataset = NULL, release_id = NULL` to `register_data()`.
After resolving `path` and before reading registration data:

```r
release <- NULL
if (xor(is.null(catalog_dataset), is.null(release_id))) {
  stop("register_data(): catalog_dataset and release_id must be supplied together",
       call. = FALSE)
}
if (!is.null(release_id)) {
  catalog <- .read_dataset_catalog(.catalog_path(cfg))
  release <- .catalog_release(catalog, catalog_dataset, release_id)
  if (!identical(release$status, "published")) {
    stop("register_data(): release is withdrawn: ", release_id,
         call. = FALSE)
  }
  if (!identical(release$file, built)) {
    stop("register_data(): release ", release_id, " does not name ", built,
         call. = FALSE)
  }
  .verify_catalog_file(release, study_dir("datasets", cfg$root))
}
```

After reading `data`, require catalog `n_rows` and `n_cols` to equal observed
dimensions. Use catalog `extract_date` and `source` for
`.registration_manifest_entry()`. If matching explicit values were supplied,
accept them; if they differ, stop before preparing either study file.

Write `release = list(dataset_id = catalog_dataset, release_id = release_id)`
into the default or named dataset contract only when release metadata was
supplied.

Treat one duplicate case as migration rather than a new registration: release
metadata is supplied, the selected study dataset already exists, its `built`
equals the requested filename, and it has no `release` block. In that case,
recompute and validate the cohort, preserve the existing population when the
caller leaves `population = NULL`, attach the release block, and replace the
single existing manifest entry in place. Every other duplicate retains the
existing refusal. Require exactly one matching manifest entry during
migration; zero or multiple matches stop before either authoritative file is
prepared.

Extend `helper-release.R` with `make_release_aware_study()`. It calls
`study_setup()`, calls `write_release_fixture()`, and registers the release at
`pinned_sequence` through the new catalog arguments. With `named = TRUE`,
first register a legacy default fixture, then register the catalog release as
`dataset = "named_data", role = "named"`. Return the fixture list with the
registered logical dataset name added as `study_dataset`.

- [ ] **Step 6: Run focused tests and commit**

Run:

```bash
Rscript -e 'devtools::test(filter = "study_config|register_data|study_data")'
```

Expected: PASS.

Commit:

```bash
git add R/study_config.R R/study_data.R R/register_data.R \
  tests/testthat/helper-release.R \
  tests/testthat/test-study_config.R tests/testthat/test-register_data.R
git commit -m "feat: register published dataset releases"
```

### Task 3: Discover newer releases without selecting them

**Files:**
- Create: `R/data_updates.R`
- Modify: `tests/testthat/helper-release.R`
- Create: `tests/testthat/test-data_updates.R`

**Interfaces:**
- Consumes: Task 1 catalog helpers and Task 2 release-aware contracts.
- Produces:
  `check_data_updates(cfg = study_config(), dataset = NULL) -> data.frame`
  with class `data_update_report`.
- Report columns, in order: `dataset`, `scope`, `pinned_release_id`,
  `candidate_release_id`, `sequence`, `file`, `status`, `is_latest`, `detail`.
- Status values: `CURRENT`, `UPDATE AVAILABLE`, `UPDATE STATUS UNKNOWN`,
  `WITHDRAWN`, and `FAIL`.
- Scope values: `pinned`, `candidate`, and `catalog`.
- Produces test helper:
  `append_release_fixture(fx, release_id, sequence, file, extract_date,
  revision)`.

- [ ] **Step 1: Write failing current and update-available tests**

```r
test_that("check_data_updates reports current and every later release", {
  fx <- make_release_aware_study(withr::local_tempdir(),
                                 pinned_sequence = 1L)

  report <- check_data_updates(study_config(fx$root))

  expect_s3_class(report, "data_update_report")
  expect_named(report, c(
    "dataset", "scope", "pinned_release_id", "candidate_release_id",
    "sequence", "file", "status", "is_latest", "detail"
  ))
  expect_identical(report$status,
                   c("CURRENT", "UPDATE AVAILABLE"))
  expect_identical(report$candidate_release_id[[2L]],
                   "surgery_cohort-20260921-r1")
  expect_true(report$is_latest[[2L]])
})

test_that("same-day candidates follow sequence rather than filename order", {
  fx <- make_release_aware_study(withr::local_tempdir(),
                                 pinned_sequence = 1L)
  append_release_fixture(
    fx,
    release_id = "surgery_cohort-20260921-r2",
    sequence = 3L,
    file = "aaa_20260921_r2.csv",
    extract_date = "2026-09-21",
    revision = 2L
  )

  available <- check_data_updates(study_config(fx$root))
  available <- available[available$scope == "candidate", ]

  expect_identical(available$sequence, c(2L, 3L))
  expect_identical(available$is_latest, c(FALSE, TRUE))
})
```

Add tests for `dataset = "named_data"`, `dataset = NULL` covering default and
named datasets, a legacy dataset producing no row, an unknown requested study
dataset, a missing catalog producing one `UPDATE STATUS UNKNOWN` row, malformed
catalog producing `FAIL`, withdrawn pinned release producing `WITHDRAWN`, and
a missing/checksum-invalid candidate producing candidate-scope `FAIL` while
the pinned row remains `CURRENT`.

Implement `append_release_fixture()` in `helper-release.R` by writing a
synthetic CSV with `sequence + 2L` rows, calculating its checksum, appending a
complete published record, and rewriting the catalog. Set `published_at` to
noon Eastern on `extract_date`; set `n_rows` and `n_cols` from the frame.

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
Rscript -e 'devtools::test(filter = "data_updates")'
```

Expected: FAIL because `check_data_updates()` does not exist.

- [ ] **Step 3: Implement report rows and pinned verification**

Use one constructor so empty and populated reports have stable types:

```r
.update_row <- function(dataset, scope, pinned_release_id,
                        candidate_release_id = NA_character_,
                        sequence = NA_integer_, file = NA_character_,
                        status, is_latest = FALSE, detail) {
  data.frame(
    dataset = dataset,
    scope = scope,
    pinned_release_id = pinned_release_id,
    candidate_release_id = candidate_release_id,
    sequence = as.integer(sequence),
    file = file,
    status = status,
    is_latest = is_latest,
    detail = detail,
    stringsAsFactors = FALSE
  )
}
```

For each release-aware study dataset, read the catalog and resolve its pinned
release. Require all three identities to agree before reporting `CURRENT`:

- `_study.yml` `built` equals catalog `file`;
- `manifest.yaml` has exactly one entry for `built` and its SHA-256 equals the
  catalog SHA-256; and
- `.verify_catalog_file()` confirms the bytes.

Catch those checks into a pinned-scope `FAIL` row. Do not let a later candidate
hide a broken pin.

- [ ] **Step 4: Implement candidate enumeration and failure isolation**

Select records with `sequence > pinned$sequence` in catalog order. Exclude
withdrawn records. Verify each candidate independently. A valid candidate gets
`UPDATE AVAILABLE`; a missing or changed one gets candidate-scope `FAIL`.
Set `is_latest = TRUE` only on the greatest valid sequence. If no later
published release exists, the pinned `CURRENT` row is the complete report.

A missing catalog is catalog-scope `UPDATE STATUS UNKNOWN`. A catalog that
exists but fails schema validation is catalog-scope `FAIL`. Wrap the combined
rows with:

```r
class(report) <- c("data_update_report", "data.frame")
report
```

- [ ] **Step 5: Run focused tests and commit**

Run:

```bash
Rscript -e 'devtools::test(filter = "dataset_catalog|data_updates")'
```

Expected: PASS.

Commit:

```bash
git add R/data_updates.R tests/testthat/helper-release.R \
  tests/testthat/test-data_updates.R
git commit -m "feat: discover published dataset updates"
```

### Task 4: Surface updates without changing pinned reads

**Files:**
- Modify: `R/data_updates.R`
- Modify: `R/study_data.R`
- Modify: `R/study_status.R`
- Modify: `tests/testthat/helper-release.R`
- Modify: `tests/testthat/test-data_updates.R`
- Modify: `tests/testthat/test-study_status.R`
- Modify: `tests/testthat/test-parquet_cache.R`

**Interfaces:**
- Changes:
  `read_built(cfg = study_config(), refresh = FALSE, dataset = "study",
  allow_withdrawn = FALSE)`.
- Produces message classes `hvtiRutilities_update_available` and
  `hvtiRutilities_update_status_unknown`.
- Produces error classes `hvtiRutilities_release_integrity` and
  `hvtiRutilities_withdrawn_release`.
- Adds `update:<dataset>` rows only for release-aware study datasets.
- Produces test helper:
  `withdraw_fixture_release(fx, release_id, reason,
  replacement_release_id = NULL)`.

- [ ] **Step 1: Write failing read-condition tests**

```r
test_that("read_built reports an update once and still reads the pin", {
  fx <- make_release_aware_study(withr::local_tempdir(),
                                 pinned_sequence = 1L)
  cfg <- study_config(fx$root)

  expect_message(
    first <- read_built(cfg),
    "surgery_cohort-20260921-r1",
    class = "hvtiRutilities_update_available"
  )
  expect_silent(second <- read_built(cfg))
  expect_identical(first, second)
  expect_equal(nrow(first), 3L)
})

test_that("a missing catalog does not block a valid pinned read", {
  fx <- make_release_aware_study(withr::local_tempdir(),
                                 pinned_sequence = 1L)
  unlink(fx$catalog_path)

  expect_message(
    d <- read_built(study_config(fx$root)),
    "status unknown",
    class = "hvtiRutilities_update_status_unknown"
  )
  expect_equal(nrow(d), 3L)
})

test_that("a bad candidate does not block a valid pinned read", {
  fx <- make_release_aware_study(withr::local_tempdir(),
                                 pinned_sequence = 1L)
  writeLines("changed", file.path(fx$data_dir, "cohort_20260921.csv"))

  expect_message(
    d <- read_built(study_config(fx$root)),
    "candidate",
    class = "hvtiRutilities_update_status_unknown"
  )
  expect_equal(nrow(d), 3L)
})
```

Reset the package notice environment in each test with a dedicated internal
`.reset_update_notices()` helper. Add a test proving a newly published release
in the same R session emits a new message because the notice key includes the
candidate release ID.

Implement `withdraw_fixture_release()` in `helper-release.R` by locating
exactly one release ID, setting `status = "withdrawn"`, adding
`withdrawal_reason`, adding `replacement_release_id` only when supplied, and
rewriting the catalog.

- [ ] **Step 2: Write the cache-regression and withdrawal tests**

```r
test_that("a changed published pin fails before cache refresh rewrites its manifest", {
  fx <- make_release_aware_study(withr::local_tempdir(),
                                 pinned_sequence = 1L)
  cfg <- study_config(fx$root)
  suppressMessages(read_built(cfg))
  manifest_path <- file.path(fx$root, "manifest.yaml")
  before <- readLines(manifest_path)
  write.csv(data.frame(id = 1L, dead = 1L, iv_dead = 1L),
            built_path(cfg), row.names = FALSE)

  expect_error(read_built(cfg),
               class = "hvtiRutilities_release_integrity")
  expect_identical(readLines(manifest_path), before)
})

test_that("withdrawn pins require an explicit historical override", {
  fx <- make_release_aware_study(withr::local_tempdir(),
                                 pinned_sequence = 1L)
  withdraw_fixture_release(fx, "surgery_cohort-20260920-r1",
                           reason = "Incorrect inclusion rule")
  cfg <- study_config(fx$root)

  expect_error(read_built(cfg), "Incorrect inclusion rule",
               class = "hvtiRutilities_withdrawn_release")
  expect_equal(nrow(suppressMessages(
    read_built(cfg, allow_withdrawn = TRUE)
  )), 3L)
})
```

- [ ] **Step 3: Run tests to verify failure**

Run:

```bash
Rscript -e 'devtools::test(filter = "data_updates|study_status|parquet_cache")'
```

Expected: FAIL because read notices, withdrawal handling, and update status
rows do not exist.

- [ ] **Step 4: Implement once-per-release structured conditions**

In `data_updates.R`, add a private environment and condition emitters:

```r
.update_notices <- new.env(parent = emptyenv())

.reset_update_notices <- function() {
  rm(list = ls(.update_notices, all.names = TRUE),
     envir = .update_notices)
  invisible(TRUE)
}

.update_message <- function(class, message, report, key) {
  if (exists(key, envir = .update_notices, inherits = FALSE)) {
    return(invisible(FALSE))
  }
  assign(key, TRUE, envir = .update_notices)
  message(structure(
    list(message = message, call = NULL, report = report),
    class = c(class, "message", "condition")
  ))
  invisible(TRUE)
}
```

Build the notice key from normalized study root, logical study dataset, status,
and candidate release ID. This suppresses a repeated notice but permits a new
catalog release to announce itself later in the same session.

- [ ] **Step 5: Guard and notify `read_built()` before `.cache_read()`**

Append `allow_withdrawn = FALSE` to the signature and validate it as one
non-missing logical. For a release-aware contract, call
`check_data_updates(cfg, dataset)` before `.cache_read()`:

- stop on pinned-scope `FAIL` with class
  `hvtiRutilities_release_integrity`;
- stop on `WITHDRAWN` with class
  `hvtiRutilities_withdrawn_release`, unless `allow_withdrawn` is true;
- emit `hvtiRutilities_update_available` for the newest valid candidate; and
- emit `hvtiRutilities_update_status_unknown` for catalog/candidate failures
  or an unavailable catalog, then continue with the pin.

Do not run discovery for a legacy contract. Keep the actual dataset read and
all normalization logic unchanged after the new pre-read guard.

- [ ] **Step 6: Add update rows and print markers to `study_status()`**

For each release-aware dataset, collapse its report to one row named
`update:study` or `update:<name>` using this priority:

1. pinned `FAIL` or `WITHDRAWN` -> `FAIL`;
2. any valid candidate -> `UPDATE AVAILABLE`;
3. catalog/candidate `FAIL` or unknown -> `UPDATE STATUS UNKNOWN`;
4. otherwise -> `CURRENT`.

Add print marks without changing existing marks:

```r
mark <- c(
  OK = "[x]", MISSING = "[ ]", FAIL = "[!]",
  CURRENT = "[x]", `UPDATE AVAILABLE` = "[~]",
  `UPDATE STATUS UNKNOWN` = "[?]"
)
```

Legacy studies retain the existing six base rows. Release-aware rows appear
after their dataset/cohort rows and before provenance.

- [ ] **Step 7: Run focused tests and commit**

Run:

```bash
Rscript -e 'devtools::test(filter = "data_updates|study_status|parquet_cache")'
```

Expected: PASS, including the assertion that a changed published pin leaves
`manifest.yaml` byte-identical.

Commit:

```bash
git add R/data_updates.R R/study_data.R R/study_status.R \
  tests/testthat/helper-release.R \
  tests/testthat/test-data_updates.R tests/testthat/test-study_status.R \
  tests/testthat/test-parquet_cache.R
git commit -m "feat: report available dataset releases"
```

### Task 5: Review an explicit candidate

**Files:**
- Modify: `R/data_updates.R`
- Modify: `tests/testthat/test-data_updates.R`

**Interfaces:**
- Produces:
  `review_data_update(cfg = study_config(), dataset = "study", release_id)`.
- Produces an object of class `data_update_review` containing `dataset`,
  `pinned`, `candidate`, `comparison`, `cohort_old`, and `cohort_new`.
- Produces: `print.data_update_review(x, ...)`.

- [ ] **Step 1: Write failing review tests**

```r
test_that("review_data_update compares an explicit valid candidate", {
  fx <- make_release_aware_study(withr::local_tempdir(),
                                 pinned_sequence = 1L)

  review <- review_data_update(
    study_config(fx$root),
    release_id = "surgery_cohort-20260921-r1"
  )

  expect_s3_class(review, "data_update_review")
  expect_identical(review$pinned$release_id,
                   "surgery_cohort-20260920-r1")
  expect_identical(review$candidate$release_id,
                   "surgery_cohort-20260921-r1")
  expect_s3_class(review$comparison, "dataset_comparison")
  expect_identical(review$cohort_old$n, 3L)
  expect_identical(review$cohort_new$n, 4L)
  expect_output(print(review), "Rows: 3 -> 4", fixed = TRUE)
})

test_that("review requires a real newer release ID", {
  fx <- make_release_aware_study(withr::local_tempdir(),
                                 pinned_sequence = 1L)
  cfg <- study_config(fx$root)

  expect_error(review_data_update(cfg, release_id = "latest"),
               "unknown release_id")
  expect_error(
    review_data_update(cfg,
                       release_id = "surgery_cohort-20260920-r1"),
    "newer"
  )
})
```

Add cases for a withdrawn candidate, a missing or changed candidate file, a
candidate with observed dimensions that disagree with its catalog record, a
named dataset without a cohort contract, and event/time columns missing from
the candidate.

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
Rscript -e 'devtools::test(filter = "data_updates")'
```

Expected: FAIL because `review_data_update()` does not exist.

- [ ] **Step 3: Implement review validation and comparison**

Resolve the study contract, catalog dataset, pinned release, and exact
candidate. Reject candidate `sequence <= pinned$sequence` and any status other
than `published`. Verify both files with `.verify_catalog_file()` and read them
with `.read_registration_data()` so review creates no parquet, sidecar, or
manifest writes.

Require `nrow()` and `ncol()` of each frame to equal its catalog record. Build
the result exactly as follows:

```r
out <- list(
  dataset = dataset,
  pinned = pinned,
  candidate = candidate,
  comparison = compare_datasets(old, new),
  cohort_old = if (is.null(contract$cohort)) NULL else
    cohort_counts(old, cfg, dataset),
  cohort_new = if (is.null(contract$cohort)) NULL else
    cohort_counts(new, cfg, dataset)
)
class(out) <- "data_update_review"
out
```

The print method names both releases, calls `print(x$comparison)`, and prints
cohort changes as `N`, `events`, and `censored` when present. Return `x`
invisibly.

- [ ] **Step 4: Run focused tests and commit**

Run:

```bash
Rscript -e 'devtools::test(filter = "compare_datasets|data_updates")'
```

Expected: PASS.

Commit:

```bash
git add R/data_updates.R tests/testthat/test-data_updates.R
git commit -m "feat: review dataset release updates"
```

### Task 6: Adopt a reviewed release atomically

**Files:**
- Modify: `R/data_updates.R`
- Modify: `tests/testthat/test-data_updates.R`

**Interfaces:**
- Produces:
  `adopt_data_update(cfg = study_config(), dataset = "study", release_id)`.
- Consumes: `review_data_update()`, `.registration_manifest_entry()`, and
  `.replace_study_pair()`.
- Returns: updated `study_status()` visibly.

- [ ] **Step 1: Write failing default and named adoption tests**

```r
test_that("adoption advances the default contract and replaces its manifest entry", {
  fx <- make_release_aware_study(withr::local_tempdir(),
                                 pinned_sequence = 1L)

  status <- adopt_data_update(
    study_config(fx$root),
    release_id = "surgery_cohort-20260921-r1"
  )

  expect_s3_class(status, "study_status")
  cfg <- study_config(fx$root)
  expect_identical(cfg$built, "cohort_20260921.csv")
  expect_identical(cfg$release$release_id,
                   "surgery_cohort-20260921-r1")
  expect_identical(cfg$cohort$n, 4L)
  manifest <- yaml::read_yaml(file.path(fx$root, "manifest.yaml"))
  files <- vapply(manifest$datasets, function(x) x$file, character(1))
  expect_false("cohort_20260920.csv" %in% files)
  expect_true("cohort_20260921.csv" %in% files)
  expect_true(file.exists(file.path(fx$data_dir,
                                    "cohort_20260920.csv")))
})
```

Repeat for a named cohort and assert the default `built`, `cohort`, and
`release` blocks remain byte-for-byte equivalent after YAML parsing.

- [ ] **Step 2: Write stale-review and rollback tests**

```r
test_that("adoption revalidates bytes changed after review", {
  fx <- make_release_aware_study(withr::local_tempdir(),
                                 pinned_sequence = 1L)
  cfg <- study_config(fx$root)
  review_data_update(cfg,
                     release_id = "surgery_cohort-20260921-r1")
  before <- study_manifest_bytes(fx$root)
  writeLines("changed after review",
             file.path(fx$data_dir, "cohort_20260921.csv"))

  expect_error(
    adopt_data_update(cfg,
                      release_id = "surgery_cohort-20260921-r1"),
    class = "hvtiRutilities_release_integrity"
  )
  expect_identical(study_manifest_bytes(fx$root), before)
})
```

Add a rename-failure test by mocking `.registration_rename()` at the second
prepared-file move, then assert both authoritative files equal their original
raw bytes. Add tests for no matching old manifest entry, more than one matching
old entry, a candidate stem collision with another active entry, withdrawn
candidate, and candidate `sequence <= pinned$sequence`.

- [ ] **Step 3: Run tests to verify failure**

Run:

```bash
Rscript -e 'devtools::test(filter = "data_updates")'
```

Expected: FAIL because `adopt_data_update()` does not exist.

- [ ] **Step 4: Prepare both replacement documents without writing**

Call `review_data_update()` inside adoption. After it returns, call
`study_config(cfg$root)` again and require its selected dataset still to name
the pinned release that was reviewed. Re-read `_study.yml` and
`manifest.yaml` only after that check so the prepared documents start from
current disk state.

Verify the candidate checksum again, read it with `.read_registration_data()`,
then verify the checksum a second time. The two hashes bracket the read so a
file changed while it was being loaded cannot be adopted. Recheck observed
dimensions against the catalog and derive cohort counts from this newly read
frame.

For the selected default or named contract, set `built`, `cohort`, and:

```r
release = list(
  dataset_id = contract$release$dataset_id,
  release_id = review$candidate$release_id
)
```

Find the old manifest entry by exact `file == contract$built` and require
exactly one match. Build the new entry with
`.registration_manifest_entry()`, using candidate `extract_date` and `source`.
Require the entry's checksum and dimensions to equal the candidate catalog
record. Replace the old entry in its existing list position. Before writing,
reject a derived stem collision with every other active manifest entry.

- [ ] **Step 5: Replace the pair and return status**

Use the same preparation and cleanup discipline as `register_data()`:

```r
targets <- c(cfg$file, file.path(cfg$root, "manifest.yaml"))
prepared <- c(
  tempfile(pattern = "._study-", tmpdir = cfg$root),
  tempfile(pattern = ".manifest-", tmpdir = cfg$root)
)
on.exit(unlink(prepared[file.exists(prepared)]), add = TRUE)
yaml::write_yaml(raw, prepared[[1L]])
yaml::write_yaml(manifest, prepared[[2L]])
.replace_study_pair(prepared, targets)
study_status(cfg$root)
```

Do not delete the old dataset or any old derived cache files. Do not run Git
commands from the R function.

- [ ] **Step 6: Run focused tests and commit**

Run:

```bash
Rscript -e 'devtools::test(filter = "data_updates|register_data|study_status")'
```

Expected: PASS.

Commit:

```bash
git add R/data_updates.R tests/testthat/test-data_updates.R
git commit -m "feat: adopt dataset releases atomically"
```

### Task 7: Document the release workflow and run every gate

**Files:**
- Modify: `R/data_updates.R`
- Modify: `R/register_data.R`
- Modify: `R/study_data.R`
- Modify: `R/study_status.R`
- Modify: `vignettes/dataset-versioning.qmd`
- Modify: `NEWS.md`
- Modify: `_pkgdown.yml`
- Generate: `man/check_data_updates.Rd`
- Generate: `man/review_data_update.Rd`
- Generate: `man/adopt_data_update.Rd`
- Generate: affected existing `man/*.Rd`, `NAMESPACE`, and `DESCRIPTION`

**Interfaces:**
- Exports: `check_data_updates`, `review_data_update`, and
  `adopt_data_update`.
- Registers: `print.data_update_review` as an S3 method.

- [ ] **Step 1: Write final roxygen using Rd markup**

Document exact arguments, report columns, condition classes, withdrawal
override, and the fact that adoption never accepts `"latest"`. Use
`\code{}`, `\link{}`, `\describe{}`, and `\itemize{}`; do not use markdown
backticks or markdown links inside roxygen.

Examples must build only temporary CSV fixtures. Put the complete
publish-catalog example inside `\dontrun{}` if it would otherwise duplicate
the fixture helper in user documentation.

- [ ] **Step 2: Replace the unsafe vignette guidance**

Remove the section that tells users to call `update_manifest()` after a file
is legitimately changed in place. Replace it with this lifecycle:

1. build and validate a mutable draft;
2. publish an immutable dated release through `hvtiRdatabuild`;
3. let `study_status()` or `read_built()` report the candidate;
4. call `review_data_update()` with its exact release ID; and
5. call `adopt_data_update()` with that same exact ID after review.

Keep a separate warning that an already overwritten legacy file cannot be
reconstructed from its checksum. Explain same-day `_r2` releases, withdrawn
releases, `allow_withdrawn = TRUE` for deliberate historical reproduction,
and why update availability does not stop revision work.

- [ ] **Step 3: Add NEWS and pkgdown entries**

Add one `NEWS.md` bullet under the unreleased heading covering the three new
functions and the changed `read_built()`/`study_status()` behavior. State that
legacy studies remain unchanged and that published in-place mutations now
stop before cache refresh.

Add the three exports to `_pkgdown.yml` under **Study Manifest and Data
Contract**, after `read_built` and before cohort functions.

- [ ] **Step 4: Generate documentation and verify generated files are current**

Run:

```bash
Rscript -e 'devtools::document()'
git diff --check
```

Expected: roxygen completes; generated changes are present; `git diff --check`
prints nothing.

- [ ] **Step 5: Install before trusting lint, then run lint**

Run:

```bash
R CMD INSTALL --no-docs .
Rscript -e 'print(lintr::lint_package())'
```

Expected: installation succeeds and lint returns no findings. Installing first
prevents `object_usage_linter` from reporting new cross-file helpers as missing.

- [ ] **Step 6: Run focused and full package tests**

Run:

```bash
Rscript -e 'devtools::test(filter = "dataset_catalog|data_updates|register_data|study_config|study_status|parquet_cache")'
Rscript -e 'devtools::test()'
```

Expected: all focused tests and all package tests pass with zero failures.

- [ ] **Step 7: Run the package check and manual-sensitive documentation gate**

Run:

```bash
Rscript -e 'devtools::check(error_on = "never")'
```

Expected: 0 errors, 0 warnings, 0 notes. Inspect the completed output rather
than relying on process exit alone.

- [ ] **Step 8: Commit the shipped documentation and generated files**

```bash
git add R/data_updates.R R/register_data.R R/study_data.R R/study_status.R \
  vignettes/dataset-versioning.qmd NEWS.md _pkgdown.yml man NAMESPACE \
  DESCRIPTION
git commit -m "docs: explain dataset release adoption"
```

- [ ] **Step 9: Review the complete branch diff**

Run:

```bash
git status --short
git diff main...HEAD --check
git diff --stat main...HEAD
```

Expected: the worktree is clean, the diff check prints nothing, and every
changed file belongs to the catalog-consumer feature. The branch is then ready
for the repository's review and pull-request workflow.
