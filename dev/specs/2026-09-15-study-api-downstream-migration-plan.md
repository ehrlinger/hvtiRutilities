# Study API Downstream Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove active `hvtiRdatabuild` development dependencies on
`study_init()` before that export disappears.

**Architecture:** Synthetic fixtures call `study_setup()` and
`register_data()` in sequence. User-facing guidance names the new recovery and
registration actions. No production data or credentials enter tests.

**Tech stack:** R 4.1+, testthat edition 3, devtools.

**Spec:** `2026-09-15-study-setup-legacy-adoption-design.md` in
`hvtiRutilities/dev/specs/`.

## Global constraints

- Apply to the active analysis-sets/release line containing `analysis_set.R`.
- Use synthetic fixtures only; no patient value may enter output.
- Keep lines at 100 characters and roxygen markdown enabled.
- Add unreleased NEWS; do not bump the version in the feature PR.

---

### Task 1: Migrate analysis-set fixtures and guidance

**Files:**
- Modify: `tests/testthat/helper-analysis-set.R`
- Modify: `R/analysis_set.R`
- Modify: `dev/specs/2026-09-14-analysis-sets-design.md`
- Modify: `dev/specs/2026-09-14-analysis-sets-plan.md`
- Modify: `NEWS.md`

- [ ] **Step 1: Change the fixture to the two-stage API**

```r
hvtiRutilities::study_setup(root, study = "Synthetic analysis-set fixture",
                            study_tracker_id = 1L, adopt = TRUE)
hvtiRutilities::register_data(root, built = basename(path),
                              event = "dead", time = "iv_dead")
```

Keep the existing synthetic dataset construction unchanged. Write it beneath
`hvtiRutilities::study_dir("datasets", root)`.

- [ ] **Step 2: Replace the runtime instruction**

Change the error to:

```r
stop("No registered study data. Run study-setup --recover when _study.yml ",
     "is missing, or hvtiRutilities::register_data() when data is not ",
     "registered.", call. = FALSE)
```

- [ ] **Step 3: Update current design/plan references**

Replace prescriptive `study_init()` calls in the active analysis-set documents
with the same two calls. Leave historical NEWS untouched.

- [ ] **Step 4: Run gates and commit**

Run: `Rscript -e 'devtools::test()'`

Run: `Rscript -e 'devtools::check(error_on = "never")'`

Expected: 0 failures and 0 errors/warnings/notes, with no real-data test run
unless `HVTI_ORACLE_DIR` was already explicitly configured.

Commit: `refactor: adopt two-stage study setup`
