# Roadmap

Work that is designed, or partly designed, and deliberately not built yet.
Each entry says where its decisions already live, so the next person starts
from the argument that was settled instead of reopening it.

This is not a list of ideas. An entry earns a place here once deferring it was
a decision someone made with reasons, and those reasons are written down.

## Study setup and legacy adoption

Replaces the production `mkdirs` path with a Study Tracker-driven
`study-setup` command and lets `_study.yml` record identity before a built
dataset exists. `register_data()` completes the dataset and cohort contract
later. Existing studies enter through an explicit, non-destructive `--adopt`
path; missing manifests enter through an explicit `--recover` path.

**Decisions already settled** are in the
[study setup and legacy adoption design][study-setup-design].
The production command set first moves into a checksum-verified `qhsprograms`
Azure DevOps repository. The command owns Tracker and Azure DevOps access;
`hvtiRutilities` owns study structure, manifest states, data registration, and
status. `renv` initialization is automatic when it can preserve every existing
environment file.

**Still open.** Two implementation plans, one for the new `qhsprograms`
repository and one for this package. The first pilot is a dry run against a
disposable copy of the designated legacy study; it does not remove the study's
`.git` or copied `templates/` directories.

## `study_checkpoint()`

Records low-burden milestones such as the first abstract and first manuscript
submission in a study's future `CORR_STUDIES` repository. The checkpoint keeps
source and reproducibility metadata, including `_study.yml` and `renv.lock`,
and excludes data, results, credentials, and PHI.

**What it builds on.** The setup and recovery design above gives each study a
stable Tracker identity and a deterministically named repository. A missing
manifest can then be restored from local or Azure DevOps history rather than
reconstructed from memory.

**Still open.** No separate spec or plan. Updating a Study Tracker task from a
checkpoint is deferred with it: task transitions are not linear, and the
current Tracker does not retain the path taken. Setup remains read-only against
Study Tracker.

[study-setup-design]:
  dev/specs/2026-09-15-study-setup-legacy-adoption-design.md

## `study_close()`

Records what a study looked like when a paper was accepted: the citation, the
accepted manuscript and its checksum, the exhibits behind it, and a grade for
how re-derivable the result actually is.

**Why it is not built.** Close-out was the original ask. Designing it showed it
to be the wrong end of the problem: a close-out function cannot manufacture
evidence that was never recorded, so run against a study today it could only
report that the identity, the lockfile and the manifest are all missing.
`study_init()` and `study_status()` were built first so that a study has
something true to record by the time it closes.

**Decisions already settled**, in the *Close-out, deferred* section of
[`2026-08-17-study-init-design.md`](2026-08-17-study-init-design.md):

- One record per accepted paper at `documents/_publications/<slug>.yml`,
  carrying the citation block (journal, year, DOI, PMID, internal tracking
  number), the `accepted:` date, the manuscript file and its SHA-256, the
  exhibit list, and `status:` / `gaps:`.
- Grade vocabulary: `verified` (identity, lockfile, verified manifest, and a
  sidecar per exhibit), `partial` (R present, something named in `gaps`
  missing), `legacy` (SAS only, recorded but not re-derivable).
- It records, it does not enforce. It refuses nothing but a manuscript file
  that does not exist. Pressure applied at acceptance is pressure applied years
  too late, which is the argument the whole design turns on.
- Legacy studies close with `exhibits: []` and are annotated by hand only when
  a specific paper is worth it. The `survival` study's flat 57-file
  `documents/`, with revisions distinguished by `rev 1.4` / `rev1.2` / `Rev 1`
  filename suffixes and Word lock files scattered through it, is what legacy
  close-out will actually meet, and it is not parseable.

**What it builds on.** `study_status()` already computes the audit. Close-out
grades a publication record from that same scanner rather than growing a second
one, because two near-identical scanners drift.

**Still open.** No spec, no plan, no tests. The manuscript-folder convention
(`<study root>/documents/manuscript/`, with `revision/` subfolders for new work)
is assumed rather than adopted, and nothing enforces it. Write the spec once
studies start reaching acceptance with a `_study.yml` already in place. Before
that there is nothing to close out.

## A study-completeness check

Would answer "is this study's set of filed results complete", which is a
different question from "is each filed result sound". `study_status()` already
answers the second one.

**The constraint that shapes it** is settled in
[Finding 4](2026-08-17-verification-gates-findings.md) of the verification-gates
findings: completeness cannot be inferred from the artifacts. A sidecar records
what a run used, but no single result knows how many results the study was
supposed to produce. The study's bootstrap screen makes the point concretely. It
lands as 25 independent chunks, each recording its own seed, entry and stay
criteria, step cap and dataset checksum, and none of them recording how many
siblings it was launched with. A pool of 12 of 25 is therefore not detectably
different from a complete run of 12. Every health check passes, every frequency
is honestly computed, and only the denominator is not the intended one.

**What follows for this package.** The expected total has to be declared
somewhere that is not the artifacts, which for a study means `_study.yml`.
`study_status()` counts sidecars and `.qmd`/`.Rmd` sources and compares the two,
but that is a ratio between two things the tree happens to contain. It cannot
become a completeness check by counting more carefully. It needs a number the
study author wrote down.

**Still open.** No spec. Two questions to settle first: what the expectation is
keyed on (a count, a named list of expected results, something per analysis),
and what a study with no expectation recorded should report. By
`study_status()`'s own rule a check that could not run is not a check that
failed, so an absent expectation is `MISSING` rather than `FAIL`, and only a
declared expectation that is not met is drift.

**Why it is written down before it is built.** This failure mode is silent by
construction, so nothing in the tree will ever prompt someone to go looking for
it. Recording the argument is the only thing that keeps it findable.
