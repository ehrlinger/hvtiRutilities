# SAS Macro Canonicalization (Phase 0)

**Date:** 2026-07-10
**Status:** Implemented and shipped in `hvtiRutilities` 1.0.4
**Package:** `hvtiRutilities`
**Amended:** 2026-08-14 — Phase 2..N ownership map re-derived from
`hvtiRtemplates::hvti_taxonomy()`, and a rule added for shared assets that carry
no `%macro` definition. See *Amendments* below.

## Context

The CORR group intends to reimplement its legacy SAS analysis library in the
`hvti*` R packages. The corpus is large enough that it is a program, not a
project:

| Corpus | Count |
|---|---|
| SAS macro library, top-level `.sas` | 179 files, ~78,000 lines |
| `%macro` definitions within them | 451, across 240 distinct names |
| Editor backups / `Copy of` duplicates | 25 `*~`, 4 `Copy of *` |
| SAS files in subdirectories | 79 (`archive` 20, `tests` 17, `table_mac` 17, `readin_samples` 17, `logis_reclassi` 4, `repeat_test` 2, `macros_to_test` 2) |
| SAS templates (`development/template`) | 229 |
| R / Quarto / Sweave templates | 48 `.R`, 7 `.qmd`, 2 `.Rnw`, 2 `.Rmd` |

The first two rows are **superseded** — the shipped implementation triages 336
files carrying 816 definitions across 307 names. See *Amendments* for why the
original glob undercounted. The rows are left as written so the correction is
legible rather than silently applied.

The program decomposes along the `tp.<prefix>` naming convention the template
repo already encodes:

- **Phase 0 (this spec)** — canonicalize the macro library.
- **Phase 1** — build a SAS oracle: synthetic fixtures, a harness, and a
  golden-output corpus. **SAS runs on a separate system**, not on the
  workstation where the R packages are developed. Phase 1 must therefore treat
  harness execution as a cross-system transfer, not a local subprocess call.
- **Phases 2..N** — port by prefix to package. The authoritative prefix table is
  `hvtiRtemplates::hvti_taxonomy()`, which also gives each prefix's template
  folder; the map below is derived from it and should be re-derived from it
  rather than maintained here by hand.

  | Prefix | Folder | Package |
  |---|---|---|
  | `bd` | `datasets` | `hvtiRdatasets` |
  | `vars`, `dt` | `datasets` | `hvtiRutilities` |
  | `dc`, `lg`, `rg` | `descriptive` | `hvtiRtables` |
  | `hp`/`mp`/`lp`/`np`/`dp`/`fp`/`gp`/`cp`/`ce`/`rp` | `graphs` | `hvtiPlotR` |
  | `lm`/`cm`/`pm`/`rm` | `analyses` | `hvtiPropensityScores` |
  | `ac`/`hz`/`hs`/`cd`/`nd` | `distributions` | `TemporalHazard` |
  | `mm`/`gm`/`bh`/`bl`/`bc`/`nm` | `analyses` | modeling, owner undecided (`multimix`, in `mixhazard/`, is a candidate for the mixed-effects subset) |
  | `ar` | `documents` | reporting, owner undecided |

  Two corrections against the 2026-07-10 draft of this line, both from reading
  the templates repo rather than inferring: **`bd` is no longer
  `hvtiRutilities`** — `hvtiRdatasets` now owns dataset build and verification
  (`dw_pull()`, `read_study_config()`, `snapshot_oracle()`, `compare_built()`) —
  and **`dc` is `hvtiRtables`**, not a descriptive corner of `hvtiRutilities`.

`TemporalHazard` (v1.1.0.9000, 27 R files) is a CRAN-target package. Anything
ported into it inherits the full release gate: `R CMD check --as-cran` with the
manual build, and an overall check-time budget under 10 minutes. This
constrains Phase 2 design and is recorded here so it is not discovered late.

Phase 0 must complete before Phase 1, because a golden output computed from a
non-canonical macro is confidently wrong and poisons every phase downstream.

Phase 0 itself has **no SAS dependency** (see *Heuristic lint*), so it runs
entirely on the R development workstation and is unaffected by SAS living
elsewhere.

### Shared assets are not sorted by prefix

Prefix sorting applies to *jobs*. It does not apply to assets that every job
reads, and mapping those by prefix is a category error.

The format catalogs are the worked example. `hvti_taxonomy()` has **no format or
label prefix**, and none of the 229 templates carries `format`, `fmt` or `label`
in its filename — formats were never a job type. Yet **201 templates reference a
format library** (`proc format`, `libname library`, `fmtsearch`), spread across
every folder: 65 in `graphs`, 46 in `analyses`, 35 in `distributions`, 29 in
`datasets`, 26 in `descriptive`.

`cvirfmts.sas` is the catalog they read. It contains **zero `%macro`
definitions and 65 `value` statements** — it is data, not code, so triage's rule
ladder does not apply to it and it will never appear in the manifest. It is
loaded at build time and inherited by everything downstream, which puts it with
the build: **`hvtiRdatasets`**.

`format_TF.sas` is the contrasting case and shows the distinction is real rather
than a technicality. It *is* a macro — recode TRUE/FALSE to yes/no, frequency
tables before and after, merged back by id — so it is variable transformation,
the `vars` prefix, and goes to **`hvtiRutilities`**, where it lands beside
`r_data_types(binary_factor=)` and `clean_labels()`.

The rule to carry into Phase 2: **a file with no `%macro` definition is an asset,
not a port target.** Route it by who loads it, not by which analyses use it.

## Problem

### The unit of canonicalization is the macro, not the file

Files are macro *collections*, averaging ~2.5 definitions each. 240 distinct
macro names are defined 451 times, and **85 names are defined in more than one
file**. A file-keyed manifest cannot express this.

Worse, redefinitions diverge. Measured by hashing each normalized macro body:

| Macro | Files defining it | Distinct bodies |
|---|---|---|
| `skip` | 14 | **11** |
| `mrg` | 13 | 2 |
| `numobs` | 7 | 2 |
| `std_dif` | 5 | **5** |
| `dist` | 3 | 2 |

In SAS, `%include`-ing two files that both define `%macro dist` means the
second **silently shadows** the first. With `skip` carrying 11 different
implementations, any harness that includes multiple macro files is exposed to
order-dependent behaviour. Detecting this is a Phase 0 deliverable, because
Phase 1's harness will do exactly that.

### Public entry points versus private helpers

The divergence is not uniform, and the structure is informative. `mrg`'s 13
copies collapse to exactly 2 bodies, split cleanly: the eight `bl_ord.*` /
`bn.*` files share one, the five `bootstrap.hazard_*` files share another. That
is two lineages of a copy-pasted helper, not chaos.

By contrast `std_dif` — a macro that is *called by name* from analysis code —
has diverged five ways across five files.

So the corpus contains two populations:

- **Public entry points.** The macro a template actually calls. These are the
  real port targets. 42 have a name exactly matching their file basename
  (`ExpdObsdPlot` in `ExpdObsdPlot.sas`).
- **Private inline helpers.** `skip`, `mrg`, `numobs`, `token`, `break`,
  `hazboot`, `skkip`. Vendored by copy-paste into whichever file needed them,
  then drifted independently.

The 42 figure is a **floor, not a count**. The heuristic undercounts, because
variant-named files define the base macro: `std_dif_wt.sas` and `std_difma.sas`
both define `%macro std_dif`. Resolving public status therefore cannot be fully
automated (see Rule 6).

### File-level duplication

Independently of the above, the file set contains uncanonicalized variants:
`CR_compare_CP` (7 files), `std_dif` (5), `CR_compare_CIF` (3),
`CR_CIF_CP_variance` (3), and ~16 more families with 2 each.

The differences are semantic, not cosmetic:

- `CR_compare_CP.sas` vs `CR_compare_CP_old.sas` differ by `keep _freq_ tau` →
  `keep freq tau`. `_FREQ_` is a SAS automatic variable; `freq` is not. One of
  these produces wrong counts.
- `CR_compare_CP_test_AT.sas` contains unbalanced quotes
  (`define dev1/display Number*events of*interest'`, `''CIF*event of*interest'`).
  It cannot compile. It is abandoned WIP.
- `.sas~` files differ from their `.sas` siblings. They are Emacs backups: the
  version immediately preceding the last save.

### Provenance is unavailable

Commit messages are cron-generated (`Daily Commit Wed May 1 04:52:50 EDT 2019`),
so git history yields timestamps but no intent. 24 `.sas` files are untracked
and have no history at all, while 23 `.sas~` backups and 4 `Copy of *` files
were committed. `.gitignore` covers `*.bak` and `*.asv` but not `*~`. The
repository's notion of what matters is inverted.

The repository is also on a network volume; `git log --follow` on one file timed
out at 120 seconds. Tooling must run against a **local clone**.

## Goals

Produce a signed-off canonical set of SAS **macro definitions**, a macro
signature database, and a name-collision hazard report.

## Non-goals

- No R implementation of any macro.
- No SAS execution, and no golden outputs (Phase 1).
- No judgment about whether a macro is *worth* porting.
- No deduplication of private helpers into a shared utility file. That is a
  refactor of legacy SAS, and the legacy SAS is being retired.

## Design

### Corpus scope

Triage operates on the **179 top-level `.sas` files plus their 25 `*~` backups
and 4 `Copy of *` duplicates**. Subdirectories are excluded by an explicit path
filter, with a stated reason each:

| Directory | Files | Disposition |
|---|---|---|
| `archive/` | 20 | Excluded — self-declared archive |
| `CVS/` | — | Excluded — legacy version-control metadata |
| `tests/` | 17 | Excluded from triage; retained as Phase 1 input (contains `naftel.sas`/`.log`/`.lst`) |
| `macros_to_test/` | 2 | Excluded from triage; retained as Phase 1 input |
| `table_mac/`, `readin_samples/`, `logis_reclassi/`, `repeat_test/` | 40 | Excluded — deferred to a later spec; flagged in the report |

Exclusions are recorded in the manifest, not silently dropped.

### Units

Four units in `hvtiRutilities`, each independently testable.

| Unit | Responsibility | Depends on |
|---|---|---|
| `sas_macro_defs(file)` | Extract **every** `%macro`…`%mend` definition in a file. Returns one row per definition: name, parameters, normalized body hash, start/end line, lint validity. | — |
| `sas_macro_signature(file)` | Parse the structured header block (`MACRO NAME:`, `MACRO CALL`, `MODIFIED BY`) into name, documented parameters, and modification dates. | — |
| `sas_triage(dir, overrides)` | Apply the rule ladder across the corpus. Returns a decision table: one row per macro definition, with `decision` and `evidence`. | both above |
| `write_macro_manifest(x, path)` | Emit versioned YAML, mirroring the schema conventions of `R/manifest.R`. | `sas_triage` |

`sas_macro_defs()` and `sas_macro_signature()` are useful beyond Phase 0: the
extracted call signatures are direct input to the Phase 1 harness (which must
know how to invoke each macro) and to the eventual R function interfaces.

### Case sensitivity is a correctness requirement

SAS macro names are case-insensitive. The corpus mixes conventions freely:
`%MACRO MRG;` in `bl_ord.ci.sas`, `%macro skip;` elsewhere. All name matching
in `sas_macro_defs()` must fold case.

This is not hypothetical. During design, a body-hash analysis run under macOS
`awk` (BWK awk, which silently ignores the gawk `IGNORECASE` extension) failed
to match `%MACRO MRG`, hashed the empty string, and reported "`mrg` has 1
distinct body — benign." The true answer is 2. **An empty macro body must be
raised as an extraction error, never hashed and treated as data.** This is
codified as a test.

### Data flow

```
local clone of macro.library
  → path filter (top-level only; exclusions recorded)
  → sas_macro_defs() per file        → one row per %macro definition
  → sas_macro_signature() per file   → documented signatures
  → group definitions by lowercased macro name
  → rule ladder
  → decision table
  → write_macro_manifest()
  → macro_manifest.yaml + macro_signatures.yaml + collision_report.md
        ↑                        ↓
  macro_overrides.yaml ← human reviews `status: ambiguous` rows
```

The loop is closed and idempotent: a human resolves ambiguity by editing
`macro_overrides.yaml`, re-runs `sas_triage()`, and the manifest regenerates
deterministically.

### Rule ladder

Ordered. First match wins. Every `drop` requires proof.

**File-level rules** (applied before definitions are extracted):

1. Filename matches `Copy of *` → **drop file**. Evidence: `filename-prefix duplicate`.
2. Extension is `.sas~` or `.SAS~` → **drop file**. Evidence: `editor backup, superseded by construction`.
3. Fails heuristic lint → **drop file**. Evidence: the specific lint failure. (Kills the `_test_AT` class.)

**Definition-level rules** (applied per macro name, across surviving files):

4. Name defined once, in one file → **canonical**.
5. Name defined in ≥2 files, **all bodies hash identical** → **canonical**;
   record every defining file. Evidence: `N identical copies`. (This is the
   benign vendored-helper case.)
6. Name defined in ≥2 files with **≥2 distinct bodies** → **`ambiguous`**.
   Do not decide.

**Rule 6 never auto-resolves.** This is the load-bearing decision of the
design. Header `MODIFIED BY` dates, the rendered diff, and the public/private
classification are attached to the row as *evidence for a human*, never consumed
as a tiebreaker. Filesystem mtime is explicitly not used: the repo froze in 2019
and lives on a network volume where timestamps do not survive copies reliably.

A tool that silently picks a winner between `_freq_` and `freq` is worse than no
tool, because it launders a coin-flip into a committed artifact. This mirrors
the existing house style in `R/manifest.R`, where `.auto_count_rows()` refuses
to guess:

```r
stop("Cannot auto-detect n_rows for file type '.", ext, "'. ...
      Please supply n_rows explicitly.")
```

Rule 6 will fire for `skip` (11 bodies), `std_dif` (5), `mrg` (2), `numobs` (2),
`dist` (2), and the rest of the 85 multiply-defined names. That is the expected
and correct outcome, not a failure.

### Public/private classification

Each definition is annotated, **advisory only**:

- `public` — macro name matches its file basename, exactly.
- `public?` — macro name matches the file's *family* basename after stripping
  known variant suffixes (`_old`, `_test`, `_wt`, `ma`, `_AT`). E.g. `%macro
  std_dif` in `std_dif_wt.sas`.
- `private` — everything else.

This annotation informs human review and scopes Phase 2..N (only public entry
points need R implementations). It never drives a `drop`.

### Heuristic lint (rule 3)

Implemented in pure R. No SAS dependency, so triage is reproducible by anyone,
with or without server access.

Checks:
- Balanced single quotes per statement.
- Matched `%macro` / `%mend`, case-insensitively.
- Matched `do` / `end`.
- Presence of at least one `%macro` definition.

This demonstrably catches the `_test_AT` class already identified. A file that
lints clean but would not compile survives to rule 4–6, which is acceptable: the
failure mode is "a human looks at it," not "a broken macro is silently declared
canonical."

Rejected alternative: driving SAS in `obs=0` / syntax-check mode.
Authoritative, but SAS runs on a separate system, so this would couple Phase 0
to a cross-system round-trip and make triage non-reproducible for anyone without
access to that host. Deferred; may be revisited if lint proves insufficient, and
is a natural add-on once the Phase 1 transfer mechanism exists.

### Overrides

`macro_overrides.yaml` is hand-edited and committed. One entry per human
decision, keyed on **macro name**:

```yaml
- macro: std_dif
  canonical_file: std_dif.sas
  rejected:
    - {file: std_difma.sas,      reason: "matched-analysis variant; superseded"}
    - {file: std_dif_TEST.sas,   reason: "abandoned WIP"}
    - {file: std_dif_TESTma.sas, reason: "abandoned WIP"}
    - {file: std_dif_wt.sas,     reason: "weighted variant; port separately as std_dif(weights=)"}
  rationale: >
    Five distinct bodies. std_dif.sas is the version called by
    tp.dc.stddiff.summarytable.sas.
  decided_by: JE
  decided_on: 2026-07-10
```

This is what manual review of 179 files could not provide: the decisions are
auditable and re-derivable months later, rather than reconstructed from memory.

### Error handling

Following the package's established philosophy: expensive or uncertain
operations are opt-in and error loudly.

- An extracted macro body that is **empty** is an error, not a datum.
- A `%macro` without a matching `%mend` is an error, reported with its line number.
- Lint failures are **recorded** in the decision table, never swallowed.
- A definition matching no rule receives `status: unclassified`.
- If any row is `unclassified`, the run **exits non-zero**. Nothing is silently
  skipped.
- `sas_triage()` on a directory containing zero `.sas` files is an error, not an
  empty result.

### Testing

`testthat`, edition 3, matching `Config/testthat/edition: 3` in `DESCRIPTION`.

Fixtures are small synthetic `.sas` files committed under
`tests/testthat/fixtures/`. They contain no PHI and require no real macro.

| Fixture | Exercises |
|---|---|
| `Copy of alpha.sas` | Rule 1 |
| `beta.sas~` | Rule 2 |
| `gamma_broken.sas` (unbalanced quote) | Rule 3 |
| `delta.sas`, `delta_dup.sas` (byte-identical `%macro delta`) | Rule 5 |
| `epsilon.sas` (unique `%macro epsilon`) | Rule 4 |
| `zeta.sas`, `zeta_old.sas` (`%macro zeta`, divergent bodies) | Rule 6 |
| `multi.sas` (three `%macro` defs in one file) | Multi-definition extraction |
| `upper.sas` (`%MACRO UPPER;`) | Case-insensitive matching |
| `nomend.sas` (`%macro x;` with no `%mend`) | Extraction error |

Critical assertions:

1. **Rule 6 refuses to decide.** `sas_triage()` marks `zeta` `ambiguous` and
   selects no canonical file.
2. **Case-insensitive matching.** `upper.sas` yields a non-empty body for
   `%MACRO UPPER`. This is a direct regression test for the `awk`/`IGNORECASE`
   defect described above.
3. **Empty body is an error.** `nomend.sas` raises, and does not produce a hash.
4. **Idempotence.** Supplying an override for `zeta` yields a byte-identical
   manifest across repeated runs.

## Deliverables

1. `R/sas_macro_defs.R`, `R/sas_macro_signature.R`, `R/sas_triage.R`,
   `R/write_macro_manifest.R`
2. `tests/testthat/` coverage for all six rules, multi-definition extraction,
   case folding, extraction errors, and idempotence
3. `macro_manifest.yaml` — the canonical set, keyed by macro name
4. `macro_signatures.yaml` — call signatures, consumed by Phase 1
5. `macro_overrides.yaml` — the human decision record
6. `collision_report.md` — every multiply-defined name, its distinct body count,
   defining files, and public/private annotation
7. A summary: files in, files dropped by rule, definitions canonical,
   definitions requiring review, subdirectories excluded

## Success criteria

- Every one of the 451 macro definitions carries a `decision` with attached
  `evidence`.
- Zero definitions are `unclassified`.
- Every `ambiguous` macro name has a corresponding entry in
  `macro_overrides.yaml`.
- Re-running `sas_triage()` reproduces `macro_manifest.yaml` byte-for-byte.
- No macro is declared canonical by a heuristic tiebreaker.
- `collision_report.md` accounts for all 85 multiply-defined names.

## Open questions deferred to Phase 1

- **Cross-system execution.** SAS lives on a separate host. The harness must
  ship canonical macros plus synthetic fixtures to that host, run them, and
  retrieve outputs. Open: transfer mechanism, whether it can be scripted or
  requires a human in the loop, and whether the host can reach this repository
  at all. This determines whether Phase 1 is an automated pipeline or a
  batched hand-off.
- Synthetic fixture design: exercising censoring patterns, competing events, and
  missingness without carrying patient data. The existing `naftel.ssd` fixture is
  real clinical data and cannot be committed, and must not be transferred to any
  host not already approved for PHI.
- Golden-output format and floating-point tolerance policy.
- Harness `%include` ordering, given that shadowing is now known to be real.
- Ownership of the `mm`/`gm`/`bh`/`bl`/`bc`/`nm` modeling group.
- Disposition of the 40 files in `table_mac/`, `readin_samples/`,
  `logis_reclassi/`, `repeat_test/`.
- Disposition of `hazard/`, which contains no `DESCRIPTION` and is not an R
  package.

## Amendments

### 2026-08-14 — ownership map and shared assets

Phase 0 shipped in 1.0.4. Two things in the *Context* section were written from
inference in July and have since been checked against `hvtiRtemplates`, which
did not exist in usable form at the time.

**The Phase 2..N prefix map was wrong in two places.** `bd` was assigned to
`hvtiRutilities`; `hvtiRdatasets` now owns dataset build and verification, so
`bd` belongs there. `dc` was not mentioned at all; it is `hvtiRtables`. The map
in *Context* is now a table derived from `hvtiRtemplates::hvti_taxonomy()`,
which is the authority — re-derive from it rather than editing the table by
hand.

**Shared assets were not addressed at all.** The original design assumed every
corpus file is either a macro to port or a file to drop. The format catalogs are
neither: `cvirfmts.sas` has no `%macro` definition, so the rule ladder never
classifies it, and it would have fallen through Phase 0 unremarked. It is data
consumed by 201 of the 229 templates across every folder. The new subsection
records the rule — a file with no `%macro` definition is an asset, routed by who
loads it — and its two worked cases.

### Figures superseded since the original draft

The measurements in *Problem* (179 files, 451 definitions, 240 names, 85
multiply-defined) were taken with a `.sas`-anchored file glob and a per-line
lint, both of which were later found defective. Corrected figures, from the
shipped implementation:

| | Original draft | Shipped |
|---|---|---|
| Files triaged | 179 | 336 |
| Macro definitions | 451 | 816 |
| Distinct names | 240 | 307 |

The gap is not a change of policy. File discovery missed every macro file
carrying no extension, and every file whose dots are word separators rather than
an extension — `deciles.hazard`, `lm.cprobs`, `kaplan.int`. Among the omitted
was `unistats`, whose statistic vocabulary turned out to specify the
`proc_means()` extension shipped in 1.0.5. The *Heuristic lint* section's
`do`/`end` balance check was also removed: textual balance is not a validity
property of macro source, since `%do`-guarded blocks emit `DO` and `END` from
separate branches.

Five files are rejected as genuinely defective: `bl_ord.norm.ci.sas`,
`CR_compare_CP_test_AT.sas`, `rem.original`, `rem.uab` and `repeated.sas`.
