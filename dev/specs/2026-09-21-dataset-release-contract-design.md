# Dataset Release and Study Adoption Contract

**Status:** Approved design for review
**Date:** 2026-09-21

## Purpose

A study can prove that its registered dataset changed, but it has no safe,
repeatable response when a new dataset becomes available. Updating a checksum
blesses the new bytes without reviewing them. Pinning a dated filename
preserves reproducibility, but it also leaves a study unaware that a newer
extract exists.

This design separates three events:

1. a statistical programmer builds a mutable draft;
2. the data-build package publishes an immutable release; and
3. each study explicitly adopts a published release.

A study always reads the release it has pinned. A newer release is visible but
does not silently change an analysis.

## Goals

- Preserve every published dataset as an immutable, dated release.
- Let a normal study run report that a newer release is available.
- Keep revision work reproducible by continuing to read the pinned release.
- Show the material differences between the pinned and candidate releases
  before adoption.
- Update `_study.yml` and `manifest.yaml` as one recoverable operation.
- Treat an in-place change to a published release as an integrity failure.
- Support same-day corrections without replacing an earlier release.

## Non-goals

- Draft datasets are not cataloged or visible to consuming studies.
- A study never follows a `current` file, symlink, or implicit latest release.
- The package does not decide whether a clinical change is correct.
- The first version does not produce a row-by-row or cell-by-cell data diff.
  It reports structure, labels, dimensions, and cohort counts.
- Existing studies without release metadata continue to work without update
  discovery.

## Terms

- **Draft:** mutable output used while a programmer builds and validates data.
- **Release:** an immutable dataset registered in the publisher's catalog.
- **Pinned release:** the exact release selected by a study contract.
- **Candidate release:** a published release newer than the pinned release.
- **Publish:** create an immutable release and register it in the catalog.
- **Adopt:** advance one study from its pinned release to a named candidate.

## Ownership

The data-build package owns publication. It validates a draft, creates the
release file, calculates release metadata, and updates the catalog.

`hvtiRutilities` owns consumption. It pins a release in the study contract,
detects newer releases, reviews a selected candidate, and adopts that candidate
without changing the published files.

The catalog is the interface between the packages. The producer and consumer
must share contract fixtures so that either package detects an incompatible
schema change.

## Alternatives considered

Scanning filenames was rejected as the primary discovery mechanism. A naming
rule can find plausible files, but it cannot distinguish a completed release
from a programmer's same-day draft or establish a reliable order when more
than one correction is published on that date.

A mutable `current` file or symlink was rejected because it lets the same
study contract resolve to different bytes over time. That is convenient for
discovery and incompatible with reproducible revision work.

The catalog was selected because publication is explicit, ordering is data
rather than a filename guess, and studies can discover updates without
following them.

## Published files and catalog location

The producer writes a catalog named `dataset-catalog.yml` in the study's
logical datasets directory. Release filenames in the catalog are basenames
relative to that directory. They may not contain path separators.

The first release on a date uses a name such as
`cohort_20260921.sas7bdat`. A second, different release on the same date uses
`cohort_20260921_r2.sas7bdat`. The catalog's sequence number, not lexical
filename order, defines release order.

The catalog is data-system state and remains beside the datasets rather than
in the study's Git repository. `_study.yml` and `manifest.yaml` record the
study's selection and remain the version-controlled audit trail.

## Catalog format

Version 1 uses a named mapping of logical dataset IDs. Each dataset has an
ordered release sequence.

```yaml
format_version: 1
datasets:
  surgery_cohort:
    releases:
      - release_id: surgery_cohort-20260921-r1
        sequence: 1
        file: cohort_20260921.sas7bdat
        extract_date: '2026-09-21'
        revision: 1
        published_at: '2026-09-21T15:42:10-04:00'
        sha256: 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
        n_rows: 1250
        n_cols: 84
        status: published
        source: Epic extract query 4.2
```

Required release fields are `release_id`, `sequence`, `file`, `extract_date`,
`revision`, `published_at`, `sha256`, `n_rows`, `n_cols`, and `status`.
`source` is optional.

Within one logical dataset:

- `release_id` is unique and never reused;
- `sequence` is a unique, positive, increasing integer;
- `revision` starts at 1 for each extract date and increases for same-day
  corrections;
- `file` is unique across the entire catalog;
- `status` is `published` or `withdrawn`; and
- a withdrawn release also records a non-empty `withdrawal_reason` and may
  record a `replacement_release_id`.

Catalog readers reject duplicate IDs, sequences, or files; missing required
fields; unknown format versions; invalid dates or checksums; and release files
that escape the datasets directory.

## Publication lifecycle

The producer exposes one explicit publication operation,
`publish_dataset()`.

Publication follows this order:

1. Read and validate the mutable draft.
2. Derive the logical dataset ID and extract date.
3. Write the release to a temporary file in the published datasets directory.
4. Read the temporary release through the supported clinical-data reader and
   calculate its SHA-256, row count, and column count.
5. Acquire the catalog lock, re-read and validate the catalog, and derive the
   next sequence, revision, release ID, and final filename from that locked
   state.
6. Move the temporary file to its final dated filename.
7. Append the release and replace the catalog through an atomic rename.
8. Release the lock and return the published release record.

Drafts never appear in the catalog. If the final release filename already
exists with the same checksum, publication is idempotent. If it exists with
different bytes, publication stops and requires a new revision filename.

If the file move succeeds but the catalog update fails, the result is an
unregistered orphan. A retry with the same bytes completes publication; no
consumer treats the orphan as a release.

## Study contract

The default and each named dataset may carry a `release` block. For example:

```yaml
built: cohort_20260921.sas7bdat
release:
  dataset_id: surgery_cohort
  release_id: surgery_cohort-20260921-r1
```

Named datasets store the same block inside their existing
`additional_datasets` entry. The catalog path is fixed at
`dataset-catalog.yml` in the logical datasets directory, so individual study
contracts do not duplicate it.

`register_data()` keeps its current meaning: it attaches a dataset to a study.
It gains a way to select a published `release_id`. Registration verifies that
the catalog release, filename, checksum, and observed dataset metadata agree
before writing the study contract. Registration without release metadata
retains the current legacy behavior and does not enable update discovery.

## Discovery

`check_data_updates()` is the programmatic discovery API. For each
release-aware study dataset, it:

1. validates the pinned file against `manifest.yaml`;
2. reads and validates the catalog;
3. locates the pinned `release_id` under its `dataset_id`;
4. verifies that the pinned catalog checksum agrees with the manifest and the
   file on disk; and
5. reports every later published sequence, identifying the newest as the
   default candidate.

Withdrawn releases are not candidates. Intermediate published releases remain
in the result even when a later release exists.

`study_status()` adds one row per release-aware dataset. Its result is
`CURRENT`, `UPDATE AVAILABLE`, `UPDATE STATUS UNKNOWN`, or `FAIL`. An available
update is informational and does not make the overall study invalid.

`read_built()` continues to read only the filename in `_study.yml`. Once per
dataset per R session, it emits a message condition with class
`hvtiRutilities_update_available` when a newer release exists. Code can handle
the condition and promote it to an error when a pipeline requires the latest
release. A missing or unreachable catalog emits
`hvtiRutilities_update_status_unknown` but does not prevent a valid pinned
read.

## Review

`review_data_update()` accepts a logical study dataset and a candidate release
ID. It never accepts `"latest"` in place of an ID. The function verifies both
releases and returns a structured review containing:

- pinned and candidate release IDs, filenames, dates, revisions, and
  checksums;
- row- and column-count changes;
- added and dropped variables;
- type and variable-label changes;
- old and new study cohort counts when the dataset has an event/time contract;
  and
- the candidate's publisher provenance.

The review reuses `compare_datasets()` for its existing structural comparison.
It does not certify that the candidate is analytically or clinically correct.

## Adoption

`adopt_data_update()` requires an explicit candidate `release_id`. It performs
the review validations again so that a previously printed review cannot become
stale, then:

1. rejects a missing, withdrawn, checksum-invalid, or non-newer release;
2. reads the candidate and verifies column-name normalization constraints;
3. derives the new cohort counts from the candidate;
4. prepares an updated `_study.yml` that names the candidate file and release;
5. prepares an updated `manifest.yaml` entry for the candidate;
6. replaces the pinned dataset's manifest entry rather than retaining it as an
   active entry; and
7. replaces both study files through the existing recoverable pair operation.

The old release file is never removed or modified. Git history retains its old
study and manifest contracts. A checkout of that revision therefore continues
to identify and verify the old dated file.

Adoption returns the updated `study_status()` visibly. It does not commit the
changed contracts to Git.

## Withdrawn releases

Withdrawal changes catalog status but never changes or deletes release bytes.
A withdrawn candidate disappears from the candidate set. A study pinned to a
withdrawn release receives `FAIL` from `study_status()`. `read_built()` errors
with class `hvtiRutilities_withdrawn_release`, naming the reason and any
replacement.

Reproducing historical work with a withdrawn release requires an explicit
`allow_withdrawn = TRUE` argument to `read_built()`. That override affects only
the read; it does not change the contract or make the status pass.

## Failure behavior

- Different bytes at a published filename are a hard integrity failure.
- A missing or checksum-invalid candidate is a catalog failure and cannot be
  reviewed or adopted. The valid pinned release remains readable.
- An unavailable catalog produces `UPDATE STATUS UNKNOWN` and leaves pinned
  reads unchanged.
- An unknown catalog format fails discovery rather than guessing.
- Multiple releases with the same sequence or release ID fail discovery.
- An interrupted adoption restores both `_study.yml` and `manifest.yaml` to
  their pre-adoption state through the existing pair-replacement mechanism.
- No failure path rewrites or removes a published release.

## Compatibility and migration

Existing `_study.yml` files remain valid. A dataset without a `release` block
has no catalog identity, so status and reads behave as they do now.

A legacy study opts in by registering its current dated file as a published
release and attaching that release ID to its existing study dataset. A file
that has already been overwritten in place cannot be reconstructed from its
checksum or schema sidecar; migration requires a trusted copy of the intended
release.

## Test contract

Producer tests belong in the data-build package and cover:

- drafts remaining invisible;
- first publication and same-day revisions;
- idempotent publication of identical bytes;
- refusal to overwrite a published filename with different bytes;
- concurrent publication and catalog locking;
- recovery from an orphaned release file; and
- withdrawal without mutation or deletion.

Consumer tests belong in `hvtiRutilities` and cover:

- catalog and study-contract validation;
- initial registration against a published release;
- current, update-available, unknown, and failed discovery states;
- visibility of intermediate and same-day candidate releases;
- pinned reads never switching to a candidate;
- the once-per-session structured update condition;
- review output and cohort-count changes;
- rejection of implicit `latest` adoption;
- atomic adoption and rollback;
- manifest entry replacement;
- in-place mutation of pinned and candidate files;
- withdrawn pinned and candidate releases; and
- unchanged behavior for legacy studies.

Documentation must explain the publisher/study boundary, the revision naming
rule, the non-failing update notice, review limitations, explicit adoption,
and historical reproduction.

## Delivery order

The work spans two repositories and should be implemented in dependency order:

1. Freeze shared version-1 catalog fixtures and validation expectations.
2. Implement publication and catalog locking in the data-build package.
3. Implement catalog consumption, discovery, review, and adoption in
   `hvtiRutilities`.
4. Run an integration fixture through both packages before enabling update
   notices in real studies.

Each repository gets its own implementation plan, tests, documentation, and
pull request. The shared fixtures prevent either implementation from silently
drifting from this contract.
