# `study_migrate()`: an exploration becomes a registered study

**Status: designed, held.** Approved by John on 2026-11-11. Implementation
waits until the StudyTracker Workspace API is up and running: until then the
Tracker's recorded folder for a study can only be read from the legacy
`Topics` data-path column, and the migration's one Tracker write
(`workspace_created`) has nowhere to go but the outbox.

Replaces `study_promote()` (shipped in 1.5.22). Builds on the exploratory-study
design in hvtiR, `dev/specs/2026-11-09-exploratory-study-design.md`.

## The rule

**An exploration registers nothing in the Study Tracker.** Not its folder, not
its checkpoints, not its existence. It is set up with
`study_setup(derived_from = <parent ST>)`, carries a `provisional_id`, and
everything it records stays local.

When an exploration turns into a real study, a person registers a **new**
study in the Tracker, which issues a new ST number. The exploration then
*migrates* to that number. "Promote", which replayed the exploration's held
checkpoints under the new number, described the wrong model and goes.

## Two cases, one function

The Tracker may already record a folder for the new study, or it may not.

| Tracker's folder for the new ST | What happens |
|---|---|
| none | **This folder becomes the study.** `study_migrate()` does it. |
| a different folder | Refused, naming that folder. The analyst copies the jobs they want into it **by hand**. The exploration is left as it is. |
| this folder | Refused: already migrated. |

Copying jobs is deliberately manual (John, 2026-11-11). A `jobs =` copy helper
can be added later if copying by hand proves error-prone; it is not built now.

## Interface

```r
study_migrate(identity, start = study_root())
```

- `identity`: a named list, the Tracker record for the new study. It must hold
  `study_tracker_id` and `study`; it may hold the other identity keys
  (`umbrella`, `owner`, `irb_number`, `cvir_no`, `study_creation_date`) and
  `path`, the folder the Tracker records for that study, or `NULL` for none.
- `start`: a directory in the exploration, found as `study_config()` finds it.
- Returns the names of the `_study.yml` keys that changed, invisibly.

**hvtiRutilities never reads the Tracker.** As with `study_update_identity()`,
the caller (`study-setup` in qhsprograms) reads the record and passes it in,
so the package stays offline and its tests need no network. Comparing
`identity$path` with this folder is the one place the package looks at what
the Tracker said, and it does so on the value it was handed.

## Refusals

Each leaves the folder byte-identical.

1. The study is not an exploration: `.study_identity_state()` is anything but
   `provisional` (registered, legacy, already migrated, or `NA`).
2. `identity$path` is a different folder. The message names it and says to
   copy the jobs into it by hand.
3. `identity$path` is this folder: already migrated.
4. `identity$study_tracker_id` equals `derived_from`: an exploration cannot
   migrate into its parent.
5. `identity$study_tracker_id` is not one positive whole number
   (`.study_whole_id()`), or `identity` is missing `study`, or names an
   unknown field.
6. The checkpoint repository is mid-write or not on `main` (the existing
   guards).
7. `.checkpoint/exploration/` exists with no migration marker (see *Resuming*
   below): an earlier migration finished, or someone made it by hand.
8. The exploration's checkpoint remote (`checkpoint: remote:` in
   `_study.yml`) already has a `main`. Explorations never push, so a remote
   with history belongs to something else; migrating would fetch it into the
   new repository (`.cp_repo_init()` fetches an existing remote's `main` and
   tags). Probed before any write.

Path comparison is on normalised absolute paths. The Tracker stores LRI paths
rooted at `/studies`; a study opened through a desktop mount
(`/Volumes/qhsstudies/...`) is compared after mapping that prefix, so a Mac
session does not read its own folder as "a different folder".

## What it writes, in order

Revised 2026-11-11 after Codex review of #290: the first draft renamed
`.checkpoint/` to `.checkpoint-exploration/`, which (a) left the archive
inside snapshot scope, because `.cp_deny_rule()` excludes only a top-level
`.checkpoint` directory, and (b) moved the lock, `.checkpoint/lock`, out from
under its holder, so a second process could take a fresh lock mid-migration.

**The whole migration runs under the existing checkpoint lock**,
`.checkpoint/lock`, which never moves. The exploration's record is set aside
*inside* `.checkpoint/`, so the existing tooling rule keeps it out of every
snapshot, whatever `include` patterns say. The active code reads only fixed
paths (`.checkpoint/repo`, `log.yml`, `kinds.yml`, `lock`), so nothing reads
`.checkpoint/exploration/`.

0. **Take the lock** and write the marker `.checkpoint/migrating.yml`
   (`provisional_id`, the new `study_tracker_id`, the target identity). From
   here on, every other checkpoint operation (`study_checkpoint()`,
   `study_checkpoint_push()`, the automatic triggers) refuses while the marker
   exists and says to rerun `study_migrate()`.
1. **Set the exploration's record aside.** Move `.checkpoint/repo` and
   `.checkpoint/log.yml` (the outbox) into `.checkpoint/exploration/`. Kept
   locally, never pushed, never delivered: no checkpoint from the
   exploration's era reaches the Tracker or a remote. `kinds.yml` stays.
2. **Rewrite `_study.yml`**, whole and atomically, as `register_data()` does:
   - set `study_tracker_id` and the identity keys from `identity`;
   - add `migrated_from: <provisional_id>`;
   - drop `provisional_id`;
   - drop `checkpoint: remote:` (the exploration's remote is not the
     topic's; the topic's repository is assigned by `study-setup` after
     migration);
   - keep `derived_from` and `workspace_id`;
   - set `identity_source: tracker` and `identity_verified: true`, because the
     number came from a Tracker read.
3. **Start a fresh checkpoint repository** (no remote, so nothing is fetched)
   and record `workspace_created` with
   `attributes: {migrated_from, derived_from}`.
4. **Remove the marker** and release the lock.

`.study_identity_state()` gains a `migrated` state (a `migrated_from` key and
a `study_tracker_id`), which behaves as `registered` everywhere except that
`study_migrate()` refuses it.

### Resuming

Any interruption (an error, a killed session, a failed rename or manifest
write) leaves the marker. **The recovery is always to rerun `study_migrate()`
with the same identity**: it takes the lock, sees the marker and resumes at
the first step not yet done. Each step is detected from the folder, not from
a step counter:

| Step | Done when |
|---|---|
| 1 | `.checkpoint/exploration/` holds the repository and outbox that existed, and `.checkpoint/repo` and `log.yml` are absent (a partial move finishes the rest) |
| 2 | `_study.yml` carries the marker's `study_tracker_id` and `migrated_from` |
| 3 | the new repository has a `workspace_created` tag |

A rerun with a **different** identity while the marker exists is refused,
naming the one in the marker. Because step 3 is only ever done by
`study_migrate()`, the lineage attributes are recorded exactly once; the
earlier `study_checkpoint("workspace_created")` recovery, which passed no
attributes, is dropped. Neither outbox is lost or delivered on any path: the
old one only ever moves into `exploration/`, and the new one starts empty.

## What goes

- `study_promote()`, its tests and its Rd page.
- The `study_promoted` row in `inst/checkpoint-kinds.yml`.
- The `study_promoted` guard added to `study_checkpoint()` in #287.
- Every pointer to promote:
  - in this package: `study_update_identity()` (its refusal now names
    `study_migrate()`), `study_checkpoint_push()`, `study_checkpoint()`, the
    vignettes, the README and `_pkgdown.yml`;
  - in hvtiR: the "Start here" section *An exploration of a registered study*;
  - in hvtiRtemplates: the exploration pointer in `vignettes/new-study.qmd`.

`study_promote()` shipped in 1.5.22 and is removed rather than deprecated:
nothing can have been promoted against a live Tracker, because there is none
yet. **Removing an export is the maintainer's version call** (patch or minor),
made when this is built.

## For the StudyTracker maintainers (Tore Klock, Patrick Vargo)

Their first look is the MVP note, `Projects/StudyTracker Workspace API - MVP
Spec.md` in the vault, which already carries what this needs: an ST is a
**Topic**, its folder record is a **TopicFolder**, and the `workspace_created`
checkpoint carries `attributes.migrated_from` (the exploration's provisional
ID) and `attributes.derived_from` (the parent ST). **No new checkpoint kind or
endpoint is needed.**

- The folder is registered at migration (`POST /topics/{stId}/folder`), from
  the exploration's folder. An exploration never registers one.
- `GET /topics/{stId}/folder` is the read `study-setup` uses to fill
  `identity$path` (`404 folder_not_found` means none).
- A `derived_from` link between topics is deferred with the other links.

Still open: one rename settling the `_study.yml` keys (`study_tracker_id`,
`workspace_id` against the API's `folder_id`, `identity_source`,
`identity_verified`), and whether `workspace_created` is renamed with it.

## Tests

All on temp studies; no network except a local bare repository standing in
for a remote.

- Each refusal (1 to 8) leaves every file byte-identical.
- Happy path: `.checkpoint/exploration/` holds the old repository and
  outbox, and the **preserved** old outbox still carries the provisional ID,
  as it should; the **new** outbox carries none. The new repository holds
  exactly one entry, `workspace_created`, with both attributes; `_study.yml`
  has the expected keys, no `provisional_id` and no `checkpoint: remote:`.
- **Snapshot scope:** plant `.checkpoint/exploration/repo/30_analyses/legacy.R`
  and `.checkpoint/exploration/log.yml`; the first post-migration checkpoint's
  git tree contains neither, with the default selector and with
  `include = "*.yml"`, and a push to a bare remote carries neither.
- **The lock holds throughout:** a competing `study_checkpoint()` started at
  the step 1 and step 2 boundaries (mocked pauses) is refused, and the
  migration's own lock is never reported lost.
- **Resume from every interruption:** fail after step 0, during and after step
  1 (a partial move), after step 2, and during step 3; each rerun with the
  same identity completes, records `workspace_created` once with both
  attributes, and delivers nothing from the old outbox. A rerun with a
  different identity is refused.
- Refusal 8: a remote with a `main` is refused before any write; an empty
  remote is dropped from `_study.yml` and nothing is fetched.
- An exploration with no checkpoint repository yet migrates and gets one.
- A `/Volumes/qhsstudies/...` start compared with a `/studies/...`
  `identity$path` for the same folder reads as "this folder".

## Out of scope

- **Folder agreement for every study** (John, 2026-11-11): when a study's
  folder disagrees with the Tracker, because it moved or was never recorded,
  flag it and correct it. This needs its own design, and it changes the API
  spec, which today leaves drift to reporting tools (§1, §3.2).
- The hvtiR wrapper for `study_migrate()`.
- The qhsprograms `study-setup` command that reads the Tracker and calls this.
