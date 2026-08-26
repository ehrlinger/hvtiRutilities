# Job-type inventory — the level-one corpus sweep

**Date:** 2026-08-26
**Status:** designed, approved, not implemented
**Package:** `hvtiRutilities` (PR 1), `hvtiRtemplates` (PR 2)
**Implements:** §2 of `hvtiRtemplates/specs/2026-08-26-job-type-census-sweep.md`
**Supersedes that spec's §5** ("Where this work should live"), which left the
destination open. Decided: `hvtiRutilities`.

This note is self-contained. It assumes no memory of the session that produced
it.

---

## 1. The question this answers

For each job prefix, **which studies have run it, and how many jobs each?**

`hvtiRtemplates` gates every template on *a second study having run that job
type* — a template extracted from one study encodes that study's choices as
though they were general. So for each pending prefix somebody must know
whether a second study exists.

On 2026-08-26 that was answered by hand, one `ls` at a time:

| prefix | maze/atricure/gender | preserve_root |
|---|---|---|
| `ac` | 30 | 40 |
| `hz` | 24 | 35 |
| `hp` | 28 | 67 |
| `hm` | **0** | 1 |
| `hs` | **0** | 3 |
| `bh` | **0** | 6 |

That table decided a real design question — `hm`/`hs`/`bh` exist in only one
study, so they cannot be templated yet and must not be stubbed. It should have
been one lookup, and it should be repeatable when the corpus changes.

**The hand-count counted files, not jobs.** Reproduced against preserve_root
on 2026-08-26: `ac` 40 files / 24 stems, `hz` 35 / 12, `hm` 1 / 1, `hs` 3 / 1,
`bh` 6 / 2. The file counts match the table exactly. So `hz` in preserve_root
is twelve jobs across thirty-five artifacts, and the parent spec's success
criterion — a column named `n_jobs` — does not describe the table it points at.
This design carries **both** columns for that reason (§4).

## 2. Scope

**In:** a filename-only inventory of `/studies`. No file contents are read, no
`.lst` is parsed, no `TemporalHazard` dependency.

**Out:** Level 2 (repeated-events flagging) and Level 3 (per-family content
parsers) from the parent spec. The file-level table designed here is the seam
they attach to later — both add *columns* to `job_files()` without changing the
roll-up.

**Also out, and tracked separately:** having `new_job()` write a README that
declares each job it creates (§8). That is a different package, a different
contract, and needs its own design pass.

## 3. Where the work lives

`hvtiRutilities`. The sweep has no study-specific content and no
`TemporalHazard` dependency, and `hvtiRutilities` already owns the study-shape
layer — `study_config()`, `study_init()`, `study_paths()`, the manifest.

The alternative was leaving it a study-tree script beside `shape-census.R`.
Rejected: `shape-census.R` is an untracked file on a network share in a tree
that is **not a git workspace** (`preserve_root` carries a stray 2023 `.git`
with no remote and hundreds of uncommitted paths — do not branch or commit
there). That is acceptable for a one-question script and wrong for tooling the
template roadmap depends on.

### 3.1 The taxonomy moves down

`hvti_taxonomy()` and `hvti_non_prefixes()` live in
`hvtiRtemplates/R/taxonomy.R` (89 lines, two exports, 138 lines of tests).
`hvtiRtemplates` currently imports nothing but `stats`; the two packages are
independent today.

**Decision: the taxonomy moves into `hvtiRutilities`, and `hvtiRtemplates`
imports it back and re-exports both functions.**

Rationale: the prefix table is shared *vocabulary* — which prefix means what,
which folder it belongs in — not template machinery. `hvtiRutilities` is the
lower layer. Adding `Imports: hvtiRtemplates` to the utilities package would
invert that, and the day anything in templates needs a utility back, there is a
cycle to unpick.

Cost, stated plainly: `hvtiRtemplates` loses its zero-dependency property, and
the change spans two repos in a fixed order (§7).

**A duplication window is not acceptable.** `taxonomy.R`'s own docstring
records why: *"The same table lived in a README and drifted from the files it
described."* The two PRs are sequenced so the table never exists twice.

## 4. `job_files()` — one row per file, nothing discarded

```r
job_files(roots)
```

Returns a data frame with **one row per candidate file, always**. Placement and
classification are columns, never reasons to drop a row.

| column | meaning |
|---|---|
| `path` | absolute path |
| `study` | parent of the nearest taxonomy-folder ancestor; `NA` when `unplaced` |
| `folder` | the matched taxonomy folder; `NA` when `unplaced` |
| `status` | `"placed"` / `"nested"` / `"unplaced"` — see §4.1 |
| `depth` | 0 for `placed`, ≥1 for `nested`, `NA` for `unplaced` |
| `naming` | which name convention matched — see §4.2 |
| `prefix` | the job prefix, or `NA` if no convention matched |
| `is_template` | `TRUE` if a `tp.` marker was stripped |
| `stem` | basename minus final extension — the `n_jobs` unit |
| `ext` | final extension |
| `prefix_class` | `"known"` / `"non_prefix"` / `"unknown"` — see §4.3 |
| `folder_expected` | the taxonomy's folder for that prefix |
| `folder_ok` | `folder == folder_expected` |

**Why status-as-a-column rather than a discard report.** The parent spec asks
three times that discards be reported. Making them rows goes one step further
and makes an unreported discard structurally impossible. This matters because
of a failure the parity handoff documents twice: in `shape-census.R` the CSV
was complete both times and only the *printed summary* narrowed — which is the
worse place for it, since the summary is what gets read. A bucket you must
remember to print can be forgotten. A row cannot.

### 4.1 Study attribution and `status`

Walk up from each file to the nearest ancestor named in
`hvti_taxonomy()$folder`; `study` is that folder's parent, recorded as a path
**relative to the sweep root** (`cardiac/rhythm/maze/atricure/gender`), not an
absolute one. The same study resolves to different absolute paths on the
server and on a Mac mount, so an absolute `study` would make two runs of the
same corpus incomparable. `path` stays absolute, since it is what you paste
into a terminal.

- `placed` — the file's immediate parent *is* the taxonomy folder. `depth = 0`.
- `nested` — a taxonomy folder is a deeper ancestor. `depth` = levels below it.
- `unplaced` — no taxonomy folder anywhere in the path. `study` and `folder`
  are `NA`; the row survives so the file can be found.

Nesting is real and already present: preserve_root holds ten `hp.*` files in
`graphs/Training/`, and its R jobs sit two levels down in
`analyses/R_hazard/qmd/`. A naive "study = the file's grandparent" rule would
credit those to a study named `graphs`. Counting them toward the study while
keeping `depth` visible means they are neither silently pooled nor silently
dropped.

### 4.2 `naming` — the corpus holds several conventions, not one

Filename parsing is **not** "split on the first dot". As of 2026-08-26 four
conventions are live:

| `naming` | pattern | example | where |
|---|---|---|---|
| `legacy` | `<prefix>.<endpoint>[...].<ext>` | `hz.dead.lst` | 527 studies in `/studies` |
| `template` | `<NN>.<MM>-<prefix>.qmd` | `03.01-ac.qmd` | `hvtiRtemplates/inst/templates/` |
| `new_job` | `<endpoint>-<type>-<ordinal>-<prefix>.qmd` | `dead_pa-parity-03.01-hz.qmd` | `hvtiRtemplates/R/new-job.R:55` |
| `ordinal_first` | `<NN>-<prefix>-<endpoint>.qmd` | `02-hz-dead_pa.qmd` | preserve_root `analyses/R_hazard/qmd/` |

`prefix` is resolved by trying each parser **in a fixed order — `template`,
`new_job`, `ordinal_first`, `legacy` — and taking the first match.** The order
is most-specific-first and must not be rearranged casually: the three R-side
patterns are tightly anchored (two required digits, a required `.qmd`), while
`legacy` is permissive enough to "succeed" on almost any dotted name and would
shadow the others if tried first. A file matching none gets `naming = NA`,
`prefix = NA`, and stays in the table.

A test asserts the order by feeding one file that more than one parser could
claim and pinning which wins.

**Two things this table makes visible.**

First, under a legacy-only parser every R job in preserve_root classifies as
prefix `01-ac-dead_pa` and lands in the unknown bucket — *the entire R
migration output would be invisible to the inventory built to track it.*

Second, `new_job`'s convention and the R jobs already on disk **do not match
each other**; the latter predate `new_job()`. See §6 for the recommended fix.

**Legacy prefix extraction, specifically.** Strip a leading `tp.` **first**,
record the file as a template, and take the prefix from what remains.
Otherwise `tp.hz.dead.lst` classifies as prefix `tp`, which both loses the fact
that it is an `hz` template and collides with the template-exclusion rule.
Anchor at `^<prefix>[.]` once the marker is stripped. Prefixes are not
fixed-width — `vars`, `rfsrc`, `rfc`, `rfs` are all in the taxonomy — so no
parser may assume two characters.

### 4.3 `prefix_class` is three-way, not two

- `known` — in `hvti_taxonomy()$prefix`.
- `non_prefix` — in `hvti_non_prefixes()`: `plots`, `ppt`, `PPTs`, `test`,
  `pp`, `ref`, `refs`. These are documented leading fields that are *not*
  analysis prefixes.
- `unknown` — neither. **This is the finding**, and the only one of the three
  that belongs in the summary as a discovery.

A two-way split would report `pp` — twenty files in preserve_root — as a
discovery when it is already documented as not-a-prefix. `hvti_non_prefixes()`
exists precisely to tell "not a prefix" apart from "a prefix nobody
documented"; reusing it keeps that distinction in one place.

Genuinely unknown prefixes do exist and must surface. preserve_root has
`pgm.*.asv`, `boost.*.rda`, `mult_imput.*.sas`.

### 4.4 There is no extension filter

`ext` is data. Nothing is excluded by extension.

An earlier draft of this design defaulted to
`ext_keep = c("sas", "lst", "log", "pdf", "rtf")`, derived from a `find`
restricted to `hz`/`ac`/`hp`/`bh`. Widening to every taxonomy folder shows what
that sample hid — the allowlist would have dropped 23 `dp.*.R`, 6 `rfsrc.*.R`,
4 `pp.*.R`, 4 `lp.*.R`, 4 `boost.*.rda`, 3 `ar.*.doc` and 2 `rf.*.qmd`. That is
every R-side job in the corpus, silently removed from a SAS→R migration
inventory, by a default nobody would revisit.

The bug shape is the one the parent spec warns about: a sample chosen for one
question (`hz` phase shapes) silently defining scope for a different question
(corpus inventory). The fix is not a better allowlist — it is not having one,
so the sample cannot leak into the design.

Two consequences, both accepted:

- `README.md` classifies as prefix `README` and lands in `unknown`. That is the
  correct place for it, and `hvti_non_prefixes()` is the existing mechanism for
  silencing it — a one-line reviewed decision, not a filter default.
- Editor backups (`bn.avregurg_grp.sas~`, seven in preserve_root) inflate
  `n_files` but **not** `n_jobs`, since they share a stem with the file they
  back up. The stem dedup absorbs that noise on its own, which is a further
  argument for `n_jobs` as the headline column.

## 5. `job_census()` and its print method

```r
job_census(x)   # x: character roots, or a job_files() data frame
```

Rolls up to one row per `(study, prefix, folder, is_template)`:

| column | meaning |
|---|---|
| `n_jobs` | distinct `stem`s — the honest unit |
| `n_files` | rows — reproduces the 2026-08-26 hand-count for reconciliation |

Returns class `c("hvti_job_census", "data.frame")`.

**The print method leads with the column the roadmap needs**: prefixes ranked
by **number of distinct studies**, jobs only, templates counted separately.
`hm`/`hs`/`bh` at one study each reads straight off it — that is the lookup
that replaces the hand-count.

Then the accounting, none of it optional:

1. `status` tallies — `placed` / `nested` / `unplaced`, with example paths.
2. `prefix_class = "unknown"` — counts and example paths.
3. `folder_ok = FALSE` — prefixes sitting outside their taxonomy folder.
4. `naming = NA` — files no convention parsed.
5. Extension breakdown.

**Do not assume the taxonomy folder.** `hz` turned out clean corpus-wide —
zero misfiled jobs, every one under `distributions/` — but that was verified,
not assumed. `folder_ok` encodes the check as data so every prefix gets it for
free; `hvti_taxonomy()` already carries the expected folder per row.

## 6. Recommended: unify `new_job()`'s output naming

**Not required for Level 1. Recorded here because it removes a permanent
parser rather than accommodating it, and because it was pre-authorised on
2026-08-26 ("we can change that if necessary").**

`new_job()` writes `<endpoint>-<type>-<ordinal>-<prefix>.qmd`
(`new-job.R:55`). The jobs already in preserve_root are
`<NN>-<prefix>-<endpoint>.qmd`. Two R-side conventions where one would do.

`.template_fields()`'s own comment states the principle the templates follow:
zero-padded ordinal-first *"is what makes a flat folder sort into run order
past nine entries."* `new_job()` then puts the endpoint first and throws that
sort order away. That reads as an oversight, not a decision — a jobs folder
sorts by endpoint instead of by run order.

**Recommendation:** `new_job()` emits `<ordinal>-<prefix>-<endpoint>[-<type>].qmd`.
It matches the template convention's ordinal-first principle and the jobs
already on disk, and collapses `naming` from four values to two — `legacy` for
the SAS corpus, `ordinal_first` for everything R.

**This changes `new_job()`'s contract and needs its own confirmation before
implementation.** Existing job files would either be renamed or left as-is; the
`ordinal_first` parser handles both either way.

## 7. Sequencing, versions, testing

**PR 1 — `hvtiRutilities` 1.1.0 → 1.1.1**
`R/taxonomy.R` moved in with the table-consistency half of its tests;
`R/job_census.R` added; `NEWS.md` and `DESCRIPTION` both updated (a test greps
NEWS for the exact DESCRIPTION version).

**PR 2 — `hvtiRtemplates` 1.0.3 → 1.0.4**
`R/taxonomy.R` deleted; `Imports: hvtiRutilities`; both functions re-exported
via `@importFrom` + `@export` so the public surface is unchanged.

Of the 18 references outside `taxonomy.R` itself, **14 move with the table**
(all of `tests/testthat/test-taxonomy.R`, which tests the table's internal
consistency) and **4 stay** and keep working untouched via the re-export:
`R/templates.R` (1), `tests/testthat/test-templates.R` (2), and
`inst/templates/README.md` (1). The templates-match-taxonomy tests stay —
they assert that the templates on disk cover the taxonomy, which is a
`hvtiRtemplates` claim about its own `inst/` and does not travel.

Merges after PR 1 installs. No window where the prefix table exists twice.

Patch bumps on both — new functions and an internal move, not a feature
consolidation. Neither PR touches the study tree.

**Testing.** A synthetic tree in `tempdir()` — no corpus, no network, CI-safe —
carrying one instance of every hazard named above: a `tp.hz.*` template, a
`graphs/Training/`-style nested file, an unplaced file, a genuinely unknown
prefix, a documented non-prefix (`pp`), an `hz.*` misfiled under `analyses/`,
one file per naming convention in §4.2, and one stem with four extensions so
`n_jobs = 1, n_files = 4` is pinned. Plus a fixture reproducing the
`ac` = 40 files / 24 stems shape, so the two count columns cannot be silently
swapped.

**Runtime.** One `list.files(recursive = TRUE)` per root; no file is opened.
Document that it runs **server-side at `/studies`, never over SMB** — the
parent spec records a 40-file scan timing out at two minutes over the mount.

## 8. Related, deliberately deferred: jobs that declare themselves

Raised 2026-08-26: have `new_job()` create or update a README recording what
job was created and where.

The connection to this design is direct and worth stating. Everything above
**infers** what a job is from its filename, and §4.2 is the cost of that — four
conventions, a parser each, and an R-migration output that a legacy-only parser
cannot see at all. A README written at creation time **declares** it instead,
and a declaration does not drift when a convention changes.

That does not remove the need for this sweep. The 527-study legacy corpus has
no declarations and never will, so inference is required regardless. The two
compose: prefer a declaration where one exists, fall back to inference.

It needs its own design pass — what the README contains, one per study or one
per folder, how it stays current when a job is renamed or deleted, what
`new_job()` does when the README is absent or hand-edited, and whether a
declaration that disagrees with the filename is an error or a finding.

## 9. What not to do

- Do not widen any prefix pattern without re-checking `tp.` exclusion.
- Do not report a sweep's coverage without reporting what it could not place.
- Do not reintroduce an extension allowlist (§4.4).
- Do not collapse `prefix_class` to two values (§4.3).
- Do not pool repeated-events and single-event fits in any parity number until
  the parent spec's §3 lands.
- Do not write per-family content parsers before a question needs them.
