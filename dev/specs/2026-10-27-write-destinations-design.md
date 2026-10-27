# Write destinations: design and compatibility plan

Status: **approved by John on 2026-10-27**, and implemented on `fix/write-destinations`.

Finding 2 of the 1.5.15 release review (ehrlinger/hvtiRutilities#257,
comment 6447632915) says that `update_manifest()` writes `manifest.yaml` into
`getwd()` when it is not given a destination, and it names
`declare_data(root = getwd())` and `cache_fit(dir = study_dir("estimates"))`
as the same pattern. The CRAN Cookbook's code chapter asks that a function
never write by default into the user's filespace, the working directory
included, and that it require a destination or use temporary or cache space
instead.

## What the package does today

Every exported writer was audited on `main` at 1.5.15. They fall into three
groups.

**1. A bare write into `getwd()`.** Only two functions do this.

| function | default | what happens outside a study |
|---|---|---|
| `update_manifest(file, ...)`, the single-file form | `manifest_path = "manifest.yaml"` | writes `./manifest.yaml`. Inside a study it also writes into the working directory, not the study root. A template job renders with `execute_dir` set to its taxonomy folder, so there it would write `30_analyses/manifest.yaml` |
| `study_setup(root = NULL)` | walks up for `_study.yml`, then falls back to `getwd()` (`.study_setup_root()`) | sets up a study in the working directory. An empty directory is set up without `adopt`; a non-empty one errors unless `adopt = TRUE` |

**2. Walk up to the study marker, and error if there is none.** These
functions call `study_config()`, `study_root()` or `study_dir()`, which start
at `getwd()`, look upward for `_study.yml`, and stop with "no _study.yml
found" when they reach the filesystem root without finding one. They write
only inside a study that someone has already created.

`declare_data(root = getwd())`, `register_data(root = getwd())`, the no-file
`update_manifest()`, `cache_fit(dir = study_dir("estimates"))` (which also
refuses a `dir` that does not exist), `add_abbreviation(start = getwd())`,
`study_update_identity(start = getwd())`, `study_declare(root = NULL)`,
`study_need(root = NULL)`, `study_checkpoint()`, `study_checkpoint_push()`,
`study_close()`, `study_reopen()` (all `root = study_root()`), the deprecated
`adopt_data_update(cfg = study_config())`, and `read_built()`'s parquet side
cache (`cfg = study_config()`).

**3. Destination required.** `publish_provenance()`, `record_provenance()`,
`write_macro_manifest()`, `write_collision_report()`, and
`study_checklist(path = NULL)`, which writes only when it is given a `path`.

## Proposal

### Group 1: require a destination (breaking, small)

- **`update_manifest(file, manifest_path = NULL)`.** With `NULL`, the
  single-file form writes the enclosing study's manifest,
  `<study root>/manifest.yaml`. That is the file the no-file form and
  `verify_manifest()` already use. Outside a study it **stops** with a message
  that names `manifest_path`, and nothing is written. Passing `manifest_path`
  works exactly as it does today. The no-file form still refuses
  `manifest_path` whenever it is passed. Its `missing()` check is unchanged.
- **`study_setup(root = NULL)`.** With `NULL`, it walks up for `_study.yml`
  and re-runs setup on the study it finds, as today. When there is no study
  above, it **stops** and asks for `root`. It no longer creates a study in
  the working directory unasked. Creating a study then always names its
  directory. To set up the current folder, call
  `study_setup(root = ".", adopt = TRUE, ...)`. *Correction found during
  implementation:* the approved text said `root = "."` alone would still work
  in an empty folder. It does not. An existing root that is named explicitly
  has always needed `adopt = TRUE`, and an RStudio project is never empty,
  because it holds its `.Rproj`. Only the bare `getwd()` fallback had skipped
  that check, and that fallback is the thing being removed. The new error
  names both forms.

### Group 2: keep the walk-up, and say so in the signature

These are not default writes into `getwd()`. A write happens only inside a
tree that someone marked as a study by creating `_study.yml`, and every one
of them errors outside such a tree. This is the active-project convention
that 'usethis' (`proj_get()`) and 'renv' use on CRAN. Requiring an explicit
root on every call would break every template job, about 170 tests across
the family, and interactive use, and it would buy no safety: the marker
check is the safety.

The change here is to make the contract visible, with no change in behaviour:

- Default `root`/`start` to `study_root()` rather than `getwd()` in the four
  functions that spell it as `getwd()`: `declare_data`, `register_data`,
  `add_abbreviation` and `study_update_identity`. Each already passes it
  through `study_config()`, so the resolved directory is the same.
- Give each group-2 `@param` the same sentence: "Defaults to the study that
  contains the working directory, found by its `_study.yml`; outside a study
  the function stops and writes nothing."
- Add a test per function that it errors and writes nothing when it is called
  from a temporary directory that holds no `_study.yml`.

The record should keep one sentence of reasoning here, so that a later
Cookbook audit does not re-raise this finding without seeing why it was
closed.

### Out of scope, and listed as follow-ups

- `read_built()`'s parquet side cache writes beside the source, inside the
  study. The Cookbook would prefer `tools::R_user_dir()` for a cache, but this
  cache is deliberately shared across the team on the study share. It can be
  switched off with `options(hvtiRutilities.disable_parquet_cache = TRUE)`.
  Leave it as it is.
- Readers that take a file in the working directory by default
  (`apply_label_overrides("labels_overrides.yml")`, `clean_labels()`,
  `apply_value_labels("value_labels.yml")`) read and never write. They are
  not in scope.
- `hvtiR::setup(root = NULL)` falls back to `getwd()` through
  `study_root_or_wd()`, then passes that `root` explicitly. Under this
  design it keeps working unchanged, but the getwd() fallback now lives in
  hvtiR. Whether hvtiR should keep it is a decision for that package, like
  hvtiRtemplates' recorded `add_job(dir = NULL)` decision, which only walks
  up and errors outside a study.

## Who is affected

Measured against `origin/main` of each repository on 2026-10-27.

| caller | today | after |
|---|---|---|
| hvtiRtemplates templates: `bd.qmd`, `sid-clusters.qmd` | no-file `update_manifest()` under `setwd(.root)` / `with_dir(.root)`; `declare_data(.root)` and `register_data(.root)` | unchanged |
| hvtiRtemplates templates: 39 `cache_fit()` calls | all pass `dir = CACHE_DIR` | unchanged |
| hvtiRtemplates tests: about 45 `study_setup()` calls | all pass `root` | unchanged |
| hvtiRtemplates wrappers: `add_job` / `open_job(dir = NULL)` | `.default_study_root()` walks up and errors outside a study | unchanged |
| hvtiRdatabuild: `analysis_set.R:431`, `snapshot_oracle.R:116` | pass `manifest_path` | unchanged |
| hvtiRdatabuild: `write_analysis_set(cfg = study_config())` | walk-up | unchanged |
| hvtiR `setup()` | passes `root` explicitly | unchanged |
| hvtiRutilities tests: 64 single-file `update_manifest()` calls | pass `manifest_path` | unchanged. `test-manifest.R:187` already expects an error |
| hvtiRutilities `test-study_setup.R:242-262` | tests the `getwd()` fallback | rewritten to expect the new error, plus a test for the walk-up re-run |
| hvtiRutilities vignettes | every single-file call passes `manifest_path` | unchanged |
| an analyst calling `update_manifest("x.csv")` outside a study | writes `./manifest.yaml` | **error** that names `manifest_path` |
| an analyst calling `update_manifest("x.csv")` inside a study, from a subfolder | writes `<subfolder>/manifest.yaml`, a stray file the study never reads | writes the study's manifest. This is a fix |
| an analyst calling `study_setup()` with no `root` in an empty folder | creates the study there | **error** that asks for `root`, or for `root = ".", adopt = TRUE`. hvtiRtemplates' study-setup article already shows that form |

## Deprecate or require?

**Require, in one step.** No known caller relies on either group-1 default.
A deprecation cycle would keep the default write for at least one more
release, which leaves the finding open for that release. It would also mean
a warning that only someone who has never set a destination would see, and
those are the callers this design is meant to stop. Both errors name the
argument to pass, so the fix at a call site is one argument.

Both are breaking changes to exported defaults. Under the versioning rule
they still ship as a patch; whether this warrants the next minor is John's
call when he names the version. Each NEWS bullet starts with "Breaking:".

## What a study job sees

Nothing changes. Template jobs pass `dir`, `root` and `.root` explicitly,
or run the no-file form from the study root. The behaviour that changes is
reachable only from code that calls `update_manifest(file)` without
`manifest_path`, or `study_setup()` without `root` outside a study, and
neither appears in any template.

## Plan, after approval

One PR, `fix/write-destinations`:

1. `update_manifest()`: `manifest_path = NULL`, resolution and error, the
   no-file guard, docs, tests (outside a study errors and writes nothing;
   inside a study from a subfolder writes the root manifest).
2. `study_setup()`: error when `root` is `NULL` and no study is found; docs;
   rewrite `test-study_setup.R:242-262`.
3. Group 2: `root`/`start` defaults spelled `study_root()`, the shared
   `@param` sentence, and a no-study test per function.
4. News fragment, `devtools::document()`, `devtools::check()` at 0/0/0, and
   the hvtiRtemplates and hvtiRdatabuild suites against the branch.
