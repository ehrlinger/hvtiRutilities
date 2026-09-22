# Endpoint-Neutral Data Contract and Subject-Based Jobs

**Date:** 2026-09-21

**Status:** Approved in conversation; job-provenance amendment approved; awaiting implementation

**Packages:** `hvtiRutilities`, followed by `hvtiRtemplates`

## Purpose

Register a study dataset as soon as the data exists, without requiring an
analysis endpoint that may not yet be known. Keep analysis jobs independently
configurable so a study can add mortality, reoperation, stroke, or other work
later without changing the registered dataset contract.

Jobs still need a stable leading identity field so related files and artifacts
sort together. That field is a **subject**, not necessarily an endpoint. An
endpoint-driven job may use `death` as its subject; an endpoint-free job may use
`cohort`, `treatment`, or `labs` without inventing an outcome.

## Problem

The current study contract combines two decisions made at different times:

1. Dataset registration records a file, release, checksum, dimensions, source,
   and extraction date.
2. Analysis configuration selects an event column, time column, event coding,
   and analysable cohort.

`register_data()` currently requires one event/time pair for the default study
dataset. `_study.yml` then stores one cohort definition and its counts. This is
too early and too narrow:

- data commonly arrives before analysis templates are selected;
- one dataset can support several endpoints;
- additional endpoints are often requested late in a study;
- some templates are descriptive or otherwise not endpoint-driven; and
- a categorical event-type column cannot be represented safely by the current
  binary count, which counts only value `1` and treats every other nonmissing
  value as a non-event.

The template layer has a related naming problem. Its leading `endpoint` field
already means “subject” for EDA jobs, where values such as `cohort` do not name
an outcome. The field's behavior is useful, but its name is false.

## Design Principles

1. **Registration describes data, not an analysis.** Registering a file must
   not choose an endpoint.
2. **Jobs own analysis choices.** Event, time, outcome, coding, and filters live
   in the job that uses them.
3. **Every job has a subject.** The subject groups related authored files and
   generated artifacts whether or not the job has an endpoint.
4. **No implicit event coding.** A helper must not interpret competing-event
   codes as censoring.
5. **One authority per fact.** `_study.yml` is authoritative for registered
   datasets; each job is authoritative for its own analysis definition.
6. **Make the clean break now.** The superseded API has not stabilized, so this
   change does not add aliases or a deprecation period.

## Chosen Architecture

The workflow has three one-way layers:

```text
registered dataset -> independently scaffolded job
                   -> optional job-specific outcome and cohort
                   -> output provenance
```

No endpoint or cohort choice flows backward into dataset registration.

### Dataset contract

The default dataset in `_study.yml` contains its filename and optional study
metadata. A release-aware example is:

```yaml
study: "Example study"
population: "Adults undergoing index cardiac surgery"
built: "cohort_20260920.csv"
release:
  dataset_id: "surgery_cohort"
  release_id: "surgery_cohort-20260920-r1"
```

A named dataset uses the same shape beneath `additional_datasets`:

```yaml
additional_datasets:
  imaging:
    built: "imaging_20260920.csv"
    population: "Patients with interpretable baseline imaging"
    release:
      dataset_id: "imaging_cohort"
      release_id: "imaging_cohort-20260920-r1"
```

Neither shape contains a `cohort` block. `manifest.yaml` continues to record
file-level integrity and provenance: checksum, row and column counts, source,
and extraction date.

### Job identity

The template naming grammar becomes:

```text
<subject>-<analysis-type>-<job-type>[-<qualifier>].qmd
```

Examples:

```text
death-hz-ac.qmd
death-hz-hm.qmd
cohort-eda-dc-tables.qmd
treatment-balance-dc-tables.qmd
labs-trends-dp.qmd
stroke-rfs-rfs-fit.qmd
```

The set key remains a two-field key, now named `(subject, type)`. Generated
artifacts continue to live under `<subject>-<type>/`, so jobs in the same set
sort and resolve together.

Every scaffolded job declares:

```r
SUBJECT <- "death"
TYPE    <- "hz"
```

Only a template that needs an outcome declares additional analysis variables.
For example, a survival job may declare:

```r
EVENT <- "dead"
TIME  <- "iv_dead"
```

An endpoint-free job declares no fake `EVENT`, `TIME`, or `OUTCOME` value.

## `hvtiRutilities` Changes

### Registration API

`register_data()` drops `event` and `time`:

```r
register_data(
  root = getwd(),
  built,
  dataset = "study",
  role = c("study", "named"),
  population = NULL,
  source = NULL,
  extract_date = NULL,
  catalog_dataset = NULL,
  release_id = NULL
)
```

The function continues to:

- validate the logical dataset name and role;
- require one filename with an extension;
- locate and read the registered file;
- reject case-folding column-name collisions;
- verify a supplied published catalog release;
- derive manifest dimensions and checksum; and
- replace `_study.yml` and `manifest.yaml` as a recoverable pair.

It no longer derives or writes cohort counts.

### Study configuration and dataset resolution

With `require_data = TRUE`, `study_config()` requires `study` and a registered
default `built` file. It does not require `cohort.n`, `cohort.n_events`,
`cohort.n_censored`, `cohort.event`, or `cohort.time`.

`.study_dataset()` returns dataset identity, population, and release metadata.
It does not expose a dataset-level cohort contract.

Existing `cohort` keys may parse as additive YAML fields during the cutover,
but no package function reads them or treats them as authoritative. New writes
do not produce them.

### Cohort helpers

`cohort_counts()` and `assert_cohort()` remain exported because a job may still
need a reproducible cohort gate. They stop reading `_study.yml` and instead
take the job's definition explicitly:

```r
cohort_counts(d, event, time)
assert_cohort(d, expected, event, time)
```

`event` and `time` are scalar column names. Among rows where both are present,
the event column must contain only binary values (`0`/`1` or
`FALSE`/`TRUE`). Any other observed value is an error rather than an implied
non-event. The return remains integer `n`, `n_events`, and `n_censored` so
existing downstream reporting concepts remain clear.

A job using a categorical event-type column must derive the binary indicator
for the endpoint it is analysing before calling these helpers. This derivation
belongs to the job because only the job knows whether a competing event is a
non-event, an exclusion, or part of a multistate analysis.

`expected` supplies the three counts directly to `assert_cohort()`. The helper
does not look up a study-wide reference.

### Status and data updates

`study_status()` reports the health of study identity, registered datasets,
the manifest, release pins and update availability, project structure, and
other existing non-cohort checks. It removes `cohort:<dataset>` rows. A valid
endpoint-free study is not incomplete.

`review_data_update()` compares the pinned and candidate datasets without
calculating study-level old and new cohort counts. `adopt_data_update()`
updates the registered filename, release pin, and manifest entry without
rewriting a cohort definition. Dataset comparison still exposes structural and
value changes that a reviewer can inspect before adoption.

### Provenance

`record_provenance()` always records the exact registered dataset, its hash,
the study manifest, R and package versions, and the lockfile state. It no
longer refuses to run when a dataset has no cohort contract and no longer
creates a required top-level cohort block from `_study.yml`.

A template adds job-specific metadata through the existing `extra` mechanism.
The required top-level keys remain `job`, `rendered`, `study`, `r`, `packages`,
`renv_lock`, and `data`. `extra` may append `subject`, `type`, `analysis`, or
`cohort`, but it cannot replace a required key.

## `hvtiRtemplates` Changes

### Public APIs

APIs that scaffold, locate, open, or migrate jobs rename the `endpoint`
argument to `subject`. This includes `add_job()`, `open_job()`, `migrate_job()`
and their internal path helpers. No `endpoint` alias or deprecation warning is
added.

The validation grammar remains `^[A-Za-z0-9_]+$` because subject and type are
still filename fields separated by `-` and terminated by an extension.

### Template markers and paths

All template marker lines change from `ENDPOINT` to `SUBJECT`. Marker
substitution, filename self-checks, set paths, artifact paths, error messages,
and template tests use `SUBJECT` and `TYPE` consistently.

Templates must not infer that `SUBJECT` names a data column or outcome.
Outcome-specific declarations remain local to the templates that require them.
The `EVENT`, `TIME`, or `OUTCOME` names are not standardized across unrelated
analysis families merely to create a uniform appearance.

### Rendered job provenance

Every shipped template ends with a `provenance` chunk that calls
`hvtiRutilities::record_provenance()` directly. Keeping the call in the
template gives the Render button, `quarto render`, and `render_job()` the same
behavior. A successful render therefore produces an HTML result and a JSON
sidecar with the same stem in the same directory:

```text
death-hz-hz.qmd
death-hz-hz.html
death-hz-hz.provenance.json
```

The setup chunk already recovers the current input as an absolute path in
`.in`. During a Quarto render that path may name the intermediate
`.rmarkdown` file, but its directory and extensionless basename are the source
job's directory and stem. The final chunk derives the eventual HTML path from
that recovered stem:

```r
.job_stem <- tools::file_path_sans_ext(basename(.in))
.output <- file.path(dirname(.in), paste0(.job_stem, ".html"))
```

It does not use `getwd()` as a provenance fallback. If no render input is
available, the chunk stops instead of writing a sidecar for a guessed job.
`record_provenance()` does not require the HTML file to exist yet, so the chunk
can run at the end of document execution before Quarto writes the final HTML.

Every job records its declared `SUBJECT` and `TYPE` as top-level extra fields.
An endpoint-free job records no `analysis` or `cohort` field unless that job
actually defines and observes one:

```r
extra <- list(
  subject = SUBJECT,
  type = TYPE
)
```

An endpoint-driven job records the local declarations and coding used by that
template. For a survival job whose local names are `TIME` and `STATUS`, and
whose cohort chunk has already produced `cc`, the shape is:

```r
extra <- list(
  subject = SUBJECT,
  type = TYPE,
  analysis = list(
    time = list(variable = TIME),
    event = list(variable = STATUS, event = 1L, censored = 0L)
  ),
  cohort = cc
)
```

The template uses its own declarations rather than renaming them to fit this
example. A classification job may instead record its response variable,
observed levels, and selected target level:

```r
analysis <- list(
  outcome = list(
    variable = RESPONSE,
    kind = "classification",
    observed_levels = levels(d[[RESPONSE]]),
    target_level = ROC_CLASS
  )
)
```

A job that explains or plots a stored fit takes outcome details from the fit or
its handoff metadata. It never derives them from `SUBJECT`. If the artifact does
not carry enough information to name the variables or coding, implementation
must preserve that information in the artifact or declare it in the consuming
job. It must not guess.

Counts describe the rows the job actually analysed. A template records them
when it has already computed them, or can read them from the fitted object
without reproducing the filtering logic. It does not substitute registered
dataset dimensions or expected reference counts for observed job counts. A
template with no local outcome or analysable-cohort definition records neither.
The dataset argument follows the data route the job used: a template with a
local `DATASET` choice passes it, while a job that reads the default registered
dataset keeps `dataset = "study"`.

### Documentation language

Documentation describes the leading field as the subject that groups a job
set. It uses “endpoint” only for a statistical endpoint, never as a synonym
for the first filename field.

## Failure Behavior

Failures stay at the layer that can explain them:

- Registration errors on missing or unreadable files, invalid names, invalid
  releases, checksum or dimension disagreements, duplicate registrations,
  derived-path collisions, malformed manifests, and incomplete pair
  replacement.
- Job scaffolding errors on an invalid subject or type, an existing target,
  missing or duplicate `SUBJECT`/`TYPE` marker lines, and a mismatch between a
  job's filename and declarations.
- `cohort_counts()` errors on missing event/time columns and on nonbinary
  observed event values.
- `assert_cohort()` errors when explicit expected counts disagree with the
  observed job cohort.
- Endpoint-free jobs do not warn or fail merely because no endpoint exists.
- A provenance-sidecar warning or error stops the render. The template does not
  return a successful result whose provenance could not be written.

## Direct Cutover

This change deliberately does not preserve the superseded public signatures or
template markers. Source, tests, generated documentation, vignettes, examples,
and current specifications change together.

No automatic job-file migration is included. Current scaffolded development
jobs can be renamed and have `ENDPOINT` changed to `SUBJECT` as part of the
coordinated repository update. Historical corpus parsing remains a separate
concern: parsers that describe legacy names may continue to use historically
accurate terminology where changing it would misdescribe the source format.
The updated catalog gives newly scaffolded jobs the provenance chunk; it does
not rewrite existing job files or add a compatibility path for jobs that omit
the chunk.

## Alternatives Rejected

### Keep an optional study-level cohort

Making the existing `cohort` block optional reduces the immediate diff but
leaves two authorities: some jobs would inherit a study endpoint while others
would declare their own. A rendered result would not make its source of truth
obvious.

### Store several named endpoints in `_study.yml`

This represents death, stroke, and reoperation but still makes an analysis
choice part of dataset registration. Late endpoint requests would mutate
study-level data metadata, and endpoint-free jobs would still sit awkwardly
outside the model.

### Retain `endpoint` as a generic grouping label

The existing behavior already stretches `endpoint` to mean `cohort` for EDA.
Keeping the name would preserve a semantic lie and encourage templates to
assume every subject is an outcome.

### Parse template source for provenance metadata

Parsing assignments from the `.qmd` would create a second interpretation of
the job. It would miss derived coding, filters, observed factor levels, and
counts that exist only after execution. The final chunk can record the objects
the analysis used, so it does not need to reconstruct them from source text.

### Infer provenance in `render_job()`

`render_job()` sees a path and the final-render flag, not the job's executed
objects. More importantly, authors also render from the editor and the Quarto
command line. Wrapper-only inference would omit provenance for those supported
paths and make identical jobs behave differently according to how they were
started.

### Keep job metadata in a separate registry

A registry would repeat `SUBJECT`, `TYPE`, outcome coding, and cohort facts
already declared in each job. The registry and the executable job could drift,
leaving the sidecar to describe metadata the render did not use. The job stays
the authority and records its runtime values directly.

## Verification

Implementation is complete only when both repositories pass their full gates
in dependency order.

### `hvtiRutilities`

Tests must cover:

- default registration without event/time arguments;
- named registration with the same endpoint-neutral contract;
- configuration and data reads without a cohort block;
- status with no cohort rows or missing-cohort findings;
- provenance for endpoint-free and endpoint-driven jobs;
- release review and adoption without cohort recalculation;
- explicit `cohort_counts()` and `assert_cohort()` calls;
- rejection of categorical or otherwise nonbinary event values; and
- preservation of registration's transactional manifest replacement.

Run documentation generation, the complete test suite, lint, package check,
manual build, pkgdown, and documentation-current verification. Every exported
signature and example must be regenerated, and `_pkgdown.yml` must remain
complete.

### `hvtiRtemplates`

Tests must cover:

- `subject` in every public job API;
- `<subject>-<type>` filenames and artifact directories;
- `SUBJECT`/`TYPE` marker substitution and filename consistency;
- endpoint-driven templates with local outcome declarations;
- endpoint-free templates without fake outcome declarations;
- exactly one final provenance chunk in every shipped template;
- an endpoint-free render whose sidecar has the rendered job stem, required
  provenance keys, `subject`, and `type`, with no invented `analysis` or
  `cohort` block;
- an endpoint-driven render whose sidecar has the local event/time or outcome
  coding and the observed job-cohort counts available to that template;
- protection of required keys when template extras are merged, and render
  failure when the sidecar cannot be written;
- migration and open-job paths; and
- the complete template catalog and render checks.

Regenerate documentation and run the complete test, lint, package-check,
pkgdown, and template-specific validation gates after installing the updated
`hvtiRutilities` dependency.

## Delivery Order

1. Implement and verify the endpoint-neutral data contract and explicit cohort
   helpers in `hvtiRutilities`.
2. Install that version locally for downstream validation.
3. Implement and verify subject-based job identity in `hvtiRtemplates`.
4. Review the combined diff for any remaining use of `endpoint` as the generic
   filename field or `cohort` as registered dataset metadata.

The two repositories require separate pull requests. `hvtiRutilities` lands
first because `hvtiRtemplates` imports it; neither change is pushed directly to
`main`.

## Non-Goals

- Defining a universal endpoint schema across survival, binary, continuous,
  longitudinal, competing-risk, and multistate analyses.
- Inferring event variables or coding from dataset contents.
- Choosing a primary endpoint for a study.
- Storing every job definition in `_study.yml`.
- Migrating the historical SAS corpus or renaming historical evidence files.
- Adding a compatibility layer for the superseded pre-stabilization APIs.
