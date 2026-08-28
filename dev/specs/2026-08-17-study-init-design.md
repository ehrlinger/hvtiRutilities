# Study Initialization — `study_init()` and `study_status()`

**Date:** 2026-08-17
**Status:** Approved design, pending implementation plan
**Package:** `hvtiRutilities`
**Predecessor:** `specs/plans/2026-08-17-hvtirutilities-provenance.md` (Stage 1)
**Successor:** study close-out (deferred; see *Sequencing*)

## Context

Stage 1 gave the package a study manifest reader (`study_config()`) and a
per-job provenance sidecar (`record_provenance()`). Both assume a `_study.yml`
already exists. Nothing creates one.

This design started as a study *close* task — record the reference once a paper
is accepted, and record how the result reproduces. Examining a real study
showed that close-out is the wrong end of the problem.

The study examined is
`/Volumes/qhsstudies/cardiac/valves/aortic/replacement/pericardial/lv_function/survival`.
Measured, not assumed:

| Observation | Value |
|---|---|
| `_study.yml` | absent |
| `manifest.yaml` | absent |
| `renv.lock` | present at the study root, git-tracked |
| `.provenance.json` files | zero, anywhere in the tree |
| SAS jobs | **187** `.sas` files study-wide, 59 of them at the top level of `analyses/`, most with `.log` and `.lst` siblings |
| R sources | 28 `.R`, 12 `.qmd` — the latter across `analyses/R_hazard/` and `analyses/R_parity/`, with `index.qmd` appearing in both |
| `documents/` | 57 entries, flat, one empty `templates/` subdirectory |
| git | 61 commits, **no remote**, 525 of 1322 files tracked, 50 uncommitted changes, no tags |
| `.gitignore` excludes | `*.sas7bdat`, `*.doc`, `*.rtf`, `*.pdf`, `bh.*.log` |

Two findings drive this design.

**A close-out function cannot manufacture evidence that was never recorded.**
Run against this study today, close-out could only report that the identity,
the dataset checksum, and the per-job provenance are all missing. That is a
true report and a useless one: the paper is already published. Everything
close-out would want to know had to be captured while the study was running.

**The provenance that exists is the part git was told to skip.** The dataset,
the manuscripts, the tables, and the SAS logs are all in `.gitignore`. The
repository is also local-only with no remote, so it is one disk away from
being nothing. Version control is not, in this tree, a provenance mechanism.

The corrective is pressure at study birth. A study that starts with a
`_study.yml`, a `renv.lock`, and a `manifest.yaml` pinning its input dataset is
a study whose eventual close-out has something true to record. That is what
this design builds.

## Scope

**In scope — three functions.**

- `study_status(root)` — read-only compliance audit. Works on any directory,
  including a study with no `_study.yml` and no R code at all.
- `study_init(root, study, built, event, time, population = NULL,
  source = NULL, extract_date = NULL)` — writes `_study.yml` and seeds
  `manifest.yaml`. Derives the cohort counts from the data rather than
  accepting them as arguments.

  `source` and `extract_date` exist because they are passed straight to
  `update_manifest()`, whose `extract_date` defaults to `Sys.Date()`. On a
  dataset built in 2006 that default writes a false fact into the manifest, so
  the argument is exposed and left `NULL` — meaning "not recorded" — rather
  than silently defaulted.
- `study_checklist(status)` — renders an audit to markdown, machine-verified
  items ticked, human items open.

**Out of scope — running `renv::init()`.** `study_init()` reports a missing
`renv.lock` as an open checklist item and does not create one.
`renv::init()` restarts the R session, rewrites `.Rprofile`, and discovers
dependencies across the whole project; on a network share holding 1322 files
that is slow and surprising. A function whose job is to write two small YAML
files must not hijack the session. The lockfile stays a human step, named
explicitly in the checklist.

**Out of scope — study close-out.** Specified separately once studies begin
life compliant. Its shape is settled and recorded under *Sequencing* so the
two halves do not drift, but it is not built here.

**Out of scope — SAS provenance harvesting.** A SAS `.log` contains the run
timestamp, the software release, the platform, the input dataset, and the
observation counts — a full provenance record in all but format. The log read
for this design (`analyses/bh.dead_s1.log`) reports SAS 8.2 (TS2M0) on
SunOS 5.9, run 2006-05-03 14:03, reading 3677 observations and reducing to
3049 — which independently corroborates the cohort `n` that Stage 1 carries
for this study.

Harvesting that into the provenance schema is tempting and deliberately
excluded. The institutional SAS licence expires 2027-09-29 and the migration
proceeds now regardless; a well-built SAS provenance path is a retention
mechanism for SAS. Reading stored logs needs no licence, so the option remains
open indefinitely. It is not taken here.

**Out of scope — validating that a study's results are correct.** These
functions record identity and pin inputs. `assert_cohort()` is the correctness
gate and already exists.

## Architecture

One auditor, two writers. `study_status()` is the only code that inspects a
study; `study_init()` calls it to decide what to report, and close-out will
later call the same function to compute its grade. Two near-identical scanners
would drift.

```
study_status(root)  ──┬──> study_init(root, ...)      writes _study.yml, manifest.yaml
   (read-only)        └──> study_checklist(status)    writes markdown
```

### The bootstrap problem

`study_init()` needs the cohort counts, and the way to get them is
`cohort_counts(read_built(cfg), cfg)`. But `read_built()` and `cohort_counts()`
take a `cfg` from `study_config()`, which reads the `_study.yml` that
`study_init()` has not written yet. Naively, init cannot run before it has run.

The resolution is that neither function needs a validated config — each touches
only a few fields. `built_path()` reads `cfg$root` and `cfg$built`;
`cohort_counts()` reads `cfg$cohort$event` and `cfg$cohort$time`. So
`study_init()` constructs a synthetic config in memory from its own arguments:

```r
cfg <- list(root   = root,
            built  = built,
            cohort = list(event = event, time = time))
```

and passes that. Task 4's own tests already exercise `cohort_counts()` with
exactly this shape of literal list, so the contract is established rather than
assumed. An implementer who does not see this will deadlock, which is why it is
written down here.

### What `study_init()` writes

`_study.yml` at the study root, in the schema Stage 1 validates:

```yaml
study: "Aortic valve replacement, pericardial — LV function and survival"
population: "First AVR, pericardial bioprosthesis"   # optional
built: "built080426.sas7bdat"                         # extension required
citation: ~                                           # null until published
cohort:
  n: 3049
  n_events: 1032
  n_censored: 2017
  event: "dead"
  time: "iv_dead"
```

`study`, `built`, `event`, and `time` come from the caller — they are identity
and cannot be inferred. The three counts are **derived**, never typed.
Hand-entered counts are the drift this design exists to remove: the Stage 1
plan records a SAS file in which the study path appears twice with two
different values because one copy of an edit was made and the other was not. A
number a human types is a number that can disagree with the data.

`citation` is written as an explicit null rather than omitted, so the key a
future close-out fills is visible in the file from day one.

`manifest.yaml` at the study root, seeded through the existing
`update_manifest()`:

```r
update_manifest(file          = built_path(cfg),
                manifest_path = file.path(root, "manifest.yaml"),
                n_rows        = nrow(d),
                source        = source)
```

`n_rows` is passed explicitly. `update_manifest()`'s automatic row counting for
`.sas7bdat` is gated behind `options(manifest.allow_heavy_rowcount = TRUE)`
because it loads the whole dataset; `study_init()` has already read the dataset
to derive the cohort, so it has the row count in hand and must not trigger a
second read.

### What `study_status()` reports

A list with a `checks` data frame — columns `item`, `status`
(`"OK"`/`"MISSING"`/`"FAIL"`), `detail` — and a small summary. The checks:

| Item | Passes when |
|---|---|
| `_study.yml` | present and `study_config()` parses it without error |
| `renv.lock` | present at the study root |
| `manifest.yaml` | present, and `verify_manifest(stop_on_error = FALSE)` reports no `FAIL` |
| `dataset` | the file named by `built` exists |
| `cohort` | `assert_cohort()` passes against the data as it stands now |
| `provenance` | count of outputs with a `.provenance.json` beside them |

Three of these checks depend on `_study.yml`: `dataset` and `cohort` cannot be
evaluated without knowing which file `built` names, and `manifest.yaml`'s
verification needs the dataset path. When `_study.yml` is absent or unparseable
those three report `MISSING` with the reason in `detail` — never `FAIL`. A check
that could not run is not a check that failed, and conflating the two would make
the audit unreadable on exactly the legacy studies it most needs to describe.

Counts are reported for R files, SAS jobs, and sidecars — not a categorical
tier label. The vault's own lesson from the `hvtiRtemplates` PHI incident is
that a filename is never evidence about its contents; four files were
misclassified from their names in a single branch. A study with a parity
testbed in `analyses/R_parity/` is not an R study because it contains `.R`
files, and `study_status()` must not claim otherwise. It counts what it sees
and leaves the interpretation to the reader.

`study_status()` never errors on an absent or malformed `_study.yml` — that is
the finding, not a failure. `study_config()` is called inside `tryCatch()` and
its error message becomes the `detail`.

## Errors

`study_init()` refuses in four cases, all of them conditions under which
writing would produce a false record:

1. **`_study.yml` already exists.** Error naming the path, instructing the
   caller to edit it. Never overwrite a study's identity — a silent overwrite
   would break every filed provenance sidecar that recorded its checksum.
2. **`built` has no file extension.** The same check `study_config()` makes,
   applied before writing rather than after. Anything `study_init()` writes
   must pass `study_config()`; a manifest that fails its own reader is worse
   than none.
3. **The dataset does not exist**, or `event`/`time` name columns it does not
   contain. `cohort_counts()` already raises the second; init lets it through
   rather than duplicating the message.
4. **The study root is not writable.** Error, not warning, consistent with
   Stage 1's rule for `record_provenance()`.

`study_status()` errors only if `root` does not exist. Everything else is a
reported check.

## Testing

`testthat` edition 3, reusing `make_study_fixture()` from Stage 1's
`tests/testthat/helper-study.R`, which already builds a disposable study tree
with a matching `.sas7bdat`.

The load-bearing test is a **round trip**: everything `study_init()` writes must
be readable by `study_config()` without error, and the cohort it derived must
satisfy `assert_cohort()` against the same data.

```r
test_that("study_init writes a manifest that study_config accepts", {
  skip_if_not_installed("haven")
  root <- withr::local_tempdir()

  # A dataset and nothing else: make_study_fixture() writes _study.yml, which
  # is what study_init() must create, so the fixture's manifest is removed
  # first. 20 rows, 8 events, by the fixture's construction.
  make_study_fixture(root, n = 20L, n_events = 8L)
  file.remove(file.path(root, "_study.yml"))

  study_init(root, study = "Test", built = "built_test.sas7bdat",
             event = "dead", time = "iv_dead")

  cfg <- study_config(root)               # must not error
  expect_equal(cfg$cohort$n, 20L)
  expect_equal(cfg$cohort$n_events, 8L)
  expect_true(assert_cohort(read_built(cfg), cfg))
})
```

Further tests:

- Derived counts match the fixture's construction, and are integer.
- `citation` round-trips as `NULL`, and the key is present in the file text.
- A second `study_init()` on the same root errors and leaves the first
  `_study.yml` byte-identical.
- `built` without an extension errors before anything is written — assert the
  absence of both output files afterwards.
- `manifest.yaml` is seeded and `verify_manifest()` passes on it; then perturb
  the dataset and confirm `verify_manifest()` reports `FAIL`.
- `study_status()` on a bare directory returns all-`MISSING` and does not error.
- `study_status()` on a fixture initialized by `study_init()` returns `OK` for
  `_study.yml`, `manifest.yaml`, `dataset`, and `cohort`, and `MISSING` for
  `renv.lock`.
- `study_checklist()` output contains a ticked item for every `OK` and an open
  item for every `MISSING`.
- `r_dir_impurities("R")` stays empty — the package's own purity rule.

Every skip must be an expected `skip_if_not_installed()`. A skip is not a pass.

## Success criteria

1. `study_init()` on a directory containing only a dataset produces a
   `_study.yml` that `study_config()` reads and an `assert_cohort()` that
   passes — verified by test, not inspection.
2. No cohort count is ever supplied by a human.
3. `study_status()` runs without error on the `survival` study as it stands
   today — no `_study.yml`, no `manifest.yaml`, 59 SAS jobs — and reports
   `renv.lock` as its one `OK`.
4. No study-specific literal appears in `R/`. Every study value is an argument
   or comes from `_study.yml` at run time. Carried forward from Stage 1.
5. `R CMD check --as-cran` stays at 0/0/0 with the manual built, under the
   10-minute budget.

## Sequencing

**Depends on Stage 1 Tasks 4 and 5**, which are open on
`feat/study-config-provenance` as of this writing. `study_init()` needs
`cohort_counts()` and `assert_cohort()` (Task 4); `study_status()`'s provenance
count needs `provenance_path()` (Task 5). This work cannot start until that
branch merges.

**Close-out, deferred.** Its shape, settled during this design and recorded so
the two halves share a data model:

- `documents/_publications/<slug>.yml` — one record per accepted paper:
  citation block (journal, year, DOI, PMID, and the study's internal tracking
  number, e.g. `R606220`), `accepted:` date, the accepted manuscript file plus
  its SHA-256 (git ignores `*.doc`), the exhibit list, and `status:` /`gaps:`.
- Grade vocabulary: `verified` (identity, lockfile, verified manifest, and a
  sidecar per exhibit), `partial` (R present, something named in `gaps`
  missing), `legacy` (SAS only — recorded, not re-derivable).
- Close-out **records, it does not enforce.** Pressure at acceptance is
  pressure applied years too late; that is the argument this whole design turns
  on. It refuses nothing but a manuscript file that does not exist.
- Manuscript folders follow `<study root>/documents/manuscript/` with
  `revision/` subfolders for new work. The `survival` study's flat 57-file
  `documents/` — revisions as `rev 1.4`/`rev1.2`/`Rev 1` filename suffixes,
  several papers and grant proposals intermixed, Word lock files present — is
  what legacy close-out will actually meet, and it is not parseable. Legacy
  closes record `exhibits: []` and are annotated by hand only when a specific
  paper is worth it.

**Version.** The implementation bumps the patch digit from whatever Stage 1
lands as (`1.0.7` → `1.0.8`). Both `DESCRIPTION` line 4 and the `NEWS.md`
top heading, which a test greps.

## Deliberate omissions

- **No `study_close()` here.** Named and shaped above; specified separately.
- **No git integration.** The study repository has no remote, tracks 40% of
  the tree, and excludes every artifact that matters. Recording a commit SHA
  would imply a recoverability that does not exist. Revisit if and when git
  adoption across the team is real — that is an organizational question, not a
  package feature.
- **No interactive prompting.** `study_init()` takes arguments and errors on
  what it cannot derive. A function that asks questions cannot be called from
  a script, and the whole point is that study setup becomes scriptable.
