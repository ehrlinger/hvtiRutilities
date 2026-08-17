# Study Initialization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `hvtiRutilities` a read-only study compliance auditor and an
initializer that writes a study's `_study.yml` and seeds its `manifest.yaml`,
deriving the cohort counts from the data so no human ever types one.

**Architecture:** One auditor, two writers. `study_status()` is the only code
that inspects a study; `study_init()` calls it to report what a new study still
lacks, and the deferred close-out will call the same function to compute a
publication record's grade. `study_init()` cannot use `study_config()` — it
writes the file `study_config()` reads — so it constructs a synthetic config
from its own arguments and passes that to `read_built()` and `cohort_counts()`,
neither of which needs a validated manifest.

**Tech Stack:** R (>= 4.1.0), roxygen2 via `devtools::document()`, testthat
edition 3, `yaml`, `tools`, `digest`. **No new dependencies.**

## Global Constraints

- **All work is in `~/Documents/GitHub/hvtiRutilities`.** Nothing in this plan
  writes to `/Volumes/qhsstudies/...`.
- **Branch first, PR at the end.** Never push to `main`. Branch name:
  `feat/study-init`.
- **Depends on PR #49 being merged.** This plan consumes `cohort_counts()`,
  `assert_cohort()`, `read_built()`, `built_path()`, and `provenance_path()`,
  all of which land in Stage 1. Start from an up-to-date `main`.
- **Version is `1.0.8`.** Bump the patch digit only — three digits, never
  `.9000`, never roll MINOR or MAJOR. Both `DESCRIPTION` line 4 (`Version:`)
  and the `NEWS.md` top heading must read `1.0.8`; a test greps NEWS for the
  exact DESCRIPTION version.
- **`R/` holds side-effect-free code only.** Every top-level expression must be
  an assignment. Enforced by `r_dir_impurities()`, which must return
  `character(0)` for `R/`.
- **No study-specific literal may appear in `R/`.** No study path, no study
  title, no dataset name, no cohort count. Everything comes from arguments or
  from `_study.yml` at run time.
- **No chatty output in computational function bodies.** No `print()`, `cat()`,
  or `message()` inside `study_init()` or `study_status()`. `cat()` inside a
  `print.*` S3 method is correct and expected.
- **Roxygen on every exported function**, with `@description`, `@param` for each
  argument, `@return`, `@export`, and a runnable `@examples` block.
  `R CMD check --as-cran` must stay at 0 errors / 0 warnings.

## Deviations from the spec, decided before planning

These are deliberate. An implementer who finds the spec says otherwise should
follow the plan, not the spec.

| Spec says | Plan does | Why |
|---|---|---|
| `extract_date = NULL` means "not recorded" | `extract_date = NULL` defaults to the **dataset file's mtime** | `update_manifest()` always writes an `extract_date` and formats it with `as.Date()`; `as.Date(NULL)` yields `character(0)` and produces a malformed manifest entry. The three options were a false fact (`Sys.Date()` on a 2006 dataset), a mandatory argument, or a true fact already on disk. The file's mtime is a true fact. |
| `provenance` check counts "outputs with a `.provenance.json` beside them" | Denominator is **`.qmd`/`.Rmd` source files**, not rendered outputs | Counting `.html`/`.pdf` would treat a 20-year study's legacy PDFs and Word-exported documents as un-provenanced analysis outputs, so the check would report `FAIL` on every legacy study for reasons unrelated to provenance. A check that always fails trains the reader to ignore it. `provenance_path()` strips the extension, so a sidecar's stem matches its source's stem — the mapping is exact. |
| `study_init()` "ends by printing `study_status()`" | Returns the `study_status` object **visibly** | A `print()` call inside a function body violates the no-chatty-output constraint and the CRAN cookbook. Returning visibly makes R auto-print it through `print.study_status()`, which has the same effect at the console and none of the side effect in a script. |

---

### Task 1: Branch, and `study_status()`

**Files:**
- Create: `R/study_status.R`
- Create: `tests/testthat/test-study_status.R`
- Reference (do not modify): `R/study_config.R`, `R/study_data.R`,
  `R/study_cohort.R`, `R/manifest.R`, `tests/testthat/helper-study.R`

**Interfaces:**
- Consumes:
  - `study_config(start)` → validated manifest list with `$root`, `$file`,
    `$study`, `$population`, `$built`, `$citation`, `$cohort` (list of `n`,
    `n_events`, `n_censored`, `event`, `time`).
  - `built_path(cfg)` → character(1).
  - `read_built(cfg)` → data.frame.
  - `assert_cohort(d, cfg)` → `invisible(TRUE)` or error.
  - `verify_manifest(manifest_path, data_dir, stop_on_error, verbose)` →
    data.frame with columns `file`, `status` (`"OK"`/`"FAIL"`), `message`.
    Warns rather than errors when `stop_on_error = FALSE`.
  - `make_study_fixture(dir, built, n, n_events, cohort_event, cohort_time,
    write_data, omit)` → character(1), the fixture root. Test helper.
- Produces:
  - `study_status(root = getwd())` → object of class `"study_status"`, a list
    with `root` (character(1)), `checks` (data.frame with character columns
    `item`, `status`, `detail`; six rows in fixed order `_study.yml`,
    `renv.lock`, `manifest.yaml`, `dataset`, `cohort`, `provenance`), and
    `counts` (list of integers `r_files`, `qmd`, `sas_jobs`, `sidecars`).
  - `print.study_status(x, ...)` → `invisible(x)`, S3 method.

- [ ] **Step 1: Create the branch**

```bash
cd ~/Documents/GitHub/hvtiRutilities && git checkout main && git pull && git checkout -b feat/study-init
```

Expected: `Switched to a new branch 'feat/study-init'`

- [ ] **Step 2: Write the failing tests**

Create `tests/testthat/test-study_status.R`:

```r
library(testthat)
library(hvtiRutilities)

# Pulls one row out of the checks frame by item name, so a test asserts on the
# check it means rather than on a row position that a later edit could shift.
check_for <- function(st, item) {
  row <- st$checks[st$checks$item == item, , drop = FALSE]
  expect_equal(nrow(row), 1L, info = paste("no check named", item))
  row
}

test_that("study_status on a bare directory reports MISSING, not an error", {
  bare <- withr::local_tempdir()
  st   <- study_status(bare)

  expect_s3_class(st, "study_status")
  expect_equal(check_for(st, "_study.yml")$status, "MISSING")
  expect_equal(check_for(st, "renv.lock")$status, "MISSING")
  expect_equal(check_for(st, "manifest.yaml")$status, "MISSING")
})

test_that("study_status returns the six checks in a fixed order", {
  st <- study_status(withr::local_tempdir())

  expect_equal(st$checks$item,
               c("_study.yml", "renv.lock", "manifest.yaml",
                 "dataset", "cohort", "provenance"))
  expect_type(st$checks$item, "character")
  expect_type(st$checks$status, "character")
  expect_type(st$checks$detail, "character")
})

test_that("study_status reports OK for a valid manifest and its dataset", {
  skip_if_not_installed("haven")
  root <- make_study_fixture(withr::local_tempdir())
  st   <- study_status(root)

  expect_equal(check_for(st, "_study.yml")$status, "OK")
  expect_equal(check_for(st, "dataset")$status, "OK")
  expect_equal(check_for(st, "cohort")$status, "OK")
})

test_that("study_status reports FAIL when _study.yml is present but invalid", {
  root <- make_study_fixture(withr::local_tempdir(), omit = "built",
                             write_data = FALSE)
  st   <- study_status(root)

  row <- check_for(st, "_study.yml")
  expect_equal(row$status, "FAIL")
  expect_match(row$detail, "built")
})

test_that("study_status reports MISSING, not FAIL, for checks it cannot run", {
  # dataset and cohort both need a valid _study.yml. A check that could not
  # run is not a check that failed.
  bare <- withr::local_tempdir()
  st   <- study_status(bare)

  expect_equal(check_for(st, "dataset")$status, "MISSING")
  expect_equal(check_for(st, "cohort")$status, "MISSING")
  expect_match(check_for(st, "dataset")$detail, "_study.yml")
})

test_that("study_status reports FAIL when the cohort no longer matches", {
  skip_if_not_installed("haven")
  root <- withr::local_tempdir()
  make_study_fixture(root, n = 20L, n_events = 8L)
  # Rewrite the data with a different event count, leaving the manifest alone.
  make_study_fixture(root, n = 20L, n_events = 9L)
  # make_study_fixture rewrote _study.yml too, so restore the original counts.
  cfg <- yaml::read_yaml(file.path(root, "_study.yml"))
  cfg$cohort$n_events   <- 8L
  cfg$cohort$n_censored <- 12L
  yaml::write_yaml(cfg, file.path(root, "_study.yml"))

  row <- check_for(study_status(root), "cohort")
  expect_equal(row$status, "FAIL")
  expect_match(row$detail, "events=8")
})

test_that("study_status verifies manifest.yaml and reports drift as FAIL", {
  skip_if_not_installed("haven")
  root <- make_study_fixture(withr::local_tempdir())
  built <- file.path(root, "datasets", "built_test.sas7bdat")

  update_manifest(file          = built,
                  manifest_path = file.path(root, "manifest.yaml"),
                  n_rows        = 20L)
  expect_equal(check_for(study_status(root), "manifest.yaml")$status, "OK")

  # Perturb the dataset; the recorded SHA-256 no longer matches.
  make_study_fixture(root, n = 20L, n_events = 9L)
  row <- check_for(study_status(root), "manifest.yaml")
  expect_equal(row$status, "FAIL")
  expect_match(row$detail, "built_test.sas7bdat")
})

test_that("study_status reports renv.lock when present", {
  root <- withr::local_tempdir()
  writeLines('{"R": {"Version": "4.5.1"}}', file.path(root, "renv.lock"))

  expect_equal(check_for(study_status(root), "renv.lock")$status, "OK")
})

test_that("provenance is FAIL when a .qmd source has no sidecar", {
  root <- withr::local_tempdir()
  writeLines("---\ntitle: x\n---", file.path(root, "01.hz.dead_JR.qmd"))

  row <- check_for(study_status(root), "provenance")
  expect_equal(row$status, "FAIL")
  expect_match(row$detail, "01.hz.dead_JR")
})

test_that("provenance is OK when every .qmd source has a matching sidecar", {
  root <- withr::local_tempdir()
  writeLines("---\ntitle: x\n---", file.path(root, "01.hz.dead_JR.qmd"))
  writeLines("{}", file.path(root, "01.hz.dead_JR.provenance.json"))

  expect_equal(check_for(study_status(root), "provenance")$status, "OK")
})

test_that("provenance is MISSING when there are no .qmd sources at all", {
  root <- withr::local_tempdir()
  writeLines("proc means data=x;", file.path(root, "bh.dead_s1.sas"))

  expect_equal(check_for(study_status(root), "provenance")$status, "MISSING")
})

test_that("counts exclude renv/ and count SAS jobs", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "renv", "library", "pkg", "R"), recursive = TRUE)
  writeLines("f <- 1", file.path(root, "renv", "library", "pkg", "R", "a.R"))
  writeLines("g <- 1", file.path(root, "helper.R"))
  writeLines("proc means data=x;", file.path(root, "bh.dead_s1.sas"))

  st <- study_status(root)
  expect_equal(st$counts$r_files, 1L)   # helper.R only, not renv's a.R
  expect_equal(st$counts$sas_jobs, 1L)
})

test_that("study_status errors only when root does not exist", {
  expect_error(study_status(file.path(tempdir(), "no-such-dir-xyz")))
})

test_that("print.study_status returns its argument invisibly", {
  st <- study_status(withr::local_tempdir())

  expect_output(print(st), "_study.yml")
  expect_invisible(print(st))
})
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::test(filter = "study_status")'
```

Expected: FAIL — `could not find function "study_status"` on every test.

- [ ] **Step 4: Write the implementation**

Create `R/study_status.R`:

```r
# The compliance auditor. One read-only function serves both ends of a study's
# life: study_init() calls it to report what a new study still lacks, and
# close-out will call it to grade a publication record. Two near-identical
# scanners would drift.
#
# Every check is reported, never raised. A study with no _study.yml is the
# finding, not a failure -- and the studies that most need describing are
# exactly the ones that would make a strict version error out.

# Directories excluded from every count. A study's renv/ holds a package
# library with thousands of .R files that say nothing about the study, and
# counting them would make the R-file count meaningless. Hidden directories
# (.git, .Rproj.user) are already skipped by list.files().
.status_excluded <- function() {
  c("renv", "packrat", "renv.cache")
}

# Files under `root` matching `pattern`, with excluded directories pruned at
# any depth -- a nested analyses/*/renv/ must be dropped too, not just a
# top-level one.
.status_files <- function(root, pattern) {
  hits <- list.files(root, pattern = pattern, recursive = TRUE,
                     full.names = TRUE)
  if (!length(hits)) return(character(0))
  parts <- strsplit(hits, .Platform$file.sep, fixed = TRUE)
  drop  <- vapply(parts, function(p) any(p %in% .status_excluded()),
                  logical(1))
  hits[!drop]
}

.status_row <- function(item, status, detail) {
  data.frame(item = item, status = status, detail = detail,
             stringsAsFactors = FALSE)
}

# verify_manifest(stop_on_error = FALSE) reports failures through warning()
# and returns the report invisibly. tryCatch() with a warning handler would
# capture the condition and discard the report, so the warning is muffled with
# a calling handler instead and the return value kept.
.status_manifest <- function(root) {
  path <- file.path(root, "manifest.yaml")
  if (!file.exists(path)) {
    return(.status_row("manifest.yaml", "MISSING",
                       "no manifest.yaml; study_init() seeds one"))
  }

  rep <- tryCatch(
    withCallingHandlers(
      verify_manifest(manifest_path = path,
                      data_dir      = file.path(root, "datasets"),
                      stop_on_error = FALSE,
                      verbose       = FALSE),
      warning = function(w) invokeRestart("muffleWarning")),
    error = function(e) e)

  if (inherits(rep, "error")) {
    return(.status_row("manifest.yaml", "FAIL", conditionMessage(rep)))
  }
  if (nrow(rep) == 0L) {
    return(.status_row("manifest.yaml", "MISSING",
                       "manifest.yaml lists no datasets"))
  }

  bad <- rep[rep$status == "FAIL", , drop = FALSE]
  if (nrow(bad)) {
    .status_row("manifest.yaml", "FAIL",
                paste0(nrow(bad), " of ", nrow(rep), " entries failed: ",
                       paste(bad$file, collapse = ", ")))
  } else {
    .status_row("manifest.yaml", "OK",
                paste0(nrow(rep), " dataset entr",
                       if (nrow(rep) == 1L) "y" else "ies", " verified"))
  }
}

# The denominator is .qmd/.Rmd sources, not rendered outputs. A legacy study
# holds decades of .pdf and Word-exported documents that are not analysis
# outputs; counting them would report unrecorded results on every such study
# and teach the reader to ignore this check. provenance_path() strips the
# extension, so a sidecar's stem is its source's stem.
.status_provenance <- function(root) {
  src   <- .status_files(root, "[.](qmd|Rmd)$")
  cars  <- .status_files(root, "[.]provenance[.]json$")
  stems <- sub("[.]provenance$", "",
               tools::file_path_sans_ext(basename(cars)))

  if (!length(src)) {
    return(.status_row("provenance", "MISSING",
                       paste0("no .qmd sources found; ", length(cars),
                              " sidecar", if (length(cars) == 1L) "" else "s")))
  }

  want    <- tools::file_path_sans_ext(basename(src))
  missing <- setdiff(want, stems)

  if (!length(missing)) {
    .status_row("provenance", "OK",
                paste0(length(want), " of ", length(want),
                       " .qmd sources have a provenance sidecar"))
  } else {
    .status_row("provenance", "FAIL",
                paste0(length(missing), " of ", length(want),
                       " .qmd sources have no provenance sidecar: ",
                       paste(missing, collapse = ", ")))
  }
}

#' Audit a study's reproducibility readiness
#'
#' @description
#' Reports, without writing anything, whether a study has the four things a
#' later result needs in order to be re-derivable: a valid \code{_study.yml},
#' an \code{renv.lock}, a \code{manifest.yaml} whose checksums still match the
#' data, and a provenance sidecar for every \code{.qmd} source.
#'
#' Every finding is reported rather than raised. A study with no
#' \code{_study.yml} is the thing this function exists to describe, so it must
#' not error on one. Checks that cannot run because an earlier one failed are
#' reported \code{"MISSING"}, never \code{"FAIL"} — a check that could not run
#' is not a check that failed, and conflating the two makes the audit
#' unreadable on exactly the legacy studies it is most needed for.
#'
#' Unlike \code{\link{study_config}}, this function does \strong{not} walk up
#' the directory tree. It asks whether \code{root} itself is a study root, so
#' that a subdirectory of a study is never mistaken for one.
#'
#' @param root Character. The study root to audit. Defaults to
#'   \code{getwd()}.
#'
#' @return An object of class \code{"study_status"}: a list with \code{root},
#'   \code{checks} (a data frame of \code{item}, \code{status} —
#'   \code{"OK"}, \code{"MISSING"} or \code{"FAIL"} — and \code{detail}, six
#'   rows), and \code{counts} (a list of \code{r_files}, \code{qmd},
#'   \code{sas_jobs} and \code{sidecars}).
#'
#' @seealso \code{\link{study_init}}, \code{\link{study_checklist}}
#'
#' @export
#'
#' @examples
#' root <- file.path(tempdir(), "study-status-example")
#' dir.create(root, showWarnings = FALSE)
#' study_status(root)
#' unlink(root, recursive = TRUE)
study_status <- function(root = getwd()) {
  root <- normalizePath(root, mustWork = TRUE)

  # _study.yml. Checked at root by file.exists() rather than by calling
  # study_config() first, because study_config() walks up: on a subdirectory
  # of a real study it would succeed and report the parent's manifest as this
  # directory's.
  yml <- file.path(root, "_study.yml")
  cfg <- NULL
  if (!file.exists(yml)) {
    row_yml <- .status_row("_study.yml", "MISSING",
                           "no _study.yml at this root; run study_init()")
  } else {
    parsed <- tryCatch(study_config(root), error = function(e) e)
    if (inherits(parsed, "error")) {
      row_yml <- .status_row("_study.yml", "FAIL",
                             conditionMessage(parsed))
    } else {
      cfg <- parsed
      row_yml <- .status_row("_study.yml", "OK",
                             paste0("study: ", cfg$study))
    }
  }

  row_lock <- if (file.exists(file.path(root, "renv.lock"))) {
    .status_row("renv.lock", "OK", "renv.lock present")
  } else {
    .status_row("renv.lock", "MISSING",
                "no renv.lock; run renv::init() in the study project")
  }

  row_man <- .status_manifest(root)

  if (is.null(cfg)) {
    row_data   <- .status_row("dataset", "MISSING",
                              "requires a valid _study.yml")
    row_cohort <- .status_row("cohort", "MISSING",
                              "requires a valid _study.yml")
  } else {
    p <- built_path(cfg)
    if (!file.exists(p)) {
      row_data   <- .status_row("dataset", "MISSING",
                                paste("not found:", p))
      row_cohort <- .status_row("cohort", "MISSING",
                                "requires the built dataset")
    } else {
      row_data <- .status_row("dataset", "OK", basename(p))
      gate <- tryCatch({
        assert_cohort(read_built(cfg), cfg)
        TRUE
      }, error = function(e) conditionMessage(e))
      row_cohort <- if (isTRUE(gate)) {
        .status_row("cohort", "OK",
                    paste0("N=", cfg$cohort$n,
                           " / events=", cfg$cohort$n_events,
                           " / censored=", cfg$cohort$n_censored))
      } else {
        .status_row("cohort", "FAIL", gate)
      }
    }
  }

  out <- list(
    root   = root,
    checks = rbind(row_yml, row_lock, row_man, row_data, row_cohort,
                   .status_provenance(root)),
    counts = list(
      r_files  = length(.status_files(root, "[.]R$")),
      qmd      = length(.status_files(root, "[.](qmd|Rmd)$")),
      sas_jobs = length(.status_files(root, "[.]sas$")),
      sidecars = length(.status_files(root, "[.]provenance[.]json$"))
    )
  )
  class(out) <- "study_status"
  out
}

#' @export
print.study_status <- function(x, ...) {
  mark <- c(OK = "[x]", MISSING = "[ ]", FAIL = "[!]")
  cat("Study: ", x$root, "\n\n", sep = "")
  for (i in seq_len(nrow(x$checks))) {
    cat(mark[[x$checks$status[i]]], " ", x$checks$item[i],
        " — ", x$checks$detail[i], "\n", sep = "")
  }
  cat("\n", x$counts$r_files, " .R  |  ", x$counts$qmd, " .qmd  |  ",
      x$counts$sas_jobs, " .sas  |  ", x$counts$sidecars,
      " provenance sidecars\n", sep = "")
  invisible(x)
}
```

- [ ] **Step 5: Document and run the tests**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::document()' && Rscript -e 'devtools::test(filter = "study_status")'
```

Expected: PASS, all 14 `test_that` blocks green, 0 failures. `NAMESPACE` gains `export(study_status)`
and `S3method(print,study_status)`.

If "study_status verifies manifest.yaml and reports drift as FAIL" fails with
the report coming back empty, the cause is `data_dir`: `update_manifest()`
records only `basename(file)`, so `verify_manifest()` must be pointed at
`<root>/datasets`, not at `<root>`.

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/GitHub/hvtiRutilities && git add R/study_status.R man/study_status.Rd NAMESPACE tests/testthat/test-study_status.R && git commit -m "feat: add study_status() reproducibility audit"
```

---

### Task 2: `study_init()`

**Files:**
- Create: `R/study_init.R`
- Create: `tests/testthat/test-study_init.R`

**Interfaces:**
- Consumes: `study_status()` from Task 1; `built_path()`, `read_built()`,
  `cohort_counts()`, `update_manifest()`.
- Produces:
  - `study_init(root, study, built, event, time, population = NULL,
    source = NULL, extract_date = NULL)` → an object of class
    `"study_status"`, returned **visibly**. Writes `<root>/_study.yml` and
    `<root>/manifest.yaml`.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-study_init.R`:

```r
library(testthat)
library(hvtiRutilities)

# A study root holding a dataset and nothing else. make_study_fixture() writes
# the _study.yml that study_init() is supposed to create, so it is removed.
bare_study <- function(n = 20L, n_events = 8L) {
  root <- withr::local_tempdir(.local_envir = parent.frame())
  make_study_fixture(root, n = n, n_events = n_events)
  file.remove(file.path(root, "_study.yml"))
  root
}

test_that("study_init writes a manifest that study_config accepts", {
  skip_if_not_installed("haven")
  root <- bare_study(n = 20L, n_events = 8L)

  study_init(root, study = "Test", built = "built_test.sas7bdat",
             event = "dead", time = "iv_dead")

  cfg <- study_config(root)               # must not error
  expect_equal(cfg$study, "Test")
  expect_equal(cfg$built, "built_test.sas7bdat")
  expect_equal(cfg$cohort$n, 20L)
  expect_equal(cfg$cohort$n_events, 8L)
  expect_equal(cfg$cohort$n_censored, 12L)
  expect_true(assert_cohort(read_built(cfg), cfg))
})

test_that("study_init derives integer cohort counts, never doubles", {
  skip_if_not_installed("haven")
  root <- bare_study(n = 20L, n_events = 8L)
  study_init(root, study = "Test", built = "built_test.sas7bdat",
             event = "dead", time = "iv_dead")

  cfg <- study_config(root)
  expect_type(cfg$cohort$n, "integer")
  expect_type(cfg$cohort$n_events, "integer")
  expect_type(cfg$cohort$n_censored, "integer")
})

test_that("study_init writes citation as an explicit null", {
  skip_if_not_installed("haven")
  root <- bare_study()
  study_init(root, study = "Test", built = "built_test.sas7bdat",
             event = "dead", time = "iv_dead")

  # The key must be visible in the file, so a future close-out has somewhere
  # obvious to write, and must round-trip as NULL.
  txt <- paste(readLines(file.path(root, "_study.yml")), collapse = "\n")
  expect_match(txt, "citation")
  expect_null(study_config(root)$citation)
})

test_that("study_init seeds manifest.yaml and verify_manifest passes on it", {
  skip_if_not_installed("haven")
  root <- bare_study()
  study_init(root, study = "Test", built = "built_test.sas7bdat",
             event = "dead", time = "iv_dead")

  man <- file.path(root, "manifest.yaml")
  expect_true(file.exists(man))

  rep <- verify_manifest(man, data_dir = file.path(root, "datasets"),
                         stop_on_error = FALSE)
  expect_equal(nrow(rep), 1L)
  expect_equal(rep$status, "OK")
})

test_that("study_init records n_rows without the heavy-rowcount option", {
  skip_if_not_installed("haven")
  # .auto_count_rows() errors on .sas7bdat unless the heavy option is set, so
  # study_init() must pass n_rows explicitly from the frame it already read.
  withr::local_options(manifest.allow_heavy_rowcount = FALSE)
  root <- bare_study(n = 20L)

  # A bare call: if study_init() let update_manifest() auto-count, this would
  # error with "Automatic row counting for SAS files ... is disabled".
  # expect_no_error() is avoided here because it postdates the package's
  # declared testthat floor (>= 3.0.0).
  study_init(root, study = "Test", built = "built_test.sas7bdat",
             event = "dead", time = "iv_dead")

  man <- yaml::read_yaml(file.path(root, "manifest.yaml"))
  expect_equal(man$datasets[[1]]$n_rows, 20L)
})

test_that("study_init defaults extract_date to the dataset's mtime", {
  skip_if_not_installed("haven")
  root <- bare_study()
  built <- file.path(root, "datasets", "built_test.sas7bdat")
  Sys.setFileTime(built, as.POSIXct("2006-05-03 14:03:00", tz = "UTC"))

  study_init(root, study = "Test", built = "built_test.sas7bdat",
             event = "dead", time = "iv_dead")

  man <- yaml::read_yaml(file.path(root, "manifest.yaml"))
  expect_equal(man$datasets[[1]]$extract_date, "2006-05-03")
})

test_that("study_init honours an explicit extract_date and source", {
  skip_if_not_installed("haven")
  root <- bare_study()
  study_init(root, study = "Test", built = "built_test.sas7bdat",
             event = "dead", time = "iv_dead",
             extract_date = "2026-08-17", source = "SAS build, vars.sas")

  man <- yaml::read_yaml(file.path(root, "manifest.yaml"))
  expect_equal(man$datasets[[1]]$extract_date, "2026-08-17")
  expect_equal(man$datasets[[1]]$source, "SAS build, vars.sas")
})

test_that("study_init refuses to overwrite an existing _study.yml", {
  skip_if_not_installed("haven")
  root   <- withr::local_tempdir()
  make_study_fixture(root)
  before <- readLines(file.path(root, "_study.yml"))

  expect_error(
    study_init(root, study = "Other", built = "built_test.sas7bdat",
               event = "dead", time = "iv_dead"),
    "already exists"
  )
  expect_equal(readLines(file.path(root, "_study.yml")), before)
})

test_that("study_init errors when built has no extension, writing nothing", {
  skip_if_not_installed("haven")
  root <- bare_study()

  expect_error(
    study_init(root, study = "Test", built = "built_test",
               event = "dead", time = "iv_dead"),
    "extension"
  )
  expect_false(file.exists(file.path(root, "_study.yml")))
  expect_false(file.exists(file.path(root, "manifest.yaml")))
})

test_that("study_init errors when the dataset is absent, writing nothing", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "datasets"))

  expect_error(
    study_init(root, study = "Test", built = "nope.sas7bdat",
               event = "dead", time = "iv_dead"),
    "missing"
  )
  expect_false(file.exists(file.path(root, "_study.yml")))
})

test_that("study_init errors when event or time names no column", {
  skip_if_not_installed("haven")
  root <- bare_study()

  expect_error(
    study_init(root, study = "Test", built = "built_test.sas7bdat",
               event = "dead", time = "no_such_column"),
    "no_such_column"
  )
  expect_false(file.exists(file.path(root, "_study.yml")))
})

test_that("study_init returns a study_status visibly", {
  skip_if_not_installed("haven")
  root <- bare_study()

  st <- study_init(root, study = "Test", built = "built_test.sas7bdat",
                   event = "dead", time = "iv_dead")

  expect_s3_class(st, "study_status")
  expect_equal(st$checks$status[st$checks$item == "_study.yml"], "OK")
  expect_equal(st$checks$status[st$checks$item == "renv.lock"], "MISSING")
})
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::test(filter = "study_init")'
```

Expected: FAIL — `could not find function "study_init"`.

- [ ] **Step 3: Write the implementation**

Create `R/study_init.R`:

```r
# Study initialization. The pressure to record provenance belongs at a study's
# birth, not at its close: by the time a paper is accepted it is years too late
# to ask for a dataset checksum. This writes the two files that make every
# later record true.
#
# No cohort count is ever supplied by a caller. A number a human types is a
# number that can disagree with the data -- the failure this whole design
# exists to remove -- so the counts are read off the dataset.

#' Initialize a study for reproducible analysis
#'
#' @description
#' Writes a study's \code{_study.yml} identity manifest and seeds a
#' \code{manifest.yaml} pinning the built dataset's SHA-256, so that a result
#' filed years later can name what produced it.
#'
#' The cohort counts are \strong{derived} from the dataset rather than accepted
#' as arguments. Only the study's identity — its title, its dataset filename,
#' and the columns that define the event and the follow-up time — has to be
#' supplied, because none of that can be inferred.
#'
#' \code{renv} is not touched. A missing \code{renv.lock} is reported as an
#' open item by \code{\link{study_status}}; creating one is
#' \code{renv::init()}'s job, and it restarts the R session.
#'
#' @param root Character. The study root to initialize. Must exist and be
#'   writable, and must not already contain a \code{_study.yml}.
#' @param study Character(1). The study title, recorded verbatim.
#' @param built Character(1). Filename of the built dataset within
#'   \code{<root>/datasets}, \strong{with} its extension — the reader
#'   dispatches on it.
#' @param event Character(1). Name of the event-indicator column.
#' @param time Character(1). Name of the follow-up-time column.
#' @param population Character(1) or \code{NULL}. Free-text description of the
#'   cohort. Optional.
#' @param source Character(1) or \code{NULL}. Free-text description of where
#'   the dataset came from, passed to \code{\link{update_manifest}}.
#' @param extract_date Character, \code{Date}, or \code{NULL}. The date the
#'   data were pulled. When \code{NULL} the dataset file's modification date is
#'   used, because recording today's date for a dataset built years ago would
#'   write a false fact into the manifest.
#'
#' @return An object of class \code{"study_status"}, returned visibly, so the
#'   remaining open items are shown at the console.
#'
#' @seealso \code{\link{study_status}}, \code{\link{study_config}},
#'   \code{\link{update_manifest}}
#'
#' @export
#'
#' @examples
#' root <- file.path(tempdir(), "study-init-example")
#' dir.create(file.path(root, "datasets"), recursive = TRUE,
#'            showWarnings = FALSE)
#' write.csv(data.frame(dead = c(1, 0, 0), iv_dead = 1:3),
#'           file.path(root, "datasets", "example.csv"), row.names = FALSE)
#' st <- study_init(root, study = "Example", built = "example.csv",
#'                  event = "dead", time = "iv_dead")
#' study_config(root)$cohort$n
#' unlink(root, recursive = TRUE)
study_init <- function(root, study, built, event, time,
                       population   = NULL,
                       source       = NULL,
                       extract_date = NULL) {
  root <- normalizePath(root, mustWork = TRUE)

  yml <- file.path(root, "_study.yml")
  if (file.exists(yml)) {
    stop("study_init(): ", yml, " already exists. Edit it rather than ",
         "re-initialising: overwriting a study's identity would invalidate ",
         "every provenance sidecar that recorded its checksum.",
         call. = FALSE)
  }

  if (file.access(root, mode = 2L) != 0L) {
    stop("study_init(): the study root is not writable: ", root,
         call. = FALSE)
  }

  if (!nzchar(tools::file_ext(built))) {
    stop("study_init(): built = '", built, "' has no file extension. Give ",
         "the dataset filename in full; the reader dispatches on the ",
         "extension.", call. = FALSE)
  }

  # A synthetic config. study_config() cannot be used here -- it reads the
  # _study.yml this function is about to write -- but neither read_built() nor
  # cohort_counts() needs a validated one: the first uses $root and $built,
  # the second $cohort$event and $cohort$time.
  cfg <- list(root   = root,
              built  = built,
              cohort = list(event = event, time = time))

  p <- built_path(cfg)
  if (!file.exists(p)) {
    stop("study_init(): the built dataset is missing: ", p,
         "\nExpected <study root>/datasets/<built>.", call. = FALSE)
  }

  d  <- read_built(cfg)
  cc <- cohort_counts(d, cfg)   # errors, naming the column, if either is absent

  if (is.null(extract_date)) {
    extract_date <- as.Date(file.info(p)$mtime)
  }

  yaml::write_yaml(
    list(
      study      = study,
      population = population,
      built      = built,
      citation   = NULL,
      cohort     = list(n          = cc$n,
                        n_events   = cc$n_events,
                        n_censored = cc$n_censored,
                        event      = event,
                        time       = time)
    ),
    yml
  )

  # n_rows is passed explicitly: .auto_count_rows() refuses .sas7bdat unless
  # options(manifest.allow_heavy_rowcount = TRUE), and the frame has already
  # been read, so a second full read would be wasted work.
  update_manifest(file          = p,
                  manifest_path = file.path(root, "manifest.yaml"),
                  extract_date  = extract_date,
                  n_rows        = nrow(d),
                  source        = source)

  study_status(root)
}
```

- [ ] **Step 4: Run the tests**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::document()' && Rscript -e 'devtools::test(filter = "study_init")'
```

Expected: PASS, all 12 `test_that` blocks green, 0 failures.

If "writes citation as an explicit null" fails because the key is absent from
the file, check that `list(citation = NULL)` is built inside a single `list()`
call — assigning `NULL` to a list element after construction deletes it
instead of storing it.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/GitHub/hvtiRutilities && git add R/study_init.R man/study_init.Rd NAMESPACE tests/testthat/test-study_init.R && git commit -m "feat: add study_init() to write _study.yml and seed manifest.yaml"
```

---

### Task 3: `study_checklist()`

**Files:**
- Create: `R/study_checklist.R`
- Create: `tests/testthat/test-study_checklist.R`

**Interfaces:**
- Consumes: `study_status()` from Task 1.
- Produces:
  - `study_checklist(status, path = NULL)` → when `path` is `NULL`, a character
    vector of markdown lines; otherwise `invisible(path)` after writing them.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-study_checklist.R`:

```r
library(testthat)
library(hvtiRutilities)

test_that("study_checklist ticks OK items and leaves others open", {
  root <- withr::local_tempdir()
  writeLines('{"R": {"Version": "4.5.1"}}', file.path(root, "renv.lock"))

  md <- study_checklist(study_status(root))

  expect_type(md, "character")
  expect_true(any(grepl("^- \\[x\\] \\*\\*renv.lock\\*\\*", md)))
  expect_true(any(grepl("^- \\[ \\] \\*\\*_study.yml\\*\\*", md)))
})

test_that("study_checklist reports counts", {
  root <- withr::local_tempdir()
  writeLines("proc means data=x;", file.path(root, "bh.dead_s1.sas"))

  md <- study_checklist(study_status(root))
  expect_true(any(grepl("`\\.sas` jobs: 1", md)))
})

test_that("study_checklist names the study root", {
  root <- withr::local_tempdir()
  md   <- study_checklist(study_status(root))
  expect_true(any(grepl(basename(root), md, fixed = TRUE)))
})

test_that("study_checklist writes to path and returns it invisibly", {
  root <- withr::local_tempdir()
  out  <- file.path(root, "CLOSEOUT.md")

  expect_invisible(study_checklist(study_status(root), path = out))
  expect_true(file.exists(out))
  expect_true(any(grepl("Study readiness", readLines(out))))
})

test_that("study_checklist rejects anything that is not a study_status", {
  expect_error(study_checklist(list(root = "x")), "study_status")
})

test_that("study_checklist errors on an unwritable path", {
  skip_on_os("windows")
  root <- withr::local_tempdir()
  bad  <- file.path(root, "no-such-dir", "CLOSEOUT.md")

  expect_error(study_checklist(study_status(root), path = bad),
               "could not write")
})
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::test(filter = "study_checklist")'
```

Expected: FAIL — `could not find function "study_checklist"`.

- [ ] **Step 3: Write the implementation**

Create `R/study_checklist.R`:

```r
# The audit, rendered for a human. Kept separate from study_status() so that
# the audit stays a data structure a caller can act on, rather than a report
# that has to be parsed back.

#' Render a study audit as a markdown checklist
#'
#' @description
#' Turns a \code{\link{study_status}} result into markdown: one checkbox per
#' check, ticked where the check passed and left open otherwise, with the
#' detail alongside. File counts follow.
#'
#' @param status An object of class \code{"study_status"}, from
#'   \code{\link{study_status}} or \code{\link{study_init}}.
#' @param path Character(1) or \code{NULL}. Where to write the markdown. When
#'   \code{NULL} (default) the lines are returned instead of written.
#'
#' @return When \code{path} is \code{NULL}, a character vector of markdown
#'   lines. Otherwise \code{path}, invisibly, after writing.
#'
#' @seealso \code{\link{study_status}}, \code{\link{study_init}}
#'
#' @export
#'
#' @examples
#' root <- file.path(tempdir(), "study-checklist-example")
#' dir.create(root, showWarnings = FALSE)
#' cat(study_checklist(study_status(root)), sep = "\n")
#' unlink(root, recursive = TRUE)
study_checklist <- function(status, path = NULL) {
  if (!inherits(status, "study_status")) {
    stop("study_checklist(): status must be a study_status object, from ",
         "study_status() or study_init().", call. = FALSE)
  }

  boxes <- vapply(
    seq_len(nrow(status$checks)),
    function(i) {
      paste0(if (identical(status$checks$status[i], "OK")) "- [x] " else "- [ ] ",
             "**", status$checks$item[i], "** — ",
             status$checks$detail[i])
    },
    character(1)
  )

  lines <- c(
    "# Study readiness",
    "",
    paste0("Study root: `", status$root, "`"),
    "",
    "## Checks",
    "",
    boxes,
    "",
    "## Counts",
    "",
    paste0("- `.R` files: ", status$counts$r_files),
    paste0("- `.qmd` sources: ", status$counts$qmd),
    paste0("- `.sas` jobs: ", status$counts$sas_jobs),
    paste0("- provenance sidecars: ", status$counts$sidecars)
  )

  if (is.null(path)) return(lines)

  written <- tryCatch({
    writeLines(lines, path)
    TRUE
  }, error = function(e) conditionMessage(e))

  if (!isTRUE(written)) {
    stop("study_checklist(): could not write ", path, ": ", written,
         call. = FALSE)
  }
  invisible(path)
}
```

- [ ] **Step 4: Run the tests**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::document()' && Rscript -e 'devtools::test(filter = "study_checklist")'
```

Expected: PASS, all 6 `test_that` blocks green, 0 failures.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/GitHub/hvtiRutilities && git add R/study_checklist.R man/study_checklist.Rd NAMESPACE tests/testthat/test-study_checklist.R && git commit -m "feat: add study_checklist() markdown renderer"
```

---

### Task 4: Reference index, NEWS, full verification, and the PR

**Files:**
- Modify: `_pkgdown.yml`
- Modify: `DESCRIPTION` (`Version`, `Date`)
- Modify: `NEWS.md`

- [ ] **Step 1: Add the new exports to the pkgdown reference index**

`_pkgdown.yml` has a `Study Manifest and Data Contract` section listing
`study_config` through `assert_cohort`. Insert a new section immediately
**before** it:

```yaml
- title: Study Setup
  desc: Initialize a study for reproducible analysis, and audit whether it is ready
  contents:
  - study_init
  - study_status
  - study_checklist
```

`print.study_status` is deliberately **not** listed. It follows the existing
convention for this package — `print.proc_contents` and
`print.dataset_comparison` carry a bare `#' @export` with no documentation
block, so roxygen registers `S3method()` without generating an `.Rd`, and
there is no topic for pkgdown to index.

- [ ] **Step 2: Bump the version**

Edit `DESCRIPTION`: set `Version: 1.0.8` and `Date:` to the implementation
date.

```bash
cd ~/Documents/GitHub/hvtiRutilities && grep -n '^Version:\|^Date:' DESCRIPTION
```

Expected: `Version: 1.0.8` and today's `Date:`.

- [ ] **Step 3: Write the NEWS entry**

Prepend to `NEWS.md`, above the `# hvtiRutilities 1.0.7` heading. The version
heading must match `DESCRIPTION` exactly — a test greps for it.

```markdown
# hvtiRutilities 1.0.8

## New features

- `study_init()` initializes a study for reproducible analysis: it writes the
  `_study.yml` identity manifest that `study_config()` reads, and seeds a
  `manifest.yaml` pinning the built dataset's SHA-256. The cohort counts are
  derived from the dataset rather than supplied, because a hand-typed count is
  a count that can disagree with the data. `citation` is written as an explicit
  null, so a study that is later published has an obvious place to record its
  reference.

- `study_status()` audits a study without writing anything, reporting whether
  it has a valid `_study.yml`, an `renv.lock`, a `manifest.yaml` whose
  checksums still match, and a provenance sidecar for every `.qmd` source. It
  never errors on an absent or malformed manifest — that is the finding, not a
  failure — and it distinguishes a check that could not run (`MISSING`) from
  one that ran and failed (`FAIL`).

- `study_checklist()` renders a `study_status()` result as a markdown
  checklist, ticked where the study already complies.

## Notes

- No new dependencies.
- `study_init()` does not run `renv::init()`. A missing `renv.lock` is
  reported as an open item instead: creating one restarts the R session and
  rewrites `.Rprofile`, which a function that writes two YAML files has no
  business doing.
```

- [ ] **Step 4: Verify NEWS and DESCRIPTION agree**

```bash
cd ~/Documents/GitHub/hvtiRutilities && grep -m1 '^Version:' DESCRIPTION && head -1 NEWS.md
```

Expected: `Version: 1.0.8` and `# hvtiRutilities 1.0.8`.

- [ ] **Step 5: Run the full test suite and the purity check**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::test()' && Rscript -e 'suppressMessages(pkgload::load_all(".", quiet = TRUE)); stopifnot(length(r_dir_impurities("R")) == 0L); cat("R/ is pure\n")'
```

Expected: 0 failures, 0 warnings. Note the skip count and confirm every skip
is an expected `skip_if_not_installed()` or `skip_on_os()`; a skip is not a
pass. Then `R/ is pure`.

- [ ] **Step 6: Run `R CMD check --as-cran` from a clean export**

Build from `git archive`, not the working tree — an empty `inst/doc`
fabricates two vignette WARNINGs, and in a worktree `.git` is a file that
`R CMD build` fails to exclude, producing a spurious hidden-files NOTE. Keep
the manual build; it is what catches raw Unicode in `.Rd`.

```bash
cd ~/Documents/GitHub/hvtiRutilities && rm -rf /tmp/hvtiRutilities-check && mkdir -p /tmp/hvtiRutilities-check && git archive --format=tar HEAD | tar -x -C /tmp/hvtiRutilities-check && cd /tmp/hvtiRutilities-check && R CMD build . && R CMD check --as-cran hvtiRutilities_1.0.8.tar.gz
```

Expected: **0 errors, 0 warnings.** One NOTE is expected and acceptable:
`checking CRAN incoming feasibility` reports "New submission" for any package
not currently on CRAN, and flags `/issues` and `/blob/main/DESCRIPTION` as
possibly-invalid URLs from environments whose network 404s authenticated
GitHub HTML paths — `https://github.com/tidyverse/dplyr/issues` returns 404
from the same client, so it is not a defect in this package. **Any other NOTE
must be explained or fixed.** Read the per-step `[Ns]` timings and confirm the
overall check time is under 10 minutes.

- [ ] **Step 7: Commit and open the PR**

```bash
cd ~/Documents/GitHub/hvtiRutilities && git add _pkgdown.yml DESCRIPTION NEWS.md && git commit -m "docs: NEWS and reference index for 1.0.8" && git push -u origin feat/study-init
```

```bash
cd ~/Documents/GitHub/hvtiRutilities && gh pr create --title "feat: study_init() and study_status() (Stage 5a)" --body "$(cat <<'EOF'
Study initialization: the pressure to record provenance moved to a study's
birth, where it can still be acted on.

`study_init()` writes the `_study.yml` that `study_config()` reads and seeds a
`manifest.yaml` pinning the built dataset's SHA-256. The cohort counts are
derived from the dataset, never supplied — a hand-typed count is a count that
can disagree with the data, which is the drift this design exists to remove.

`study_status()` audits a study without writing anything and never errors on a
missing manifest, so it is useful today on studies that predate all of this. It
distinguishes a check that could not run (`MISSING`) from one that ran and
failed (`FAIL`).

`study_checklist()` renders the audit as markdown.

`renv::init()` is reported as an open item, not run.

## Verification

- `devtools::test()` — 0 failures, 0 warnings.
- `R CMD check --as-cran` from a clean `git archive` export with the manual
  built — 0 errors, 0 warnings, 1 expected NOTE (CRAN incoming feasibility:
  "New submission" plus environment-specific URL 404s).
- `r_dir_impurities("R")` returns `character(0)`.

Design: `specs/2026-08-17-study-init-design.md`
Plan: `specs/plans/2026-08-17-study-init.md`

Study close-out is deferred; its data model is recorded in the design doc's
Sequencing section so the two halves do not drift.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: a PR URL. Leave it for John to merge.

---

## Self-review against the spec

| Spec requirement | Task |
|---|---|
| `study_status(root)` read-only, works with no `_study.yml` | 1 |
| Six checks: `_study.yml`, `renv.lock`, `manifest.yaml`, `dataset`, `cohort`, `provenance` | 1 |
| Checks that cannot run report `MISSING`, never `FAIL` | 1 |
| Counts reported, no categorical tier label | 1 |
| `study_status()` never errors on absent/malformed `_study.yml` | 1 |
| `study_init()` writes `_study.yml` in the Stage 1 schema | 2 |
| Cohort counts derived, never typed | 2 |
| `citation` written as explicit null | 2 |
| `manifest.yaml` seeded via `update_manifest()`, `n_rows` explicit | 2 |
| The bootstrap problem — synthetic cfg, not `study_config()` | 2 |
| Errors: existing `_study.yml`, no extension, absent dataset, unwritable root | 2 |
| `renv::init()` reported, not run | 2, 4 |
| `study_checklist()` renders ticked/open markdown | 3 |
| Round-trip: everything written passes `study_config()` | 2 (test 1) |
| No study-specific literal in `R/` | 1–3, by construction |
| `r_dir_impurities("R")` empty | 4 |
| `R CMD check` 0 errors / 0 warnings, under 10 min | 4 |
| Version bumped in both `DESCRIPTION` and `NEWS.md` | 4 |

**Spec success criterion 3** — "`study_status()` runs without error on the
`survival` study as it stands today and reports `renv.lock` as its one `OK`" —
is not covered by an automated test, deliberately. It depends on a mounted
network share at a fixed absolute path, so a test asserting it would fail on
any other machine and would embed a study path in the package. Verify it by
hand after merge:

```r
hvtiRutilities::study_status(
  "/Volumes/qhsstudies/cardiac/valves/aortic/replacement/pericardial/lv_function/survival"
)
```

Expected: `renv.lock` `OK`; `_study.yml`, `manifest.yaml`, `dataset`, `cohort`
all `MISSING`; `provenance` `MISSING` or `FAIL` depending on whether the
`R_hazard`/`R_parity` subprojects hold `.qmd` sources. Flagged here rather than
silently dropped.
