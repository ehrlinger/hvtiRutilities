# Stage 1 — Provenance in `hvtiRutilities` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `hvtiRutilities` a study manifest reader and a per-job JSON provenance sidecar, so a filed result can name exactly what produced it.

**Architecture:** One new primitive, `study_config()`, walks up for `_study.yml` and returns the parsed manifest plus the study root. Every other function in this plan takes that config as an argument rather than reading hard-coded constants — the six data-contract functions currently living in `analyses/R_hazard/R/` are ported on that basis, and `record_provenance()` writes a JSON sidecar next to a rendered output. All work happens in the `hvtiRutilities` git repository; the study tree is not modified.

**Tech Stack:** R (>= 4.1.0), roxygen2 8.1.0, testthat edition 3, `yaml`, `digest`, `tools`, `haven`, and one new dependency, `jsonlite`.

## Global Constraints

- **All work is in `~/Documents/GitHub/hvtiRutilities`.** Nothing in this plan writes to `/Volumes/qhsstudies/...`. The study tree has no git and no undo; the bootstrap chunk run is live in `analyses/R_hazard/_output/`.
- **Branch first, PR at the end.** Never push to `main`. Branch name: `feat/study-config-provenance`.
- **Version is `1.0.7`.** Bump the patch digit only — three digits, never `.9000`, never roll MINOR or MAJOR. Both `DESCRIPTION` line 4 (`Version:`) and the `NEWS.md` top heading must read `1.0.7`; a test greps NEWS for the exact DESCRIPTION version.
- **`R/` holds side-effect-free code only.** Every top-level expression must be an assignment. Enforced by `r_dir_impurities()`, added in Task 6.
- **No study-specific literal may appear in `R/`.** No study path, no study title, no dataset name, no cohort count. Every one of those comes from `_study.yml` at run time. This is success criterion 4 and the reason the port is not a copy-paste.
- **Errors, not warnings, on a missing provenance record.** Spec §6: "an unrecorded result is the failure this design exists to prevent."
- **Roxygen on every exported function**, with `@description`, `@param` for each argument, `@return`, `@export`, and a runnable `@examples` block. `R CMD check --as-cran` must stay at 0/0/0.

## Deviations from the spec, decided before planning

These are deliberate. An implementer who finds the spec says otherwise should follow the plan, not the spec.

| Spec says | Plan does | Why |
|---|---|---|
| §4.1 example: `built: built103006` | `built: built080426.sas7bdat` — filename **with** extension, required | `built103006` is the pre-`vars.sas` dataset (3677 rows). The spec's own `cohort:` block (3049/1032/2017) is the post-`vars.sas` `built080426`, so the example contradicts itself. See `analyses/R_hazard/R/read_built.R:1-14`. The extension is required because `read_clinical_data()` dispatches on it. |
| §4.1 `cohort:` holds only counts | `cohort:` also requires `event:` and `time:` | `cohort_counts()` currently hardcodes `iv_dead`/`dead`. Those are study-specific column names; in a shared package they cannot be literals. |
| §7 "`record_provenance()` output validates against a JSON schema" | Structural validation in testthat against `.provenance_required()`, no `jsonvalidate` dependency | A real JSON Schema needs `jsonvalidate` (which needs V8). The assertion being made — required keys present, correct types — is fully expressed by a structural test. If a formal schema is wanted later, `.provenance_required()` is the thing to generate it from. |
| §4.2 the R_hazard contract "moves here" | Ported here; the R_hazard copies are **left in place** | Deleting them and rewiring the `.qmd` files is Stage 4 adoption. Doing it now means editing the study tree during a live bootstrap run, with no undo. |
| R_hazard's `built_manifest()` records `md5` | Records `sha256` | §5's sidecar specifies `sha256`. One hash algorithm across the design, not two. |

## Corrections applied at execution, 2026-08-17

Three defects were found by verifying the plan's claims against the repository
before Task 1, and fixed with John's approval. Each was confirmed by running the
check, not by reading.

| Plan said | Executed as | Why |
|---|---|---|
| Task 6 `r_dir_impurities()` rejects every non-assignment | Rejects non-assignment **calls**; bare constants (`NULL`, `"_PACKAGE"`) pass | The function's own `@return` says "Function definitions and constants pass; calls do not", and the code contradicted it. `R/help.R:31` ends with the roxygen package-doc `NULL`, so the shipped package failed its own purity rule. Measured: `r_dir_impurities("R")` returned `help.R: NULL`. Editing `help.R` instead would not have helped — `"_PACKAGE"` is also a non-assignment. |
| Task 6 test 5 locates `R/` via `system.file("..", "R", package = "hvtiRutilities")` | `testthat::test_path("..", "..", "R")` | `system.file()` returns `""` there, so `dir.exists("")` is `FALSE` and `skip_if_not()` skipped the test permanently. It is the test that would have caught the defect above. A skip is not a pass — Task 7 Step 3 says so, and this plan tripped over its own rule two tasks earlier. |
| Task 1 test 3 asserts `expect_error(study_config(bare), "walked")` | Asserts `"Walked"` | `expect_error()` matches a case-sensitive regex; the implementation's message reads `"Walked, in order:"`. Measured: `grepl("walked", msg)` is `FALSE`, so the test failed against a correct implementation. |
| Task 6 test 5 asserts the source `R/` is present | Skips, with a reason, when it is not | The first correction below replaced a permanent silent skip with `expect_true(dir.exists())` — which then failed under `R CMD check`, because an installed package has no `.R` files at all, only the lazy-load database. Purity is a property of the **source tree** and cannot be checked post-install. It now runs under `devtools::test()` (0 skips) and skips under an installed check, which is the honest reading. Recorded because the intermediate state shipped an ERROR in the first full check. |
| Task 7 Step 4 expects `Status: OK`, 0/0/0 | Expects 1 NOTE | The package is not on CRAN, so *checking CRAN incoming feasibility* always NOTEs "New submission". `main` at 1.0.6 checked at exactly 1 NOTE, so 0/0/0 was never the baseline and chasing it would mean suppressing a NOTE that is correct. |
| No task updates `_pkgdown.yml` | Added a *Study Manifest and Data Contract* section, a *Provenance* section, and `r_dir_impurities` under *Package Utilities* | A gap in the plan, not a defect in it. `_pkgdown.yml` carries an **enumerated** reference index and pkgdown fails the build on any exported topic missing from it, so all eleven new exports would have broken the `pkgdown` workflow after merge — the check that catches it does not run in the test suite. Verified with `pkgdown::check_pkgdown()`: "No problems found." |
| Task 5 `record_provenance()` catches only `error` from `write_json()` | Catches `warning` as well, on the same failure path | Found at Task 5 Step 5, not by inspection: the suite came back `FAIL 0 | WARN 1`. `jsonlite::write_json()` warns (`cannot open file ...`) *before* it errors on an unwritable path, so the warning escaped the `tryCatch` and Task 7's "0 warnings" gate could never have been met. Treating a warning as failure is also the stricter reading of §6 — any warning here means the record may not have landed, which is the state this function exists to prevent. |

**Plan relocated.** The authored copy lives in the R_hazard study tree at
`docs/plans/2026-08-17-hvtirutilities-provenance.md`, on a network share with no
git and no undo. A plan whose first constraint is "all work is in
`~/Documents/GitHub/hvtiRutilities`" belongs in that repository, so this copy is
the executed one. The R_hazard original is left untouched.

---

### Task 1: Branch, and `study_config()`

**Files:**
- Create: `R/study_config.R`
- Create: `tests/testthat/helper-study.R`
- Create: `tests/testthat/test-study_config.R`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `study_config(start = getwd())` → named `list` with elements `root` (character(1), absolute path of the directory holding `_study.yml`), `file` (character(1), path to `_study.yml`), `study` (character(1)), `population` (character(1) or `NULL`), `built` (character(1), filename with extension), `citation` (character(1) or `NULL`), `cohort` (list of `n`, `n_events`, `n_censored` — all integer — plus `event` and `time`, both character(1)).
  - `make_study_fixture(dir, built = "built_test.sas7bdat", n = 20L, n_events = 8L, cohort_event = "dead", cohort_time = "iv_dead", write_data = TRUE, omit = character(0))` → character(1), the fixture root. Test helper, not exported.

- [ ] **Step 1: Create the branch**

```bash
cd ~/Documents/GitHub/hvtiRutilities && git checkout main && git pull && git checkout -b feat/study-config-provenance
```

Expected: `Switched to a new branch 'feat/study-config-provenance'`

- [ ] **Step 2: Write the fixture helper**

This helper is used by every task in the plan. It builds a throwaway study on disk: a root holding `_study.yml`, a `datasets/` directory, and a small `.sas7bdat` whose cohort counts match the manifest.

Create `tests/testthat/helper-study.R`:

```r
# Builds a disposable study tree for tests: <dir>/_study.yml plus
# <dir>/datasets/<built>. The dataset's cohort counts are constructed to match
# the manifest, so assert_cohort() passes by default and a test that wants a
# failure perturbs one or the other deliberately.
#
# `omit` drops keys from the written YAML, which is how the missing-key errors
# are exercised. Nested keys use dotted form: "cohort.n_events".

make_study_fixture <- function(dir,
                               built        = "built_test.sas7bdat",
                               n            = 20L,
                               n_events     = 8L,
                               cohort_event = "dead",
                               cohort_time  = "iv_dead",
                               write_data   = TRUE,
                               omit         = character(0)) {
  dir.create(file.path(dir, "datasets"), recursive = TRUE, showWarnings = FALSE)

  cfg <- list(
    study      = "Test study for hvtiRutilities",
    population = "Fixture, n=20",
    built      = built,
    citation   = "No citation; fixture.",
    cohort     = list(
      n          = n,
      n_events   = n_events,
      n_censored = n - n_events,
      event      = cohort_event,
      time       = cohort_time
    )
  )

  for (k in omit) {
    parts <- strsplit(k, ".", fixed = TRUE)[[1]]
    if (length(parts) == 1L) {
      cfg[[parts]] <- NULL
    } else {
      cfg[[parts[1]]][[parts[2]]] <- NULL
    }
  }

  yaml::write_yaml(cfg, file.path(dir, "_study.yml"))

  if (write_data) {
    d <- data.frame(
      id = seq_len(n),
      x  = as.numeric(seq_len(n))
    )
    # Event indicator: exactly n_events ones. The time column carries no NAs,
    # matching the real built080426 (see read_built.R's cohort note).
    d[[cohort_event]] <- c(rep(1L, n_events), rep(0L, n - n_events))
    d[[cohort_time]]  <- as.numeric(seq_len(n))
    suppressWarnings(haven::write_sas(d, file.path(dir, "datasets", built)))
  }

  dir
}
```

- [ ] **Step 3: Write the failing tests**

Create `tests/testthat/test-study_config.R`:

```r
library(testthat)
library(hvtiRutilities)

test_that("study_config finds the manifest in the starting directory", {
  root <- make_study_fixture(withr::local_tempdir())
  cfg  <- study_config(root)

  expect_equal(normalizePath(cfg$root), normalizePath(root))
  expect_equal(cfg$built, "built_test.sas7bdat")
  expect_equal(cfg$cohort$n, 20L)
  expect_equal(cfg$cohort$n_events, 8L)
  expect_equal(cfg$cohort$n_censored, 12L)
  expect_equal(cfg$cohort$event, "dead")
  expect_equal(cfg$cohort$time, "iv_dead")
})

test_that("study_config walks up from a nested subdirectory", {
  root <- make_study_fixture(withr::local_tempdir())
  deep <- file.path(root, "analyses", "R_hazard", "scripts")
  dir.create(deep, recursive = TRUE)

  expect_equal(normalizePath(study_config(deep)$root), normalizePath(root))
})

test_that("study_config errors when no manifest exists, naming what it walked", {
  bare <- withr::local_tempdir()

  expect_error(study_config(bare), "_study.yml")
  expect_error(study_config(bare), "Walked")
})

test_that("study_config errors on a missing required key, naming the key", {
  root <- make_study_fixture(withr::local_tempdir(), omit = "built")
  expect_error(study_config(root), "built")

  root2 <- make_study_fixture(withr::local_tempdir(), omit = "cohort.n_events")
  expect_error(study_config(root2), "cohort:n_events")
})

test_that("study_config errors when built has no file extension", {
  root <- make_study_fixture(withr::local_tempdir(),
                             built = "built080426", write_data = FALSE)
  expect_error(study_config(root), "extension")
})

test_that("study_config returns integer cohort counts, not doubles", {
  root <- make_study_fixture(withr::local_tempdir())
  cfg  <- study_config(root)

  expect_type(cfg$cohort$n, "integer")
  expect_type(cfg$cohort$n_events, "integer")
  expect_type(cfg$cohort$n_censored, "integer")
})

test_that("study_config errors when the cohort counts are inconsistent", {
  root <- withr::local_tempdir()
  make_study_fixture(root, write_data = FALSE)
  cfg <- yaml::read_yaml(file.path(root, "_study.yml"))
  cfg$cohort$n_censored <- 999L
  yaml::write_yaml(cfg, file.path(root, "_study.yml"))

  expect_error(study_config(root), "n_censored")
})
```

- [ ] **Step 4: Run tests to verify they fail**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::test(filter = "study_config")'
```

Expected: FAIL — `could not find function "study_config"` on every test.

- [ ] **Step 5: Write the implementation**

Create `R/study_config.R`:

```r
# The study manifest. One `_study.yml` at the study root replaces the sixteen
# identity lines that every SAS job carried as literals, and the drift that
# came with them: in distributions/ac.dead_JR.sas the study path appears twice
# with two different values, because one copy of an edit was made and the other
# was not.
#
# This is the primitive the rest of the data contract is built on. It does the
# directory walk itself; study_root() is a thin accessor over it, not the other
# way round.

# Required keys, in the order they are reported. Nested keys are dotted.
.study_required <- function() {
  c("study", "built",
    "cohort.n", "cohort.n_events", "cohort.n_censored",
    "cohort.event", "cohort.time")
}

.study_pluck <- function(cfg, key) {
  parts <- strsplit(key, ".", fixed = TRUE)[[1]]
  out <- cfg
  for (p in parts) {
    if (!is.list(out) || is.null(out[[p]])) return(NULL)
    out <- out[[p]]
  }
  out
}

#' Read the study manifest
#'
#' @description
#' Walks up from \code{start} until a \code{_study.yml} is found, parses it,
#' validates that every required key is present, and returns the result with
#' the study root attached.
#'
#' A study without a manifest must not render, so an absent or incomplete
#' \code{_study.yml} is an error rather than a set of defaults. The directories
#' walked are named in the error, because the usual cause is starting from
#' outside the study tree.
#'
#' Required keys are \code{study}, \code{built}, and a \code{cohort} block
#' holding \code{n}, \code{n_events}, \code{n_censored}, \code{event} and
#' \code{time}. \code{population} and \code{citation} are optional.
#' \code{built} must carry its file extension, because the reader dispatches
#' on it.
#'
#' @param start Character. Directory to start the upward walk from. Defaults
#'   to \code{getwd()}.
#'
#' @return A list with elements \code{root}, \code{file}, \code{study},
#'   \code{population}, \code{built}, \code{citation}, and \code{cohort} (a
#'   list of \code{n}, \code{n_events}, \code{n_censored}, \code{event},
#'   \code{time}).
#'
#' @seealso \code{\link{study_root}}, \code{\link{record_provenance}}
#'
#' @export
#'
#' @examples
#' root <- file.path(tempdir(), "study-example")
#' dir.create(root, showWarnings = FALSE)
#' yaml::write_yaml(
#'   list(study = "Example", built = "example.sas7bdat",
#'        cohort = list(n = 10L, n_events = 4L, n_censored = 6L,
#'                      event = "dead", time = "iv_dead")),
#'   file.path(root, "_study.yml")
#' )
#' cfg <- study_config(root)
#' cfg$study
#' unlink(root, recursive = TRUE)
study_config <- function(start = getwd()) {
  dir     <- normalizePath(start, mustWork = TRUE)
  walked  <- character(0)
  found   <- NULL

  repeat {
    walked <- c(walked, dir)
    candidate <- file.path(dir, "_study.yml")
    if (file.exists(candidate)) {
      found <- candidate
      break
    }
    parent <- dirname(dir)
    if (identical(parent, dir)) break
    dir <- parent
  }

  if (is.null(found)) {
    stop("study_config(): no _study.yml found. Walked, in order:\n  ",
         paste(walked, collapse = "\n  "),
         "\nStart from inside a study tree, or create a _study.yml at its root.",
         call. = FALSE)
  }

  raw <- yaml::read_yaml(found)

  missing <- Filter(function(k) is.null(.study_pluck(raw, k)),
                    .study_required())
  if (length(missing)) {
    stop("study_config(): ", found, " is missing required key",
         if (length(missing) > 1) "s" else "", ": ",
         paste(gsub(".", ":", missing, fixed = TRUE), collapse = ", "),
         ". No defaults are supplied for a study manifest.", call. = FALSE)
  }

  if (!nzchar(tools::file_ext(raw$built))) {
    stop("study_config(): built: '", raw$built, "' has no file extension. ",
         "Give the dataset filename in full (for example ",
         "'built080426.sas7bdat'); the reader dispatches on the extension.",
         call. = FALSE)
  }

  n   <- as.integer(raw$cohort$n)
  ev  <- as.integer(raw$cohort$n_events)
  cen <- as.integer(raw$cohort$n_censored)

  # An internally inconsistent cohort block would make assert_cohort() a
  # gate that can never pass, and the error it raised would point at the
  # data rather than at the manifest that is actually wrong.
  if (!identical(n, ev + cen)) {
    stop("study_config(): ", found, " cohort is inconsistent: n = ", n,
         " but n_events + n_censored = ", ev + cen,
         " (n_events = ", ev, ", n_censored = ", cen, ").", call. = FALSE)
  }

  list(
    root       = dir,
    file       = found,
    study      = raw$study,
    population = raw$population,
    built      = raw$built,
    citation   = raw$citation,
    cohort     = list(
      n          = n,
      n_events   = ev,
      n_censored = cen,
      event      = raw$cohort$event,
      time       = raw$cohort$time
    )
  )
}
```

- [ ] **Step 6: Document and run the tests**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::document()' && Rscript -e 'devtools::test(filter = "study_config")'
```

Expected: PASS, 7 tests, 0 failures. `NAMESPACE` gains `export(study_config)`.

- [ ] **Step 7: Commit**

```bash
cd ~/Documents/GitHub/hvtiRutilities && git add R/study_config.R man/study_config.Rd NAMESPACE tests/testthat/helper-study.R tests/testthat/test-study_config.R && git commit -m "feat: add study_config() to read and validate _study.yml"
```

---

### Task 2: `study_root()` and `sas_path()`

**Files:**
- Create: `R/study_paths.R`
- Create: `tests/testthat/test-study_paths.R`
- Reference (do not modify): `analyses/R_hazard/R/paths.R` in the study tree

**Interfaces:**
- Consumes: `study_config(start)` from Task 1, specifically its `$root` element.
- Produces:
  - `study_root(start = getwd())` → character(1), absolute path.
  - `sas_path(..., start = getwd())` → character(1), path under the study root.

The port changes the marker. R_hazard's `study_root()` walks up for four sibling directories (`datasets`, `distributions`, `graphs`, `analyses`); this one walks up for `_study.yml`, per spec §4.1. That is why it delegates rather than duplicating the loop.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-study_paths.R`:

```r
library(testthat)
library(hvtiRutilities)

test_that("study_root returns the directory holding _study.yml", {
  root <- make_study_fixture(withr::local_tempdir())
  expect_equal(normalizePath(study_root(root)), normalizePath(root))
})

test_that("study_root walks up from a nested subdirectory", {
  root <- make_study_fixture(withr::local_tempdir())
  deep <- file.path(root, "distributions")
  dir.create(deep, recursive = TRUE)

  expect_equal(normalizePath(study_root(deep)), normalizePath(root))
})

test_that("study_root errors outside a study tree", {
  expect_error(study_root(withr::local_tempdir()), "_study.yml")
})

test_that("sas_path joins components under the study root", {
  root <- make_study_fixture(withr::local_tempdir())

  expect_equal(
    normalizePath(sas_path("datasets", start = root)),
    normalizePath(file.path(root, "datasets"))
  )
  expect_equal(
    sas_path("distributions", "hz.dead_JR.sas", start = root),
    file.path(study_root(root), "distributions", "hz.dead_JR.sas")
  )
})

test_that("sas_path with no components returns the root", {
  root <- make_study_fixture(withr::local_tempdir())
  expect_equal(sas_path(start = root), study_root(root))
})
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::test(filter = "study_paths")'
```

Expected: FAIL — `could not find function "study_root"`.

- [ ] **Step 3: Write the implementation**

Create `R/study_paths.R`:

```r
# Runtime path resolution. The study resolves to different absolute paths on
# the server and on a Mac mount, so nothing here may contain a literal prefix.
#
# The root is the directory holding _study.yml. This replaces the earlier
# marker-directory walk (datasets/ distributions/ graphs/ analyses/), which
# located a study by its shape rather than by its declaration and so could not
# tell a study root from a copy of one.

#' Locate the study root
#'
#' @description
#' Returns the absolute path of the directory holding \code{_study.yml}, found
#' by walking up from \code{start}. Errors if there is none, naming the
#' directories walked.
#'
#' @param start Character. Directory to start the upward walk from. Defaults
#'   to \code{getwd()}.
#'
#' @return Character(1). The absolute path of the study root.
#'
#' @seealso \code{\link{study_config}}, \code{\link{sas_path}}
#'
#' @export
#'
#' @examples
#' root <- file.path(tempdir(), "study-root-example")
#' dir.create(root, showWarnings = FALSE)
#' yaml::write_yaml(
#'   list(study = "Example", built = "example.sas7bdat",
#'        cohort = list(n = 10L, n_events = 4L, n_censored = 6L,
#'                      event = "dead", time = "iv_dead")),
#'   file.path(root, "_study.yml")
#' )
#' study_root(root)
#' unlink(root, recursive = TRUE)
study_root <- function(start = getwd()) {
  study_config(start)$root
}

#' Build a path under the study root
#'
#' @description
#' Joins its arguments onto the study root. Use this instead of any literal
#' path: the same study is mounted at different absolute paths on the analysis
#' server and on a laptop.
#'
#' @param ... Character. Path components, passed to \code{file.path()}.
#' @param start Character. Directory to start the upward walk from. Defaults
#'   to \code{getwd()}.
#'
#' @return Character(1). The joined path. It is not checked for existence.
#'
#' @seealso \code{\link{study_root}}
#'
#' @export
#'
#' @examples
#' root <- file.path(tempdir(), "sas-path-example")
#' dir.create(file.path(root, "datasets"), recursive = TRUE,
#'            showWarnings = FALSE)
#' yaml::write_yaml(
#'   list(study = "Example", built = "example.sas7bdat",
#'        cohort = list(n = 10L, n_events = 4L, n_censored = 6L,
#'                      event = "dead", time = "iv_dead")),
#'   file.path(root, "_study.yml")
#' )
#' sas_path("datasets", start = root)
#' unlink(root, recursive = TRUE)
sas_path <- function(..., start = getwd()) {
  file.path(study_root(start), ...)
}
```

- [ ] **Step 4: Run the tests**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::document()' && Rscript -e 'devtools::test(filter = "study_paths")'
```

Expected: PASS, 5 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/GitHub/hvtiRutilities && git add R/study_paths.R man/study_root.Rd man/sas_path.Rd NAMESPACE tests/testthat/test-study_paths.R && git commit -m "feat: add study_root() and sas_path() keyed on _study.yml"
```

---

### Task 3: The data contract — `built_path()`, `built_manifest()`, `read_built()`

**Files:**
- Create: `R/study_data.R`
- Create: `tests/testthat/test-study_data.R`
- Reference (do not modify): `analyses/R_hazard/R/read_built.R` in the study tree

**Interfaces:**
- Consumes: `study_config()` from Task 1.
- Produces:
  - `built_path(cfg = study_config())` → character(1).
  - `built_manifest(cfg = study_config())` → `data.frame` with columns `file` (character), `size_bytes` (numeric), `mtime` (character, `"%Y-%m-%d %H:%M:%S"`), `sha256` (character), one row.
  - `read_built(cfg = study_config())` → `data.frame`, names lower-cased, logicals coerced to integer, `haven_labelled` stripped to plain vectors with `label` attributes retained.

The type-normalising behaviour in `read_built()` is load-bearing and is carried over verbatim in intent from `analyses/R_hazard/R/read_built.R:44-66`. Do not simplify it. Two read paths (`read_clinical_data()` and the `haven::read_sas()` fallback) deliver different types for the same column, and `hzr_kaplan()` rejects a logical `status` outright — so the same `.qmd` runs under one path and fails under the other.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-study_data.R`:

```r
library(testthat)
library(hvtiRutilities)

test_that("built_path resolves under datasets/ using the manifest name", {
  root <- make_study_fixture(withr::local_tempdir())
  cfg  <- study_config(root)

  expect_equal(
    normalizePath(built_path(cfg)),
    normalizePath(file.path(root, "datasets", "built_test.sas7bdat"))
  )
})

test_that("built_manifest reports file, size, mtime and sha256", {
  skip_if_not_installed("haven")
  root <- make_study_fixture(withr::local_tempdir())
  m    <- built_manifest(study_config(root))

  expect_s3_class(m, "data.frame")
  expect_equal(nrow(m), 1L)
  expect_named(m, c("file", "size_bytes", "mtime", "sha256"))
  expect_equal(m$file, "built_test.sas7bdat")
  expect_gt(m$size_bytes, 0)
  expect_match(m$sha256, "^[0-9a-f]{64}$")
})

test_that("built_manifest sha256 changes when the file changes", {
  skip_if_not_installed("haven")
  root <- withr::local_tempdir()
  make_study_fixture(root, n = 20L, n_events = 8L)
  before <- built_manifest(study_config(root))$sha256

  make_study_fixture(root, n = 20L, n_events = 9L)
  after <- built_manifest(study_config(root))$sha256

  expect_false(identical(before, after))
})

test_that("built_manifest errors when the dataset is absent", {
  root <- make_study_fixture(withr::local_tempdir(), write_data = FALSE)
  expect_error(built_manifest(study_config(root)), "missing")
})

test_that("read_built lower-cases names and returns a plain data.frame", {
  skip_if_not_installed("haven")
  root <- make_study_fixture(withr::local_tempdir())
  d    <- read_built(study_config(root))

  expect_s3_class(d, "data.frame")
  expect_false(inherits(d, "tbl_df"))
  expect_equal(names(d), tolower(names(d)))
  expect_true(all(c("dead", "iv_dead") %in% names(d)))
})

test_that("read_built returns no logical and no labelled columns", {
  skip_if_not_installed("haven")
  root <- make_study_fixture(withr::local_tempdir())
  d    <- read_built(study_config(root))

  expect_false(any(vapply(d, is.logical, logical(1))))
  expect_false(any(vapply(d, function(x) inherits(x, "haven_labelled"),
                          logical(1))))
})

test_that("read_built errors when the dataset is absent", {
  root <- make_study_fixture(withr::local_tempdir(), write_data = FALSE)
  expect_error(read_built(study_config(root)), "missing")
})
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::test(filter = "study_data")'
```

Expected: FAIL — `could not find function "built_path"`.

- [ ] **Step 3: Write the implementation**

Create `R/study_data.R`:

```r
# The data contract. The built dataset lives on a mutable network share outside
# version control: the SAS run that produced the results we validate against
# rewrote it in place, and nothing stops the next run rewriting it mid-analysis.
# Every stage records the manifest so a run cannot straddle two dataset states.
#
# The dataset name is not a constant here. It comes from _study.yml, because
# this package is shared across studies and a literal filename in R/ is exactly
# the early binding this design exists to remove.

#' Path to the study's built dataset
#'
#' @description
#' Resolves \code{<study root>/datasets/<built>}, where \code{built} is the
#' filename declared in \code{_study.yml}. The path is not checked for
#' existence.
#'
#' @param cfg List. A study manifest from \code{\link{study_config}}.
#'
#' @return Character(1). The path to the built dataset.
#'
#' @seealso \code{\link{built_manifest}}, \code{\link{read_built}}
#'
#' @export
#'
#' @examples
#' root <- file.path(tempdir(), "built-path-example")
#' dir.create(file.path(root, "datasets"), recursive = TRUE,
#'            showWarnings = FALSE)
#' yaml::write_yaml(
#'   list(study = "Example", built = "example.sas7bdat",
#'        cohort = list(n = 10L, n_events = 4L, n_censored = 6L,
#'                      event = "dead", time = "iv_dead")),
#'   file.path(root, "_study.yml")
#' )
#' built_path(study_config(root))
#' unlink(root, recursive = TRUE)
built_path <- function(cfg = study_config()) {
  file.path(cfg$root, "datasets", cfg$built)
}

#' Record the state of the built dataset
#'
#' @description
#' Returns a one-row data frame identifying the built dataset by name, size,
#' modification time and SHA-256. This is the record that lets a later reader
#' tell whether two results were produced from the same data.
#'
#' @param cfg List. A study manifest from \code{\link{study_config}}.
#'
#' @return A one-row data frame with columns \code{file}, \code{size_bytes},
#'   \code{mtime} and \code{sha256}.
#'
#' @seealso \code{\link{built_path}}, \code{\link{record_provenance}}
#'
#' @export
#'
#' @examples
#' root <- file.path(tempdir(), "built-manifest-example")
#' dir.create(file.path(root, "datasets"), recursive = TRUE,
#'            showWarnings = FALSE)
#' yaml::write_yaml(
#'   list(study = "Example", built = "example.csv",
#'        cohort = list(n = 3L, n_events = 1L, n_censored = 2L,
#'                      event = "dead", time = "iv_dead")),
#'   file.path(root, "_study.yml")
#' )
#' write.csv(data.frame(dead = c(1, 0, 0), iv_dead = 1:3),
#'           file.path(root, "datasets", "example.csv"), row.names = FALSE)
#' built_manifest(study_config(root))
#' unlink(root, recursive = TRUE)
built_manifest <- function(cfg = study_config()) {
  p <- built_path(cfg)
  if (!file.exists(p)) {
    stop("built_manifest(): missing ", p, call. = FALSE)
  }
  info <- file.info(p)
  data.frame(
    file       = cfg$built,
    size_bytes = as.numeric(info$size),
    mtime      = format(info$mtime, "%Y-%m-%d %H:%M:%S"),
    sha256     = digest::digest(p, algo = "sha256", file = TRUE),
    stringsAsFactors = FALSE
  )
}

#' Read the study's built dataset
#'
#' @description
#' Reads the dataset named in \code{_study.yml} and normalises its types so
#' that both available read paths deliver the same frame.
#'
#' The normalisation is not cosmetic. \code{\link{read_clinical_data}} converts
#' SAS 0/1 numerics to logical while \code{haven::read_sas()} leaves them
#' numeric, and downstream modelling code rejects a logical status vector
#' outright — so without this the same document would run under one read path
#' and fail under the other. Labelled vectors are likewise reduced to plain
#' vectors, keeping the SAS variable label as an attribute because listings
#' print labels rather than names.
#'
#' @param cfg List. A study manifest from \code{\link{study_config}}.
#'
#' @return A data frame with lower-cased names, no logical columns and no
#'   \code{haven_labelled} columns.
#'
#' @seealso \code{\link{built_manifest}}, \code{\link{assert_cohort}}
#'
#' @export
#'
#' @examples
#' root <- file.path(tempdir(), "read-built-example")
#' dir.create(file.path(root, "datasets"), recursive = TRUE,
#'            showWarnings = FALSE)
#' yaml::write_yaml(
#'   list(study = "Example", built = "example.csv",
#'        cohort = list(n = 3L, n_events = 1L, n_censored = 2L,
#'                      event = "dead", time = "iv_dead")),
#'   file.path(root, "_study.yml")
#' )
#' write.csv(data.frame(DEAD = c(1, 0, 0), IV_DEAD = 1:3),
#'           file.path(root, "datasets", "example.csv"), row.names = FALSE)
#' names(read_built(study_config(root)))
#' unlink(root, recursive = TRUE)
read_built <- function(cfg = study_config()) {
  p <- built_path(cfg)
  if (!file.exists(p)) {
    stop("read_built(): missing ", p, call. = FALSE)
  }

  # Carries SAS variable labels through; listings print labels, not names.
  d <- as.data.frame(read_clinical_data(p, convert_types = FALSE))
  names(d) <- tolower(names(d))

  logi <- vapply(d, is.logical, logical(1))
  d[logi] <- lapply(d[logi], as.integer)

  lab <- vapply(d, function(x) inherits(x, "haven_labelled"), logical(1))
  d[lab] <- lapply(d[lab], function(x) {
    a   <- attributes(x)
    out <- as.vector(x)
    if (!is.null(a$label)) attr(out, "label") <- a$label
    out
  })

  d
}
```

- [ ] **Step 4: Run the tests**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::document()' && Rscript -e 'devtools::test(filter = "study_data")'
```

Expected: PASS, 7 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/GitHub/hvtiRutilities && git add R/study_data.R man/built_path.Rd man/built_manifest.Rd man/read_built.Rd NAMESPACE tests/testthat/test-study_data.R && git commit -m "feat: add built_path(), built_manifest() and read_built()"
```

---

### Task 4: The cohort gate — `cohort_counts()` and `assert_cohort()`

**Files:**
- Create: `R/study_cohort.R`
- Create: `tests/testthat/test-study_cohort.R`
- Reference (do not modify): `analyses/R_hazard/R/read_built.R:71-114` in the study tree

**Interfaces:**
- Consumes: `study_config()` from Task 1, `read_built()` from Task 3.
- Produces:
  - `cohort_counts(d, cfg = study_config())` → list of `n`, `n_events`, `n_censored`, all integer.
  - `assert_cohort(d, cfg = study_config())` → `invisible(TRUE)`, or an error.

The column names come from `cfg$cohort$event` and `cfg$cohort$time`. R_hazard's version hardcodes `dead` and `iv_dead`; those are study-specific and cannot be literals in a shared package.

Carry the substance of the R_hazard comment into the roxygen: on the reference study the missingness filter is currently **vacuous** — `vars.sas` already filtered the cohort upstream, so no test exercises the filtering branch, only the counting. A passing cohort gate is not evidence that the filtering works.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-study_cohort.R`:

```r
library(testthat)
library(hvtiRutilities)

test_that("cohort_counts counts rows and events from the manifest columns", {
  cfg <- list(cohort = list(event = "dead", time = "iv_dead"))
  d   <- data.frame(dead = c(1, 1, 0, 0, 0), iv_dead = 1:5)

  expect_equal(cohort_counts(d, cfg),
               list(n = 5L, n_events = 2L, n_censored = 3L))
})

test_that("cohort_counts excludes rows missing either the event or the time", {
  cfg <- list(cohort = list(event = "dead", time = "iv_dead"))
  d   <- data.frame(dead    = c(1, 1, 0, NA, 0),
                    iv_dead = c(1, 2, NA, 4, 5))

  expect_equal(cohort_counts(d, cfg),
               list(n = 3L, n_events = 2L, n_censored = 1L))
})

test_that("cohort_counts treats logical and numeric event columns alike", {
  cfg <- list(cohort = list(event = "dead", time = "iv_dead"))
  num <- data.frame(dead = c(1, 0, 1), iv_dead = 1:3)
  log <- data.frame(dead = c(TRUE, FALSE, TRUE), iv_dead = 1:3)

  expect_equal(cohort_counts(num, cfg), cohort_counts(log, cfg))
})

test_that("cohort_counts errors when a named column is absent", {
  cfg <- list(cohort = list(event = "dead", time = "iv_dead"))
  d   <- data.frame(dead = c(1, 0))

  expect_error(cohort_counts(d, cfg), "iv_dead")
})

test_that("assert_cohort passes when the data matches the manifest", {
  cfg <- list(cohort = list(n = 5L, n_events = 2L, n_censored = 3L,
                            event = "dead", time = "iv_dead"))
  d   <- data.frame(dead = c(1, 1, 0, 0, 0), iv_dead = 1:5)

  expect_true(assert_cohort(d, cfg))
})

test_that("assert_cohort errors and reports both expected and observed", {
  cfg <- list(cohort = list(n = 5L, n_events = 2L, n_censored = 3L,
                            event = "dead", time = "iv_dead"))
  d   <- data.frame(dead = c(1, 1, 1, 0, 0), iv_dead = 1:5)

  expect_error(assert_cohort(d, cfg), "expected")
  expect_error(assert_cohort(d, cfg), "events=2")
  expect_error(assert_cohort(d, cfg), "events=3")
})

test_that("assert_cohort fails on a fixture whose data no longer matches", {
  skip_if_not_installed("haven")
  root <- withr::local_tempdir()
  make_study_fixture(root, n = 20L, n_events = 8L)
  cfg  <- study_config(root)

  # Rewrite the data with a different event count, leaving the manifest alone.
  make_study_fixture(root, n = 20L, n_events = 9L)
  d <- read_built(cfg)

  expect_error(assert_cohort(d, cfg), "events=8")
})
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::test(filter = "study_cohort")'
```

Expected: FAIL — `could not find function "cohort_counts"`.

- [ ] **Step 3: Write the implementation**

Create `R/study_cohort.R`:

```r
# The cohort gate. A build that changes the analysable cohort must fail every
# job rather than quietly producing different numbers, so a rendered page is
# itself evidence that this gate passed.

#' Count the analysable cohort
#'
#' @description
#' Counts rows for which both the event and the time column declared in
#' \code{_study.yml} are present, and the events among them.
#'
#' \strong{The missingness filter may be vacuous on a given study.} Where the
#' upstream build has already filtered the cohort, both columns have no missing
#' values and this reduces to \code{nrow(d)} and the event total. The filter is
#' kept because it is the correct definition of analysable and it stops a
#' future dataset with genuine missingness from being miscounted — but a
#' passing cohort gate is not evidence that the filtering works.
#'
#' The event column may arrive logical or numeric depending on the read path,
#' so the comparison is against \code{1}, which is correct for both. Do not
#' simplify it to \code{sum(d[[event]])}.
#'
#' @param d A data frame, typically from \code{\link{read_built}}.
#' @param cfg List. A study manifest from \code{\link{study_config}}; supplies
#'   \code{cohort$event} and \code{cohort$time}.
#'
#' @return A list with integer elements \code{n}, \code{n_events} and
#'   \code{n_censored}.
#'
#' @seealso \code{\link{assert_cohort}}
#'
#' @export
#'
#' @examples
#' cfg <- list(cohort = list(event = "dead", time = "iv_dead"))
#' d <- data.frame(dead = c(1, 1, 0, 0, 0), iv_dead = 1:5)
#' cohort_counts(d, cfg)
cohort_counts <- function(d, cfg = study_config()) {
  event <- cfg$cohort$event
  time  <- cfg$cohort$time

  missing_cols <- setdiff(c(event, time), names(d))
  if (length(missing_cols)) {
    stop("cohort_counts(): data has no column",
         if (length(missing_cols) > 1) "s" else "", " named ",
         paste(missing_cols, collapse = ", "),
         ". The cohort columns are declared in _study.yml.", call. = FALSE)
  }

  ok <- !is.na(d[[time]]) & !is.na(d[[event]])
  n  <- sum(ok)
  ev <- sum(d[[event]][ok] == 1)

  list(n          = as.integer(n),
       n_events   = as.integer(ev),
       n_censored = as.integer(n - ev))
}

#' Assert the cohort matches the study manifest
#'
#' @description
#' Compares \code{\link{cohort_counts}} against the \code{cohort} block of
#' \code{_study.yml} and errors on any disagreement. Call it before any
#' analysis that would otherwise run happily on an unreconciled cohort.
#'
#' @param d A data frame, typically from \code{\link{read_built}}.
#' @param cfg List. A study manifest from \code{\link{study_config}}.
#'
#' @return \code{invisible(TRUE)} on success; otherwise an error.
#'
#' @seealso \code{\link{cohort_counts}}
#'
#' @export
#'
#' @examples
#' cfg <- list(cohort = list(n = 5L, n_events = 2L, n_censored = 3L,
#'                           event = "dead", time = "iv_dead"))
#' d <- data.frame(dead = c(1, 1, 0, 0, 0), iv_dead = 1:5)
#' assert_cohort(d, cfg)
assert_cohort <- function(d, cfg = study_config()) {
  cc   <- cohort_counts(d, cfg)
  want <- list(n          = as.integer(cfg$cohort$n),
               n_events   = as.integer(cfg$cohort$n_events),
               n_censored = as.integer(cfg$cohort$n_censored))

  if (!identical(cc, want)) {
    stop("cohort gate: expected N=", want$n, " / events=", want$n_events,
         " / censored=", want$n_censored,
         ", got N=", cc$n, " / events=", cc$n_events,
         " / censored=", cc$n_censored,
         ". Analysis must not run on an unreconciled cohort.", call. = FALSE)
  }
  invisible(TRUE)
}
```

- [ ] **Step 4: Run the tests**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::document()' && Rscript -e 'devtools::test(filter = "study_cohort")'
```

Expected: PASS, 7 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/GitHub/hvtiRutilities && git add R/study_cohort.R man/cohort_counts.Rd man/assert_cohort.Rd NAMESPACE tests/testthat/test-study_cohort.R && git commit -m "feat: add cohort_counts() and assert_cohort() keyed on _study.yml"
```

---

### Task 5: `record_provenance()`

**Files:**
- Modify: `DESCRIPTION` (add `jsonlite` to `Imports`, bump `Version` to `1.0.7`, update `Date`)
- Create: `R/provenance.R`
- Create: `tests/testthat/test-provenance.R`

**Interfaces:**
- Consumes: `study_config()` (Task 1), `built_manifest()` (Task 3).
- Produces:
  - `record_provenance(path, extra = list(), cfg = study_config())` → `invisible(list)`, and writes `<path without extension>.provenance.json`.
  - `provenance_path(path)` → character(1). Exported so a caller can name the sidecar without writing it.
  - `.provenance_required()` → named character vector mapping required JSON keys to expected types. Internal; the structural test reads it.

Sidecar shape, per spec §5. Key order is fixed and must not depend on anything that varies between runs, because "two runs in the same environment differ only in `rendered`" is a test.

```json
{
  "job":       "01.hz.dead_JR",
  "rendered":  "2026-08-13T14:22:07Z",
  "study":     { "name": "...", "file": "_study.yml", "sha256": "..." },
  "r":         { "version": "4.5.1", "platform": "x86_64-apple-darwin20" },
  "packages":  [ { "package": "hvtiRutilities", "version": "1.0.7", "source": "GitHub" } ],
  "renv_lock": { "path": "renv.lock", "sha256": "..." },
  "data":      [ { "file": "built080426.sas7bdat", "bytes": 4194304, "mtime": "...", "sha256": "..." } ],
  "cohort":    { "n": 3049, "n_events": 1032, "n_censored": 2017 }
}
```

`renv_lock` is `null` when the study has no `renv.lock`; the key is always present. `packages` records **every loaded namespace**, sorted by name — not a curated list, because the curated list is what goes wrong when a dependency starts mattering and nobody notices.

- [ ] **Step 1: Add the dependency and bump the version**

Edit `DESCRIPTION`: set `Version: 1.0.7`, set `Date:` to the implementation date, and add `jsonlite` to `Imports` in alphabetical position (between `haven` and `labelled`).

```bash
cd ~/Documents/GitHub/hvtiRutilities && grep -n -A 12 '^Imports:' DESCRIPTION && grep -n '^Version:' DESCRIPTION
```

Expected: `Version: 1.0.7`, and `jsonlite,` listed between `haven,` and `labelled,`.

- [ ] **Step 2: Write the failing tests**

Create `tests/testthat/test-provenance.R`:

```r
library(testthat)
library(hvtiRutilities)

# A rendered output to sit beside. record_provenance() does not require the
# output to exist -- it names the sidecar from the path -- but the realistic
# case has it there.
make_output <- function(root, name = "01.hz.dead_JR.html") {
  dir.create(file.path(root, "_output"), recursive = TRUE,
             showWarnings = FALSE)
  p <- file.path(root, "_output", name)
  writeLines("<html></html>", p)
  p
}

test_that("provenance_path swaps the extension for .provenance.json", {
  expect_equal(basename(provenance_path("a/b/01.hz.dead_JR.html")),
               "01.hz.dead_JR.provenance.json")
  expect_equal(basename(provenance_path("a/b/01.hz.dead_JR.qmd")),
               "01.hz.dead_JR.provenance.json")
})

test_that("record_provenance writes a sidecar next to the output", {
  skip_if_not_installed("haven")
  root <- make_study_fixture(withr::local_tempdir())
  out  <- make_output(root)

  record_provenance(out, cfg = study_config(root))

  expect_true(file.exists(provenance_path(out)))
})

test_that("the sidecar carries every required key with the right type", {
  skip_if_not_installed("haven")
  root <- make_study_fixture(withr::local_tempdir())
  out  <- make_output(root)

  record_provenance(out, cfg = study_config(root))
  j <- jsonlite::fromJSON(provenance_path(out), simplifyVector = FALSE)

  req <- hvtiRutilities:::.provenance_required()
  for (key in names(req)) {
    expect_true(key %in% names(j), info = paste("missing key:", key))
  }

  expect_equal(j$job, "01.hz.dead_JR")
  expect_match(j$rendered, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$")
  expect_equal(j$study$file, "_study.yml")
  expect_match(j$study$sha256, "^[0-9a-f]{64}$")
  expect_equal(j$r$version, paste(R.version$major, R.version$minor, sep = "."))
  expect_true(length(j$packages) > 0)
  expect_equal(j$cohort$n, 20L)
  expect_equal(j$cohort$n_events, 8L)
  expect_equal(j$data[[1]]$file, "built_test.sas7bdat")
  expect_match(j$data[[1]]$sha256, "^[0-9a-f]{64}$")
})

test_that("renv_lock is present as null when the study has no lock", {
  skip_if_not_installed("haven")
  root <- make_study_fixture(withr::local_tempdir())
  out  <- make_output(root)

  record_provenance(out, cfg = study_config(root))
  txt <- paste(readLines(provenance_path(out)), collapse = "\n")

  expect_match(txt, "renv_lock")
  expect_null(jsonlite::fromJSON(provenance_path(out),
                                 simplifyVector = FALSE)$renv_lock)
})

test_that("renv_lock records path and sha256 when a lock exists", {
  skip_if_not_installed("haven")
  root <- make_study_fixture(withr::local_tempdir())
  writeLines('{"R": {"Version": "4.5.1"}}', file.path(root, "renv.lock"))
  out <- make_output(root)

  record_provenance(out, cfg = study_config(root))
  j <- jsonlite::fromJSON(provenance_path(out), simplifyVector = FALSE)

  expect_equal(j$renv_lock$path, "renv.lock")
  expect_match(j$renv_lock$sha256, "^[0-9a-f]{64}$")
})

test_that("two runs differ only in the rendered timestamp", {
  skip_if_not_installed("haven")
  root <- make_study_fixture(withr::local_tempdir())
  out  <- make_output(root)

  record_provenance(out, cfg = study_config(root))
  first <- readLines(provenance_path(out))

  record_provenance(out, cfg = study_config(root))
  second <- readLines(provenance_path(out))

  drop_rendered <- function(x) x[!grepl('"rendered"', x)]
  expect_equal(drop_rendered(first), drop_rendered(second))
})

test_that("extra fields are merged in and do not displace required keys", {
  skip_if_not_installed("haven")
  root <- make_study_fixture(withr::local_tempdir())
  out  <- make_output(root)

  record_provenance(out, extra = list(template = list(name = "hz",
                                                      version = "1.0.0")),
                    cfg = study_config(root))
  j <- jsonlite::fromJSON(provenance_path(out), simplifyVector = FALSE)

  expect_equal(j$template$name, "hz")
  expect_equal(j$job, "01.hz.dead_JR")
})

test_that("an unwritable sidecar location is an error, not a warning", {
  skip_if_not_installed("haven")
  skip_on_os("windows")
  root <- make_study_fixture(withr::local_tempdir())
  out  <- file.path(root, "_output", "nope", "01.hz.dead_JR.html")

  expect_error(record_provenance(out, cfg = study_config(root)),
               "provenance")
})

test_that("record_provenance returns the record invisibly", {
  skip_if_not_installed("haven")
  root <- make_study_fixture(withr::local_tempdir())
  out  <- make_output(root)

  expect_invisible(record_provenance(out, cfg = study_config(root)))
  rec <- record_provenance(out, cfg = study_config(root))
  expect_type(rec, "list")
  expect_equal(rec$job, "01.hz.dead_JR")
})
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::test(filter = "provenance")'
```

Expected: FAIL — `could not find function "provenance_path"`.

- [ ] **Step 4: Write the implementation**

Create `R/provenance.R`:

```r
# The provenance sidecar.
#
# renv.lock alone does not close the provenance gap. It is project-scoped and
# time-varying: a study runs eighty jobs over three years and is snapshotted
# repeatedly, so the lock at the end does not say what produced a particular
# output in month two. The lock is a restore mechanism, not a record. The
# result is job-scoped and frozen when filed, so the record lives beside it.
#
# JSON, not RDS: the record must be readable in 2035 by someone who may not
# have R, and two runs must be diffable with diff. RDS fails both.

# Required top-level keys and their expected JSON types. The structural test
# reads this; it is also what a formal JSON Schema would be generated from.
.provenance_required <- function() {
  c(job       = "character",
    rendered  = "character",
    study     = "list",
    r         = "list",
    packages  = "list",
    renv_lock = "list",
    data      = "list",
    cohort    = "list")
}

# Every loaded namespace, sorted, with the source recorded where the
# installation left a trace of one. Not a curated list: a curated list is what
# goes wrong when a dependency starts mattering and nobody notices.
.loaded_packages <- function() {
  ns <- sort(loadedNamespaces())
  lapply(ns, function(p) {
    desc <- tryCatch(utils::packageDescription(p), error = function(e) NULL)
    src <- if (is.null(desc)) {
      NA_character_
    } else if (!is.null(desc$RemoteType)) {
      desc$RemoteType
    } else if (!is.null(desc$Repository)) {
      desc$Repository
    } else if (identical(desc$Priority, "base")) {
      "base"
    } else {
      NA_character_
    }
    list(package = p,
         version = as.character(utils::packageVersion(p)),
         source  = src)
  })
}

#' Name the provenance sidecar for an output
#'
#' @description
#' Returns the path of the sidecar belonging to a rendered output: the output
#' path with its extension replaced by \code{.provenance.json}.
#'
#' @param path Character(1). Path to a rendered output.
#'
#' @return Character(1). The sidecar path.
#'
#' @seealso \code{\link{record_provenance}}
#'
#' @export
#'
#' @examples
#' provenance_path("_output/01.hz.dead_JR.html")
provenance_path <- function(path) {
  file.path(dirname(path),
            paste0(tools::file_path_sans_ext(basename(path)),
                   ".provenance.json"))
}

#' Write the provenance record for a rendered output
#'
#' @description
#' Writes \code{<output>.provenance.json} beside a rendered result, recording
#' what produced it: the study manifest and its checksum, the R version and
#' platform, every loaded package and its version, the \code{renv.lock}
#' checksum if there is one, the built dataset's checksum, and the cohort.
#'
#' This closes a loop that is otherwise impossible. Revisiting a study becomes:
#' read the sidecar off the filed output, \code{renv::restore()} to that lock,
#' re-render, confirm the filed numbers reproduce, and only then wind forward.
#'
#' Failure to write the sidecar is an error rather than a warning. Every other
#' failure in this design is recoverable; a silently unrecorded result is not.
#'
#' @param path Character(1). Path to the rendered output the record belongs to.
#'   The file itself need not exist; only its name and directory are used.
#' @param extra List. Additional named fields merged into the record — for
#'   example a \code{template} block naming the template and its version.
#'   Required keys cannot be displaced.
#' @param cfg List. A study manifest from \code{\link{study_config}}.
#'
#' @return Invisibly, the record that was written, as a list.
#'
#' @seealso \code{\link{provenance_path}}, \code{\link{study_config}},
#'   \code{\link{built_manifest}}
#'
#' @export
#'
#' @examples
#' root <- file.path(tempdir(), "provenance-example")
#' dir.create(file.path(root, "datasets"), recursive = TRUE,
#'            showWarnings = FALSE)
#' yaml::write_yaml(
#'   list(study = "Example", built = "example.csv",
#'        cohort = list(n = 3L, n_events = 1L, n_censored = 2L,
#'                      event = "dead", time = "iv_dead")),
#'   file.path(root, "_study.yml")
#' )
#' write.csv(data.frame(dead = c(1, 0, 0), iv_dead = 1:3),
#'           file.path(root, "datasets", "example.csv"), row.names = FALSE)
#' out <- file.path(root, "example.html")
#' writeLines("<html></html>", out)
#' rec <- record_provenance(out, cfg = study_config(root))
#' rec$job
#' unlink(root, recursive = TRUE)
record_provenance <- function(path, extra = list(), cfg = study_config()) {
  sidecar <- provenance_path(path)

  lock      <- file.path(cfg$root, "renv.lock")
  lock_rec  <- if (file.exists(lock)) {
    list(path   = "renv.lock",
         sha256 = digest::digest(lock, algo = "sha256", file = TRUE))
  } else {
    NULL
  }

  bm <- built_manifest(cfg)

  record <- list(
    job      = tools::file_path_sans_ext(basename(path)),
    # Fixed-offset UTC, so two machines in different zones produce comparable
    # records and the string sorts chronologically.
    rendered = format(as.POSIXlt(Sys.time(), tz = "UTC"),
                      "%Y-%m-%dT%H:%M:%SZ"),
    study    = list(
      name   = cfg$study,
      file   = basename(cfg$file),
      sha256 = digest::digest(cfg$file, algo = "sha256", file = TRUE)
    ),
    r = list(
      version  = paste(R.version$major, R.version$minor, sep = "."),
      platform = R.version$platform
    ),
    packages  = .loaded_packages(),
    renv_lock = lock_rec,
    data      = list(list(
      file   = bm$file,
      bytes  = bm$size_bytes,
      mtime  = bm$mtime,
      sha256 = bm$sha256
    )),
    cohort = list(
      n          = cfg$cohort$n,
      n_events   = cfg$cohort$n_events,
      n_censored = cfg$cohort$n_censored
    )
  )

  # Extra fields are appended, never allowed to displace a required key.
  extra <- extra[setdiff(names(extra), names(.provenance_required()))]
  record <- c(record, extra)

  written <- tryCatch({
    jsonlite::write_json(record, sidecar, auto_unbox = TRUE, pretty = TRUE,
                         null = "null", digits = NA)
    TRUE
  }, error = function(e) conditionMessage(e))

  if (!isTRUE(written)) {
    stop("record_provenance(): could not write the provenance sidecar ",
         sidecar, ": ", written,
         "\nAn unrecorded result is the failure this check exists to prevent.",
         call. = FALSE)
  }

  invisible(record)
}
```

- [ ] **Step 5: Run the tests**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::document()' && Rscript -e 'devtools::test(filter = "provenance")'
```

Expected: PASS, 9 tests, 0 failures.

If "two runs differ only in the rendered timestamp" fails, the cause is almost always `.loaded_packages()` — a namespace loaded by the first call and not the second. Check that the test does not load a package between the two calls.

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/GitHub/hvtiRutilities && git add DESCRIPTION R/provenance.R man/record_provenance.Rd man/provenance_path.Rd NAMESPACE tests/testthat/test-provenance.R && git commit -m "feat: add record_provenance() JSON sidecar; add jsonlite; bump to 1.0.7"
```

---

### Task 6: `r_dir_impurities()` and the package's own purity check

**Files:**
- Create: `R/purity.R`
- Create: `tests/testthat/test-purity.R`
- Reference (do not modify): `analyses/R_hazard/R/purity.R` in the study tree

**Interfaces:**
- Consumes: nothing.
- Produces: `r_dir_impurities(dir)` → character vector of complaints, empty when clean.

Spec §7 requires this check in both packages. It is exported because `hvtiRtemplates` will call it in Stage 2/3, and because a study's own `R/` directory is checked with it.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-purity.R`:

```r
library(testthat)
library(hvtiRutilities)

test_that("a directory of assignments only is clean", {
  d <- withr::local_tempdir()
  writeLines(c("f <- function(x) x + 1", "K <- 42"), file.path(d, "ok.R"))

  expect_equal(r_dir_impurities(d), character(0))
})

test_that("a top-level call is reported with file and expression", {
  d <- withr::local_tempdir()
  writeLines(c("f <- function(x) x + 1", "print(f(1))"),
             file.path(d, "bad.R"))

  out <- r_dir_impurities(d)
  expect_length(out, 1L)
  expect_match(out, "bad.R")
  expect_match(out, "print")
})

test_that("library() at the top level is reported", {
  d <- withr::local_tempdir()
  writeLines("library(stats)", file.path(d, "lib.R"))

  expect_length(r_dir_impurities(d), 1L)
})

test_that("an empty directory is clean", {
  expect_equal(r_dir_impurities(withr::local_tempdir()), character(0))
})

test_that("a bare constant is clean -- the roxygen package-doc idiom", {
  d <- withr::local_tempdir()
  writeLines(c("#' @name pkg-package", "NULL"), file.path(d, "help.R"))
  writeLines("\"_PACKAGE\"", file.path(d, "pkg.R"))

  expect_equal(r_dir_impurities(d), character(0))
})

test_that("the package's own R/ directory is pure", {
  # test_path() resolves from tests/testthat/, so this is <pkg>/R. Do not use
  # system.file("..", "R", ...): it returns "" and the test skips forever.
  r_dir <- testthat::test_path("..", "..", "R")
  expect_true(dir.exists(r_dir))

  expect_equal(r_dir_impurities(r_dir), character(0))
})
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::test(filter = "purity")'
```

Expected: FAIL — `could not find function "r_dir_impurities"`.

- [ ] **Step 3: Write the implementation**

Create `R/purity.R`:

```r
# A study's R/ directory is sourced wholesale by every document:
#
#   for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)
#
# so a file there with top-level executable code runs on every render. This was
# not hypothetical: a helper file called read_built() and ran a 500-replicate
# bootstrap at its top level, meaning every render fired a long job nobody
# asked for. Scripts belong in scripts/.
#
# The check is syntactic, not behavioural: parse each file and require every
# top-level expression to be an assignment. That admits function definitions
# and constants, and rejects calls.

#' Report top-level executable code in an R directory
#'
#' @description
#' Parses every \code{.R} file in \code{dir} and reports any top-level
#' expression that is not an assignment. Function definitions and constants
#' pass; calls do not.
#'
#' Use this on any directory that is sourced wholesale, where a stray call
#' would execute on every render.
#'
#' @param dir Character(1). Directory to check.
#'
#' @return A character vector of complaints, one per offending expression,
#'   empty when the directory is clean. The caller decides whether to warn or
#'   to fail.
#'
#' @export
#'
#' @examples
#' d <- file.path(tempdir(), "purity-example")
#' dir.create(d, showWarnings = FALSE)
#' writeLines(c("f <- function(x) x + 1", "print(f(1))"),
#'            file.path(d, "example.R"))
#' r_dir_impurities(d)
#' unlink(d, recursive = TRUE)
.is_assignment <- function(e) {
  is.call(e) && as.character(e[[1]])[1] %in% c("<-", "=", "<<-", "assign")
}

r_dir_impurities <- function(dir) {
  files <- list.files(dir, pattern = "[.]R$", full.names = TRUE)
  out <- character(0)
  for (f in files) {
    for (e in parse(f)) {
      # Only calls can have side effects. A bare constant cannot -- and the
      # roxygen package-doc idiom is a top-level NULL or "_PACKAGE", so
      # rejecting constants would fail every correctly documented package.
      if (is.call(e) && !.is_assignment(e)) {
        out <- c(out, paste0(
          basename(f), ": top-level expression is not an assignment: ",
          paste(deparse(e), collapse = " ")))
      }
    }
  }
  out
}
```

- [ ] **Step 4: Run the tests**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::document()' && Rscript -e 'devtools::test(filter = "purity")'
```

Expected: PASS, 6 tests, 0 failures. No skips — test 5 runs.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/GitHub/hvtiRutilities && git add R/purity.R man/r_dir_impurities.Rd NAMESPACE tests/testthat/test-purity.R && git commit -m "feat: add r_dir_impurities() top-level-code check"
```

---

### Task 7: NEWS, full check, and the PR

**Files:**
- Modify: `NEWS.md`
- Verify: `DESCRIPTION`

- [ ] **Step 1: Write the NEWS entry**

Prepend to `NEWS.md`, above the `# hvtiRutilities 1.0.6` heading. The version heading must match `DESCRIPTION` exactly — a test greps for it.

```markdown
# hvtiRutilities 1.0.7

## New features

- `study_config()` reads a study's `_study.yml` manifest, found by walking up
  from a starting directory. It validates that every required key is present
  and errors otherwise, naming the key: a study without a complete manifest
  must not render, and a partial default would be a silent wrong answer.

- `record_provenance()` writes a JSON sidecar beside a rendered output,
  recording the study manifest checksum, the R version and platform, every
  loaded package and its version, the `renv.lock` checksum, the input
  dataset's SHA-256, and the cohort. `renv.lock` alone cannot say what
  produced a particular result — it is project-scoped and re-snapshotted
  through a study's life — so the record is job-scoped and lives with the
  result. Failure to write it is an error, not a warning.

- The study data contract moves in from the per-study `R/` directories:
  `study_root()`, `sas_path()`, `built_path()`, `built_manifest()`,
  `read_built()`, `cohort_counts()` and `assert_cohort()`. All of them read
  study-specific values from `_study.yml` rather than from constants, so no
  study path, title, dataset name or cohort count appears in package code.

- `r_dir_impurities()` reports top-level executable code in a directory that
  is sourced wholesale, where a stray call would run on every render.

## Notes

- New dependency: `jsonlite`, for the provenance sidecar.
- `built_manifest()` records `sha256` rather than the `md5` used by the
  earlier per-study version, matching the provenance record. One hash
  algorithm across the design, not two.
```

- [ ] **Step 2: Verify the NEWS and DESCRIPTION versions agree**

```bash
cd ~/Documents/GitHub/hvtiRutilities && grep -m1 '^Version:' DESCRIPTION && head -1 NEWS.md
```

Expected: `Version: 1.0.7` and `# hvtiRutilities 1.0.7`.

- [ ] **Step 3: Run the full test suite**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::test()'
```

Expected: all tests pass, 0 failures, 0 warnings. Note the skip count and confirm every skip is an expected `skip_if_not_installed()`; a skip is not a pass.

- [ ] **Step 4: Run `R CMD check --as-cran` from a clean export**

Build from `git archive`, not the working tree — an empty `inst/doc` fabricates two vignette WARNINGs, and in a worktree `.git` is a file that `R CMD build` fails to exclude, producing a spurious hidden-files NOTE. Keep the manual build; it is what catches raw Unicode in `.Rd`.

```bash
cd ~/Documents/GitHub/hvtiRutilities && rm -rf /tmp/hvtiRutilities-check && mkdir -p /tmp/hvtiRutilities-check && git archive --format=tar HEAD | tar -x -C /tmp/hvtiRutilities-check && cd /tmp/hvtiRutilities-check && R CMD build . && R CMD check --as-cran hvtiRutilities_1.0.7.tar.gz
```

Expected: `Status: OK`, 0 errors / 0 warnings / 0 notes. Read the per-step `[Ns]` timings and confirm the overall check time is under 10 minutes.

- [ ] **Step 5: Commit and open the PR**

```bash
cd ~/Documents/GitHub/hvtiRutilities && git add NEWS.md && git commit -m "docs: NEWS for 1.0.7" && git push -u origin feat/study-config-provenance
```

```bash
cd ~/Documents/GitHub/hvtiRutilities && gh pr create --title "feat: study manifest and provenance sidecar (Stage 1)" --body "$(cat <<'EOF'
Stage 1 of the templates-and-provenance design: `study_config()`,
`record_provenance()`, and the port of the per-study data contract into the
package.

A filed result can now name exactly what produced it — study manifest
checksum, R version and platform, every loaded package version, `renv.lock`
checksum, input dataset SHA-256, and cohort — in a JSON sidecar written beside
the output. `renv.lock` alone could not do this: it is project-scoped and
re-snapshotted through a study's life, so it cannot say what produced one
result in month two of three years.

No study-specific literal appears in `R/`. Every study value comes from
`_study.yml` at run time.

Adoption in `R_hazard` (deleting the per-study copies and rewiring the `.qmd`
files) is Stage 4 and is not in this PR.

Plan: `dev/specs/2026-08-17-hvtirutilities-provenance-plan.md` (in this repo; the
authored copy is in the R_hazard study tree under
`docs/plans/`, which has no version control)
Design: `analyses/R_hazard/docs/specs/2026-08-13-templates-and-provenance-design.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: a PR URL. Leave it for John to merge.

---

## Self-review against the spec

| Spec requirement | Task |
|---|---|
| §4.2 `study_config()` walks up, validates, errors | 1 |
| §4.2 the data contract moves here, reading from `study_config()` | 2, 3, 4 |
| §4.2 `record_provenance()` writes the sidecar | 5 |
| §5 sidecar shape, JSON, every loaded package, diffable | 5 |
| §6 `_study.yml` absent → error naming directories walked | 1 |
| §6 missing key → error naming the key, no partial defaults | 1 |
| §6 cohort disagrees with the dataset → `assert_cohort()` errors | 4 |
| §6 sidecar unwritable → error, not warning | 5 |
| §7 `study_config()` walks up; errors on absent and on missing keys | 1 |
| §7 `record_provenance()` output validates structurally | 5 |
| §7 two runs differ only in `rendered` | 5 |
| §7 changing a fixture dataset changes its checksum and fails the gate | 3, 4 |
| §7 `R/` holds no top-level executable code | 6 |
| §11 criterion 1 — sidecar names versions and checksums | 5 |
| §11 criterion 2 — `renv::restore()` from a filed lock | 5 records the lock checksum; the restore drill itself is Stage 4, once a real study writes sidecars |
| §11 criterion 4 — no study path, title or dataset name in code | 1–4, enforced by construction |

**Not covered here, deliberately:** §11 criterion 2's end-to-end restore drill needs a real study with a real `renv.lock` and a filed result to restore. Stage 1 supplies the record; the drill belongs to Stage 4 adoption. Flagged rather than silently dropped.
