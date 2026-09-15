# Add-job and Numbered-layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename `new_job()` to `add_job()` and place jobs correctly in
numbered new studies and unnumbered legacy studies.

**Architecture:** `hvtiRtemplates` delegates study-directory resolution to
`hvtiRutilities::study_dir()`. The template catalog continues reporting bare
logical folder names. No compatibility wrapper is retained because the API has
no adopted callers.

**Tech stack:** R 4.1+, testthat edition 3, devtools.

**Spec:** `2026-09-15-study-setup-legacy-adoption-design.md` in
`hvtiRutilities/dev/specs/`.

## Global constraints

- Begin only after the `study_dir()` release is installable.
- Preserve the 135-character limit and Rd roxygen syntax.
- Keep `_pkgdown.yml` without a `reference:` section.
- Add unreleased NEWS; do not bump the version in the feature PR.

---

### Task 1: Rename the public job creator

**Files:**
- Rename: `R/new-job.R` to `R/add-job.R`
- Rename: `tests/testthat/test-new-job.R` to `tests/testthat/test-add-job.R`
- Modify: `README.md`, `inst/templates/README.md`, `AGENTS.md`, `NEWS.md`
- Regenerate: `NAMESPACE`, `man/add_job.Rd`

- [ ] **Step 1: Rename tests and make them fail against `add_job()`**

Replace calls and expected error prefixes with `add_job()`. Add:

```r
test_that("the unused new_job name is not exported", {
  expect_false("new_job" %in% getNamespaceExports("hvtiRtemplates"))
  expect_true("add_job" %in% getNamespaceExports("hvtiRtemplates"))
})
```

- [ ] **Step 2: Confirm failure**

Run: `Rscript -e 'devtools::test(filter = "add-job")'`

Expected: FAIL because `add_job()` does not exist.

- [ ] **Step 3: Rename function, diagnostics, docs, and examples**

Rename the function and every current `new_job():` error prefix. Do not leave a
wrapper or alias. Change the example directory stem to `add-job-example`.

- [ ] **Step 4: Document and commit**

Run: `Rscript -e 'devtools::document()'`

Run: `Rscript -e 'devtools::test(filter = "add-job")'`

Expected: PASS.

Commit: `feat: rename job creation to add_job`

### Task 2: Resolve the study layout before writing

**Files:**
- Modify: `R/add-job.R`
- Modify: `DESCRIPTION`
- Modify: `tests/testthat/test-add-job.R`
- Modify: `README.md`, `inst/templates/README.md`, `AGENTS.md`, `NEWS.md`

- [ ] **Step 1: Add failing numbered, legacy, and mixed tests**

```r
test_that("add_job follows the study directory layout", {
  numbered <- make_job_study("numbered")
  legacy <- make_job_study("legacy")
  expect_match(add_job("ac", "dead", "hz", numbered),
               "20_distributions/dead-hz-ac[.]qmd$")
  expect_match(add_job("ac", "dead", "hz", legacy),
               "distributions/dead-hz-ac[.]qmd$")
})

test_that("add_job refuses a mixed study", {
  root <- make_job_study("numbered")
  dir.create(file.path(root, "analyses"))
  expect_error(add_job("ac", "dead", "hz", root), "mixed")
})
```

- [ ] **Step 2: Confirm failure**

Run: `Rscript -e 'devtools::test(filter = "add-job")'`

Expected: numbered and mixed-layout tests FAIL.

- [ ] **Step 3: Use the shared resolver**

Replace `file.path(dir, row$folder[[1L]])` with:

```r
out_dir <- hvtiRutilities::study_dir(row$folder[[1L]], root = dir)
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
```

Raise the minimum `hvtiRutilities` version to the release containing
`study_dir()`.

- [ ] **Step 4: Run all gates and commit**

Run: `Rscript -e 'devtools::test()'`

Run: `Rscript -e 'devtools::check(error_on = "never")'`

Expected: 0 failures and 0 errors/warnings/notes.

Run: `Rscript -e 'lintr::lint_package()'`

Expected: no new lints.

Commit: `feat: add jobs to numbered studies`
