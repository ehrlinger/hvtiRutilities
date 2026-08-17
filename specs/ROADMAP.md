# Roadmap

Work that is designed, or partly designed, and deliberately not built yet.
Each entry says where its decisions already live, so the next person starts
from the argument that was settled instead of reopening it.

This is not a list of ideas. An entry earns a place here once deferring it was
a decision someone made with reasons, and those reasons are written down.

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
