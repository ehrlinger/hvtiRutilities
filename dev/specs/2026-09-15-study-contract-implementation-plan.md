# Study Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add numbered study setup, identity-only manifests, and registration
of a default or named dataset to `hvtiRutilities`.

**Architecture:** One internal layout resolver maps logical taxonomy folders
to numbered or legacy names. `study_setup()` creates identity and structure;
`register_data()` validates data and commits `_study.yml` and `manifest.yaml`
as one recoverable transaction. Existing readers select a dataset through one
internal config projection.

**Tech stack:** R 4.1+, testthat edition 3, yaml, digest, haven, devtools.

**Spec:** `dev/specs/2026-09-15-study-setup-legacy-adoption-design.md`

## Global constraints

- Work on a `codex/` branch and never push `main`.
- Preserve unnumbered legacy studies; reject any root mixing numbered and bare
  taxonomy directories.
- Keep existing positional arguments working by adding `dataset = "study"`
  last.
- Derive cohort counts from data; never accept counts from a caller.
- Write no absolute study path, credential, PHI, or data into `_study.yml`.
- Use Rd markup in roxygen, keep lines at 80 characters, run documentation,
  and add every export to `_pkgdown.yml`.
- Add an unreleased NEWS entry; do not bump `Version:`.

---

### Task 1: Resolve numbered and legacy study directories

**Files:**
- Create: `R/study_layout.R`
- Create: `tests/testthat/test-study_layout.R`
- Modify: `R/study_data.R`
- Modify: `R/study_status.R`
- Modify: `_pkgdown.yml`

**Interfaces:**
- Produces: `study_dir(folder, root = study_root()) -> character(1)`.
- Produces: internal `.study_layout(root) -> "numbered" | "legacy"`.

- [ ] **Step 1: Write failing layout tests**

```r
test_that("study_dir resolves numbered and legacy layouts", {
  numbered <- withr::local_tempdir()
  dir.create(file.path(numbered, "00_datasets"))
  expect_equal(study_dir("datasets", numbered),
               file.path(numbered, "00_datasets"))

  legacy <- withr::local_tempdir()
  dir.create(file.path(legacy, "datasets"))
  expect_equal(study_dir("datasets", legacy),
               file.path(legacy, "datasets"))
})

test_that("study_dir refuses a mixed root", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "datasets"))
  dir.create(file.path(root, "30_analyses"))
  expect_error(study_dir("datasets", root), "mixed")
})
```

- [ ] **Step 2: Confirm the tests fail**

Run: `Rscript -e 'devtools::test(filter = "study_layout")'`

Expected: FAIL because `study_dir()` does not exist.

- [ ] **Step 3: Implement the fixed mapping and resolver**

```r
.study_folders <- function() {
  c(datasets = "00_datasets", descriptive = "10_descriptive",
    distributions = "20_distributions", analyses = "30_analyses",
    graphs = "40_graphs", documents = "50_documents",
    estimates = "90_estimates")
}

.study_layout <- function(root) {
  map <- .study_folders()
  numbered <- any(dir.exists(file.path(root, unname(map))))
  legacy <- any(dir.exists(file.path(root, names(map))))
  if (numbered && legacy) stop("study layout is mixed", call. = FALSE)
  if (numbered) "numbered" else "legacy"
}

study_dir <- function(folder, root = study_root()) {
  map <- .study_folders()
  if (!folder %in% names(map)) stop("unknown study folder: ", folder,
                                    call. = FALSE)
  leaf <- if (.study_layout(root) == "numbered") map[[folder]] else folder
  file.path(root, leaf)
}
```

- [ ] **Step 4: Route data and manifest status paths through `study_dir()`**

Replace literal `file.path(cfg$root, "datasets", ...)` and status data-dir
construction with `study_dir("datasets", cfg$root)`.

- [ ] **Step 5: Run focused tests and commit**

Run: `Rscript -e 'devtools::test(filter = "study_(layout|data|status)")'`

Expected: PASS.

Commit: `feat: resolve numbered study directories`

### Task 2: Create identity-only studies

**Files:**
- Create: `R/study_setup.R`
- Create: `tests/testthat/test-study_setup.R`
- Modify: `R/study_config.R`
- Modify: `tests/testthat/test-study_config.R`
- Modify: `tests/testthat/helper-study.R`

**Interfaces:**
- Produces: `study_setup(root, study, study_tracker_id, umbrella = NULL,
  owner = NULL, irb_number = NULL, cvir_no = NULL,
  study_creation_date = NULL, adopt = FALSE)`.
- Changes: `study_config(start, require_data = TRUE)`.

- [ ] **Step 1: Test new, identity-only, adoption, and conflict states**

```r
test_that("study_setup creates numbered identity state", {
  root <- file.path(withr::local_tempdir(), "study")
  study_setup(root, "Example", 42L, owner = "Analyst")
  expect_true(all(dir.exists(file.path(root, unname(.study_folders())))))
  cfg <- study_config(root, require_data = FALSE)
  expect_equal(cfg$study_tracker_id, 42L)
  expect_null(cfg$built)
  expect_error(study_config(root), "register_data")
})

test_that("adoption preserves existing files and layout", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "datasets"))
  writeLines("keep", file.path(root, ".Renviron"))
  study_setup(root, "Legacy", 42L, adopt = TRUE)
  expect_identical(readLines(file.path(root, ".Renviron")), "keep")
  expect_true(dir.exists(file.path(root, "analyses")))
  expect_false(dir.exists(file.path(root, "30_analyses")))
})
```

- [ ] **Step 2: Confirm failure**

Run: `Rscript -e 'devtools::test(filter = "study_(setup|config)")'`

Expected: FAIL on the missing function and `require_data` argument.

- [ ] **Step 3: Implement setup with atomic single-file writes**

Create the root when absent. For a new or empty root use `.study_folders()`;
for adoption use `.study_layout()`. Write `_study.yml` through a tempfile in
the root followed by `file.rename()`. Create missing `.Renviron` containing
`RENV_CONFIG_CACHE_SYMLINKS=FALSE` and `.renvignore` containing both numbered
and legacy data/output directories plus `*.sas`, `*.log`, `*.lst`, `*.doc*`,
`*.pp*`, and `templates/`. Never replace an existing initialization file.

- [ ] **Step 4: Make `study_config()` validate identity separately**

Use `.study_required(require_data)` so `study` is always required and the
current built/cohort keys are required only when `require_data` is true.
Return Tracker identity fields and `additional_datasets` without dropping
unknown additive fields.

- [ ] **Step 5: Run focused tests and commit**

Run: `Rscript -e 'devtools::test(filter = "study_(setup|config|layout)")'`

Expected: PASS.

Commit: `feat: set up study identity before data`

### Task 3: Register default and named datasets transactionally

**Files:**
- Create: `R/register_data.R`
- Create: `tests/testthat/test-register_data.R`
- Modify: `R/study_config.R`

**Interfaces:**
- Produces: `register_data(root = getwd(), built, event = NULL, time = NULL,
  dataset = "study", role = c("study", "named"), population = NULL,
  source = NULL, extract_date = NULL)`.

- [ ] **Step 1: Write failing registration tests**

```r
test_that("register_data derives the default cohort", {
  root <- make_identity_fixture(withr::local_tempdir())
  write_registration_csv(root, "built.csv", n = 5L, events = 2L)
  register_data(root, "built.csv", "dead", "time")
  cfg <- study_config(root)
  expect_equal(unlist(cfg$cohort[c("n", "n_events", "n_censored")]),
               c(n = 5L, n_events = 2L, n_censored = 3L))
})

test_that("named registration preserves the default", {
  root <- make_registered_fixture(withr::local_tempdir())
  before <- study_config(root)
  write_registration_csv(root, "subset.csv", n = 3L, events = 1L)
  register_data(root, "subset.csv", "dead", "time",
                dataset = "complete_cases", role = "named")
  after <- study_config(root)
  expect_identical(after$built, before$built)
  expect_equal(after$additional_datasets$complete_cases$cohort$n, 3L)
})
```

- [ ] **Step 2: Confirm failure**

Run: `Rscript -e 'devtools::test(filter = "register_data")'`

Expected: FAIL because `register_data()` does not exist.

- [ ] **Step 3: Implement validation and prepared outputs**

Validate `role` with `match.arg()`, validate names with
`^[a-z][a-z0-9_]*$`, reserve `study`, require event/time together, and require
both for the default. Read the file once, derive counts, write candidate YAML
and manifest files to tempfiles, then replace the pair with backup-and-rollback
logic. A failed second rename restores the first original.

- [ ] **Step 4: Cover ancillary and refusal cases**

Add tests for `cohort: ~`, duplicate names, a second default, missing files,
invalid names, one-sided event/time, missing columns, and rollback. Assert the
original bytes of both manifests after every failure.

- [ ] **Step 5: Run focused tests and commit**

Run: `Rscript -e 'devtools::test(filter = "register_data|manifest")'`

Expected: PASS.

Commit: `feat: register study datasets`

### Task 4: Select named data throughout the contract

**Files:**
- Modify: `R/study_data.R`
- Modify: `R/study_cohort.R`
- Modify: `R/provenance.R`
- Modify: `R/study_status.R`
- Modify: corresponding `tests/testthat/test-*.R` files

**Interfaces:**
- Produces: internal `.study_dataset(cfg, dataset) -> list`.
- Changes: append `dataset = "study"` to `built_path()`, `built_manifest()`,
  `read_built()`, `cohort_counts()`, `assert_cohort()`, and
  `record_provenance()`.

- [ ] **Step 1: Add failing selection tests**

Assert that every helper selects `complete_cases`, default calls remain
unchanged, an unknown name lists choices, and `assert_cohort()` reports a
missing contract for an ancillary dataset.

- [ ] **Step 2: Confirm failure**

Run:

```sh
Rscript -e 'devtools::test(
  filter = "study_data|study_cohort|provenance")'
```

Expected: FAIL on unused `dataset` arguments.

- [ ] **Step 3: Implement one projection helper**

```r
.study_dataset <- function(cfg, dataset = "study") {
  if (identical(dataset, "study")) {
    return(list(built = cfg$built, population = cfg$population,
                cohort = cfg$cohort))
  }
  out <- cfg$additional_datasets[[dataset]]
  if (is.null(out)) stop("unknown dataset '", dataset, "'; registered: ",
                         paste(c("study", names(cfg$additional_datasets)),
                               collapse = ", "), call. = FALSE)
  out
}
```

Route all six public helpers through it and include `dataset` in provenance's
data record. Preserve existing argument order.

- [ ] **Step 4: Expand `study_status()` rows and run tests**

Emit `dataset:<name>` and `cohort:<name>` rows after the fixed default rows.
Named `cohort: ~` is `MISSING`; unreadable data or a mismatched gate is `FAIL`.

Run:

```sh
Rscript -e 'devtools::test(
  filter = "study_data|study_cohort|provenance|study_status")'
```

Expected: PASS.

- [ ] **Step 5: Commit**

Commit: `feat: select named study datasets`

### Task 5: Remove `study_init()` and finish package documentation

**Files:**
- Delete: `R/study_init.R`
- Delete: `tests/testthat/test-study_init.R`
- Modify: `R/study_checklist.R`, `R/study_status.R`, and stale code comments
- Modify: `NEWS.md`, `_pkgdown.yml`, `DESCRIPTION`
- Regenerate: `NAMESPACE`, `man/*.Rd`

- [ ] **Step 1: Move still-relevant initialization tests**

Move cohort derivation, extract date, manifest row-count, and failure-byte
tests into `test-register_data.R`; move identity tests into
`test-study_setup.R`. Add `expect_false("study_init" %in%
getNamespaceExports("hvtiRutilities"))`.

- [ ] **Step 2: Replace actionable messages**

Missing `_study.yml` messages must direct interactive users to
`study-setup --recover`; missing default data must direct them to
`register_data()`. No analysis helper contacts ADO or prompts.

- [ ] **Step 3: Remove source, update exports and NEWS, and document**

Add `study_setup`, `register_data`, and `study_dir` to `_pkgdown.yml`; remove
`study_init`. Add an unreleased NEWS bullet. Run:

`Rscript -e 'devtools::document()'`

Expected: `study_init.Rd` and its export disappear; new topics appear.

- [ ] **Step 4: Run the full package gates**

Run: `Rscript -e 'devtools::test()'`

Expected: 0 failures.

Run: `Rscript -e 'devtools::check(error_on = "never")'`

Expected: 0 errors, 0 warnings, 0 notes.

Run: `Rscript -e 'lintr::lint_package()'`

Expected: no new lints.

- [ ] **Step 5: Commit**

Commit: `feat: replace study initialization with setup and registration`
