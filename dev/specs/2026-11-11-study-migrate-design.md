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

Path comparison is on normalised absolute paths. The Tracker stores LRI paths
rooted at `/studies`; a study opened through a desktop mount
(`/Volumes/qhsstudies/...`) is compared after mapping that prefix, so a Mac
session does not read its own folder as "a different folder".

## What it writes, in order

1. **Set the exploration's record aside.** Rename `.checkpoint/` to
   `.checkpoint-exploration/`. It is kept locally, never pushed and never
   delivered; the outbox entries go with it, so no checkpoint from the
   exploration's era ever reaches the Tracker or the study's remote. A
   `.checkpoint-exploration/` that already exists is refused before anything
   is written.
2. **Rewrite `_study.yml`**, whole and atomically, as `register_data()` does:
   - set `study_tracker_id` and the identity keys from `identity`;
   - add `migrated_from: <provisional_id>`;
   - drop `provisional_id`;
   - keep `derived_from` and `workspace_id`;
   - set `identity_source: tracker` and `identity_verified: true`, because the
     number came from a Tracker read.
3. **Start a fresh checkpoint repository** and record a `workspace_created`
   checkpoint with `attributes: {migrated_from, derived_from}`. Its remote,
   when `_study.yml` names one, sees only post-migration history.

`.study_identity_state()` gains a `migrated` state (a `migrated_from` key and
a `study_tracker_id`), which behaves as `registered` everywhere except that
`study_migrate()` refuses it.

**A failure in step 3** leaves steps 1 and 2 in place, and a rerun is refused
because the study is no longer an exploration. The recovery is
`study_checkpoint("workspace_created")` by hand. The error says so.
(Unverified at design time: confirm that `study_checkpoint()` creates the
repository when none exists, or have the recovery say how.)

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

Additions to the Workspace API spec (`Projects/StudyTracker Workspace API -
Spec.md` in the vault). **No new checkpoint kind is needed.**

1. **`workspace_created` carries `attributes.migrated_from`** (the
   exploration's provisional ID) and `attributes.derived_from` (the parent ST)
   when the study came from an exploration. Stored uninterpreted, as §3.3
   already says.
2. **An optional `derived_from` StudyLink kind** (§3.5), from the new study to
   its parent, posted at migration. Alternatively `continues` covers it; the
   maintainers choose.
3. **The workspace is registered at migration**, with the new `st_id`, from
   the exploration's folder. An exploration never calls `POST /workspaces`,
   so §3.1's `invalid_workspace` guard needs no exception.
4. **A read of the study's recorded folder.** `GET /studies/{stId}/workspaces`
   (§7) already returns it; `study-setup` uses it to fill `identity$path`.

Carried over, still open from 2026-09-25: an `adhoc` kind; one rename settling
the `_study.yml` keys (`st_id` vs `study_tracker_id`, `workspace_id`,
`identity_source`, `identity_verified`); an optional `git_commit` on Closure;
open question 2 (the `Tasks.status` values).

## Tests

All on temp studies; no network.

- Each refusal (1 to 6, plus an existing `.checkpoint-exploration/`) leaves
  every file byte-identical.
- Happy path: `.checkpoint-exploration/` holds the old repository and outbox;
  the new repository holds exactly one entry, `workspace_created`, with both
  attributes; no outbox entry anywhere carries the provisional ID;
  `_study.yml` has the expected keys and no `provisional_id`.
- An exploration with no checkpoint repository yet migrates and gets one.
- Step 3 fails (mock `.cp_record`): `_study.yml` is migrated, a rerun is
  refused, and `study_checkpoint("workspace_created")` recovers.
- A `/Volumes/qhsstudies/...` start compared with a `/studies/...`
  `identity$path` for the same folder reads as "this folder".

## Out of scope

- **Folder agreement for every study** (John, 2026-11-11): when a study's
  folder disagrees with the Tracker, because it moved or was never recorded,
  flag it and correct it. This needs its own design, and it changes the API
  spec, which today leaves drift to reporting tools (§1, §3.2).
- The hvtiR wrapper for `study_migrate()`.
- The qhsprograms `study-setup` command that reads the Tracker and calls this.
