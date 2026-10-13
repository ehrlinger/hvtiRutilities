# One version scheme for study datasets: dated versions with provenance, and working reads

**Date:** 2026-10-13
**Status:** design approved by John Ehrlinger on 2026-10-13 (decisions in section 3, taken one
at a time). Not built.
**Implements:** sub-project A of hvtiRtemplates `dev/specs/2026-10-13-dataset-creation-design.md`
(sections 3, 4 and 6.1). That note's decisions are not reopened here.
**Builds on:** hvtiR `dev/specs/2026-10-07-dated-parquet-manifest-design.md` (dated versions,
shipped in 1.5.0 to 1.5.2).
**Retires:** `2026-09-21-dataset-release-contract-design.md` and
`2026-09-21-dataset-release-consumer-plan.md`, for study datasets and for every other dataset.
**Package:** hvtiRutilities. Hand-offs to hvtiRtemplates and hvtiRdatabuild are in section 8.

This note is self-contained. It assumes no memory of the session that produced it.

⚠️ No study, variable value or patient identifier appears here. The migration count in section 6
was taken by reading key names and manifest roles only.

## 1. The problem

hvtiRutilities registers a study dataset in two ways that cannot meet:

1. **Dated versions.** `register_data()` without a release converts the file once to
   `<stem>_YYYYMMDD[_rN].parquet`, and `update_manifest()` registers each rebuild as the next
   version, keeping the old ones in `history`. This is the architecture's decision 4.
2. **Catalog releases.** `register_data(catalog_dataset =, release_id =)` pins the study to a
   release in `datasets/dataset-catalog.yml`, written by hvtiRdatabuild's `publish_dataset()`.
   `check_data_updates()`, `review_data_update()`, `adopt_data_update()` and `read_built()`'s
   release branch serve it. `update_manifest()` skips such a dataset, and `register_data()`
   refuses to move a versioned dataset onto a release.

The architecture keeps only the first. Three gaps remain in it:

- **A version does not say how its data were produced.** It records the parquet, its hashes,
  extract date, counts, schema hash, reader and `recovered_from`. A version cut by `bd` and one
  built by SAS look the same.
- **There is no review before registering.** The release path had check, review, adopt. Dated
  versions have check (`source_changed`, `PENDING`) and adopt (`update_manifest()`), and nothing
  between them.
- **A rebuilt `built` cannot be read before it is registered.** Once a dataset has a registered
  version, `read_built()` serves that parquet and `refresh = TRUE` stops. A stat programmer
  building the study dataset cannot run a descriptive on the file they are building without
  first registering it, which defeats the review.

## 2. What stays fixed

From the architecture, and not reopened:

- A study has **one working file, `built`**, undated and overwritten in place, whatever made it.
  Users do not want dated `built` files.
- Only a **registered** dataset is dated, and every registered dataset the same way:
  `<stem>_YYYYMMDD[_rN].parquet`. How it was produced is provenance on the version, never a
  second scheme.
- A legacy study enters by registering its existing `built` (sub-project B, hvtiRtemplates#225),
  and B is built on the scheme this note leaves standing.

## 3. Decisions

| # | question | answer |
|---|---|---|
| 1 | How does a build's provenance reach registration? | **Sidecar discovery.** `bd` writes `<stem>.build.yml` beside `built`; registration finds it, checks it describes these bytes, and moves it beside the version (section 4) |
| 2 | Does the release path survive for datasets another producer publishes? | **No. It is retired entirely.** A dataset taken from another producer is a file registered like any other; a later design may give it its own `origin` value |
| 3 | What replaces the release path's review step? | **A new `review_built()`**, comparing the registered version with the working `built` (section 5.2) |
| 4 | How is a template switched to read the working file? | **An argument, `working =`, defaulting from the environment variable `HVTI_DATA=working`**, so an existing template runs on the working file unedited |
| 5 | Who may read the working file? | **Jobs in the datasets and descriptive stages, and the console.** Gated by the rendering job's stage, with no duplicated templates (section 5.1) |
| 6 | Convert release-registered studies, or refuse them? | **Refuse with a message.** Measured: no study is registered by release (section 6) |

Rejected alternatives, briefly. Explicit `origin =`/`build_record =` arguments (1) would record a
bd cut as `legacy` whenever someone ran `update_manifest()` by hand, and would need the same hash
check anyway. Keeping releases for other producers' datasets (2) keeps 1,023 lines of the most
complex code alive for a use with no users, and two schemes in one manifest. Documenting a
`compare_datasets()` recipe instead of a function (3) is a recipe nobody remembers. Re-pointing
`review_data_update()` (3) changes a name's meaning during its own deprecation. A study-level
flag in `_study.yml` (4) is committed and persistent, so it is easy to leave on and render
reports from unregistered data. Copying the descriptive templates into `00_datasets` (5) makes
two Table 1s that drift, the failure the architecture rejects for derivations in its section 5.3.

## 4. Provenance on a version

### 4.1 Origin

Every registered version, current or in `history`, has an `origin`, recorded in the manifest's
`provenance:` map (section 4.4), not on the version record itself:

| value | meaning |
|---|---|
| `legacy` | registered without a valid build record: a SAS build, a hand-written program, anything not cut by `bd` |
| `bd` | registered with a build record that describes these exact bytes |

A version with no row in `provenance:` **reads as `legacy`**: every version written before this
change, and any version an older hvtiRutilities writes later. Nothing is rewritten to add a row. No other value is defined here; a new producer adds one under its own
design.

### 4.2 The sidecar

`bd` (sub-project D) writes `datasets/<stem>.build.yml` beside `datasets/<built>`, where
`<stem>` is `built` without its extension. When `register_data()` or `update_manifest()`
converts `built`:

1. **No sidecar:** the version's provenance row records `origin: legacy`.
2. **A sidecar whose `built_sha256` equals the `source_sha256` just computed** for the file
   being converted: it is validated (section 4.3), then renamed to
   `<stem>_YYYYMMDD[_rN].build.yml`, beside the version's parquet and schema files and sharing
   their name. The version's provenance row records `origin: bd` and a `build:` block (section 4.4).
3. **A sidecar whose `built_sha256` differs:** it describes another file. The version's row records
   `origin: legacy`, the sidecar is left where it is, and the update report row says so: "<stem>.build.yml
   describes a different <built>, so this version is recorded as legacy". Loud, and it does not
   block the registration: `legacy` is the truthful record of what is known.
4. **A matching sidecar that fails validation**, or one recording
   `derived_after_overlay: false`, **stops the registration** and writes nothing. The second is
   the architecture's section 5.3 rule: a cut whose derivations were not recomputed after its
   overlay was applied is never registered.

The rename joins the existing rollback. `.write_version()` already removes its parquet and schema
on error, and `.update_study_manifest()` restores renamed files when the manifest write fails
(`restore$from`, `restore$to`); the build record is one more renamed file in that list, and
`register_data()` gets the same treatment in its `on.exit()`.

An unchanged source keeps its version, as today. A sidecar beside an unchanged source (a
re-render that produced the same bytes) is left alone and the version is not touched.

### 4.3 The build record

YAML, on the share beside the data, **never in a repository**. hvtiRutilities validates the
fields it relies on and ignores the rest, so `bd` may record more without a change here.

| field | type | required |
|---|---|---|
| `schema` | integer, `1` | yes |
| `built_sha256` | 64 lower-case hex characters | yes |
| `job` | study-relative path of the job file | yes |
| `view` | name of the master view cut | yes |
| `as_of` | ISO 8601 timestamp the cut is pinned to | yes |
| `cohort_sha256` | hash of the canonical cohort rules | yes |
| `overlay_sha256` | hash of the study corrections overlay, or null when there is none | yes |
| `derived_after_overlay` | logical | yes; true when there is no overlay |
| `cohort`, `settings`, `attrition`, ... | anything `bd` adds | no |

What may be recorded: names, paths, hashes, timestamps, counts, and the cohort rules as text.
**No key value and no data value, ever.** The cohort rules are the one place a careless rule
could carry a key (an exclusion written as a list of identifiers), which is why the record lives
on the share and the committed manifest carries only `cohort_sha256`. hvtiRutilities cannot
enforce what a rule says; D's design must forbid rules that list keys.

### 4.4 The manifest

`manifest.yaml` is committed, so it carries pointers and hashes only. Provenance is a
**top-level map keyed by parquet name**, beside `datasets:`, and the version records in
`datasets:` are unchanged:

```yaml
datasets:
- hvtiRutilities 1.5.1 or later required: ...      # the existing guard line
- file: built.sas7bdat
  role: primary
  parquet: built_20261013.parquet
  sha256: <parquet hash>
  source_sha256: <built hash when registered>
  extract_date: '2026-10-13'
  n_rows: <n>
  n_cols: <n>
  schema_sha256: <hash>
  reader: haven 2.5.5
  history:
    - parquet: built_20260915.parquet
      ...
provenance:
  built_20261013.parquet:
    origin: bd
    build:
      record: built_20261013.build.yml
      record_sha256: <hash of the record>
      job: 00_datasets/bd.qmd
      view: <view name>
      as_of: '2026-10-01T00:00:00Z'
      cohort_sha256: <hash>
      overlay_sha256: <hash or null>
  built_20260915.parquet:
    origin: legacy
```

**Why a separate map, not fields on the version.** hvtiRutilities 1.5.1 and 1.5.2 are already
installed and cannot be changed. Their `.entry_extra()` copies every field it does not know onto
the next version it writes, and their `.history_record()` keeps only the fields they know. So an
`origin: bd` on the entry would be **inherited by a later SAS rebuild that 1.5.2 registers**,
which is false provenance, and the moved-to-history record would lose its own. The guard line
stops only readers before 1.5.1. Those versions do rewrite `manifest$datasets` and keep every
other top-level key, so a map keyed by parquet name survives an older reader intact. A version
the older reader registers has no row, and reads as `legacy`, which is true.

Code changes this implies, in `R/registered_versions.R` and `R/register_data.R`:

- `.version_fields`, `.history_record()` and `.entry_extra()` are **unchanged**.
- Every writer of a version record writes its provenance row in the same manifest write:
  `.write_version()`'s callers in `register_data()`, `.next_version()` and `.migrate_entry()`,
  and `.recover_cached_version()`, whose recovered version gets `origin: legacy`.
- `.recorded_version_names()` adds each row's `build$record`, so `.reserved_names()` keeps a new
  version from taking a record's name.
- A row whose parquet no entry records (a hand-edited manifest) is reported by
  `verify_manifest()` and otherwise ignored.

### 4.5 Verification

`verify_manifest()` checks every build record named in `provenance:` against its
`record_sha256`, as it already checks every recorded parquet. A missing or changed record
**stops**, with a message naming the record and saying it is the provenance of a registered
version and must be restored from backup, not edited.

## 5. Reading, reviewing and registering

### 5.1 Working reads

`read_built(cfg, refresh, dataset, working = .hvti_working_default())`.

**The default.** `.hvti_working_default()` returns `TRUE` when `Sys.getenv("HVTI_DATA")` is
`"working"`, `FALSE` when it is unset or empty, and **stops** for any other value, naming the one
accepted value. A typo (`HVTI_DATA=wroking`) must not quietly serve registered data to someone
who believes they are looking at the working file, nor the reverse. An explicit `working =`
argument wins over the variable.

**The stage gate.** The gate is applied to **the data actually read**, not to the argument: it
runs whenever the read would serve the working file, which is `working = TRUE` on any dataset,
and **any** read of a dataset with no manifest entry (see "Every read of unregistered data" below). A working
read is honoured when either:

- **the session is interactive** (`interactive()` is `TRUE` and no render is running): the
  console, where a stat programmer looks at `built` and no report results; or
- **the job file's first directory under the study root is the `datasets` or `descriptive`
  folder of that study's layout**, resolved through `.study_folders()` so it holds for numbered
  (`00_datasets`, `10_descriptive`) and adopted (`datasets`, `descriptive`) studies alike. The
  job file is `knitr::current_input(dir = TRUE)` during a render, and the `--file=` argument of
  `commandArgs()` under `Rscript`.

A non-interactive session whose job file cannot be found (a `source()` from a batch, an
`R CMD BATCH`) is refused, so `HVTI_DATA=working Rscript 30_analyses/.../fit.R` cannot save
estimates from unregistered data.

Otherwise it stops: "<stage> jobs read registered data only. Register <built> with
update_manifest(), or unset HVTI_DATA." A render of a file outside the study root is refused the
same way. ⚠️ Under `quarto render`, knitr knits an intermediate
file; the gate depends on that file sitting in the job's own directory, so it is tested under a
real Quarto render (section 9), not only under knitr. The gate is a proxy: nothing in the family knows who is rendering, and the stage a job
lives in is the honest stand-in for "a stat programmer building the dataset". It keeps
`HVTI_DATA=working` from leaking into an analysis, distribution or graph render.

**The read.** `read_clinical_data(<source>, convert_types = FALSE)`, the lower-case collision
check, then `.normalise_built()`, exactly as a registered or cached read is normalised. It
**writes nothing**: no read cache, no manifest entry. It must not go through `.cache_read()`,
which writes `<stem>.parquet` beside the source, a name `.reserved_names()` holds for a versioned
entry. A missing source stops. `refresh = TRUE` with `working = TRUE` is an error: there is no
cache to refresh.

**The signal.** Every working read emits a message of class
`c("hvtiRutilities_working_read", "message", "condition")`: "Read the working <built>, not a
registered version. Results from it are a draft." Sub-project F catches this class to mark the
report a draft, as templates already catch `hvtiRutilities_source_changed`.

**Every read of unregistered data is a working read, gated and signalled.** A dataset with no
entry in `manifest.yaml` has nothing registered, so whatever `working` says, reading it serves
the working file. Such a read therefore passes the stage gate above and signals
`hvtiRutilities_working_read`, so F marks it a draft. A default read (`working = FALSE`) keeps
the existing cache path, so a datasets or descriptive job is not slowed; `working = TRUE` is the
same read without the cache write. Without this, an analysis job could read unregistered data
simply by leaving `HVTI_DATA` unset, and decision 5 would hold only for studies that had
registered something.

"Registered" here means the dataset has a manifest entry, versioned or not. A legacy entry
(`role: source`, written before 1.5.0) records the file's SHA-256 and is registered data in the
old scheme; it keeps today's read until its next `update_manifest()` migrates it, and the gate
does not apply to it.

⚠️ **This changes behaviour for studies that have registered nothing.** Today they render every
stage from the working file. After A, their analysis, distribution and graph jobs stop with the
gate's message until the dataset is registered, which is the architecture's order: register,
then analyse. Measured on 2026-10-13, 3 of the 14 studies found have nothing registered
(section 6). An additional dataset with no manifest entry is gated the same way.

**Provenance.** `provenance_data()` gains the same `working =` argument and default. A working
read records the source file (`datasets/built.sas7bdat`) where a registered read records the
parquet (`datasets/built_20261013.parquet`). The record's shape does not change; the path says
which was read. Any further draft marker in the sidecar is F's.

### 5.2 `review_built()`

```r
review_built(cfg = study_config(), dataset = "study")
```

Returns an object of class `built_review`, with a print method:

| element | content |
|---|---|
| `dataset` | the canonical dataset name |
| `registered` | the current version record from the manifest |
| `working` | the source's `sha256`, `n_rows`, `n_cols` |
| `changed` | whether the source differs from the registered version (`.source_changed()`, after the existence check below) |
| `comparison` | `compare_datasets(<registered>, <working>)`, or `NULL` when `changed` is `FALSE` |

It reads only, and the working side is read the same way as section 5.1's read, without the
stage gate (a review is not a render of results). A missing source **stops** before
`.source_changed()` is consulted, because that helper returns `FALSE` for a missing file and the
review would report a deleted `built` as unchanged. A dataset with no registered version stops
with "nothing is registered to compare against; register it with register_data()". It
describes drift; it does not certify the new file, the same caveat `review_data_update()`
carried.

`update_manifest()`'s message for a registered rebuild, and the `hvtiRutilities_source_changed`
text, both name `review_built()` as the step before registering.

### 5.3 What replaces each retired piece

| retired | replacement |
|---|---|
| `register_data(catalog_dataset =, release_id =)` | `register_data()`; provenance comes from the sidecar |
| `check_data_updates()` | `study_status()` and `verify_manifest()` `PENDING` rows, already shipped |
| `review_data_update()` | `review_built()` |
| `adopt_data_update()` | `update_manifest(dataset =)` |
| `read_built(allow_withdrawn =)` | nothing: a dated version is never withdrawn |
| `release:` in `_study.yml` | nothing |
| `print.data_update_review` | `print.built_review` |

`publish_dataset()` has **no role for study datasets.** Whether hvtiRdatabuild keeps it for any
other purpose is hvtiRdatabuild's decision (section 8).

`read_clinical_data(catalog_file =)` is a SAS format catalogue, an unrelated use of the word,
and is not touched.

## 6. Migration

**Measured on 2026-10-13** on `/Volumes/qhsstudies-1` (the only mounted study share;
`/Volumes/qhsstudies` is an empty mount point), walked with shell globs (never `find`, which
stalls over SMB) under `cardiac`, `general`, `thoracic` and `vascular`, reading the key names of
each `_study.yml` and the `role` and presence of `parquet` in each `manifest.yaml` entry. No data
file and no value was read. `_study.yml` was sought at depths 2 to 6 below the share root, and
`dataset-catalog.yml` at depths 2 to 6. The depth-6 glob took over 40 minutes over SMB and
finished after this note was first merged (#215); this table includes it. A catalog would matter
only beside a `release:` contract, and none of the fourteen studies has one.

| state | studies |
|---|---|
| `release:` contract, on the study dataset or an additional one | **0** |
| `dataset-catalog.yml` anywhere | **0** |
| registered as legacy (`role: source`) | 11 |
| registered as dated versions | 1 |
| no dataset registered yet | 3 |

So **A refuses rather than converts.** There is nothing to convert, and conversion code nobody
runs is code nobody has tested. The eleven legacy studies need nothing from A: their next
`update_manifest()` already migrates them through `.migrate_entry()`, and they read as `legacy`.

The refusal, from the removal release on (section 7), is a `study_config()` stop: "_study.yml
pins dataset '<name>' to catalog release <release_id>. Catalog releases were retired in
hvtiRutilities <version>. Remove the release: block and run update_manifest(), which registers
the file as a dated version." It names the dataset and the release ID and never a value.

## 7. Deprecation

Two releases, as hvtiRtemplates did for renamed templates. Versions follow AGENTS.md: patch
bumps only, and the minor digit is John Ehrlinger's decision.

**The deprecation release (next patch, 1.5.x).** Ships everything in sections 4 and 5, and:

- `check_data_updates()`, `review_data_update()` and `adopt_data_update()` keep working and
  call `.Deprecated()` naming their replacement.
- `register_data()` warns when `catalog_dataset` or `release_id` is supplied;
  `read_built()` warns when `allow_withdrawn` is supplied.
- `study_config()` warns, once per session per study, when it reads a `release:` contract.
- Base `.Deprecated()`, not lifecycle: no new dependency for a two-release window.

**The removal release.** Removes the three functions and their print method, the two
`register_data()` arguments, `read_built(allow_withdrawn =)`, `R/dataset_catalog.R`,
`R/data_updates.R`, the release branches in `study_config.R`, `study_status.R`,
`dataset_shape.R`, `study_data.R` and `update_manifest()`, `tests/testthat/helper-release.R`,
`test-data_updates.R` and `test-dataset_catalog.R`, and the three `_pkgdown.yml` entries.
`study_config()` then stops on a `release:` key (section 6).

⚠️ Removing exports breaks callers, so **John chooses the removal release's number**. It must
not ship before hvtiRtemplates' `bd.qmd`, `templates.json`, `test-templates.R`, the
`study-setup` vignette and hvtiRdatabuild's `publish_dataset()` documentation stop naming the
removed functions; the reverse-dependency check in the release gate is what proves it.

## 8. Hand-offs

| to | what |
|---|---|
| hvtiRtemplates, D | `bd.qmd` writes `datasets/<stem>.build.yml` (section 4.3), writes `built` in place, and calls `register_data()` or `update_manifest()`; it stops calling `publish_dataset()`, `register_data(release_id =)` and `adopt_data_update()`. Its "registered without a release, so a build cannot replace it" stop becomes the normal path. Its cohort rules must never list keys |
| hvtiRtemplates, B (#225) | the adoption job registers a legacy `built` with plain `register_data()`; it gets `origin: legacy` with no extra work |
| hvtiRtemplates, F | catches `hvtiRutilities_working_read` to mark a render a draft. **The unpushed `spec/data-freeze` branch is folded into F rather than pushed as it stands** (decided 2026-10-13); its `draft:` reads become working reads |
| hvtiRtemplates | `templates.json`, `test-templates.R` and the `study-setup` vignette stop naming the release functions before the removal release |
| hvtiRdatabuild | decide whether `publish_dataset()` and `withdraw_dataset_release()` keep any role once no study consumes releases; update their documentation, which points at `adopt_data_update()` |

## 9. Tests

New or changed, in `tests/testthat/`:

- **Origin.** Provenance rows are written beside every version, including a recovered one. No
  sidecar gives `legacy`. A matching sidecar gives `bd`, the record renamed beside
  the parquet, `build:` copied, `record_sha256` correct. A mismatched sidecar gives `legacy`, a
  report row naming it, and the sidecar left in place. A record missing a required field, or
  with `derived_after_overlay: false`, stops and leaves no parquet, schema or record behind. A
  failed manifest write renames the record back. A version with no row reads as `legacy`.
  **Compatibility:** a manifest with a `bd` row, updated by the installed 1.5.2 after a
  rebuild, leaves the row on its own parquet, and the new version has no row and reads as
  `legacy`. A new version never takes a recorded record's name.
- **Verification.** `verify_manifest()` stops on a changed and on a missing record, current and
  in `history`.
- **Working reads.** `HVTI_DATA` unset, empty, `working`, and a misspelling (stops); the argument
  overriding the variable. The stage gate for numbered and legacy layouts: datasets and
  descriptive allowed, the other stages and a file outside the study refused; interactive console
  allowed; `Rscript` honoured or refused by its `--file=` stage; non-interactive with no job file
  refused; one case under a real `quarto render` (skipped when Quarto is absent, and that skip
  reported). A **default** read (`HVTI_DATA` unset, `working = FALSE`) of a dataset with no
  manifest entry: allowed and signalled from datasets and descriptive jobs, **stopped** from
  distributions, analyses and graphs jobs and from a non-interactive script with no job file. A
  legacy `role: source` entry is not gated.
  The read writes nothing (the datasets directory listing and manifest bytes are identical before
  and after). The condition class. `refresh = TRUE` with `working = TRUE` errors.
  `provenance_data(working = TRUE)` records the source path.
- **`review_built()`.** Missing source (stops), unchanged source (no comparison), changed source (a `compare_datasets()`
  result), a never-registered dataset (stops), the print method.
- **Deprecation.** Each retired function and argument warns naming its replacement and still
  returns what it did; `study_config()` warns once on a `release:` contract.

Definition of done is AGENTS.md's: `devtools::test()` passes, `devtools::check()` is 0/0/0,
`devtools::document()` committed, `review_built` added to `_pkgdown.yml`'s reference index (its
absence errors the site build), lint clean, a `news/` fragment, and Rd markup rather than
markdown in roxygen.

## 10. Out of scope

The build record's contents beyond section 4.3's required fields (D's design); the overlay's
file format and its reconciliation (E); how F marks a draft report; the master port and its open
questions (C); and analysis sets.
