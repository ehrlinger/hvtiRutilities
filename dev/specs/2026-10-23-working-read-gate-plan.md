# Working-read gate: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Key the working-read gate on draft or final instead of the job's folder. Make a draft on unregistered data say so in its report, and keep a draft's hand-off out of a final render. Let `bd` name a new study's working file without registering it.

**Architecture:** Two pull requests, in release order. Part A (hvtiRutilities) changes the gate in `.assert_working_stage()`. It makes a read of a declared-but-unregistered dataset write nothing, adds a `working` field to provenance records and adds `declare_data()`. Part B (hvtiRtemplates) turns the working-read condition into a draft mark and a data-table note, refuses a working-data hand-off in a final render, and has `bd` call `declare_data()`.

**Tech Stack:** R, testthat edition 3, withr, yaml. Quarto for the one end-to-end render.

**Design:** `dev/specs/2026-10-23-working-read-gate-design.md` (approved 2026-10-23).

## Global Constraints

- Final is `HVTI_TEMPLATE_STRICT` set to anything but `""`, `"0"`, `"false"` or `"no"` (case-insensitive), exactly as hvtiRtemplates' `.strict_render()` reads it.
- Versions are three digits and patch bumps only. Neither PR edits `Version:` or `NEWS.md`. Each adds `news/<branch-with-dashes>.md` holding its bullets and no heading.
- hvtiRutilities ships first. hvtiRtemplates raises its floor to the hvtiRutilities version that carries Part A (`1.5.12` if no other release lands first: read hvtiRutilities' `DESCRIPTION` on `origin/main` when Part A is tagged, and use that).
- hvtiRtemplates roxygen is Rd markup (`\code{}`), not markdown. Lines up to 135 characters in hvtiRtemplates; check hvtiRutilities' `.lintr` before assuming its width.
- No study, variable value or patient identifier in code, tests or messages.
- Definition of done in each repo: `devtools::document()`, `devtools::test()` passing, `devtools::check()` 0/0/0, `lintr::lint_package()` clean. For hvtiRtemplates, run tests with `NOT_CRAN=true` and read the `SKIP n | PASS` line.
- Run `/code-review` locally before opening each PR and say so in the PR body (Copilot quota is exhausted).
- Never `git add -A` after a test run: failing testthat runs write `tests/testthat/_problems/`.

---

## Part A: hvtiRutilities

Branch `feat/working-read-gate` from `origin/main`.

### Task A1: the gate keys on draft or final

**Files:**
- Modify: `R/working_read.R` (`.assert_working_stage()`, and a new `.final_render()` beside `.is_interactive()`)
- Test: `tests/testthat/test-working_read.R` (replace the two folder-rule tests)

**Interfaces:**
- Produces: `.final_render()`, logical(1). `.assert_working_stage(cfg, built, caller, unregistered, explicit, env)`, same signature, returns `invisible(TRUE)` or stops.

- [ ] **Step 1: Replace the folder-rule tests with the draft/final matrix**

Delete `test_that("the gate allows datasets and descriptive jobs and refuses the rest", ...)` and `test_that("a legacy (bare-name) layout is gated by the same stages", ...)`. Add:

```r
gate_case <- function(cfg, job, rendering, strict) {
  withr::local_envvar(HVTI_TEMPLATE_STRICT = strict)
  local_mocked_bindings(.is_interactive = function() FALSE, .job_file = function() job,
                        .knitr_input = function() if (rendering) job)
  tryCatch(isTRUE(.assert_working_stage(cfg, "built.csv")), error = function(e) conditionMessage(e))
}

test_that("a draft render reads the working file in every stage folder", {
  cfg <- stage_study()
  for (stage in c("datasets", "descriptive", "distributions", "analyses", "graphs")) {
    job <- file.path(study_dir(stage, cfg$root), "job", "job.qmd")
    for (strict in c("", "0", "false", "no", "FALSE")) expect_true(gate_case(cfg, job, TRUE, strict))
  }
})

test_that("a final render reads registered data only, in every stage folder", {
  cfg <- stage_study()
  for (stage in c("datasets", "descriptive", "distributions", "analyses", "graphs")) {
    job <- file.path(study_dir(stage, cfg$root), "job", "job.qmd")
    for (strict in c("1", "true", "yes", "TRUE")) {
      msg <- gate_case(cfg, job, TRUE, strict)
      expect_match(msg, "job.qmd is a final render", fixed = TRUE)
      expect_match(msg, "update_manifest()", fixed = TRUE)
      expect_match(msg, "or render a draft", fixed = TRUE)
    }
  }
})

test_that("an Rscript job is final, wherever it sits", {
  cfg <- stage_study()
  for (stage in c("datasets", "descriptive", "analyses")) {
    job <- file.path(study_dir(stage, cfg$root), "fit.R")
    msg <- gate_case(cfg, job, FALSE, "")
    expect_match(msg, "fit.R runs under Rscript", fixed = TRUE)
    expect_no_match(msg, "render a draft", fixed = TRUE)
  }
})

test_that("a render outside the study or at its root is refused, draft or not", {
  cfg <- stage_study()
  expect_match(gate_case(cfg, file.path(tempdir(), "elsewhere.qmd"), TRUE, ""), "outside the study")
  expect_match(gate_case(cfg, file.path(cfg$root, "top.qmd"), TRUE, ""), "at the study root")
})

test_that("a legacy (bare-name) layout follows the same rule", {
  root <- file.path(withr::local_tempdir(), "study")
  dir.create(file.path(root, "analyses"), recursive = TRUE)
  cfg <- list(root = root)
  expect_true(gate_case(cfg, file.path(root, "analyses", "km.qmd"), TRUE, ""))
  expect_match(gate_case(cfg, file.path(root, "analyses", "km.qmd"), TRUE, "1"), "final render")
})
```

Keep the existing "interactive console is allowed" test and the `.job_file()` tests unchanged.

- [ ] **Step 2: Run, expect failures**

Run: `Rscript -e 'devtools::test(filter = "working_read")'`
Expected: FAIL. The analyses/graphs draft cases are refused ("analyses jobs read registered data only") and the final descriptive cases pass.

- [ ] **Step 3: Rewrite the gate**

In `R/working_read.R`, add below `.knitr_input`:

```r
# A final render, as hvtiRtemplates' render_job(final = TRUE) marks one. Read with
# .strict_render()'s parsing there, so the two packages cannot disagree on a value.
.final_render <- function() !tolower(Sys.getenv("HVTI_TEMPLATE_STRICT")) %in% c("", "0", "false", "no")
```

Replace the body of `.assert_working_stage()` from `allowed <- ...` through the `stop(...)` with:

```r
  rendering <- !is.null(.knitr_input())
  where <- NULL
  if (!is.null(job)) {
    job <- .real_path(job)
    root <- .real_path(cfg$root)
    if (startsWith(job, paste0(root, "/")) || startsWith(job, paste0(root, "\\"))) {
      parts <- strsplit(substring(job, nchar(root) + 2L), "[/\\\\]")[[1L]]
      where <- if (length(parts) > 1L) "stage" else "root"
    }
  }
  # A draft render of a job in a stage folder may read the working file; nothing else may.
  if (identical(where, "stage") && rendering && !.final_render()) return(invisible(TRUE))
  final <- identical(where, "stage") && rendering
  who <- if (is.null(job)) {
    "A non-interactive session with no job file can"
  } else if (is.null(where)) {
    paste0(basename(job), " is outside the study, so it can")
  } else if (identical(where, "root")) {
    paste0(basename(job), " is at the study root, outside any stage folder, so it can")
  } else if (final) {
    paste0(basename(job), " is a final render, so it can")
  } else {
    paste0(basename(job), " runs under Rscript, so it can")
  }
  why <- if (unregistered) {
    paste0(built, " has no dated version")
  } else {
    c(if (explicit) "working = TRUE asks for the working file", if (env) "HVTI_DATA asks for the working file")
  }
  fix <- if (unregistered) {
    c("register it with update_manifest()", if (final) "render a draft")
  } else {
    c(if (explicit) "call read_built() without working = TRUE", if (env) "unset HVTI_DATA")
  }
  stop(caller, "(): ", who, " read registered data only. ", paste(why, collapse = " and "), ". ",
       sub("^(.)", "\\U\\1", paste(fix, collapse = ", or "), perl = TRUE), ".", call. = FALSE)
```

Rewrite the header comment of the file (lines 1-7) to say the gate is honoured in the console and in draft renders of jobs in any stage folder, citing `2026-10-23-working-read-gate-design.md`.

- [ ] **Step 4: Run, expect pass**

Run: `Rscript -e 'devtools::test(filter = "working_read")'`
Expected: PASS, 0 failures.

- [ ] **Step 5: Prove the folder rule is gone, by mutation**

Temporarily put back, before the `rendering <-` line: `if (basename(dirname(job)) %in% c("datasets", "descriptive")) return(invisible(TRUE))`. Run the filter again. Expected: "a final render reads registered data only" FAILS. Remove the line and run again. Expected: PASS.

- [ ] **Step 6: Run the tests that mock the gate elsewhere**

Run: `Rscript -e 'devtools::test(filter = "registered_versions|version_provenance|study_data")'`
Expected: PASS. If a test at `test-registered_versions.R:796`/`:819` or `test-version_provenance.R:262` asserted the folder rule, update its expectation to the draft/final rule. Do not delete it.

- [ ] **Step 7: Commit**

```bash
git add R/working_read.R tests/testthat/test-working_read.R
git commit -m "feat(working-read): gate on draft or final, not the job's folder"
```

### Task A2: a declared, unregistered dataset is read without writing anything

**Files:**
- Modify: `R/study_data.R` (`read_built()`, the `if (working || unregistered)` branch, about line 310)
- Test: `tests/testthat/test-working_read.R`

**Interfaces:**
- Consumes: A1's gate.
- Produces: `read_built()` on a dataset with a `_study.yml` contract and **no manifest entry** returns the data, signals `hvtiRutilities_working_read`, and writes no parquet, schema or manifest.

- [ ] **Step 1: Write the failing test**

```r
test_that("a declared dataset with no manifest entry is read and nothing is written", {
  cfg <- stage_study()
  datasets <- study_dir("datasets", cfg$root)
  utils::write.csv(data.frame(ccfid = 1:3, age = c(50, 60, 70)), file.path(datasets, "built.csv"), row.names = FALSE)
  yml <- yaml::read_yaml(cfg$file)
  yml$built <- "built.csv"
  yaml::write_yaml(yml, cfg$file)
  cfg <- study_config(cfg$root, require_data = FALSE)
  before <- sort(list.files(cfg$root, recursive = TRUE, all.files = TRUE))
  expect_message(d <- read_built(cfg), class = "hvtiRutilities_working_read")
  expect_identical(nrow(d), 3L)
  expect_identical(sort(list.files(cfg$root, recursive = TRUE, all.files = TRUE)), before)
})
```

(The console stand-in in `setup-working-context.R` makes the session interactive, so the gate allows it.)

- [ ] **Step 2: Run, expect failure**

Run: `Rscript -e 'devtools::test(filter = "working_read")'`
Expected: FAIL. The file listing differs: `.cache_read()` wrote `built.parquet`, `built.schema.csv` and `manifest.yaml`.

- [ ] **Step 3: Route an entry-less read through the working read**

In `read_built()`, change `if (working) {` inside the `if (working || unregistered)` branch to:

```r
    # A dataset declared in _study.yml with no manifest entry has nothing registered to cache
    # against: read it as the working file, writing nothing, as an explicit working read does.
    if (working || is.null(entry)) {
```

- [ ] **Step 4: Run, expect pass**

Run: `Rscript -e 'devtools::test(filter = "working_read|study_data|parquet_cache")'`
Expected: PASS. A legacy entry with an unversioned manifest row still takes the cache path, so the `parquet_cache` tests are unchanged.

- [ ] **Step 5: Commit**

```bash
git add R/study_data.R tests/testthat/test-working_read.R
git commit -m "fix(read_built): a declared, unregistered dataset is read without writing a cache"
```

### Task A3: provenance records say when they are a working read

**Files:**
- Modify: `R/provenance.R` (`provenance_data()`, its return about line 446, and its `@return`)
- Test: `tests/testthat/test-provenance.R`

**Interfaces:**
- Produces: `provenance_data(..., working = TRUE)` returns the record with one more element, `working = TRUE`. With `working = FALSE`, the record is exactly as before (no `working` name).

- [ ] **Step 1: Write the failing test**

```r
test_that("a working read's provenance record says so, and a registered one is unchanged", {
  cfg <- stage_study_with_data()   # use the helper this file already uses to register built.csv
  plain <- provenance_data(cfg, working = FALSE)
  expect_false("working" %in% names(plain))
  expect_identical(names(plain), c("dataset", "path", "role", "bytes", "mtime", "sha256"))
  work <- provenance_data(cfg, working = TRUE)
  expect_true(isTRUE(work$working))
  expect_identical(work[names(work) != "working"][c("dataset", "role")], plain[c("dataset", "role")])
})
```

Replace `stage_study_with_data()` with the registering fixture already defined at the top of `test-provenance.R`. Read the file first and use its name.

- [ ] **Step 2: Run, expect failure**

Run: `Rscript -e 'devtools::test(filter = "^provenance$")'`
Expected: FAIL on `isTRUE(work$working)`.

- [ ] **Step 3: Implement**

Change the last expression of `provenance_data()` to:

```r
  c(list(dataset = dataset), snapshot["path"], list(role = role),
    snapshot[c("bytes", "mtime", "sha256")], if (isTRUE(working)) list(working = TRUE))
```

Add to its `@return`: "A working read's record also carries \code{working = TRUE}; a registered read's carries no \code{working} element, so records written before 1.5.12 read the same."

- [ ] **Step 4: Run, expect pass, then commit**

Run: `Rscript -e 'devtools::test(filter = "provenance")'`. Expected: PASS.

```bash
git add R/provenance.R tests/testthat/test-provenance.R
git commit -m "feat(provenance): mark a working read's record working = TRUE"
```

### Task A4: `declare_data()` names the study's working file without registering it

**Files:**
- Create: `R/declare_data.R`
- Create: `tests/testthat/test-declare_data.R`
- Modify: `R/study_data.R` (`read_built()` roxygen `@details`: document `HVTI_TEMPLATE_STRICT`)
- Create: `news/feat-working-read-gate.md`

**Interfaces:**
- Produces: `declare_data(root = getwd(), built, key = NULL)`, exported. It returns `invisible(TRUE)` when it wrote the contract and `invisible(FALSE)` when the same `built` was already declared. It stops when a different `built` is declared. It writes `built:` and, when given, `key:` to `_study.yml` and touches nothing else.

- [ ] **Step 1: Write the failing tests**

```r
declare_fixture <- function(env = parent.frame()) {
  root <- file.path(withr::local_tempdir(.local_envir = env), "study")
  suppressMessages(study_setup(root, "Declare fixture", 7L, renv = FALSE))
  saveRDS(data.frame(ccfid = 1:3), file.path(study_dir("datasets", root), "study_cohort.rds"))
  root
}

test_that("declare_data() writes the contract and registers nothing", {
  root <- declare_fixture()
  expect_true(declare_data(root, built = "study_cohort.rds", key = "ccfid"))
  yml <- yaml::read_yaml(file.path(root, "_study.yml"))
  expect_identical(yml$built, "study_cohort.rds")
  expect_identical(yml$key, "ccfid")
  expect_false(file.exists(file.path(root, "manifest.yaml")) &&
                 length(yaml::read_yaml(file.path(root, "manifest.yaml"))$datasets) > 0L)
})

test_that("declaring the same file again is a no-op, and another file stops", {
  root <- declare_fixture()
  declare_data(root, built = "study_cohort.rds", key = "ccfid")
  expect_false(declare_data(root, built = "study_cohort.rds", key = "ccfid"))
  expect_error(declare_data(root, built = "other.rds"), "already declares study_cohort.rds")
})

test_that("a declared dataset registers its first version through update_manifest()", {
  root <- declare_fixture()
  declare_data(root, built = "study_cohort.rds", key = "ccfid")
  withr::local_dir(root)
  out <- update_manifest(dataset = "study")
  expect_identical(out$action[[1L]], "registered")
})

test_that("declare_data() checks its arguments", {
  root <- declare_fixture()
  expect_error(declare_data(root, built = "no_ext"), "one filename with its extension")
  expect_error(declare_data(root, built = "missing.rds"), "dataset is missing")
  expect_error(declare_data(root, built = "study_cohort.rds", key = NA_character_), "key")
})
```

- [ ] **Step 2: Run, expect failure**

Run: `Rscript -e 'devtools::test(filter = "declare_data")'`
Expected: FAIL, `could not find function "declare_data"`.

- [ ] **Step 3: Implement `R/declare_data.R`**

```r
#' Name a study's working dataset without registering it
#'
#' Writes the study dataset's contract, \code{built:} and \code{key:}, to
#' \code{_study.yml}, and nothing else. The dataset is then known but has no
#' registered version, so every read of it is a working read: allowed in the
#' console and in a draft render, refused in a final one. Register it with
#' \code{\link{update_manifest}()} when it is ready.
#'
#' A new study's first build needs this before any job can read it, because
#' \code{\link{read_built}()} finds the file through the contract. The
#' \code{bd} template calls it on its first render with \code{REGISTER = FALSE}.
#'
#' @param root The study root.
#' @param built The working file's name in the datasets folder, with its extension.
#' @param key Columns that make a row unique, or \code{NULL} to leave
#'   \code{key:} unset.
#' @return \code{TRUE}, invisibly, when the contract was written;
#'   \code{FALSE}, invisibly, when \code{built} was already declared.
#'   Stops when the study already declares a different file.
#' @examples
#' root <- file.path(tempdir(), "declare-example")
#' study_setup(root, "Example", 1L, renv = FALSE)
#' saveRDS(data.frame(ccfid = 1:3), file.path(study_dir("datasets", root), "study_cohort.rds"))
#' declare_data(root, built = "study_cohort.rds", key = "ccfid")
#' unlink(root, recursive = TRUE)
#' @export
declare_data <- function(root = getwd(), built, key = NULL) {
  built <- .study_scalar(built, "built", TRUE, caller = "declare_data")
  if (!identical(basename(built), built) || !nzchar(tools::file_ext(built))) {
    stop("declare_data(): built must be one filename with its extension", call. = FALSE)
  }
  if (!is.null(key) && (!is.character(key) || !length(key) || anyNA(key) || !all(nzchar(key)))) {
    stop("declare_data(): key must be NULL or column names", call. = FALSE)
  }
  cfg <- study_config(root, require_data = FALSE)
  if (!file.exists(file.path(study_dir("datasets", cfg$root), built))) {
    stop("declare_data(): dataset is missing: ", file.path(study_dir("datasets", cfg$root), built), call. = FALSE)
  }
  raw <- .read_study_yml(cfg$file, "declare_data")
  if (!is.null(raw$built)) {
    if (identical(raw$built, built)) return(invisible(FALSE))
    stop("declare_data(): _study.yml already declares ", raw$built, ", not ", built,
         ". A study has one study dataset; change it deliberately in _study.yml.", call. = FALSE)
  }
  raw$built <- built
  if (!is.null(key)) raw$key <- key
  .study_write_atomic(raw, cfg$file)
  invisible(TRUE)
}
```

Add to `read_built()`'s `@details`: "A render counts as final when the environment variable \code{HVTI_TEMPLATE_STRICT} is set to anything but empty, \code{0}, \code{false} or \code{no}, as hvtiRtemplates' \code{render_job(final = TRUE)} sets it. A final render, and a script run with \code{Rscript}, read registered data only. A draft render of a job in any stage folder may read the working file."

- [ ] **Step 4: Document, run, expect pass**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "declare_data|working_read")'`
Expected: PASS. `NAMESPACE` gains `export(declare_data)`. If `_pkgdown.yml` keeps an explicit reference index (hvtiRutilities does), add `declare_data` beside `register_data`.

- [ ] **Step 5: News fragment**

`news/feat-working-read-gate.md`:

```markdown
* The working-read gate keys on draft or final, not on the job's folder. A draft render of a job in any stage folder may read the working file; a final render (`HVTI_TEMPLATE_STRICT` set, as `render_job(final = TRUE)` sets it) and a script run with `Rscript` read registered data only, in every folder. A final descriptive render on an unregistered build now stops and names `update_manifest()`.

* New `declare_data()` names a study's working dataset in `_study.yml` without registering a version, so a new study's first build can be read by a draft. A read of a declared dataset with no manifest entry writes nothing: no parquet cache, no manifest entry.

* `provenance_data(working = TRUE)` records `working = TRUE`; a registered read's record is unchanged.
```

- [ ] **Step 6: Full gate, then commit**

Run: `Rscript -e 'devtools::test()'`, then `Rscript -e 'devtools::check()'` (expect 0/0/0), then `Rscript -e 'lintr::lint_package()'` (expect no lints).

```bash
git add R/declare_data.R R/study_data.R tests/testthat/test-declare_data.R man/ NAMESPACE _pkgdown.yml news/feat-working-read-gate.md
git commit -m "feat: declare_data() names a working dataset without registering it"
```

- [ ] **Step 7: Review and PR**

Run `/code-review`, fix what it finds, then `gh pr create --base main`. The body says the local review stood in for Copilot. **Part B waits until this merges and is tagged.**

---

## Part B: hvtiRtemplates

Branch `feat/working-read-gate` from `origin/main`, after Part A is tagged. Install that hvtiRutilities into the library the tests use.

### Task B1: a working read marks the run a draft and adds a note

**Files:**
- Modify: `R/job-data.R` (`.read_registered()`, about line 1113, and a new `.with_working_read()` beside `.with_out_of_date_notes()`)
- Test: `tests/testthat/test-job-data.R`

**Interfaces:**
- Consumes: hvtiRutilities' `hvtiRutilities_working_read` condition; `.run_mark_draft(reason)` in `R/run-info.R`.
- Produces: `.with_working_read(read)`, which takes and returns the `list(value, record, ...)` shape `.provenance_read()` returns. On a working read it sets `record$working <- TRUE`, prepends a note to `notes`, and calls `.run_mark_draft()`.

- [ ] **Step 1: Write the failing test**

```r
test_that("a working read is a draft, and the data table says so", {
  old <- .run_state$draft_reasons
  withr::defer(.run_state$draft_reasons <- old)
  .run_state$draft_reasons <- character()
  signal <- function() {
    message(structure(class = c("hvtiRutilities_working_read", "message", "condition"),
                      list(message = "Read the working built.rds, not a registered version.\n", call = NULL)))
    list(value = data.frame(ccfid = 1:2), record = list(dataset = "study", path = "datasets/built.rds"))
  }
  read <- .with_out_of_date_notes(.with_working_read(signal()))
  expect_true(isTRUE(read$record$working))
  expect_match(read$notes[[1L]], "**Unregistered data.**", fixed = TRUE)
  expect_match(read$notes[[1L]], "update_manifest()", fixed = TRUE)
  expect_match(.run_state$draft_reasons, "unregistered", fixed = TRUE)
})

test_that("a registered read is left as it was", {
  read <- .with_working_read(list(value = data.frame(ccfid = 1L), record = list(dataset = "study")))
  expect_null(read$record$working)
  expect_null(read$notes)
})
```

- [ ] **Step 2: Run, expect failure**

Run: `NOT_CRAN=true Rscript -e 'devtools::test(filter = "job-data")'`
Expected: FAIL, `could not find function ".with_working_read"`.

- [ ] **Step 3: Implement**

`.with_working_read()` takes a promise, as `.with_out_of_date_notes()` does, so the handler is in place while the read runs:

```r
# A read of the working file, not a registered version, is a draft whatever the render
# was asked to be. hvtiRutilities signals it as hvtiRutilities_working_read. The run is
# marked a draft, so "About this run" opens with the notice. The data table's first note
# says so beside the file read, and the record carries working = TRUE, so a hand-off
# saved from these rows is refused by a final render downstream (.check_handoff_working()).
.with_working_read <- function(read) {
  file <- NULL
  read <- withCallingHandlers(read, hvtiRutilities_working_read = function(m) {
    file <<- sub("^Read the working (.+?), not a registered version.*$", "\\1", trimws(conditionMessage(m)))
    invokeRestart("muffleMessage")
  })
  if (is.null(file)) return(read)
  read$record$working <- TRUE
  read$notes <- c(paste0("**Unregistered data.** This job read the working ", file, ", which has no registered ",
                         "version, so every number here is a draft. Register the build with ",
                         "hvtiRutilities::update_manifest() and render again."), read$notes)
  .run_mark_draft(paste0("it read the working ", file, ", which is unregistered"))
  read
}
```

Change `.read_registered()` to:

```r
.read_registered <- function(dataset, cfg) {
  .with_out_of_date_notes(.with_working_read(.provenance_read(dataset, cfg, function() {
    hvtiRutilities::read_built(cfg = cfg, dataset = dataset)
  })))
}
```

`.with_out_of_date_notes()` assigns `read$notes <- unique(notes)`, which would overwrite the note added inside it. Change its last two lines to keep earlier notes:

```r
  read$notes <- unique(c(read$notes, notes))
  read
```

- [ ] **Step 4: Run, expect pass, then commit**

Run: `NOT_CRAN=true Rscript -e 'devtools::test(filter = "job-data|template-provenance")'`. Expected: PASS.

```bash
git add R/job-data.R tests/testthat/test-job-data.R
git commit -m "feat(read_job_data): a working read marks the run a draft and notes it"
```

### Task B2: a hand-off saved from working data cannot reach a final render

**Files:**
- Modify: `R/provenance.R` (new `.check_handoff_working()`; call it in `.read_handoff()` and `.read_bootstrap_artifact()`)
- Test: `tests/testthat/test-template-provenance.R`

**Interfaces:**
- Consumes: B1's `record$working`; `.strict_render()` in `R/partial-render.R`; `.run_mark_draft()`.
- Produces: `.check_handoff_working(lineage, path, rebuild)`. It stops in a final render when any `lineage$data` record has `working = TRUE`. In a draft it marks the run a draft. It returns `invisible(lineage)`.

- [ ] **Step 1: Write the failing tests**

```r
working_lineage <- function(working) {
  rec <- list(dataset = "study", path = "datasets/built.rds", role = "analysis", bytes = 1, mtime = "t", sha256 = "s")
  if (working) rec$working <- TRUE
  list(data = list(rec), artifacts = list(), analysis = NULL, cohort = NULL)
}

test_that("a final render refuses a hand-off saved from working data", {
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "1")
  expect_error(.check_handoff_working(working_lineage(TRUE), "hz.rds", "the hz job"),
               "hz.rds was saved from the working built.rds")
  expect_error(.check_handoff_working(working_lineage(TRUE), "hz.rds", "the hz job"), "render the hz job again")
})

test_that("a draft reads it and becomes a draft", {
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "")
  old <- .run_state$draft_reasons
  withr::defer(.run_state$draft_reasons <- old)
  .run_state$draft_reasons <- character()
  expect_no_error(.check_handoff_working(working_lineage(TRUE), "hz.rds", "the hz job"))
  expect_match(.run_state$draft_reasons, "hz.rds", fixed = TRUE)
})

test_that("a hand-off with no working field reads as registered, final or not", {
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "1")
  expect_no_error(.check_handoff_working(working_lineage(FALSE), "hz.rds", "the hz job"))
})
```

- [ ] **Step 2: Run, expect failure**

Run: `NOT_CRAN=true Rscript -e 'devtools::test(filter = "template-provenance")'`
Expected: FAIL, `could not find function ".check_handoff_working"`.

- [ ] **Step 3: Implement**

In `R/provenance.R`, after `.validate_handoff_lineage()`:

```r
# A hand-off whose rows came from the working file is a draft's result. A final render must
# not carry it one job removed, so it stops and names the way out: register, then rerender
# upstream. A lineage written before records carried `working` reads as registered (design
# 2026-10-23, section 7.2).
.check_handoff_working <- function(lineage, path, rebuild) {
  working <- Filter(function(r) isTRUE(r$working), lineage$data)
  if (!length(working)) return(invisible(lineage))
  file <- basename(working[[1L]]$path)
  if (.strict_render()) {
    stop(basename(path), " was saved from the working ", file, ", not a registered version. Register the build with ",
         "hvtiRutilities::update_manifest(), render ", rebuild, " again, then render this one.", call. = FALSE)
  }
  .run_mark_draft(paste0("it read ", basename(path), ", which was saved from the unregistered ", file))
  invisible(lineage)
}
```

In `.read_handoff()`, after `lineage <- .validate_handoff_lineage(value, path, rebuild)`, add `.check_handoff_working(lineage, path, rebuild)`. In `.read_bootstrap_artifact()`, after its `.validate_handoff_lineage(...)` line, add `.check_handoff_working(lineage, path, "the bootstrap runner")`.

- [ ] **Step 4: Run, expect pass, then commit**

Run: `NOT_CRAN=true Rscript -e 'devtools::test(filter = "template-provenance|handoff")'`. Expected: PASS.

```bash
git add R/provenance.R tests/testthat/test-template-provenance.R
git commit -m "feat(handoff): refuse a working-data hand-off in a final render"
```

### Task B3: `bd` declares the study's working file on its first render

**Files:**
- Modify: `inst/templates/00_datasets/bd.qmd` (the version guard at about line 58, and the `register` chunk at about line 300)
- Test: `tests/testthat/test-bd-template.R`

**Interfaces:**
- Consumes: hvtiRutilities' `declare_data(root, built, key)`.

- [ ] **Step 1: Write the failing test**

Read `helper-bd.R` for the fixture that renders `bd` on a synthetic study, and use it here (`bd_render()` below stands for that helper; use its real name):

```r
test_that("bd with REGISTER = FALSE declares the working file and registers nothing", {
  skip_on_cran()
  study <- bd_render(register = FALSE)
  yml <- yaml::read_yaml(file.path(study, "_study.yml"))
  expect_identical(yml$built, "study_cohort.rds")
  expect_false(is.null(yml$key))
  manifest <- file.path(study, "manifest.yaml")
  expect_true(!file.exists(manifest) || !length(yaml::read_yaml(manifest)$datasets))
})

test_that("a second bd render keeps the contract, and another DATASET_ID stops", {
  skip_on_cran()
  study <- bd_render(register = FALSE)
  first <- readLines(file.path(study, "_study.yml"))
  bd_render(register = FALSE, study = study)
  expect_identical(readLines(file.path(study, "_study.yml")), first)
  expect_error(bd_render(register = FALSE, study = study, dataset_id = "other_cut"), "registered as study_cohort.rds")
})
```

- [ ] **Step 2: Run, expect failure**

Run: `NOT_CRAN=true Rscript -e 'devtools::test(filter = "bd-template")'`
Expected: FAIL. `yml$built` is NULL after a `REGISTER = FALSE` render.

- [ ] **Step 3: Implement in `bd.qmd`**

Raise the guard to the Part A version (shown here as 1.5.12; use the tagged version):

```r
# Declaring the working file needs declare_data(), from hvtiRutilities 1.5.12.
if (utils::packageVersion("hvtiRutilities") < "1.5.12") {
  .bd_stop("setup", "this job needs hvtiRutilities >= 1.5.12 to declare its working file; ",
           utils::packageVersion("hvtiRutilities"), " is installed.")
}
```

In the `register` chunk, move the "registered under another file" check out of `if (REGISTER) {` so it runs first, for both settings. Then add, before `if (REGISTER) {`:

```r
# A new study's first build is named in _study.yml, with no version registered, so a draft
# job can read it before it is registered (design 2026-10-23, section 7.1). Registering
# stays a separate step: REGISTER = TRUE, or hvtiRutilities::update_manifest().
if (!REGISTER && is.null(.registered$built)) {
  hvtiRutilities::declare_data(.root, built = basename(.built), key = KEY)
  .register_step <- "Declared as the study dataset: nothing registered"
}
```

The `REGISTER = TRUE` path needs no change: once declared, `.registered$built` is set and the chunk calls `update_manifest(dataset = "study")`, which registers a first version (`.register_first_version()`).

- [ ] **Step 4: Run, expect pass**

Run: `NOT_CRAN=true Rscript -e 'devtools::test(filter = "bd")'`
Expected: PASS, the e2e file included. Run the template-catalog tests (`filter = "templates|add-job"`) too, since `bd.qmd` changed.

- [ ] **Step 5: Commit**

```bash
git add inst/templates/00_datasets/bd.qmd tests/testthat/test-bd-template.R
git commit -m "feat(bd): declare the working file on a first render that registers nothing"
```

### Task B4: floor, documentation, end-to-end render, release prep

**Files:**
- Modify: `DESCRIPTION` (`hvtiRutilities (>= 1.5.12)`)
- Modify: `R/render-job.R` (roxygen for `final`)
- Modify: `inst/templates/README.md` and `vignettes/work-a-job.qmd` (a short "Unregistered data" paragraph)
- Create: `news/feat-working-read-gate.md`
- Test: `tests/testthat/test-job-data.R` (end-to-end draft render)

- [ ] **Step 1: End-to-end draft render of `ac` on a declared, unregistered build**

```r
test_that("a draft ac render reads an unregistered build and says so", {
  skip_on_cran()
  skip_if_not(nzchar(Sys.which("quarto")))
  # Use the synthetic-study helper the rf/hazard render tests use. Declare built.rds with
  # hvtiRutilities::declare_data() and do not register it. Scaffold ac with add_job().
  # Render with render_job(final = FALSE) and read the HTML.
  html <- render_unregistered_ac()
  expect_match(html, "Unregistered data.", fixed = TRUE)
  expect_match(html, "This run ended as a draft", fixed = TRUE)
  expect_error(render_unregistered_ac(final = TRUE), "final render")
})
```

Write `render_unregistered_ac(final = FALSE)` in `tests/testthat/helper-setup.R`. Base it on the existing render helper there, using a private library (`R CMD INSTALL -l <lib>` and `R_LIBS`) so a concurrent session's install cannot change the package under the render.

- [ ] **Step 2: Documentation**

`render_job()`'s `@param final`: "Logical. \code{TRUE} for the accepted result. A final render reads registered data only: a job whose data, or whose upstream hand-off, came from an unregistered build stops and names \code{hvtiRutilities::update_manifest()}."

Add to `vignettes/work-a-job.qmd`, under "Render as you go": "A draft may read a build that is not registered yet, and says so in its data table and in 'About this run'. A final render (`render_job(final = TRUE)`) reads registered data only. Register the build with `hvtiRutilities::update_manifest()` first." Add the same two sentences to `inst/templates/README.md` beside "What every report says about its run".

- [ ] **Step 3: News fragment**

`news/feat-working-read-gate.md`:

```markdown
* A job may now read an unregistered build in a draft, in any folder, and its report says so: the data table opens its notes with **Unregistered data**, and "About this run" marks the run a draft. A final render reads registered data only, descriptive jobs included. A final render that reads a hand-off saved from an unregistered build stops and names `hvtiRutilities::update_manifest()`. Needs hvtiRutilities 1.5.12.

* `bd` with `REGISTER = FALSE` now names its working file in `_study.yml` on a study's first build, with no version registered, so draft jobs can read the build before it is registered.
```

- [ ] **Step 4: Full gate**

```bash
NOT_CRAN=true Rscript -e 'devtools::document(); devtools::test()'
```

Expected: the `SKIP n | PASS` line shows no new skips against `main`. Then `Rscript -e 'devtools::check()'` (expect 0/0/0) and `Rscript -e 'lintr::lint_package()'`.

- [ ] **Step 5: Commit, review, PR**

```bash
git add DESCRIPTION R/render-job.R man/ vignettes/work-a-job.qmd inst/templates/README.md tests/testthat/test-job-data.R tests/testthat/helper-setup.R news/feat-working-read-gate.md
git commit -m "feat: drafts may read an unregistered build; a final render may not"
```

Run `/code-review`, fix, then `gh pr create --base main`.

## After both merge

- The gallery's per-template "before you run this" panel (layer 2 of publishing the runbooks) can be built. Its data line is the same for every template: "A draft can run on an unregistered build; a final render needs registered data."
- Update the bio_aggrecan runbook and any other vault runbook that says descriptive jobs read the working file in a final render.
