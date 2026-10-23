# The working-read gate: draft or final, not the folder

**Date:** 2026-10-23
**Status:** design approved by John Ehrlinger on 2026-10-23: the direction (sections 3.1 to
3.4) and both follow-on questions (section 7). Not built.
**Amends:** section 5.1 of `2026-10-13-one-version-scheme-design.md` ("Working reads"), its
decision 5 ("Who may read the working file?") only. The other decisions there still stand,
the working read itself included.
**Packages:** hvtiRutilities (the gate, the provenance field) and hvtiRtemplates (the report,
the hand-off check). The hand-offs are listed in section 6.

This note is self-contained. It assumes no memory of the session that produced it.

⚠️ No study, variable value or patient identifier appears here.

## 1. The problem

A stat programmer building a study dataset wants to run notebooks against the build before
registering it. Today the stage gate in `.assert_working_stage()` (`R/working_read.R`) allows a
working read in two places only:

- the console, and
- jobs whose first folder under the study root is the `datasets` or `descriptive` folder.

That leaves out the case that matters while building: trying a distribution or analysis job
(`ac`, `hz`, a forest) on the build to see whether it holds up. The gate refuses it whether the
render is a throwaway draft or a result someone will cite.

At the same time it allows something it should not: a **final** descriptive render on
unregistered data. A final `dc-eda` report on the working file looks exactly like one on a
registered version, so the gate's own stated purpose, keeping unregistered data out of results,
is met only for the folders it happens to cover.

The folder is a stand-in for what the gate is really about: whether this run is a draft or a
result. hvtiRtemplates already knows that. Every job renders as a draft unless
`render_job(final = TRUE)` sets `HVTI_TEMPLATE_STRICT`, and background runs (`submit_job()`,
`run_job()`) go through the same switch.

## 2. What stays fixed

From the 2026-10-13 design, and not reopened:

- One working file per dataset, undated and overwritten in place. Only a registered dataset is
  dated.
- A working read is asked for with `working = TRUE` or `HVTI_DATA=working`, or happens when a
  dataset has no dated version. It writes nothing: no cache, no manifest entry.
- Every working read signals `hvtiRutilities_working_read`.
- A non-interactive session with no job file (a `source()` from a batch, `R CMD BATCH`) is
  refused.

## 3. Decisions

The aim, in John's words, is to **push users to registered data**: the working read is there
for building, and every path out of it should lead to `update_manifest()`.

| # | question | answer |
|---|---|---|
| 3.1 | What does the gate key on? | **Draft or final**, read from `HVTI_TEMPLATE_STRICT`. The folder no longer matters |
| 3.2 | May a final render read the working file? | **No, in every folder**, descriptive and datasets included |
| 3.3 | What does a draft on the working file look like? | **A draft in the report itself**: a callout at the read, the run marked a draft, a `Note` row in the data table |
| 3.4 | Can a draft's results reach a final report through another job? | **No.** A hand-off saved from working data is refused by a downstream final render |

### 3.1 Draft or final

The gate allows a working read when either:

- the session is interactive and no render is running (the console, unchanged), or
- a **render** is running (`knitr::current_input()` names the job) and **`HVTI_TEMPLATE_STRICT`
  is not set to a true value**: unset, empty, `0`, `false` or `no`, as hvtiRtemplates'
  `.strict_render()` reads it.

A script run with `Rscript` is treated as final. It has no draft banner, no run record and no
lineage on what it saves, so `HVTI_DATA=working Rscript 30_analyses/.../fit.R` must still be
unable to save estimates from unregistered data, which is why the 2026-10-13 design refused it.
That design allowed an `Rscript` job in the datasets and descriptive folders; this one does not,
since no folder differs any more. A script that needs the working file runs in the console.

It refuses otherwise. The refusal names the dataset and one exit, registering:

> `<job>` is a final render, and a final render reads registered data only. `<built>` has no
> registered version. Register it with `update_manifest()`, or render a draft.

When the working read was asked for (`working = TRUE` or `HVTI_DATA`) and a dated version
exists, the message names dropping the request as the exit instead, as it does today.

The job file must still sit inside the study root. A render of a file outside the study is
refused as today, so `HVTI_DATA=working` cannot reach a study's data from elsewhere.

hvtiRutilities reads `HVTI_TEMPLATE_STRICT` with the same parsing as `.strict_render()`. The
variable becomes a contract between the two packages: section 6 records it on both sides.

**Why not keep the folder rule as well.** Folder and draft were each a stand-in for "is this a
result". Keeping both would allow a final descriptive render on the working file, the case 3.2
removes, and still refuse a draft analysis, the case section 1 needs.

### 3.2 No final render on the working file, anywhere

This is the one change in behavior for existing jobs. A final `dc-*` render on a build that has
not been registered stops, where today it passes. That is intended: a final descriptive report
is a result, and its data should be a version someone can name.

`bd` itself is not affected. It reads the master snapshot with `arrow::read_parquet()`, not
through `read_built()`, so the gate never sees it. A final `bd` render with `REGISTER = TRUE` is
how the build becomes registered data in the first place.

### 3.3 A draft on the working file says so in the report

Today a working read raises a message, which lands in the render log and not in the report. The
report on a working file looks like any other draft. Under this design, hvtiRtemplates'
`read_job_data()` catches `hvtiRutilities_working_read` and does three things:

1. **Opens the data table's notes with the warning**, in bold, beside the file the job read:

   > **Unregistered data.** This job read the working `<built>`, which has no registered
   > version, so every number here is a draft. Register the build with `update_manifest()` and
   > render again.

   (The first draft of this note asked for a callout printed at the read. `read_job_data()`
   returns data and does not print, so a callout there would mean editing every template's
   chunk options. The table row and item 2's notice reach the same reader. Changed 2026-10-23
   while planning.)
2. **Marks the run a draft** with `.run_mark_draft()`, so the "About this run" table opens with
   the "This run ended as a draft" notice and the run facts read draft. The box under the title
   was printed before the read and cannot be taken back. This mechanism exists for exactly that.
3. **Marks the provenance record** `working = TRUE`, so a hand-off saved from these rows carries it (3.4).

The provenance record says so as well. `provenance_data(working = TRUE)` adds one field,
`working = TRUE`, to the record it returns. A registered read's record is unchanged, so every
lineage written before this design still reads as it did.

**Why print rather than warn.** The point is to make a draft on unregistered data visibly
unfinished to whoever opens the HTML, who is often not the person who rendered it. A warning
reaches only the console.

### 3.4 A hand-off saved from working data stays a draft

Without this, the gate can be passed one job removed. A draft `hz` on the working file saves
`hz.rds`. A final `hm` reads that hand-off, its own data read is of the registered version,
and the final report carries a fit made from unregistered data.

hvtiRtemplates' `.read_handoff()` already validates the hand-off's lineage. It gains one check:
if any record in `lineage$data` carries `working = TRUE`,

- in a **final** render it stops:
  > `<file>` was saved from the working `<built>`, not a registered version. Register the
  > build with `update_manifest()`, render `<upstream job>` again, then render this one.
- in a **draft** it marks the run a draft (as 3.3, item 2) and adds a `Note` row naming the
  hand-off.

Bootstrap bags (`.read_bootstrap_artifact()`) get the same check, since they carry the same
lineage.

A hand-off written before this design has no `working` field and is treated as registered. Some
of those were saved by descriptive jobs from working data under the folder rule. That is the
cost of not breaking every existing hand-off, and it is accepted (section 7.2).

### 3.5 An analysis set is built from registered data only

Found in review (Codex, PR #244), decided by John on 2026-10-23. `hvtiRdatabuild::write_analysis_set()`
reads the study dataset through `read_built()`. Under `HVTI_DATA=working` in a draft, it built the
set from the working file, while its sidecar's `.built_state()` fingerprinted the **registered**
parent. A later final render then read the set through `read_job_data(analysis_set = )` with no
check, so draft rows reached a final report looking registered.

**Decided:** `write_analysis_set()` stops when its read of the study dataset is a working read
(it catches `hvtiRutilities_working_read`), naming `update_manifest()`. An analysis set is a
durable artifact other jobs reuse, so, like a final render, it is built from registered data. A
draft can still read the working dataset directly through `read_job_data(dataset = )`. No
sidecar format changes, and `read_job_data(analysis_set = )` needs no new gate, because no
analysis set can hold working rows.

## 4. What it costs a user

| doing | today | after |
|---|---|---|
| console, building | reads the working file | same |
| draft descriptive on the working file | reads it, says so in the log | reads it, **says so in the report** |
| draft analysis on the working file | **refused** | reads it, says so in the report |
| final descriptive on the working file | reads it | **refused**: register first |
| final analysis on the working file | refused | refused (message names registering) |
| final job reading a hand-off made from the working file | reads it | **refused**: register, rerun upstream |
| `write_analysis_set()` on the working file | writes it, sidecar names the registered parent | **refused**: register first |
| `Rscript` job in datasets or descriptive on the working file | reads it | **refused**: use the console or a draft render |

Every new refusal ends in the same instruction: register with `update_manifest()`. No refusal
offers a way around registering for a final render.

## 5. Tests

hvtiRutilities, in `test-working-read.R` (or the gate's existing file):

- The gate matrix: {interactive, a render of a job in each of the study's stage folders, at the
  study root and outside the study, an `Rscript` job in each of those places, no job file} x {`HVTI_TEMPLATE_STRICT` unset, `1`,
  `true`, `yes`, `0`, `false`, `no`, empty}. Assert allowed or refused for each cell, and for a
  refusal that the message names `update_manifest()`.
- Prove the folder rule is gone **by mutation**: restore the `datasets`/`descriptive` check and
  confirm a final descriptive render on the working file goes green again, so the test is the
  thing that stops it.
- `provenance_data(working = TRUE)` carries `working = TRUE`; a registered read's record is
  byte-identical to today's (snapshot it).

hvtiRtemplates:

- `read_job_data()` on a working read, in a draft render: the callout is in the output, the run
  is marked a draft, the data table has the `Note`.
- `.read_handoff()` with a lineage carrying `working = TRUE`: stops in a final render with the
  message above; in a draft, marks the run a draft. A lineage without the field reads as today.
- `bd` with `REGISTER = FALSE` on a study with no contract: `_study.yml` gains `built:` and
  `key:`, the manifest is unchanged, and a following draft `dc-eda` reads the working file. A
  second render does not rewrite the contract, and one with a different `DATASET_ID` stops.
- One end-to-end draft render of an analysis template (`ac` is the cheapest) on an unregistered
  synthetic build, run under a real Quarto render: the gate depends on the job file knitr reports,
  which section 5.1 of the 2026-10-13 design notes differs under `quarto render`.

## 6. Hand-offs between packages

| package | change |
|---|---|
| hvtiRutilities | `.assert_working_stage()`: key on draft or final; drop the folder rule; new messages. `provenance_data()`: the `working` field. Document `HVTI_TEMPLATE_STRICT` as read by `read_built()` |
| hvtiRtemplates `bd` | with `REGISTER = FALSE`, write `built:` and `key:` to `_study.yml` on the first render that finds no contract (section 7.1). Through an hvtiRutilities call, not by editing the YAML in the template |
| hvtiRtemplates | `read_job_data()`: catch the condition, callout, `.run_mark_draft()`, `Note` row. `.read_handoff()` and `.read_bootstrap_artifact()`: the hand-off check. Raise the hvtiRutilities floor to the release that carries this. `render_job()`'s help says that `final = TRUE` also requires registered data |
| hvtiRdatabuild | `write_analysis_set()`: stop on `hvtiRutilities_working_read` (3.5). Released after hvtiRutilities, before hvtiRtemplates |
| hvtiRtemplates gallery | the per-template "before you run this" panel (layer 2 of publishing the runbooks) says "a draft can run on an unregistered build; a final render needs registered data" for every template, now that no folder differs |

Release order: hvtiRutilities, then hvtiRdatabuild, then hvtiRtemplates with the new floors.
A hvtiRtemplates release before that floor would ask a gate that still refuses draft analyses.

## 7. Decided after the direction

Both questions were left open in the first draft of this note and decided by John on
2026-10-23.

### 7.1 `bd` names the working file on its first render

**The problem.** `read_built()` finds the file through the dataset's contract in `_study.yml`
(`.study_dataset()`, then `built_path()`). `bd` with `REGISTER = FALSE` wrote
`<DATASET_ID>.rds` and its build record and touched neither `_study.yml` nor the manifest. On a
new study, then, no job could read the first build, draft or not, until it had been registered
once: the case "especially when we're building a dataset" names.

**Decided:** `bd` with `REGISTER = FALSE` writes the contract, `built:` and `key:` in
`_study.yml`, on the first render that finds none, and registers no version. When the study has
no `manifest.yaml` it also writes an empty one (`datasets: []`): a fresh `study_setup()` writes
none, and every template calls `verify_manifest()` before it reads data, which stops on a missing
file (found in review). An empty manifest registers nothing and verifies clean.

The first read of a declared dataset takes the legacy read path. It writes the parquet cache
and an unversioned manifest entry, as a study with `built:` and no manifest always has. The
dataset stays unregistered (no dated version), so the gate and the draft marking apply.
Registering it later reports `migrated`, which `bd` already treats as registering. Decided
2026-10-23 over a no-write read, which would have changed that path for every legacy study. The dataset is then
known but unregistered, so every read of it is a working read and goes through this gate.
Registering stays a separate, deliberate step: a render with `REGISTER = TRUE`, or
`update_manifest()`.

- A study that already has a contract keeps it. `bd` does not rewrite `built:` or `key:` once
  set. A `DATASET_ID` that disagrees with the contract's `built:` stops, as it does today when
  registering.
- Writing the contract is not registering. `study_status()` reports such a dataset as having no
  dated version, which it already flags.
- **Rejected:** letting `HVTI_DATA=working` guess the file from a listing of `datasets/`. The
  gate would then depend on what else happens to sit in that folder.

### 7.2 Hand-offs written before this design are treated as registered

**Decided:** a lineage record without the `working` field reads as registered, in a final render
and a draft alike. The folder rule confined working reads to the datasets and descriptive
folders, whose jobs rarely hand off a fit, so the exposure is small. The alternative, refusing a
final render on any hand-off without the field, would force every downstream job in every study
to be rerun once.
