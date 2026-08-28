# Roadmap

Work that is designed, or partly designed, and deliberately not built
yet. Each entry says where its decisions already live, so the next
person starts from the argument that was settled instead of reopening
it.

This is not a list of ideas. An entry earns a place here once deferring
it was a decision someone made with reasons, and those reasons are
written down.

## `study_close()`

Records what a study looked like when a paper was accepted: the
citation, the accepted manuscript and its checksum, the exhibits behind
it, and a grade for how re-derivable the result actually is.

**Why it is not built.** Close-out was the original ask. Designing it
showed it to be the wrong end of the problem: a close-out function
cannot manufacture evidence that was never recorded, so run against a
study today it could only report that the identity, the lockfile and the
manifest are all missing.
[`study_init()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_init.md)
and
[`study_status()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md)
were built first so that a study has something true to record by the
time it closes.

**Decisions already settled**, in the *Close-out, deferred* section of
[`2026-08-17-study-init-design.md`](https://ehrlinger.github.io/hvtiRutilities/2026-08-17-study-init-design.md):

- One record per accepted paper at `documents/_publications/<slug>.yml`,
  carrying the citation block (journal, year, DOI, PMID, internal
  tracking number), the `accepted:` date, the manuscript file and its
  SHA-256, the exhibit list, and `status:` / `gaps:`.
- Grade vocabulary: `verified` (identity, lockfile, verified manifest,
  and a sidecar per exhibit), `partial` (R present, something named in
  `gaps` missing), `legacy` (SAS only, recorded but not re-derivable).
- It records, it does not enforce. It refuses nothing but a manuscript
  file that does not exist. Pressure applied at acceptance is pressure
  applied years too late, which is the argument the whole design turns
  on.
- Legacy studies close with `exhibits: []` and are annotated by hand
  only when a specific paper is worth it. The `survival` study’s flat
  57-file `documents/`, with revisions distinguished by `rev 1.4` /
  `rev1.2` / `Rev 1` filename suffixes and Word lock files scattered
  through it, is what legacy close-out will actually meet, and it is not
  parseable.

**What it builds on.**
[`study_status()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md)
already computes the audit. Close-out grades a publication record from
that same scanner rather than growing a second one, because two
near-identical scanners drift.

**Still open.** No spec, no plan, no tests. The manuscript-folder
convention (`<study root>/documents/manuscript/`, with `revision/`
subfolders for new work) is assumed rather than adopted, and nothing
enforces it. Write the spec once studies start reaching acceptance with
a `_study.yml` already in place. Before that there is nothing to close
out.

## A study-completeness check

Would answer “is this study’s set of filed results complete”, which is a
different question from “is each filed result sound”.
[`study_status()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md)
already answers the second one.

**The constraint that shapes it** is settled in [Finding
4](https://ehrlinger.github.io/hvtiRutilities/2026-08-17-verification-gates-findings.md)
of the verification-gates findings: completeness cannot be inferred from
the artifacts. A sidecar records what a run used, but no single result
knows how many results the study was supposed to produce. The study’s
bootstrap screen makes the point concretely. It lands as 25 independent
chunks, each recording its own seed, entry and stay criteria, step cap
and dataset checksum, and none of them recording how many siblings it
was launched with. A pool of 12 of 25 is therefore not detectably
different from a complete run of 12. Every health check passes, every
frequency is honestly computed, and only the denominator is not the
intended one.

**What follows for this package.** The expected total has to be declared
somewhere that is not the artifacts, which for a study means
`_study.yml`.
[`study_status()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md)
counts sidecars and `.qmd`/`.Rmd` sources and compares the two, but that
is a ratio between two things the tree happens to contain. It cannot
become a completeness check by counting more carefully. It needs a
number the study author wrote down.

**Still open.** No spec. Two questions to settle first: what the
expectation is keyed on (a count, a named list of expected results,
something per analysis), and what a study with no expectation recorded
should report. By
[`study_status()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md)’s
own rule a check that could not run is not a check that failed, so an
absent expectation is `MISSING` rather than `FAIL`, and only a declared
expectation that is not met is drift.

**Why it is written down before it is built.** This failure mode is
silent by construction, so nothing in the tree will ever prompt someone
to go looking for it. Recording the argument is the only thing that
keeps it findable.
