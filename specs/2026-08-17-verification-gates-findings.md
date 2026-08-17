# Findings: verification gates that pass without verifying

**Date:** 2026-08-17
**Source:** work in the `survival` study tree (`analyses/R_hazard`), during the
bootstrap screen for the pericardial AVR / LV function study.
**Status:** one confirmed defect in this package, plus a defect class and two
migration consequences. No code in this package has been changed by this note.

---

## 1. Confirmed defect: `verify_manifest()` passes an entry it did not verify

`R/manifest.R` gates the row count cross-check on the manifest entry carrying a
row count:

```r
if (ext %in% c("csv", "sas7bdat", "xlsx", "xls") && !is.null(entry$n_rows)) {
```

When `entry$n_rows` is absent the check is skipped, no note is made, and the
entry returns `status = "OK"`. The reported message is worse than silent: it
prints the row count field with nothing in it.

### Reproduction

Verified against the installed 1.0.2 and again against the working tree at
1.0.7. Same behaviour in both.

```r
d   <- file.path(tempdir(), "vm"); dir.create(d)
csv <- file.path(d, "cohort.csv")
write.csv(data.frame(id = 1:10), csv, row.names = FALSE)
sha <- digest::digest(csv, algo = "sha256", file = TRUE)

# A manifest entry with a checksum but NO n_rows.
yaml::write_yaml(list(datasets = list(list(file = "cohort.csv", sha256 = sha))),
                 file.path(d, "manifest.yaml"))

verify_manifest(file.path(d, "manifest.yaml"), data_dir = d,
                stop_on_error = FALSE)
```

Observed:

```
status: OK   message: SHA-256 match (n = )
```

The same manifest with a deliberately wrong `n_rows = 999` correctly returns
`FAIL`. So the check works; it just does not run, and not running reads as
passing.

### Why it matters here specifically

`verify_manifest()` exists to answer "is this the dataset the analysis was run
against". A caller cannot currently distinguish these three states from the
return value:

| Real state | Reported |
|---|---|
| checksum verified, rows verified | `OK` |
| checksum verified, rows **not checked** | `OK` |
| checksum verified, rows verified, count happens to be blank in the message | `OK` |

The middle row is the problem. A manifest written by an older version, by hand,
or by a writer that could not count rows (`.auto_count_rows()` refuses
`.sas7bdat` and Excel unless `manifest.allow_heavy_rowcount` is set, which is
the **default** path for exactly the file types this group uses most) produces
entries with no `n_rows`. Those entries then verify clean forever.

### Suggested shape of a fix

Not implemented here, deliberately: this is a behaviour change with a release
gate attached, and it is the package owner's call.

The minimum is that "not checked" must be a distinct, visible outcome. Options,
weakest to strongest:

1. Report it. Add a `checks` column naming what actually ran
   (`sha256`, `sha256+n_rows`), so `OK` is qualified rather than bare.
2. Add a `SKIP` status alongside `OK`/`FAIL`, so a summary count of `OK` cannot
   silently include unverified entries.
3. Make a missing `n_rows` a `FAIL` under a `strict = TRUE` argument, defaulting
   to `FALSE` for backwards compatibility.

Whichever is chosen, the empty `(n = )` in the message should go: a blank value
in a field labelled as verified is the most misleading part of the current
output.

---

## 2. The defect class: absence is not agreement, and absence is not verification

The `verify_manifest()` case above is one instance of a shape that appeared
twice in one day, in unrelated code.

The second instance was in the study tree, in `pool_bagging()`, which decides
whether bootstrap chunks may be pooled. It compared each chunk's value of a
field by formatting it to a string and asking whether more than one distinct
string resulted:

```r
vals <- vapply(chunks, function(k) paste(format(get(k)), collapse = "\r"),
               character(1))
if (length(unique(vals)) > 1L) stop(...)
```

In R, `format(NULL)` returns the character string `"NULL"`, not a zero length
vector. So a field that **no chunk records** produces the same string for every
chunk, the gate passes unanimously, and the accessor then returns `NULL` as the
agreed value. The guard on the step cap had been vacuous in the test fixture for
this reason, and the suite was green.

Stated generally, and worth adopting as a review question for this package:

> A check that compares recorded values must establish that the values were
> recorded before it compares them. Otherwise "nobody wrote this down" and
> "everybody wrote the same thing" are the same observation.

This is [[fail-loud-engineering]] applied to verification code specifically. The
failure is not that the check is wrong; it is that the check is absent while
reporting itself as present, which is strictly worse than having no check at
all, because the surrounding documentation asserts that the protection exists.

Concrete review questions for this package:

- Every `if (!is.null(x))` that wraps a comparison: what does the caller see
  when `x` is `NULL`, and can they tell it apart from a pass?
- Every `identical()` against a value read from a file: what if the file did not
  carry the field?
- Anything that summarises many records into "they agree": does it separate
  "agree" from "none recorded"?

---

## 3. Migration consequence: `built_manifest()` moving from `md5` to `sha256`

The Stage 1 plan for this package (`analyses/R_hazard/docs/plans/2026-08-17-hvtirutilities-provenance.md`
in the study tree) has the packaged `built_manifest()` emit `sha256`, where the
per-study version emits `md5`, so that one hash algorithm serves both the
manifest and the provenance sidecar. That is the right call.

It has a downstream consequence that is invisible at the call site.

`analyses/R_hazard/R/bagging-pool.R` read the chunk checksum as
`k$manifest$md5`. After the change that expression returns `NULL` for every
chunk written by the new code, and by the mechanism in section 2 the dataset
checksum gate would have gone quiet exactly when the manifest changed. The gate
whose comment describes it as "the one that means the cohort itself changed"
would have stopped meaning anything, with no error.

This was fixed in the study tree on 2026-08-17: the accessor now reads whichever
of `sha256` or `md5` is present, and returns the digest tagged with its
algorithm (`"md5:abc…"`, `"sha256:abc…"`) so that two chunks hashed differently
disagree and are refused rather than compared as though comparable.

**Action for this package:** when the Stage 1 change lands, grep consumers for
`manifest$md5` and for any hard coded column name over a manifest. The pattern
to prefer is "read whichever algorithm is recorded, and carry the algorithm name
with the digest", not "read the column we currently write".

Note also that `verify_manifest()` compares `entry$sha256` and is therefore
already sha256-only. Manifests written by the current `built_manifest()`, which
records md5, are not verifiable by it. That mismatch predates this note and is
worth resolving as part of the same change.

---

## 4. Completeness expectations must come from outside the artifacts

Relevant to `record_provenance()` and to any future check of the form "did all
the pieces arrive".

The bootstrap screen in the study runs as 25 independent chunks that land over
roughly twelve hours. Each chunk records everything about itself: its seed, its
entry and stay criteria, its step cap, its dataset checksum. **None of them
records how many siblings it was launched with**, because none of them knows.

The consequence is that a pool of 12 of 25 chunks is not detectably different
from a complete run of 12 chunks. Every health check passes, every frequency is
honestly computed, and only the denominator is not the intended one. No amount
of inspecting the artifacts can catch it.

The fix was to declare the expected totals outside the artifacts, in the
consuming document, and to report a shortfall prominently rather than leaving it
to a reader to compare two table cells.

**Why this belongs in this package's thinking:** the same shape will appear in
provenance. A sidecar can record what a run used. It cannot, on its own, record
that a study's set of filed results is complete, because no single result knows
how many results the study was supposed to produce. If a "is this study fully
recorded" check is ever wanted, the expectation has to live in `_study.yml` or
an equivalent, not be inferred from the sidecars present.

The same argument applies to the spec's proposed test that
`hvtiRtemplates`'s `inst/sas/` and `inst/macros/` file counts match a recorded
expectation. That expectation is correct precisely because it is recorded
separately from the files it checks.

---

## Evidence and provenance of this note

Everything above was observed on 2026-08-17:

- `verify_manifest()` behaviour: executed, both installed 1.0.2 and working tree
  1.0.7, output quoted verbatim.
- `format(NULL)` returning `"NULL"`: executed and confirmed.
- The `pool_bagging()` defect: found by reading, confirmed by three tests that
  failed for the expected reason before the fix and pass after it.
- The chunk completeness gap: confirmed against a synthetic 25 chunk pool and
  against real runner output on disk.

No claim here is inferred from documentation alone.
