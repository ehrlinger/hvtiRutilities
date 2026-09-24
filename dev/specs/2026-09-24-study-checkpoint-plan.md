# Study Checkpoints (core) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `study_checkpoint()`, `study_checkpoint_push()`, `study_close()` and `study_reopen()` to hvtiRutilities: an allow-listed snapshot of a study committed and tagged in `.checkpoint/repo/`, recorded in an outbox log, and pushed to any git remote.

**Architecture:** The study folder never becomes a git working tree. Each checkpoint selects files by allow-list and hard deny, copies them into a private clone at `.checkpoint/repo/`, writes `CHECKPOINT.yml`, commits and tags locally, appends an entry to `.checkpoint/log.yml`, then delivers (push) as a separate, retryable step. All git work goes through the system `git` binary so the user's own credential helper handles authentication.

**Tech Stack:** R (>= 4.1), system git, `yaml`, `digest`, `uuid` (new Import), `withr`, testthat edition 3.

**Spec:** `dev/specs/2026-09-24-study-checkpoint-design.md`. Out of scope here: the `qhsprograms` layer (ADO repo creation, ST delivery, CLI commands), which gets its own plan.

## Global Constraints

- Roxygen is **Rd markup, not markdown**: `\code{}`, `\strong{}`, `\emph{}`, `\itemize{}`, `\link{}`. No backticks, `**`, `*` bullets or `[fn()]` in roxygen.
- Every new export goes into `_pkgdown.yml` (pkgdown errors on a missing topic).
- Lines at most 135 characters; `lintr::lint_package()` must be clean. Qualify `testthat::` inside helper **function definitions**.
- `devtools::check()` 0 errors, 0 warnings, 0 notes. Examples that need git run inside `\donttest{}` and `if (nzchar(Sys.which("git")))`, writing only under `tempdir()`.
- No `set.seed()`, no `options()` changes, no writes outside the study root or `tempdir()`.
- Never hand-edit `man/` or `NAMESPACE`; run `devtools::document()`.
- NEWS: add the entry under `# hvtiRutilities (unreleased)` (create the heading if absent). Do **not** change `Version:`.
- ST is "ST" in prose and new identifiers; the existing `_study.yml` key `study_tracker_id` keeps its name.
- Tests needing git call `skip_if_no_git()` and `local_git_env()` (Task 1), so the developer's own git config (signing, hooks) never leaks into tests.
- **Sequencing with PR #146.** #146 (identity_source / identity_verified) merges first. Rebase this branch onto `main` after it; expect text conflicts in `NEWS.md` (both add the unreleased heading: keep one heading, both entries) and `R/study_status.R` (#146 changes the `_study.yml` row; Task 11 appends rows after provenance, so keep both).

## File map

| File | Responsibility |
|---|---|
| `R/checkpoint_git.R` (new) | git runner, repo init, remote sync, tag sequencing, tree sync, commit/tag, rollback |
| `R/checkpoint_kinds.R` (new) | base + live vocabulary, kind validation |
| `R/checkpoint_select.R` (new) | allow-list, hard deny, size cap |
| `R/checkpoint_study.R` (new) | reading identity, remote and include patterns from `_study.yml` |
| `R/checkpoint_log.R` (new) | outbox read / append / write |
| `R/checkpoint_meta.R` (new) | `CHECKPOINT.yml`, manifest check, package versions |
| `R/checkpoint_deliver.R` (new) | push, replay on divergence, retarget and renumber tags |
| `R/study_checkpoint.R` (new) | `study_checkpoint()`, `study_checkpoint_push()`, snapshot transaction, result object |
| `R/study_close.R` (new) | `study_close()`, `study_reopen()`, closure state |
| `inst/checkpoint-kinds.yml` (new) | base vocabulary (API spec section 6 rows) |
| `R/study_status.R` (modify) | checkpoint and closure rows, two new print marks |
| `R/study_setup.R` (modify) | `.checkpoint/` in `.renvignore` |
| `tests/testthat/helper-checkpoint.R` (new) | git env, fixtures, bare remotes |
| `tests/testthat/test-checkpoint_*.R`, `test-study_checkpoint.R`, `test-study_close.R` (new) | tests per unit |
| `DESCRIPTION`, `NEWS.md`, `_pkgdown.yml` (modify) | Import, release note, reference index |

---

### Task 1: Git runner, `uuid` import and test helpers

**Files:**
- Create: `R/checkpoint_git.R`
- Create: `tests/testthat/helper-checkpoint.R`
- Create: `tests/testthat/test-checkpoint_git.R`
- Modify: `DESCRIPTION` (Imports)

**Interfaces:**
- Produces: `.cp_or(x, y)`; `.cp_git(repo, args)` returning `list(ok = logical(1), out = character())`, never raising; `.cp_git_do(repo, args)` returning `character()` or raising `"git <args> failed:\n<output>"`; `.cp_require_git(caller)`.
- Produces (tests): `skip_if_no_git()`, `local_git_env(.env)`, `plant_files(root, paths, text = "x")`, `set_study_keys(root, ...)`, `make_checkpoint_study(dir)`, `make_bare_remote(dir, name)`, `git_out(repo, args)`.

- [ ] **Step 1: Add `uuid` to Imports**

In `DESCRIPTION`, add `uuid,` to `Imports:` after `utils,`, keeping alphabetical order:

```
    utils,
    uuid,
    withr,
```

Run: `Rscript -e 'install.packages("uuid")'` if it is not installed.

- [ ] **Step 2: Write the test helpers**

Create `tests/testthat/helper-checkpoint.R`:

```r
# Fixtures for the checkpoint tests. Every git-using test calls
# skip_if_no_git() and local_git_env(): the second points git at an empty
# global config so a developer's signing, hooks or default branch cannot
# change the result, and supplies an author identity.

skip_if_no_git <- function() {
  testthat::skip_if_not(nzchar(Sys.which("git")), "git is not available")
}

local_git_env <- function(.env = parent.frame()) {
  cfg <- withr::local_tempfile(.local_envir = .env)
  file.create(cfg)
  withr::local_envvar(
    c(GIT_CONFIG_GLOBAL = cfg,
      GIT_CONFIG_NOSYSTEM = "1",
      GIT_AUTHOR_NAME = "Test Analyst",
      GIT_AUTHOR_EMAIL = "analyst@example.org",
      GIT_COMMITTER_NAME = "Test Analyst",
      GIT_COMMITTER_EMAIL = "analyst@example.org"),
    .local_envir = .env
  )
}

plant_files <- function(root, paths, text = "x") {
  for (p in paths) {
    dest <- file.path(root, p)
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    writeLines(text, dest)
  }
  invisible(paths)
}

set_study_keys <- function(root, ...) {
  path <- file.path(root, "_study.yml")
  cfg <- yaml::read_yaml(path)
  keys <- list(...)
  for (k in names(keys)) cfg[[k]] <- keys[[k]]
  yaml::write_yaml(cfg, path)
  invisible(cfg)
}

make_checkpoint_study <- function(dir) {
  root <- file.path(dir, "study")
  study_setup(root, "Checkpoint fixture", 1267L)
  plant_files(root, c("30_analyses/fit.R", "renv.lock"))
  root
}

make_bare_remote <- function(dir, name = "remote.git") {
  bare <- file.path(dir, name)
  system2("git", shQuote(c("init", "--bare", "-q", bare)))
  bare
}

git_out <- function(repo, args) {
  suppressWarnings(system2("git", shQuote(c("-C", repo, args)),
                           stdout = TRUE, stderr = TRUE))
}
```

- [ ] **Step 3: Write the failing tests**

Create `tests/testthat/test-checkpoint_git.R`:

```r
test_that(".cp_git reports success without raising", {
  skip_if_no_git()
  local_git_env()
  repo <- withr::local_tempdir()
  res <- .cp_git(repo, c("init", "-q"))
  expect_true(res$ok)
  expect_true(dir.exists(file.path(repo, ".git")))
})

test_that(".cp_git reports failure without raising", {
  skip_if_no_git()
  local_git_env()
  repo <- withr::local_tempdir()
  .cp_git(repo, c("init", "-q"))
  res <- .cp_git(repo, c("rev-parse", "--verify", "HEAD"))
  expect_false(res$ok)
})

test_that(".cp_git_do raises with the command and git's output", {
  skip_if_no_git()
  local_git_env()
  repo <- withr::local_tempdir()
  .cp_git(repo, c("init", "-q"))
  expect_error(.cp_git_do(repo, c("rev-parse", "--verify", "HEAD")),
               "git rev-parse --verify HEAD failed")
})

test_that(".cp_or returns the fallback only for NULL", {
  expect_equal(.cp_or(NULL, 2), 2)
  expect_equal(.cp_or(1, 2), 1)
  expect_false(.cp_or(FALSE, TRUE))
})
```

- [ ] **Step 4: Run to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "checkpoint_git")'`
Expected: FAIL, `could not find function ".cp_git"`.

- [ ] **Step 5: Implement the runner**

Create `R/checkpoint_git.R`:

```r
# Git plumbing for study checkpoints. Every call goes through the system git
# binary, so the user's own configuration (Git Credential Manager on the LRI
# server) handles authentication and the package holds no credentials.

.cp_or <- function(x, y) if (is.null(x)) y else x

# Run git in `repo`. Returns list(ok, out) and never raises, so callers can
# treat an unreachable remote as a state rather than an error.
.cp_git <- function(repo, args) {
  out <- suppressWarnings(system2(
    "git", shQuote(c("-C", repo, args)), stdout = TRUE, stderr = TRUE
  ))
  status <- attr(out, "status")
  list(ok = is.null(status) || identical(as.integer(status), 0L),
       out = as.character(out))
}

# Run git in `repo` and raise on failure, naming the command and git's output.
.cp_git_do <- function(repo, args) {
  res <- .cp_git(repo, args)
  if (!res$ok) {
    stop("git ", paste(args, collapse = " "), " failed:\n",
         paste(res$out, collapse = "\n"), call. = FALSE)
  }
  res$out
}

.cp_require_git <- function(caller) {
  if (!nzchar(Sys.which("git"))) {
    stop(caller, "(): git is not installed or not on the PATH",
         call. = FALSE)
  }
  invisible(TRUE)
}
```

- [ ] **Step 6: Run to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "checkpoint_git")'`
Expected: PASS (4 tests).

- [ ] **Step 7: Commit**

```bash
git add DESCRIPTION R/checkpoint_git.R tests/testthat/helper-checkpoint.R tests/testthat/test-checkpoint_git.R
git commit -m "feat: git runner and test fixtures for study checkpoints"
```

---

### Task 2: Checkpoint vocabulary

**Files:**
- Create: `inst/checkpoint-kinds.yml`
- Create: `R/checkpoint_kinds.R`
- Create: `tests/testthat/test-checkpoint_kinds.R`

**Interfaces:**
- Consumes: `.cp_or()` (Task 1).
- Produces: `.cp_kinds(root)` returning a data.frame with columns `kind` (chr), `trigger` (`"manual"` or `"auto"`), `numbered` (lgl), `retired` (lgl); `.cp_kind_check(kinds, kind, caller)` returning the one-row data.frame or raising.

- [ ] **Step 1: Write the base vocabulary**

Create `inst/checkpoint-kinds.yml`:

```yaml
# Base checkpoint vocabulary: the initial lk_checkpoint_kinds rows of the
# StudyTracker Workspace API spec, section 6. The live table, cached by
# qhsprograms in <study>/.checkpoint/kinds.yml, overrides these rows by kind.
- {kind: workspace_created, label: Workspace created, task_type: null, task_status: null, trigger: manual, numbered: false, retired: false}
- {kind: data_request_submitted, label: Data request submitted, task_type: Data Request, task_status: in progress, trigger: manual, numbered: true, retired: false}
- {kind: data_received, label: Data received, task_type: Data Request, task_status: complete, trigger: auto, numbered: true, retired: false}
- {kind: analysis_dataset_frozen, label: Analysis dataset frozen, task_type: Analysis Dataset, task_status: complete, trigger: auto, numbered: true, retired: false}
- {kind: analysis_started, label: Analysis started, task_type: Data Analysis, task_status: in progress, trigger: auto, numbered: true, retired: false}
- {kind: abstract_submitted, label: Abstract submitted, task_type: Presentation, task_status: in progress, trigger: manual, numbered: true, retired: false}
- {kind: abstract_accepted, label: Abstract accepted, task_type: Presentation, task_status: complete, trigger: manual, numbered: true, retired: false}
- {kind: manuscript_submitted, label: Manuscript submitted, task_type: Manuscript, task_status: in progress, trigger: manual, numbered: true, retired: false}
- {kind: manuscript_rejected, label: Manuscript rejected, task_type: Manuscript, task_status: in progress, trigger: manual, numbered: true, retired: false}
- {kind: revision_submitted, label: Revision submitted, task_type: Manuscript, task_status: in progress, trigger: manual, numbered: true, retired: false}
- {kind: manuscript_accepted, label: Manuscript accepted, task_type: Manuscript, task_status: in progress, trigger: manual, numbered: true, retired: false}
- {kind: manuscript_published, label: Manuscript published, task_type: Manuscript, task_status: complete, trigger: manual, numbered: true, retired: false}
```

- [ ] **Step 2: Write the failing tests**

Create `tests/testthat/test-checkpoint_kinds.R`:

```r
test_that("the base vocabulary has the twelve API rows", {
  root <- withr::local_tempdir()
  kinds <- .cp_kinds(root)
  expect_equal(nrow(kinds), 12L)
  expect_true(all(c("workspace_created", "manuscript_submitted",
                    "manuscript_published") %in% kinds$kind))
  expect_false(kinds$numbered[kinds$kind == "workspace_created"])
  expect_equal(kinds$trigger[kinds$kind == "data_received"], "auto")
})

test_that("an unknown kind errors and lists the valid kinds", {
  root <- withr::local_tempdir()
  expect_error(.cp_kind_check(.cp_kinds(root), "manuscript", "study_checkpoint"),
               "unknown checkpoint kind 'manuscript'.*manuscript_submitted")
})

test_that("the live cache adds kinds and overrides base rows", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, ".checkpoint"))
  yaml::write_yaml(
    list(list(kind = "adhoc", trigger = "manual"),
         list(kind = "abstract_accepted", retired = TRUE)),
    file.path(root, ".checkpoint", "kinds.yml")
  )
  kinds <- .cp_kinds(root)
  expect_true("adhoc" %in% kinds$kind)
  expect_equal(nrow(.cp_kind_check(kinds, "adhoc", "f")), 1L)
  expect_error(.cp_kind_check(kinds, "abstract_accepted", "f"), "is retired")
})
```

- [ ] **Step 3: Run to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "checkpoint_kinds")'`
Expected: FAIL, `could not find function ".cp_kinds"`.

- [ ] **Step 4: Implement**

Create `R/checkpoint_kinds.R`:

```r
# The checkpoint vocabulary. The package ships the StudyTracker Workspace
# API's initial rows; qhsprograms caches the live, administrator-owned table
# in .checkpoint/kinds.yml, and a live row replaces a base row of the same
# kind. There are no study-level kinds: extension happens in the ST table.

.cp_kinds <- function(root) {
  base <- yaml::read_yaml(system.file("checkpoint-kinds.yml",
                                      package = "hvtiRutilities",
                                      mustWork = TRUE))
  live_path <- file.path(root, ".checkpoint", "kinds.yml")
  live <- if (file.exists(live_path)) yaml::read_yaml(live_path) else list()
  rows <- c(base, .cp_or(live, list()))
  ids <- vapply(rows, function(r) as.character(r$kind), character(1))
  rows <- rows[!duplicated(ids, fromLast = TRUE)]
  data.frame(
    kind = vapply(rows, function(r) as.character(r$kind), character(1)),
    trigger = vapply(rows, function(r) as.character(.cp_or(r$trigger, "manual")),
                     character(1)),
    numbered = vapply(rows, function(r) !isFALSE(r$numbered), logical(1)),
    retired = vapply(rows, function(r) isTRUE(r$retired), logical(1)),
    stringsAsFactors = FALSE
  )
}

.cp_kind_check <- function(kinds, kind, caller) {
  if (length(kind) != 1L || is.na(kind) || !kind %in% kinds$kind) {
    stop(caller, "(): unknown checkpoint kind '", paste(kind, collapse = ", "),
         "'. Valid kinds: ",
         paste(kinds$kind[!kinds$retired], collapse = ", "),
         call. = FALSE)
  }
  row <- kinds[kinds$kind == kind, , drop = FALSE]
  if (row$retired) {
    stop(caller, "(): checkpoint kind '", kind, "' is retired and cannot ",
         "be used for a new checkpoint", call. = FALSE)
  }
  row
}
```

- [ ] **Step 5: Run to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "checkpoint_kinds")'`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add inst/checkpoint-kinds.yml R/checkpoint_kinds.R tests/testthat/test-checkpoint_kinds.R
git commit -m "feat: checkpoint vocabulary from the ST Workspace API kinds"
```

---

### Task 3: File selection (allow-list, hard deny, size cap)

**Files:**
- Create: `R/checkpoint_select.R`
- Create: `tests/testthat/test-checkpoint_select.R`

**Interfaces:**
- Produces: `.cp_select(root, include = character(0), max_bytes = 50 * 1024^2)` returning `list(files = character(), skipped = data.frame(path, bytes), denied = c(data_folder =, data_extension =, output_extension =))` (integer counts).

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-checkpoint_select.R`:

```r
allowed <- c(
  "_study.yml", "renv.lock", "renv/activate.R", ".Rprofile", "manifest.yaml",
  "study.Rproj", "_quarto.yml", "30_analyses/fit.R", "30_analyses/report.qmd",
  "30_analyses/old.Rmd", "10_descriptive/desc.sas", "30_analyses/run.sh",
  "30_analyses/q.sql", "30_analyses/x.py", "50_documents/manuscript.docx",
  "50_documents/slides.pptx", "50_documents/submitted.pdf",
  "50_documents/refs.bib", "50_documents/fig1.png", "50_documents/fig2.tiff",
  "50_documents/paper.qmd"
)
denied_folder <- c("00_datasets/built.sas7bdat", "00_datasets/notes.R",
                   "90_estimates/fit.R")
denied_data <- c("30_analyses/cohort.csv", "30_analyses/out.rds",
                 "10_descriptive/desc.lst", "10_descriptive/desc.log",
                 "50_documents/supplement.xlsx", "50_documents/table.csv")
denied_output <- c("30_analyses/report.html", "30_analyses/report.pdf",
                   "40_graphs/fig.png", "30_analyses/draft.docx")
tooling <- c("renv/library/pkg/R/pkg.R", ".checkpoint/log.yml")

test_that("selection keeps exactly the allow-list and never a denied file", {
  root <- withr::local_tempdir()
  plant_files(root, c(allowed, denied_folder, denied_data, denied_output,
                      tooling, "30_analyses/notes.txt"))
  sel <- .cp_select(root, include = "**/*.csv")
  expect_setequal(sel$files, allowed)
  expect_equal(sel$denied[["data_folder"]], 3L)
  expect_equal(sel$denied[["data_extension"]], 6L)
  expect_equal(sel$denied[["output_extension"]], 4L)
})

test_that("include patterns admit extra files but cannot admit data", {
  root <- withr::local_tempdir()
  plant_files(root, c("30_analyses/notes.txt", "30_analyses/cohort.csv",
                      "00_datasets/extra.txt"))
  sel <- .cp_select(root, include = c("*.txt", "*.csv"))
  expect_equal(sel$files, "30_analyses/notes.txt")
})

test_that("legacy folder spellings get the same rules", {
  root <- withr::local_tempdir()
  plant_files(root, c("datasets/built.csv", "estimates/fit.R",
                      "documents/manuscript.docx", "analyses/fit.R"))
  sel <- .cp_select(root)
  expect_setequal(sel$files, c("documents/manuscript.docx", "analyses/fit.R"))
  expect_equal(sel$denied[["data_folder"]], 2L)
})

test_that("files over the size cap are skipped and reported", {
  root <- withr::local_tempdir()
  plant_files(root, "30_analyses/big.R", text = strrep("x", 200))
  plant_files(root, "30_analyses/small.R")
  sel <- .cp_select(root, max_bytes = 100)
  expect_equal(sel$files, "30_analyses/small.R")
  expect_equal(sel$skipped$path, "30_analyses/big.R")
})
```

- [ ] **Step 2: Run to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "checkpoint_select")'`
Expected: FAIL, `could not find function ".cp_select"`.

- [ ] **Step 3: Implement**

Create `R/checkpoint_select.R`:

```r
# Which study files a checkpoint may commit. Three passes: a hard deny that no
# configuration can override, then the allow-list, then a size cap. Denied
# files are counted per rule but never named, because dataset filenames can
# carry cohort-identifying fragments.

.cp_code_ext <- function() c("r", "rmd", "qmd", "sas", "sh", "py", "sql", "rproj")
.cp_doc_ext  <- function() c("docx", "pptx", "pdf", "qmd", "bib", "png", "tiff")
.cp_data_ext <- function() {
  c("sas7bdat", "xpt", "parquet", "rds", "rdata", "csv", "xlsx", "xls",
    "lst", "log")
}
.cp_output_ext <- function() c("html", "pdf", "docx", "pptx", "png", "tiff")
.cp_always <- function() {
  c("_study.yml", "renv.lock", "renv/activate.R", ".Rprofile",
    "manifest.yaml", "_quarto.yml")
}
.cp_data_dirs <- function() c("00_datasets", "datasets", "90_estimates", "estimates")
.cp_doc_dirs  <- function() c("50_documents", "documents")

# The deny rule a relative path hits, or NA. "tooling" covers the package's
# own and renv's directories and is not counted.
.cp_deny_rule <- function(rel) {
  parts <- strsplit(rel, "/", fixed = TRUE)[[1]]
  ext <- tolower(tools::file_ext(rel))
  n <- length(parts)
  in_renv_lib <- n >= 2L && any(parts[-n] == "renv" & parts[-1] == "library")
  if (parts[1] %in% c(".checkpoint", ".git") || ".git" %in% parts ||
        in_renv_lib) {
    return("tooling")
  }
  if (parts[1] %in% .cp_data_dirs()) return("data_folder")
  if (ext %in% .cp_data_ext()) return("data_extension")
  if (!parts[1] %in% .cp_doc_dirs() && ext %in% .cp_output_ext()) {
    return("output_extension")
  }
  NA_character_
}

# A pattern without "/" matches the file name; one with "/" matches the whole
# relative path, with "*" free to cross directories.
.cp_included <- function(rel, include) {
  for (p in include) {
    target <- if (grepl("/", p, fixed = TRUE)) rel else basename(rel)
    if (grepl(utils::glob2rx(p), target)) return(TRUE)
  }
  FALSE
}

.cp_allowed <- function(rel, include) {
  top <- strsplit(rel, "/", fixed = TRUE)[[1]][1]
  ext <- tolower(tools::file_ext(rel))
  rel %in% .cp_always() ||
    ext %in% .cp_code_ext() ||
    (top %in% .cp_doc_dirs() && ext %in% .cp_doc_ext()) ||
    .cp_included(rel, include)
}

.cp_select <- function(root, include = character(0), max_bytes = 50 * 1024^2) {
  rel <- list.files(root, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  rules <- vapply(rel, .cp_deny_rule, character(1), USE.NAMES = FALSE)
  ok <- vapply(rel, .cp_allowed, logical(1), include = include,
               USE.NAMES = FALSE)
  cand <- rel[is.na(rules) & ok]
  bytes <- file.size(file.path(root, cand))
  big <- bytes > max_bytes
  counted <- factor(rules[!is.na(rules) & rules != "tooling"],
                    levels = c("data_folder", "data_extension",
                               "output_extension"))
  tab <- table(counted)
  list(
    files = sort(cand[!big]),
    skipped = data.frame(path = cand[big], bytes = bytes[big],
                         stringsAsFactors = FALSE),
    denied = structure(as.integer(tab), names = names(tab))
  )
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "checkpoint_select")'`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add R/checkpoint_select.R tests/testthat/test-checkpoint_select.R
git commit -m "feat: allow-list and hard deny for checkpoint snapshots"
```

---

### Task 4: Reading the study for a checkpoint

**Files:**
- Create: `R/checkpoint_study.R`
- Create: `tests/testthat/test-checkpoint_study.R`

**Interfaces:**
- Consumes: `.cp_or()`.
- Produces: `.cp_study(root, caller)` returning `list(root, st_id = integer(1), workspace_id = chr or NULL, verified = logical(1), remote = chr or NULL, include = character())`.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-checkpoint_study.R`:

```r
test_that("st_id falls back to study_tracker_id", {
  root <- withr::local_tempdir()
  yaml::write_yaml(list(study = "S", study_tracker_id = 1267L),
                   file.path(root, "_study.yml"))
  s <- .cp_study(root, "f")
  expect_identical(s$st_id, 1267L)
  expect_null(s$workspace_id)
  expect_true(s$verified)
  expect_null(s$remote)
  expect_identical(s$include, character(0))
})

test_that("st_id wins, and checkpoint keys and verification are read", {
  root <- withr::local_tempdir()
  yaml::write_yaml(
    list(st_id = 42L, study_tracker_id = 1L, workspace_id = "ws-1",
         identity_verified = FALSE,
         checkpoint = list(remote = "https://example.org/r.git",
                           include = list("*.txt"))),
    file.path(root, "_study.yml")
  )
  s <- .cp_study(root, "f")
  expect_identical(s$st_id, 42L)
  expect_equal(s$workspace_id, "ws-1")
  expect_false(s$verified)
  expect_equal(s$remote, "https://example.org/r.git")
  expect_equal(s$include, "*.txt")
})

test_that("a missing _study.yml or ST number is an error", {
  root <- withr::local_tempdir()
  expect_error(.cp_study(root, "study_checkpoint"), "no _study.yml")
  yaml::write_yaml(list(study = "S"), file.path(root, "_study.yml"))
  expect_error(.cp_study(root, "study_checkpoint"), "no valid st_id")
})
```

- [ ] **Step 2: Run to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "checkpoint_study")'`
Expected: FAIL, `could not find function ".cp_study"`.

- [ ] **Step 3: Implement**

Create `R/checkpoint_study.R`:

```r
# The _study.yml keys a checkpoint needs. The key names are not settled (spec
# open item 1): read st_id, falling back to study_tracker_id, and treat an
# absent workspace_id as NULL. An absent identity_verified counts as verified,
# which is how every study written before PR #146 reads.

.cp_study <- function(root, caller) {
  yml <- file.path(root, "_study.yml")
  if (!file.exists(yml)) {
    stop(caller, "(): no _study.yml at ", root, "; run study_setup() first",
         call. = FALSE)
  }
  raw <- yaml::read_yaml(yml)
  st <- suppressWarnings(as.integer(.cp_or(raw$st_id, raw$study_tracker_id)))
  if (length(st) != 1L || is.na(st) || st < 1L) {
    stop(caller, "(): _study.yml has no valid st_id or study_tracker_id",
         call. = FALSE)
  }
  cp <- .cp_or(raw$checkpoint, list())
  list(
    root = root,
    st_id = st,
    workspace_id = raw$workspace_id,
    verified = !isFALSE(raw$identity_verified),
    remote = cp$remote,
    include = as.character(unlist(cp$include))
  )
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "checkpoint_study")'`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add R/checkpoint_study.R tests/testthat/test-checkpoint_study.R
git commit -m "feat: read checkpoint identity and settings from _study.yml"
```

---

### Task 5: The outbox log

**Files:**
- Create: `R/checkpoint_log.R`
- Create: `tests/testthat/test-checkpoint_log.R`

**Interfaces:**
- Consumes: `.atomic_write(target, write_fn)` (existing, `R/parquet_cache.R`).
- Produces: `.cp_log_path(root)`; `.cp_log_read(root)` returning a list of entries (empty list when absent); `.cp_log_write(root, log)`; `.cp_log_append(root, entry)`; `.cp_entry_id(entry)`; `.cp_date(x)` returning `"YYYY-MM-DD"`.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-checkpoint_log.R`:

```r
test_that("an absent log reads as empty", {
  root <- withr::local_tempdir()
  expect_identical(.cp_log_read(root), list())
})

test_that("entries append in order and round-trip, NULLs included", {
  root <- withr::local_tempdir()
  .cp_log_append(root, list(type = "checkpoint", checkpoint_id = "a",
                            note = NULL, delivery = list(git = "pending")))
  .cp_log_append(root, list(type = "closure", closure_id = "b",
                            delivery = list(git = "pending")))
  log <- .cp_log_read(root)
  expect_length(log, 2L)
  expect_equal(vapply(log, .cp_entry_id, character(1)), c("a", "b"))
  expect_true("note" %in% names(log[[1]]))
  expect_equal(log[[1]]$delivery$git, "pending")
})

test_that(".cp_date formats dates and date strings", {
  expect_equal(.cp_date(as.Date("2026-09-24")), "2026-09-24")
  expect_equal(.cp_date("2026-10-02"), "2026-10-02")
})
```

- [ ] **Step 2: Run to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "checkpoint_log")'`
Expected: FAIL, `could not find function ".cp_log_read"`.

- [ ] **Step 3: Implement**

Create `R/checkpoint_log.R`:

```r
# The outbox: .checkpoint/log.yml, one entry per checkpoint, closure or
# reopening, in the StudyTracker Workspace API's record shapes so qhsprograms
# can post an entry unchanged. The core marks git delivery; qhsprograms marks
# ST delivery. Entries are appended, and only their delivery fields change.

.cp_log_path <- function(root) file.path(root, ".checkpoint", "log.yml")

.cp_log_read <- function(root) {
  path <- .cp_log_path(root)
  if (!file.exists(path)) return(list())
  .cp_or(yaml::read_yaml(path), list())
}

.cp_log_write <- function(root, log) {
  path <- .cp_log_path(root)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  .atomic_write(path, function(tmp) yaml::write_yaml(log, tmp))
  invisible(log)
}

.cp_log_append <- function(root, entry) {
  .cp_log_write(root, c(.cp_log_read(root), list(entry)))
  invisible(entry)
}

.cp_entry_id <- function(entry) {
  .cp_or(entry$checkpoint_id, .cp_or(entry$closure_id, entry$reopening_id))
}

.cp_date <- function(x) format(as.Date(x), "%Y-%m-%d")
```

- [ ] **Step 4: Run to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "checkpoint_log")'`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add R/checkpoint_log.R tests/testthat/test-checkpoint_log.R
git commit -m "feat: checkpoint outbox log"
```

---

### Task 6: The local checkpoint repository

**Files:**
- Modify: `R/checkpoint_git.R` (append)
- Modify: `R/study_setup.R:31-48` (`.study_renvignore()`)
- Modify: `tests/testthat/test-study_setup.R` (one expectation)
- Modify: `tests/testthat/test-checkpoint_git.R` (append)

**Interfaces:**
- Consumes: `.cp_git()`, `.cp_git_do()`.
- Produces: `.cp_repo_path(root)`; `.cp_set_remote(repo, remote)`; `.cp_remote_probe(repo)` returning `list(reachable, has_main, out)`; `.cp_repo_init(root, remote = NULL)` returning the repo path; `.cp_tags(repo, pattern)`; `.cp_seq_of(tags)`; `.cp_next_tag(repo, prefix)`; `.cp_sync_tree(repo, root, files)`; `.cp_head(repo)` (full SHA or `NA`); `.cp_message_file(lines)`; `.cp_commit_tag(repo, tag, message)` returning the new HEAD SHA; `.cp_tag_head(repo, tag, message)`; `.cp_rollback(repo, head_before, tag)`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-checkpoint_git.R`:

```r
test_that("the repo initialises on main under .checkpoint/repo", {
  skip_if_no_git()
  local_git_env()
  root <- withr::local_tempdir()
  repo <- .cp_repo_init(root)
  expect_equal(repo, file.path(root, ".checkpoint", "repo"))
  expect_equal(git_out(repo, c("symbolic-ref", "HEAD")), "refs/heads/main")
  expect_true(is.na(.cp_head(repo)))
})

test_that("commit, tag and sequencing work and stale files are removed", {
  skip_if_no_git()
  local_git_env()
  root <- withr::local_tempdir()
  plant_files(root, c("a.R", "b.R"))
  repo <- .cp_repo_init(root)
  expect_equal(.cp_next_tag(repo, "manuscript_submitted"),
               "manuscript_submitted-1")
  .cp_sync_tree(repo, root, c("a.R", "b.R"))
  sha <- .cp_commit_tag(repo, "manuscript_submitted-1", c("subject", "", "body"))
  expect_equal(sha, .cp_head(repo))
  expect_equal(.cp_next_tag(repo, "manuscript_submitted"),
               "manuscript_submitted-2")
  .cp_sync_tree(repo, root, "a.R")
  .cp_commit_tag(repo, "manuscript_submitted-2", "second")
  expect_equal(git_out(repo, c("ls-tree", "-r", "--name-only",
                               "manuscript_submitted-2")), "a.R")
})

test_that("rollback removes the tag and restores the previous head", {
  skip_if_no_git()
  local_git_env()
  root <- withr::local_tempdir()
  plant_files(root, "a.R")
  repo <- .cp_repo_init(root)
  .cp_sync_tree(repo, root, "a.R")
  first <- .cp_commit_tag(repo, "x-1", "first")
  .cp_commit_tag(repo, "x-2", "second")
  .cp_rollback(repo, first, "x-2")
  expect_equal(.cp_head(repo), first)
  expect_equal(git_out(repo, c("tag", "-l")), "x-1")
  .cp_rollback(repo, NA_character_, "x-1")
  expect_true(is.na(.cp_head(repo)))
})

test_that("init continues from an existing remote's history and tags", {
  skip_if_no_git()
  local_git_env()
  dir <- withr::local_tempdir()
  bare <- make_bare_remote(dir)
  src <- file.path(dir, "src")
  plant_files(src, "a.R")
  repo1 <- .cp_repo_init(src, bare)
  .cp_sync_tree(repo1, src, "a.R")
  .cp_commit_tag(repo1, "k-1", "one")
  git_out(repo1, c("push", "-q", "origin", "main", "refs/tags/k-1"))
  other <- file.path(dir, "other")
  dir.create(other)
  repo2 <- .cp_repo_init(other, bare)
  expect_equal(.cp_next_tag(repo2, "k"), "k-2")
  expect_true(file.exists(file.path(repo2, "a.R")))
})
```

In `tests/testthat/test-study_setup.R`, directly after the line `ignore <- readLines(file.path(root, ".renvignore"))` (line 44), add:

```r
  expect_true(".checkpoint/" %in% ignore)
```

- [ ] **Step 2: Run to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "checkpoint_git|study_setup")'`
Expected: FAIL, `could not find function ".cp_repo_init"`, and the `.renvignore` expectation fails.

- [ ] **Step 3: Implement**

Append to `R/checkpoint_git.R`:

```r
# The private clone. Its working tree only ever holds files that passed
# .cp_select(), which is what keeps data out of git: no tool can stage a file
# that is not there.
.cp_repo_path <- function(root) file.path(root, ".checkpoint", "repo")

# Keep origin pointed at the remote _study.yml names, which qhsprograms may
# write after the first local checkpoint.
.cp_set_remote <- function(repo, remote) {
  if (is.null(remote)) return(invisible(FALSE))
  cur <- .cp_git(repo, c("remote", "get-url", "origin"))
  if (!cur$ok) {
    .cp_git_do(repo, c("remote", "add", "origin", remote))
  } else if (!identical(cur$out[1], remote)) {
    .cp_git_do(repo, c("remote", "set-url", "origin", remote))
  }
  invisible(TRUE)
}

.cp_remote_probe <- function(repo) {
  res <- .cp_git(repo, c("ls-remote", "--heads", "origin", "main"))
  list(reachable = res$ok,
       has_main = res$ok && any(grepl("refs/heads/main$", res$out)),
       out = res$out)
}

# Create the clone on first use. When the remote already has history (a
# re-cloned or second copy), start from it so tag numbers continue.
.cp_repo_init <- function(root, remote = NULL) {
  repo <- .cp_repo_path(root)
  if (dir.exists(file.path(repo, ".git"))) {
    .cp_set_remote(repo, remote)
    return(repo)
  }
  dir.create(repo, recursive = TRUE, showWarnings = FALSE)
  .cp_git_do(repo, c("init", "-q"))
  .cp_git_do(repo, c("symbolic-ref", "HEAD", "refs/heads/main"))
  .cp_set_remote(repo, remote)
  if (!is.null(remote) && .cp_remote_probe(repo)$has_main) {
    .cp_git_do(repo, c("fetch", "-q", "origin",
                       "+refs/heads/main:refs/remotes/origin/main",
                       "+refs/tags/*:refs/tags/*"))
    .cp_git_do(repo, c("reset", "-q", "--hard", "refs/remotes/origin/main"))
  }
  repo
}

.cp_tags <- function(repo, pattern) {
  tags <- .cp_git_do(repo, c("tag", "-l"))
  tags[grepl(pattern, tags)]
}

.cp_seq_of <- function(tags) as.integer(sub("^.*-([0-9]+)$", "\\1", tags))

# Sequence numbers come from the tags themselves, never a counter file, so a
# re-cloned repository cannot hand out a number twice.
.cp_next_tag <- function(repo, prefix) {
  tags <- .cp_tags(repo, paste0("^", prefix, "-[0-9]+$"))
  n <- if (length(tags)) max(.cp_seq_of(tags)) + 1L else 1L
  paste0(prefix, "-", n)
}

# Replace the working tree with `files`, so a file deleted from the study
# shows as a deletion in the next snapshot.
.cp_sync_tree <- function(repo, root, files) {
  old <- setdiff(list.files(repo, all.files = TRUE, no.. = TRUE), ".git")
  unlink(file.path(repo, old), recursive = TRUE, force = TRUE)
  for (rel in files) {
    dest <- file.path(repo, rel)
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(file.path(root, rel), dest, overwrite = TRUE,
                   copy.date = TRUE)) {
      stop("could not copy ", rel, " into the checkpoint", call. = FALSE)
    }
  }
  invisible(files)
}

.cp_head <- function(repo) {
  res <- .cp_git(repo, c("rev-parse", "--verify", "-q", "HEAD"))
  if (res$ok) res$out[1] else NA_character_
}

.cp_message_file <- function(lines) {
  path <- tempfile("cp-msg-")
  writeLines(lines, path, useBytes = TRUE)
  path
}

.cp_commit_tag <- function(repo, tag, message) {
  msg <- .cp_message_file(message)
  on.exit(unlink(msg), add = TRUE)
  .cp_git_do(repo, c("add", "-A"))
  .cp_git_do(repo, c("commit", "-q", "--allow-empty", "-F", msg))
  .cp_git_do(repo, c("tag", "-a", tag, "-F", msg))
  .cp_head(repo)
}

.cp_tag_head <- function(repo, tag, message) {
  msg <- .cp_message_file(message)
  on.exit(unlink(msg), add = TRUE)
  .cp_git_do(repo, c("tag", "-a", tag, "-F", msg))
  .cp_head(repo)
}

# Undo a partial checkpoint: drop the tag and put main back where it was. An
# NA head means the repository had no commits before.
.cp_rollback <- function(repo, head_before, tag) {
  if (!is.null(tag)) .cp_git(repo, c("tag", "-d", tag))
  if (is.na(head_before)) {
    .cp_git(repo, c("update-ref", "-d", "refs/heads/main"))
  } else {
    .cp_git(repo, c("reset", "-q", "--hard", head_before))
  }
  invisible(NULL)
}
```

In `R/study_setup.R`, add `".checkpoint/",` as the first element of the vector in `.study_renvignore()`:

```r
.study_renvignore <- function() {
  c(
    ".checkpoint/",
    "00_datasets/",
```

- [ ] **Step 4: Run to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "checkpoint_git|study_setup")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/checkpoint_git.R R/study_setup.R tests/testthat/test-checkpoint_git.R tests/testthat/test-study_setup.R
git commit -m "feat: local checkpoint repository, tag sequencing and rollback"
```

---

### Task 7: `CHECKPOINT.yml` and the manifest check

**Files:**
- Create: `R/checkpoint_meta.R`
- Create: `tests/testthat/test-checkpoint_meta.R`

**Interfaces:**
- Consumes: `.cp_select()` result shape (Task 3); `verify_manifest(manifest_path, data_dir, stop_on_error, verbose, strict)` (existing).
- Produces: `.cp_manifest_check(root)` returning `NULL` or a named list file to `"OK"`/`"FAIL"`/`"unchecked"` (or `list(error = msg)`); `.cp_write_meta(repo, root, entry, selection)` writing `<repo>/CHECKPOINT.yml` and returning the meta list.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-checkpoint_meta.R`:

```r
test_that("CHECKPOINT.yml hashes every copied file and names no denied file", {
  root <- withr::local_tempdir()
  repo <- withr::local_tempdir()
  plant_files(repo, c("a.R", "30_analyses/b.R"))
  sel <- list(files = c("a.R", "30_analyses/b.R"),
              skipped = data.frame(path = "big.R", bytes = 9e7),
              denied = c(data_folder = 2L, data_extension = 1L,
                         output_extension = 0L))
  entry <- list(type = "checkpoint", checkpoint_id = "id-1", st_id = 1267L,
                kind = "manuscript_submitted", tag = "manuscript_submitted-1",
                delivery = list(git = "pending"))
  .cp_write_meta(repo, root, entry, sel)
  meta <- yaml::read_yaml(file.path(repo, "CHECKPOINT.yml"))
  expect_equal(meta$tag, "manuscript_submitted-1")
  expect_null(meta$delivery)
  expect_equal(meta$files[["a.R"]],
               digest::digest(file.path(repo, "a.R"), algo = "sha256",
                              file = TRUE))
  expect_equal(meta$denied$data_folder, 2L)
  expect_equal(meta$skipped[[1]]$path, "big.R")
  expect_false(any(grepl("datasets", names(meta$files))))
  expect_true(nzchar(meta$r_version))
})

test_that("a manifest entry without n_rows is recorded as unchecked", {
  root <- withr::local_tempdir()
  plant_files(root, "00_datasets/built.csv")
  sha <- digest::digest(file.path(root, "00_datasets/built.csv"),
                        algo = "sha256", file = TRUE)
  yaml::write_yaml(
    list(datasets = list(list(file = "built.csv", extract_date = "2026-09-01",
                              sha256 = sha, role = "source"))),
    file.path(root, "manifest.yaml")
  )
  res <- suppressWarnings(.cp_manifest_check(root))
  expect_equal(res[["built.csv"]], "unchecked")
})

test_that("a manifest mismatch warns and is recorded as FAIL", {
  root <- withr::local_tempdir()
  plant_files(root, "00_datasets/built.csv")
  yaml::write_yaml(
    list(datasets = list(list(file = "built.csv", extract_date = "2026-09-01",
                              n_rows = 1L, sha256 = strrep("0", 64),
                              role = "source"))),
    file.path(root, "manifest.yaml")
  )
  expect_warning(res <- .cp_manifest_check(root))
  expect_equal(res[["built.csv"]], "FAIL")
})

test_that("no manifest gives NULL", {
  expect_null(.cp_manifest_check(withr::local_tempdir()))
})
```

- [ ] **Step 2: Run to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "checkpoint_meta")'`
Expected: FAIL, `could not find function ".cp_write_meta"`.

- [ ] **Step 3: Implement**

Create `R/checkpoint_meta.R`:

```r
# CHECKPOINT.yml: what a snapshot contains and what produced it. It pins the
# data by manifest hash without shipping it, and records verify_manifest()'s
# verdict so a checkpoint taken against unverified data says so.

.cp_sha <- function(path) {
  if (!file.exists(path)) return(NULL)
  digest::digest(path, algo = "sha256", file = TRUE)
}

.cp_hvtir_versions <- function() {
  pkgs <- grep("^hvtiR", .packages(all.available = TRUE), value = TRUE)
  structure(
    lapply(pkgs, function(p) as.character(utils::packageVersion(p))),
    names = pkgs
  )
}

# verify_manifest() reports an entry without n_rows as OK although it never
# counted the rows; record those as "unchecked" instead. A mismatch warns (via
# verify_manifest) and is recorded; it never blocks the checkpoint.
.cp_manifest_check <- function(root) {
  path <- file.path(root, "manifest.yaml")
  if (!file.exists(path)) return(NULL)
  report <- tryCatch(
    verify_manifest(path, stop_on_error = FALSE),
    error = function(e) {
      warning("manifest could not be verified: ", conditionMessage(e),
              call. = FALSE)
      NULL
    }
  )
  if (is.null(report)) return(list(error = "manifest could not be verified"))
  status <- structure(as.list(report$status), names = report$file)
  for (d in yaml::read_yaml(path)$datasets) {
    if (is.null(d$n_rows) || is.na(d$n_rows)) status[[d$file]] <- "unchecked"
  }
  status
}

.cp_write_meta <- function(repo, root, entry, selection) {
  meta <- entry[setdiff(names(entry), c("delivery", "git_commit"))]
  meta$committed_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  meta$user <- Sys.info()[["user"]]
  meta$r_version <- R.version.string
  meta$platform <- R.version$platform
  meta$packages <- .cp_hvtir_versions()
  meta$renv_lock_sha256 <- .cp_sha(file.path(root, "renv.lock"))
  meta$manifest_sha256 <- .cp_sha(file.path(root, "manifest.yaml"))
  meta$manifest_check <- .cp_manifest_check(root)
  meta$files <- structure(
    lapply(selection$files, function(f) .cp_sha(file.path(repo, f))),
    names = selection$files
  )
  meta$skipped <- lapply(seq_len(nrow(selection$skipped)), function(i) {
    list(path = selection$skipped$path[i], bytes = selection$skipped$bytes[i])
  })
  meta$denied <- as.list(selection$denied)
  yaml::write_yaml(meta, file.path(repo, "CHECKPOINT.yml"))
  invisible(meta)
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "checkpoint_meta")'`
Expected: PASS (4 tests). If the "unchecked" test shows `verify_manifest()` raising rather than reporting on a missing `n_rows`, the `tryCatch` path records `list(error = ...)`; in that case change the test's expectation to the reported status and note it in the commit message, because it means the fail-open behaviour described in `AGENTS.md` has changed.

- [ ] **Step 5: Commit**

```bash
git add R/checkpoint_meta.R tests/testthat/test-checkpoint_meta.R
git commit -m "feat: CHECKPOINT.yml with file hashes and manifest verdict"
```

---

### Task 8: `study_checkpoint()` (local)

**Files:**
- Create: `R/study_checkpoint.R`
- Create: `tests/testthat/test-study_checkpoint.R`

**Interfaces:**
- Consumes: Tasks 1 to 7.
- Produces (exported): `study_checkpoint(kind, note = NULL, attributes = NULL, occurred_at = Sys.Date(), root = study_root())` returning, invisibly, an object of class `"study_checkpoint"`: `list(type, tag, commit, files = integer(1), skipped = data.frame, delivery = list, entry = list)`. `print.study_checkpoint()`.
- Produces (internal, used by Tasks 9 and 10): `.cp_snapshot(root, study, tag_fn, entry, caller)` returning `list(entry, selection, repo)`; `.cp_tag_message(entry)`; `.cp_result(entry, snap)`; `.cp_log_find(root, id)`.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-study_checkpoint.R`:

```r
test_that("no denied file reaches the committed tree", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  set_study_keys(root, checkpoint = list(include = list("**/*.csv")))
  plant_files(root, c("00_datasets/built.sas7bdat", "90_estimates/fit.R",
                      "30_analyses/cohort.csv", "10_descriptive/d.log",
                      "50_documents/table.xlsx", "30_analyses/draft.docx",
                      "50_documents/manuscript.docx"))
  cp <- study_checkpoint("manuscript_submitted", root = root)
  tree <- git_out(.cp_repo_path(root),
                  c("ls-tree", "-r", "--name-only", cp$tag))
  expect_false(any(grepl("datasets|estimates|\\.csv$|\\.log$|\\.xlsx$|draft",
                         tree)))
  expect_true(all(c("_study.yml", "30_analyses/fit.R", "CHECKPOINT.yml",
                    "50_documents/manuscript.docx") %in% tree))
})

test_that("tags are numbered per kind and workspace_created is not", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  expect_equal(study_checkpoint("workspace_created", root = root)$tag,
               "workspace_created")
  expect_error(study_checkpoint("workspace_created", root = root),
               "already recorded")
  expect_equal(study_checkpoint("abstract_submitted", root = root)$tag,
               "abstract_submitted-1")
  expect_equal(study_checkpoint("abstract_submitted", root = root)$tag,
               "abstract_submitted-2")
})

test_that("the log entry has the API checkpoint shape", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  cp <- study_checkpoint("manuscript_submitted", note = "JTCVS",
                         attributes = list(journal = "JTCVS"),
                         occurred_at = as.Date("2026-10-02"), root = root)
  e <- .cp_log_read(root)[[1]]
  expect_equal(e$type, "checkpoint")
  expect_match(e$checkpoint_id, "^[0-9a-f-]{36}$")
  expect_equal(e$st_id, 1267L)
  expect_equal(e$occurred_at, "2026-10-02")
  expect_equal(e$git_commit, cp$commit)
  expect_equal(e$attributes$journal, "JTCVS")
  expect_equal(e$delivery$st, "pending")
})

test_that("an automatic kind logs an entry but makes no commit", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  cp <- study_checkpoint("data_received", root = root)
  expect_null(cp$commit)
  e <- .cp_log_read(root)[[1]]
  expect_null(e$git_commit)
  expect_equal(e$delivery$git, "none")
  expect_false(dir.exists(file.path(.cp_repo_path(root), ".git")))
})

test_that("a failure before the commit leaves no tag and no log entry", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  local_mocked_bindings(.cp_write_meta = function(...) stop("boom"))
  expect_error(study_checkpoint("manuscript_submitted", root = root), "boom")
  expect_length(.cp_log_read(root), 0L)
  expect_length(git_out(.cp_repo_path(root), c("tag", "-l")), 0L)
  expect_true(is.na(.cp_head(.cp_repo_path(root))))
})

test_that("a failure after the commit rolls the commit and tag back", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  first <- study_checkpoint("abstract_submitted", root = root)
  local_mocked_bindings(.cp_log_append = function(...) stop("disk full"))
  expect_error(study_checkpoint("abstract_submitted", root = root),
               "disk full")
  repo <- .cp_repo_path(root)
  expect_equal(.cp_head(repo), first$commit)
  expect_equal(git_out(repo, c("tag", "-l")), "abstract_submitted-1")
})

test_that("an unknown kind is rejected before anything is written", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  expect_error(study_checkpoint("submitted", root = root),
               "unknown checkpoint kind")
  expect_false(dir.exists(file.path(root, ".checkpoint")))
})
```

- [ ] **Step 2: Run to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "study_checkpoint")'`
Expected: FAIL, `could not find function "study_checkpoint"`.

- [ ] **Step 3: Implement**

Create `R/study_checkpoint.R`:

```r
# Study checkpoints: an allow-listed snapshot of the study committed and
# tagged in .checkpoint/repo, recorded in the outbox, then delivered. Steps up
# to the log entry are all-or-nothing; delivery never undoes them.

.cp_tag_message <- function(entry) {
  body <- entry[setdiff(names(entry), c("delivery", "git_commit", "tag"))]
  c(paste0(entry$type, " ", entry$tag, " (ST ", entry$st_id, ")"), "",
    strsplit(yaml::as.yaml(body), "\n", fixed = TRUE)[[1]])
}

# Select, copy, describe, commit, tag and log. `tag_fn(repo)` names the tag,
# so checkpoints, closures and the unnumbered workspace_created share one
# transaction. Any failure puts the repository back as it was.
.cp_snapshot <- function(root, study, tag_fn, entry, caller) {
  repo <- .cp_repo_init(root, study$remote)
  tag <- tag_fn(repo)
  sel <- .cp_select(root, study$include)
  if (nrow(sel$skipped)) {
    warning(caller, "(): skipped over the 50 MB cap: ",
            paste(sel$skipped$path, collapse = ", "), call. = FALSE)
  }
  head_before <- .cp_head(repo)
  done <- FALSE
  on.exit(if (!done) .cp_rollback(repo, head_before, tag), add = TRUE)
  entry$tag <- tag
  .cp_sync_tree(repo, root, sel$files)
  .cp_write_meta(repo, root, entry, sel)
  entry$git_commit <- .cp_commit_tag(repo, tag, .cp_tag_message(entry))
  entry$delivery$git <- "pending"
  .cp_log_append(root, entry)
  done <- TRUE
  list(entry = entry, selection = sel, repo = repo)
}

.cp_log_find <- function(root, id) {
  for (e in .cp_log_read(root)) {
    if (identical(.cp_entry_id(e), id)) return(e)
  }
  NULL
}

.cp_result <- function(entry, snap) {
  structure(
    list(type = entry$type, tag = entry$tag, commit = entry$git_commit,
         files = if (is.null(snap)) 0L else length(snap$selection$files),
         skipped = if (is.null(snap)) NULL else snap$selection$skipped,
         delivery = entry$delivery, entry = entry),
    class = "study_checkpoint"
  )
}

#' Record a study checkpoint
#'
#' @description
#' Commits an allow-listed snapshot of the study (code, identity,
#' reproducibility files and the documents in \code{50_documents/}) to a
#' private git repository in \code{.checkpoint/repo/}, tags it with the
#' checkpoint kind and a sequence number, records it in the outbox
#' \code{.checkpoint/log.yml}, and pushes it when \code{_study.yml} names a
#' remote. Data never enter the snapshot: \code{00_datasets/},
#' \code{90_estimates/} and data or output file types are always excluded.
#'
#' @details
#' The kind comes from the StudyTracker checkpoint vocabulary, for example
#' \code{"abstract_submitted"} or \code{"manuscript_submitted"}. Automatic
#' kinds such as \code{"data_received"} are logged without a snapshot.
#' A checkpoint is committed locally before anything is pushed, so an
#' unreachable remote never loses one; \code{\link{study_checkpoint_push}}
#' retries later.
#'
#' @param kind Character(1). A checkpoint kind.
#' @param note Optional character(1), stored with the checkpoint.
#' @param attributes Optional named list of kind-specific details, for example
#'   \code{list(journal = "JTCVS")}.
#' @param occurred_at Date the event happened. Defaults to today.
#' @param root Character. Study root. Defaults to \code{study_root()}.
#'
#' @return An object of class \code{"study_checkpoint"}, returned invisibly,
#'   with the tag, commit, file count, skipped files and delivery states.
#'
#' @seealso \code{\link{study_checkpoint_push}}, \code{\link{study_close}},
#'   \code{\link{study_status}}
#'
#' @export
#'
#' @examples
#' \donttest{
#' if (nzchar(Sys.which("git"))) {
#'   root <- file.path(tempdir(), "checkpoint-example")
#'   study_setup(root, "Checkpoint example", 1267L)
#'   writeLines("x <- 1", file.path(root, "30_analyses", "fit.R"))
#'   # A throwaway identity, so the example commits on a machine with no
#'   # git user configured.
#'   withr::with_envvar(c(GIT_AUTHOR_NAME = "Example",
#'                        GIT_AUTHOR_EMAIL = "example@example.org",
#'                        GIT_COMMITTER_NAME = "Example",
#'                        GIT_COMMITTER_EMAIL = "example@example.org"), {
#'     cp <- study_checkpoint("abstract_submitted", root = root)
#'     print(cp$tag)
#'   })
#'   unlink(root, recursive = TRUE)
#' }
#' }
study_checkpoint <- function(kind, note = NULL, attributes = NULL,
                             occurred_at = Sys.Date(), root = study_root()) {
  .cp_require_git("study_checkpoint")
  root <- normalizePath(root, mustWork = TRUE)
  study <- .cp_study(root, "study_checkpoint")
  row <- .cp_kind_check(.cp_kinds(root), kind, "study_checkpoint")

  entry <- list(
    type = "checkpoint", checkpoint_id = uuid::UUIDgenerate(),
    st_id = study$st_id, workspace_id = study$workspace_id, kind = kind,
    occurred_at = .cp_date(occurred_at), trigger = row$trigger,
    artifact = NULL, git_commit = NULL, note = note, attributes = attributes,
    tag = NULL, delivery = list(git = "none", st = "pending")
  )

  if (!identical(row$trigger, "manual")) {
    .cp_log_append(root, entry)
    return(invisible(.cp_result(entry, NULL)))
  }

  tag_fn <- function(repo) {
    if (row$numbered) return(.cp_next_tag(repo, kind))
    if (length(.cp_tags(repo, paste0("^", kind, "$")))) {
      stop("study_checkpoint(): '", kind, "' is already recorded for this ",
           "study", call. = FALSE)
    }
    kind
  }
  snap <- .cp_snapshot(root, study, tag_fn, entry, "study_checkpoint")
  invisible(.cp_result(snap$entry, snap))
}

#' @export
print.study_checkpoint <- function(x, ...) {
  cat(x$type, if (!is.null(x$tag)) paste0(" ", x$tag), "\n", sep = "")
  cat("  commit:   ", .cp_or(x$commit, "none (no snapshot)"), "\n", sep = "")
  cat("  files:    ", x$files, "\n", sep = "")
  cat("  git:      ", x$delivery$git,
      if (!is.null(x$delivery$reason)) paste0(" (", x$delivery$reason, ")"),
      "\n", sep = "")
  cat("  ST:       ", x$delivery$st, "\n", sep = "")
  invisible(x)
}
```

- [ ] **Step 4: Document and run**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "study_checkpoint")'`
Expected: PASS (7 tests). No repository is created for an automatic kind, which the last assertion of that test checks.

- [ ] **Step 5: Commit**

```bash
git add R/study_checkpoint.R tests/testthat/test-study_checkpoint.R man/study_checkpoint.Rd NAMESPACE
git commit -m "feat: study_checkpoint() snapshots, tags and logs locally"
```

---

### Task 9: Delivery, divergence and `study_checkpoint_push()`

**Files:**
- Create: `R/checkpoint_deliver.R`
- Modify: `R/study_checkpoint.R` (call delivery; add `study_checkpoint_push()`)
- Create: `tests/testthat/test-checkpoint_deliver.R`

**Interfaces:**
- Consumes: Tasks 1 to 8.
- Produces: `.cp_deliver(root, study)` returning the updated log invisibly; `.cp_push(repo, entries)` returning `list(reason = NULL or chr, entries)`; `.cp_replay(repo)` returning a named character map old SHA to new SHA; `.cp_retarget(entry, repo, map)`; `.cp_renumber(repo, tag)`. Exported `study_checkpoint_push(root = study_root())` returning, invisibly, a data.frame with columns `type`, `tag`, `git`, `st`, `reason`.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-checkpoint_deliver.R`:

```r
test_that("a checkpoint is pushed to the remote with its tag", {
  skip_if_no_git()
  local_git_env()
  dir <- withr::local_tempdir()
  root <- make_checkpoint_study(dir)
  bare <- make_bare_remote(dir)
  set_study_keys(root, checkpoint = list(remote = bare))
  cp <- study_checkpoint("abstract_submitted", root = root)
  expect_equal(cp$delivery$git, "delivered")
  expect_equal(git_out(bare, c("tag", "-l")), "abstract_submitted-1")
  expect_true("CHECKPOINT.yml" %in%
                git_out(bare, c("ls-tree", "--name-only", "main")))
})

test_that("an unreachable remote keeps the checkpoint and retries later", {
  skip_if_no_git()
  local_git_env()
  dir <- withr::local_tempdir()
  root <- make_checkpoint_study(dir)
  missing <- file.path(dir, "later.git")
  set_study_keys(root, checkpoint = list(remote = missing))
  expect_warning(cp <- study_checkpoint("abstract_submitted", root = root),
                 "not pushed")
  expect_equal(.cp_log_read(root)[[1]]$delivery$git, "pending")
  make_bare_remote(dir, "later.git")
  res <- study_checkpoint_push(root)
  expect_equal(res$git, "delivered")
  expect_equal(git_out(missing, c("tag", "-l")), "abstract_submitted-1")
  expect_silent(study_checkpoint_push(root))
})

test_that("no remote leaves delivery pending without a warning", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  expect_silent(study_checkpoint("abstract_submitted", root = root))
  e <- .cp_log_read(root)[[1]]
  expect_equal(e$delivery$git, "pending")
  expect_equal(e$delivery$reason, "no remote configured")
})

test_that("an unverified identity is committed but never pushed", {
  skip_if_no_git()
  local_git_env()
  dir <- withr::local_tempdir()
  root <- make_checkpoint_study(dir)
  bare <- make_bare_remote(dir)
  set_study_keys(root, identity_verified = FALSE,
                 checkpoint = list(remote = bare))
  expect_message(study_checkpoint("abstract_submitted", root = root),
                 "identity unverified")
  expect_length(git_out(bare, c("tag", "-l")), 0L)
  expect_equal(.cp_log_read(root)[[1]]$delivery$reason, "identity unverified")
  set_study_keys(root, identity_verified = TRUE)
  study_checkpoint_push(root)
  expect_equal(git_out(bare, c("tag", "-l")), "abstract_submitted-1")
})

test_that("divergence replays, renumbers and never force-pushes", {
  skip_if_no_git()
  local_git_env()
  dir <- withr::local_tempdir()
  root <- make_checkpoint_study(dir)
  bare <- make_bare_remote(dir)
  study_checkpoint("data_request_submitted", root = root)  # local only
  other <- file.path(dir, "other")
  git_out(dir, c("clone", "-q", bare, other))
  git_out(other, c("checkout", "-q", "-b", "main"))
  plant_files(other, "other.R")
  git_out(other, c("add", "-A"))
  git_out(other, c("commit", "-q", "-m", "other copy"))
  git_out(other, c("tag", "-a", "data_request_submitted-1", "-m", "other"))
  git_out(other, c("push", "-q", "origin", "main",
                   "refs/tags/data_request_submitted-1"))
  set_study_keys(root, checkpoint = list(remote = bare))
  study_checkpoint_push(root)
  e <- .cp_log_read(root)[[1]]
  expect_equal(e$delivery$git, "delivered")
  expect_equal(e$tag, "data_request_submitted-2")
  expect_equal(e$renumbered_from, "data_request_submitted-1")
  expect_setequal(git_out(bare, c("tag", "-l")),
                  c("data_request_submitted-1", "data_request_submitted-2"))
  expect_length(git_out(bare, c("rev-list", "main")), 2L)
  expect_true("30_analyses/fit.R" %in%
                git_out(bare, c("ls-tree", "-r", "--name-only",
                                "data_request_submitted-2")))
})

test_that("a re-cloned .checkpoint continues the sequence", {
  skip_if_no_git()
  local_git_env()
  dir <- withr::local_tempdir()
  root <- make_checkpoint_study(dir)
  bare <- make_bare_remote(dir)
  set_study_keys(root, checkpoint = list(remote = bare))
  study_checkpoint("abstract_submitted", root = root)
  study_checkpoint("abstract_submitted", root = root)
  unlink(file.path(root, ".checkpoint"), recursive = TRUE)
  expect_equal(study_checkpoint("abstract_submitted", root = root)$tag,
               "abstract_submitted-3")
})
```

- [ ] **Step 2: Run to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "checkpoint_deliver")'`
Expected: FAIL, `could not find function "study_checkpoint_push"`.

- [ ] **Step 3: Implement delivery**

Create `R/checkpoint_deliver.R`:

```r
# Delivery: replicate local checkpoints to the remote. Nothing here undoes a
# local checkpoint. When another copy of the study pushed first, unpushed
# snapshots are replayed on top of the remote main with git commit-tree: a
# snapshot's content never depends on its parent, so a replay cannot
# conflict. A pushed tag is never moved and nothing is ever force-pushed.

.cp_last <- function(out) if (length(out)) out[length(out)] else "no output"

.cp_replay <- function(repo) {
  if (.cp_git(repo, c("merge-base", "--is-ancestor",
                      "refs/remotes/origin/main", "HEAD"))$ok) {
    return(character(0))
  }
  commits <- .cp_git_do(repo, c("rev-list", "--reverse", "HEAD",
                                "^refs/remotes/origin/main"))
  base <- .cp_git_do(repo, c("rev-parse", "refs/remotes/origin/main"))[1]
  map <- character(0)
  for (old in commits) {
    tree <- .cp_git_do(repo, c("rev-parse", paste0(old, "^{tree}")))[1]
    msg <- .cp_message_file(.cp_git_do(repo, c("log", "-1", "--format=%B", old)))
    new <- .cp_git_do(repo, c("commit-tree", tree, "-p", base, "-F", msg))[1]
    unlink(msg)
    map[[old]] <- new
    base <- new
  }
  .cp_git_do(repo, c("reset", "-q", "--hard", base))
  map
}

.cp_remote_tags <- function(repo) {
  .cp_git_do(repo, c("for-each-ref", "--format=%(refname:strip=2)",
                     "refs/remote-tags"))
}

.cp_renumber <- function(repo, tag) {
  prefix <- sub("-[0-9]+$", "", tag)
  family <- if (startsWith(tag, "closed-")) "closed-[a-z_]+" else prefix
  all <- c(.cp_git_do(repo, c("tag", "-l")), .cp_remote_tags(repo))
  seqs <- .cp_seq_of(all[grepl(paste0("^", family, "-[0-9]+$"), all)])
  paste0(prefix, "-", max(c(0L, seqs)) + 1L)
}

.cp_commit_of <- function(repo, ref) {
  res <- .cp_git(repo, c("rev-parse", "-q", "--verify", paste0(ref, "^{commit}")))
  if (res$ok) res$out[1] else NA_character_
}

# Move an unpushed tag to its replayed commit, renumbering it when the remote
# already holds the same name on a different commit.
.cp_retarget <- function(entry, repo, map) {
  if (is.null(entry$tag)) return(entry)
  old <- entry$git_commit
  new <- if (!is.null(old) && old %in% names(map)) map[[old]] else old
  remote <- .cp_commit_of(repo, paste0("refs/remote-tags/", entry$tag))
  collides <- !is.na(remote) && !identical(remote, new)
  if (!collides && identical(new, old)) return(entry)
  msg <- .cp_message_file(.cp_git_do(repo, c("tag", "-l", "--format=%(contents)",
                                             entry$tag)))
  on.exit(unlink(msg), add = TRUE)
  .cp_git_do(repo, c("tag", "-d", entry$tag))
  if (collides) {
    entry$renumbered_from <- entry$tag
    entry$tag <- .cp_renumber(repo, entry$tag)
  }
  .cp_git_do(repo, c("tag", "-a", entry$tag, "-F", msg, new))
  entry$git_commit <- new
  entry
}

.cp_push <- function(repo, entries) {
  probe <- .cp_remote_probe(repo)
  if (!probe$reachable) {
    return(list(reason = paste("remote unreachable:", .cp_last(probe$out))))
  }
  refspecs <- "+refs/tags/*:refs/remote-tags/*"
  if (probe$has_main) {
    refspecs <- c("+refs/heads/main:refs/remotes/origin/main", refspecs)
  }
  .cp_git_do(repo, c("fetch", "-q", "origin", refspecs))
  map <- if (probe$has_main) .cp_replay(repo) else character(0)
  entries <- lapply(entries, .cp_retarget, repo = repo, map = map)
  res <- .cp_git(repo, c("push", "-q", "origin", "refs/heads/main:refs/heads/main"))
  if (!res$ok) return(list(reason = paste("push rejected:", .cp_last(res$out))))
  tags <- unique(unlist(lapply(entries, function(e) e$tag)))
  tags <- tags[vapply(tags, function(t) {
    !identical(.cp_commit_of(repo, paste0("refs/remote-tags/", t)),
               .cp_commit_of(repo, t))
  }, logical(1))]
  if (length(tags)) {
    res <- .cp_git(repo, c("push", "-q", "origin", paste0("refs/tags/", tags)))
    if (!res$ok) {
      return(list(reason = paste("tag push rejected:", .cp_last(res$out))))
    }
  }
  list(reason = NULL, entries = entries)
}

# Deliver every pending entry. An unverified identity is never pushed (the
# manual-identity rule); no remote is a normal state for a study that has not
# been given one yet.
.cp_deliver <- function(root, study) {
  log <- .cp_log_read(root)
  pending <- which(vapply(log, function(e) identical(e$delivery$git, "pending"),
                          logical(1)))
  if (!length(pending)) return(invisible(log))
  reason <- if (!study$verified) {
    "identity unverified"
  } else if (is.null(study$remote)) {
    "no remote configured"
  } else {
    NULL
  }
  if (is.null(reason)) {
    pushed <- .cp_push(.cp_repo_init(root, study$remote), log[pending])
    reason <- pushed$reason
    if (is.null(reason)) log[pending] <- pushed$entries
  }
  for (i in pending) {
    if (is.null(reason)) log[[i]]$delivery$git <- "delivered"
    log[[i]]$delivery$reason <- reason
  }
  .cp_log_write(root, log)
  if (identical(reason, "identity unverified")) {
    message(length(pending), " checkpoint(s) saved locally and not pushed: ",
            "identity unverified. Run study-setup --verify, then ",
            "study_checkpoint_push().")
  } else if (!is.null(reason) && reason != "no remote configured") {
    warning(length(pending), " checkpoint(s) saved locally, not pushed: ",
            reason, ". Run study_checkpoint_push() to retry.", call. = FALSE)
  }
  invisible(log)
}

.cp_log_frame <- function(log) {
  pick <- function(f) vapply(log, function(e) as.character(.cp_or(f(e), NA)),
                             character(1))
  data.frame(type = pick(function(e) e$type), tag = pick(function(e) e$tag),
             git = pick(function(e) e$delivery$git),
             st = pick(function(e) e$delivery$st),
             reason = pick(function(e) e$delivery$reason),
             stringsAsFactors = FALSE)
}
```

- [ ] **Step 4: Wire delivery into `study_checkpoint()` and add the export**

In `R/study_checkpoint.R`, replace the last two lines of `study_checkpoint()`:

```r
  snap <- .cp_snapshot(root, study, tag_fn, entry, "study_checkpoint")
  invisible(.cp_result(snap$entry, snap))
}
```

with:

```r
  snap <- .cp_snapshot(root, study, tag_fn, entry, "study_checkpoint")
  .cp_deliver(root, study)
  final <- .cp_or(.cp_log_find(root, entry$checkpoint_id), snap$entry)
  invisible(.cp_result(final, snap))
}
```

and append:

```r
#' Push pending study checkpoints
#'
#' @description
#' Retries delivery of every checkpoint, closure and reopening in
#' \code{.checkpoint/log.yml} that has not reached the remote yet.
#' \code{\link{study_checkpoint}} does this on every call; use this function
#' after a network outage, or once \code{study-setup --verify} has verified a
#' manually entered identity.
#'
#' @param root Character. Study root. Defaults to \code{study_root()}.
#'
#' @return A data frame, returned invisibly, with one row per logged event and
#'   columns \code{type}, \code{tag}, \code{git}, \code{st} and \code{reason}.
#'
#' @seealso \code{\link{study_checkpoint}}
#'
#' @export
study_checkpoint_push <- function(root = study_root()) {
  .cp_require_git("study_checkpoint_push")
  root <- normalizePath(root, mustWork = TRUE)
  study <- .cp_study(root, "study_checkpoint_push")
  invisible(.cp_log_frame(.cp_deliver(root, study)))
}
```

- [ ] **Step 5: Document and run**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "checkpoint_deliver|study_checkpoint")'`
Expected: PASS. The Task 8 tests still pass: with no remote, delivery is silent and stays `pending`.

- [ ] **Step 6: Commit**

```bash
git add R/checkpoint_deliver.R R/study_checkpoint.R tests/testthat/test-checkpoint_deliver.R man/ NAMESPACE
git commit -m "feat: deliver checkpoints to the remote, replaying on divergence"
```

---

### Task 10: `study_close()` and `study_reopen()`

**Files:**
- Create: `R/study_close.R`
- Modify: `R/study_checkpoint.R` (closed-study warning, publication hint)
- Create: `tests/testthat/test-study_close.R`

**Interfaces:**
- Consumes: `.cp_snapshot()`, `.cp_deliver()`, `.cp_result()`, `.cp_log_find()`, `.cp_tags()`, `.cp_tag_head()`, `.cp_repo_init()`.
- Produces (exported): `study_close(outcome, reason = NULL, publication = NULL, superseded_by = NULL, closed_at = Sys.Date(), root = study_root())`; `study_reopen(reason, new_lead = NULL, reopened_at = Sys.Date(), root = study_root())`; both return a `"study_checkpoint"` object invisibly. Internal: `.cp_closure_counts(repo)` returning `c(closed =, reopened =)`; `.cp_is_closed(root)`.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-study_close.R`:

```r
pub <- list(title = "A paper", journal = "JTCVS", accepted_on = "2026-05-26",
            published_on = "2026-06-12", doi = "10.1016/j.jtcvs.2026.05.027")

test_that("close guards fail before anything is written", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  expect_error(study_close("published", publication = pub, root = root),
               "needs a manuscript_published checkpoint")
  study_checkpoint("manuscript_published", root = root)
  expect_error(study_close("published", publication = pub[1:2], root = root),
               "accepted_on, published_on")
  expect_error(study_close("published",
                           publication = pub[c("title", "journal",
                                               "accepted_on", "published_on")],
                           root = root),
               "doi or pmid")
  expect_error(study_close("superseded", root = root), "superseded_by")
  expect_error(study_close("unrecorded", root = root), "legacy migration")
  expect_false(any(grepl("^closed-",
                         git_out(.cp_repo_path(root), c("tag", "-l")))))
})

test_that("close snapshots and tags; reopen tags without committing", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  cl <- study_close("not_published", reason = "no journal fit", root = root)
  expect_equal(cl$tag, "closed-not_published-1")
  expect_true(.cp_is_closed(root))
  expect_error(study_close("abandoned", root = root), "already closed")
  repo <- .cp_repo_path(root)
  head <- .cp_head(repo)
  ro <- study_reopen("new cohort", root = root)
  expect_equal(ro$tag, "reopened-1")
  expect_equal(.cp_head(repo), head)
  expect_false(.cp_is_closed(root))
  expect_error(study_reopen("again", root = root), "not closed")
  study_checkpoint("manuscript_published", root = root)
  expect_equal(study_close("published", publication = pub, root = root)$tag,
               "closed-published-2")
  types <- vapply(.cp_log_read(root), function(e) e$type, character(1))
  expect_equal(types, c("closure", "reopening", "checkpoint", "closure"))
})

test_that("a checkpoint on a closed study succeeds and warns", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  study_close("abandoned", root = root)
  expect_warning(cp <- study_checkpoint("abstract_submitted", root = root),
                 "study is closed")
  expect_equal(cp$tag, "abstract_submitted-1")
})

test_that("manuscript_published hints at study_close", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  expect_message(study_checkpoint("manuscript_published", root = root),
                 "study_close\\(\"published\"")
})
```

- [ ] **Step 2: Run to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "study_close")'`
Expected: FAIL, `could not find function "study_close"`.

- [ ] **Step 3: Implement**

Create `R/study_close.R`:

```r
# Closing and reopening, following the StudyTracker Workspace API's Closure
# and Reopening rules. Closing always takes a final snapshot; reopening only
# tags. A study is closed when its latest closed-* tag has no reopened-* tag
# after it; because the two alternate, that is read from counts, which cannot
# tie the way tag timestamps can.

.cp_outcomes <- function() c("published", "not_published", "superseded", "abandoned")

.cp_closure_counts <- function(repo) {
  if (!dir.exists(file.path(repo, ".git"))) return(c(closed = 0L, reopened = 0L))
  tags <- .cp_git_do(repo, c("tag", "-l"))
  c(closed = sum(grepl("^closed-[a-z_]+-[0-9]+$", tags)),
    reopened = sum(grepl("^reopened-[0-9]+$", tags)))
}

.cp_is_closed <- function(root) {
  n <- .cp_closure_counts(.cp_repo_path(root))
  n[["closed"]] > n[["reopened"]]
}

.cp_check_publication <- function(repo, publication) {
  required <- c("title", "journal", "accepted_on", "published_on")
  have <- vapply(required, function(k) {
    !is.null(publication[[k]]) && nzchar(as.character(publication[[k]]))
  }, logical(1))
  missing <- required[!have]
  if (is.null(publication$doi) && is.null(publication$pmid)) {
    missing <- c(missing, "doi or pmid")
  }
  if (length(missing)) {
    stop("study_close(): outcome 'published' needs publication fields: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  if (!length(.cp_tags(repo, "^manuscript_published-[0-9]+$"))) {
    stop("study_close(): outcome 'published' needs a manuscript_published ",
         "checkpoint first; run study_checkpoint(\"manuscript_published\")",
         call. = FALSE)
  }
  lapply(publication, function(v) if (inherits(v, "Date")) .cp_date(v) else v)
}

#' Close or reopen a study
#'
#' @description
#' \code{study_close()} records how a study ended and freezes it: it takes a
#' final checkpoint snapshot, tags it \code{closed-<outcome>-<n>} and records
#' a closure in the outbox. \code{study_reopen()} records a reopening and tags
#' the current snapshot \code{reopened-<n>}; the next checkpoint snapshots as
#' usual. A study may be closed and reopened any number of times, and every
#' cycle is kept.
#'
#' @details
#' The outcomes follow the StudyTracker closure rules:
#' \itemize{
#'   \item \code{"published"} needs \code{publication} (\code{title},
#'     \code{journal}, \code{accepted_on}, \code{published_on}, and at least
#'     one of \code{doi} and \code{pmid}) and an earlier
#'     \code{"manuscript_published"} checkpoint.
#'   \item \code{"superseded"} needs \code{superseded_by}, the ST number of
#'     the study that replaced it.
#'   \item \code{"not_published"} and \code{"abandoned"} need nothing further.
#' }
#' These rules are checked before anything is written, so a close made
#' offline fails at once rather than when the outbox is delivered.
#'
#' @param outcome Character(1). One of \code{"published"},
#'   \code{"not_published"}, \code{"superseded"} or \code{"abandoned"}.
#' @param reason Optional character(1). For \code{study_reopen()}, required.
#' @param publication Named list of publication details; required for
#'   \code{"published"}.
#' @param superseded_by Integer(1). ST number; required for
#'   \code{"superseded"}.
#' @param closed_at,reopened_at Date of the event. Defaults to today.
#' @param new_lead Optional character(1), the username of a new study lead.
#' @param root Character. Study root. Defaults to \code{study_root()}.
#'
#' @return An object of class \code{"study_checkpoint"}, returned invisibly.
#'
#' @seealso \code{\link{study_checkpoint}}, \code{\link{study_status}}
#'
#' @export
#'
#' @examples
#' \donttest{
#' if (nzchar(Sys.which("git"))) {
#'   root <- file.path(tempdir(), "close-example")
#'   study_setup(root, "Close example", 1267L)
#'   # A throwaway identity, so the example commits on a machine with no
#'   # git user configured.
#'   withr::with_envvar(c(GIT_AUTHOR_NAME = "Example",
#'                        GIT_AUTHOR_EMAIL = "example@example.org",
#'                        GIT_COMMITTER_NAME = "Example",
#'                        GIT_COMMITTER_EMAIL = "example@example.org"), {
#'     study_close("abandoned", reason = "PI left", root = root)
#'     study_reopen("new PI", root = root)
#'   })
#'   unlink(root, recursive = TRUE)
#' }
#' }
study_close <- function(outcome, reason = NULL, publication = NULL,
                        superseded_by = NULL, closed_at = Sys.Date(),
                        root = study_root()) {
  .cp_require_git("study_close")
  root <- normalizePath(root, mustWork = TRUE)
  study <- .cp_study(root, "study_close")
  if (length(outcome) != 1L || is.na(outcome) || !outcome %in% .cp_outcomes()) {
    stop("study_close(): outcome must be one of ",
         paste(.cp_outcomes(), collapse = ", "),
         if (identical(outcome, "unrecorded")) {
           "; 'unrecorded' is reserved for the legacy migration"
         },
         call. = FALSE)
  }
  repo <- .cp_repo_init(root, study$remote)
  if (.cp_is_closed(root)) {
    stop("study_close(): the study is already closed; run study_reopen() ",
         "first", call. = FALSE)
  }
  if (outcome == "published") {
    publication <- .cp_check_publication(repo, publication)
  }
  if (outcome == "superseded") {
    sb <- suppressWarnings(as.integer(superseded_by))
    if (length(sb) != 1L || is.na(sb) || sb < 1L) {
      stop("study_close(): outcome 'superseded' needs superseded_by, one ST ",
           "number", call. = FALSE)
    }
    superseded_by <- sb
  }

  entry <- list(
    type = "closure", closure_id = uuid::UUIDgenerate(), st_id = study$st_id,
    workspace_id = study$workspace_id, outcome = outcome,
    closed_at = .cp_date(closed_at), reason = reason,
    publication = publication, superseded_by = superseded_by,
    git_commit = NULL, tag = NULL,
    delivery = list(git = "none", st = "pending")
  )
  tag_fn <- function(repo) {
    tags <- .cp_tags(repo, "^closed-[a-z_]+-[0-9]+$")
    n <- if (length(tags)) max(.cp_seq_of(tags)) + 1L else 1L
    paste0("closed-", outcome, "-", n)
  }
  snap <- .cp_snapshot(root, study, tag_fn, entry, "study_close")
  .cp_deliver(root, study)
  invisible(.cp_result(.cp_or(.cp_log_find(root, entry$closure_id),
                              snap$entry), snap))
}

#' @rdname study_close
#' @export
study_reopen <- function(reason, new_lead = NULL, reopened_at = Sys.Date(),
                         root = study_root()) {
  .cp_require_git("study_reopen")
  root <- normalizePath(root, mustWork = TRUE)
  study <- .cp_study(root, "study_reopen")
  if (missing(reason) || length(reason) != 1L || is.na(reason) ||
        !nzchar(reason)) {
    stop("study_reopen(): a reason is required", call. = FALSE)
  }
  repo <- .cp_repo_init(root, study$remote)
  if (!.cp_is_closed(root)) {
    stop("study_reopen(): the study is not closed", call. = FALSE)
  }
  tag <- paste0("reopened-", .cp_closure_counts(repo)[["reopened"]] + 1L)
  entry <- list(
    type = "reopening", reopening_id = uuid::UUIDgenerate(),
    st_id = study$st_id, workspace_id = study$workspace_id,
    reopened_at = .cp_date(reopened_at), reason = reason, new_lead = new_lead,
    git_commit = NULL, tag = tag,
    delivery = list(git = "pending", st = "pending")
  )
  done <- FALSE
  on.exit(if (!done) .cp_git(repo, c("tag", "-d", tag)), add = TRUE)
  entry$git_commit <- .cp_tag_head(repo, tag, .cp_tag_message(entry))
  .cp_log_append(root, entry)
  done <- TRUE
  .cp_deliver(root, study)
  invisible(.cp_result(.cp_or(.cp_log_find(root, entry$reopening_id), entry),
                       NULL))
}
```

In `R/study_checkpoint.R`, in `study_checkpoint()`, directly after the line `row <- .cp_kind_check(.cp_kinds(root), kind, "study_checkpoint")`, add:

```r
  if (.cp_is_closed(root)) {
    warning("study_checkpoint(): the study is closed; recording the ",
            "checkpoint anyway", call. = FALSE)
  }
```

and directly before the final `invisible(.cp_result(final, snap))`, add:

```r
  if (identical(kind, "manuscript_published")) {
    message("The study can now be closed as published: ",
            "study_close(\"published\", publication = list(...))")
  }
```

`.cp_is_closed()` returns `FALSE` when `.checkpoint/repo` does not exist, so this adds no repository to a study that has none.

- [ ] **Step 4: Document and run**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "study_close|study_checkpoint|checkpoint_deliver")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/study_close.R R/study_checkpoint.R tests/testthat/test-study_close.R man/ NAMESPACE
git commit -m "feat: study_close() and study_reopen() with closure tags"
```

---

### Task 11: Checkpoints and closure in `study_status()`

**Files:**
- Modify: `R/study_status.R` (new helper; `checks` rbind; print marks)
- Modify: `tests/testthat/test-study_status.R` (append)

**Interfaces:**
- Consumes: `.cp_log_read()`, `.cp_is_closed()`.
- Produces: `.status_checkpoints(root)` returning `NULL` (no `.checkpoint/`) or a data.frame of rows `checkpoints` (status `OK` or `PENDING`) and, when closed, `closure` (status `CLOSED`).

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-study_status.R`:

```r
test_that("study_status adds no checkpoint row to a study without one", {
  root <- file.path(withr::local_tempdir(), "s")
  study_setup(root, "No checkpoints", 7L)
  expect_false("checkpoints" %in% study_status(root)$checks$item)
})

test_that("study_status reports checkpoints, pending pushes and closure", {
  skip_if_no_git()
  local_git_env()
  root <- make_checkpoint_study(withr::local_tempdir())
  study_checkpoint("abstract_submitted", root = root)
  study_close("abandoned", closed_at = as.Date("2026-11-14"), root = root)
  checks <- study_status(root)$checks
  cp <- checks[checks$item == "checkpoints", ]
  expect_equal(cp$status, "PENDING")
  expect_match(cp$detail, "2 recorded")
  expect_match(cp$detail, "2 not pushed")
  expect_match(cp$detail, "2 not in ST")
  cl <- checks[checks$item == "closure", ]
  expect_equal(cl$status, "CLOSED")
  expect_equal(cl$detail, "abandoned (2026-11-14)")
  expect_output(print(study_status(root)), "closure")
})
```

- [ ] **Step 2: Run to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "study_status")'`
Expected: FAIL on the second test (no `checkpoints` row).

- [ ] **Step 3: Implement**

In `R/study_status.R`, add before `study_status <- function(`'s roxygen block:

```r
# Checkpoint and closure rows. Absent for a study that has never been
# checkpointed, so the audit of a plain study is unchanged.
.status_checkpoints <- function(root) {
  if (!dir.exists(file.path(root, ".checkpoint"))) return(NULL)
  log <- .cp_log_read(root)
  count <- function(channel) {
    sum(vapply(log, function(e) identical(e$delivery[[channel]], "pending"),
               logical(1)))
  }
  git_pending <- count("git")
  last <- if (length(log)) log[[length(log)]] else NULL
  when <- .cp_or(last$occurred_at, .cp_or(last$closed_at, last$reopened_at))
  detail <- paste0(
    length(log), " recorded",
    if (!is.null(last$tag)) paste0(" (last ", last$tag, ", ", when, ")"),
    if (git_pending) paste0("; ", git_pending, " not pushed"),
    if (count("st")) paste0("; ", count("st"), " not in ST")
  )
  rows <- .status_row("checkpoints", if (git_pending) "PENDING" else "OK",
                      detail)
  closed <- tryCatch(.cp_is_closed(root), error = function(e) FALSE)
  closures <- Filter(function(e) identical(e$type, "closure"), log)
  if (closed && length(closures)) {
    lc <- closures[[length(closures)]]
    rows <- rbind(rows, .status_row("closure", "CLOSED",
                                    paste0(lc$outcome, " (", lc$closed_at, ")")))
  }
  rows
}
```

In `study_status()`, change the `checks` element of `out` to:

```r
    checks = rbind(row_yml, row_lock, row_man, row_data,
                   default_update,
                   named_rows,
                   .status_provenance(root),
                   .status_checkpoints(root)),
```

In `print.study_status()`, extend `mark`:

```r
    "UPDATE STATUS UNKNOWN" = "[?]",
    PENDING = "[~]",
    CLOSED = "[x]"
```

- [ ] **Step 4: Run to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "study_status")'`
Expected: PASS, including every pre-existing `study_status` test.

- [ ] **Step 5: Commit**

```bash
git add R/study_status.R tests/testthat/test-study_status.R
git commit -m "feat: study_status() reports checkpoints and closure"
```

---

### Task 12: Reference index, NEWS and the full gate

**Files:**
- Modify: `_pkgdown.yml` (new section after `Study Setup`)
- Modify: `NEWS.md`

- [ ] **Step 1: Add the reference section**

In `_pkgdown.yml`, after the `Study Setup` section's `- preflight_report` line, add:

```yaml

- title: Study Checkpoints
  desc: Snapshot a study's code and documents at each checkpoint, and record its closure
  contents:
  - study_checkpoint
  - study_checkpoint_push
  - study_close
```

(`study_reopen` shares the `study_close` topic through `@rdname`.)

- [ ] **Step 2: Add the NEWS entry**

At the top of `NEWS.md`, above `# hvtiRutilities 1.4.0`, add:

```markdown
# hvtiRutilities (unreleased)

## New features

* `study_checkpoint()` commits an allow-listed snapshot of a study (code,
  identity, reproducibility files and the documents in `50_documents/`) to a
  private repository in `.checkpoint/repo/`, tags it with a StudyTracker
  checkpoint kind such as `manuscript_submitted-1`, records it in the outbox
  `.checkpoint/log.yml`, and pushes it when `_study.yml` names a
  `checkpoint: remote:`. Data never enter the snapshot. A checkpoint is
  committed locally first, so an unreachable remote never loses one;
  `study_checkpoint_push()` retries. A study whose identity is unverified is
  committed but not pushed.

* `study_close()` closes a study as published, not published, superseded or
  abandoned, with a final snapshot tagged `closed-<outcome>-<n>`;
  `study_reopen()` reopens it. `study_status()` reports checkpoints, pending
  deliveries and closure.

```

If the heading already exists (PR #146 landed first), add the two bullets under its `## New features` instead.

- [ ] **Step 3: Run the full gate**

Run each and read the output, not just the exit status:

```bash
Rscript -e 'devtools::document()'
git diff --exit-code man/ NAMESPACE DESCRIPTION
R CMD INSTALL --no-docs .
Rscript -e 'devtools::test()'
Rscript -e 'Sys.setenv(LINTR_ERROR_ON_LINT = "true"); lintr::lint_package()'
Rscript -e 'devtools::check()'
Rscript -e 'pkgdown::check_pkgdown()'
```

Expected: `git diff` empty after `document()` has been committed; all tests pass with the checkpoint tests **run, not skipped** (the summary's SKIP count must not include `git is not available`); zero lints; `check()` 0 errors, 0 warnings, 0 notes; `check_pkgdown()` reports no problems.

- [ ] **Step 4: Commit**

```bash
git add _pkgdown.yml NEWS.md man/ NAMESPACE
git commit -m "docs: reference index and NEWS for study checkpoints"
```

---

## Deviations from the spec, decided while planning

- **`.checkpoint/` layout.** The clone is `.checkpoint/repo/`, with `log.yml` and `kinds.yml` beside it, so the log is never committed (spec section 3.0 updated).
- **Always commit.** `CHECKPOINT.yml` differs on every checkpoint, so the "no change: tag the existing commit" rule was dropped (spec updated).
- **Closure state from counts,** not tag dates, which can tie within one second (spec 6.4 updated).
- **Replay instead of rebase** on divergence, using `git commit-tree` (spec 6.1 updated).
- **No ST delivery hook in the core.** `qhsprograms` reads the log and marks `st: delivered` itself (spec step 6 updated).
- **Renumbered tags keep their original message,** so a tag renamed from `-1` to `-2` still names `-1` in its subject line. The log's `renumbered_from` field is the record.
- **Warnings.** A failed push warns; an unverified identity prints a message; no remote configured is silent, since a study may not have been given a remote yet.
