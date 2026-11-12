# Folder agreement: flag, then confirm

**Status: designed, held.** Approved by John on 2026-11-12. The check needs
the Tracker's recorded folder, which only the StudyTracker Topic API can
supply; until it is live the check is inert. Companion to the
`study_migrate()` design (`2026-11-11-study-migrate-design.md`). The API side
is the TopicFolder and Relocation of the Topic API first look sent to the
Tracker maintainers on 2026-11-12 (vault: `Projects/StudyTracker Topic
API.md`); this design needs nothing new from them.

## The problem

The Tracker records one folder per topic (an ST number). Folders move, get
copied, and get opened through different mounts. When the folder a tool runs
in disagrees with the Tracker's record, either the study moved (the record is
stale) or this folder is a copy (it must not write to the record). The tools
cannot tell which, so they **flag the mismatch and let the analyst confirm a
move**. Nothing changes the record silently, so a stray copy cannot take over
a topic's record by being opened.

## The cached record

`_study.yml` gains one key:

```yaml
tracker_path: /studies/cardiac/congenital/chss/avsd/2023/virtual_twins
```

- It is the topic folder **the Tracker records**, always a `/studies/...`
  path.
- **Only the qhsprograms layer writes it, from a Tracker read**:
  `study-setup` when it registers the folder, `study-setup --verify` to
  refresh it (from `GET /topics/{stId}/folder`). `study_relocate()` (below)
  sets it when a move is confirmed.
- **hvtiRutilities only reads it.** It never talks to the Tracker; the
  comparison is offline and instant.
- An absent or empty `tracker_path` means "not known": before the API, or a
  topic whose folder the Tracker has not recorded.

**Before the API** (John, 2026-11-12), `tracker_path` is left empty
everywhere. The legacy `Topics` data-path column is not used: it often names
a data folder or a stale path, and copying it would raise false alarms. The
check switches on at API cutover with no code change.

## The comparison

`.study_folder_agreement(root)` returns one of four states:

| State | When |
|---|---|
| `agrees` | the normalised folder equals the normalised `tracker_path` |
| `unknown` | `tracker_path` is absent or empty |
| `disagrees` | both are known and they differ |
| `exploration` | `.study_identity_state()` is `provisional`; explorations register nothing and are never compared |

**Normalising** both sides before comparing:

- map a desktop mount to the server root: `/Volumes/qhsstudies/...` to
  `/studies/...` (the one mapping in use; kept in one internal table so a
  second mount is a one-line addition);
- resolve symlinks (`normalizePath()`), then re-apply the mount mapping;
- drop a trailing `/`.

Comparison is exact after that: no case folding, since the LRI filesystem is
case-sensitive.

## Where it shows

### `study_status()`

A new checklist line, `folder`, using the existing marks:

| State | Status | Mark | Detail |
|---|---|---|---|
| `agrees` | `OK` | `[x]` | matches the Tracker |
| `unknown` | `PENDING` | `[~]` | not checked: the Tracker records no folder yet |
| `disagrees` | `MISSING` | `[ ]` | names both paths; "if the study moved here, run `study_relocate()`; if this is a copy, its checkpoints are held and never sent" |
| `exploration` | (no line) | | |

### Checkpoints: record locally, hold delivery

`study_checkpoint()`, `study_close()` and `study_reopen()` warn once when the
folder `disagrees`, naming both paths, then **commit and tag locally as
usual**. Delivery is held: `.cp_deliver()` gains a reason in its existing
precedence chain, after `provisional` and `identity unverified`:

```r
} else if (identical(.study_folder_agreement(root), "disagrees")) {
  "folder mismatch"
```

so the entry stays `delivery: git: pending` with reason `folder mismatch`,
and the qhsprograms layer, which posts outbox entries to the Tracker, applies
the same rule. Work is never blocked, and a copy's events never reach the
Tracker or the topic's remote.

`study_checkpoint_push()` refuses with the same message while the folder
disagrees, as it already refuses an exploration.

Jobs, `read_built()` and other study functions do not check: they write
nothing to the Tracker.

## Confirming a move: `study_relocate()`

```r
study_relocate(reason = NULL, start = study_root())
```

1. **Refuses**, writing nothing, when the study is an exploration, when
   `tracker_path` is empty (nothing to relocate from: the folder is
   registered by `study-setup`, not here), or when the folder already
   `agrees`.
2. Takes the checkpoint lock (`.checkpoint/lock`).
3. **Queues a Relocation** in the outbox: `relocation_id` (a new UUID),
   `from_path` = the cached `tracker_path`, `to_path` = this folder
   (normalised), `reason`, `occurred_at`.
4. **Updates `tracker_path`** in `_study.yml` (atomic rewrite) to this
   folder.
5. **Releases the holds**: every entry held for `folder mismatch` goes back
   to pending, and delivery runs as usual. The outbox is delivered in order,
   so the Relocation reaches the Tracker before the checkpoints it unblocked.

Returns the Relocation entry, invisibly.

**When someone else moved the record first**, the API answers
`409 stale_from_path` to the Relocation. Delivery stops on that entry (later
entries wait behind it) and `study_status()` reports it. The fix is
`study-setup --verify`, which refreshes `tracker_path` from the Tracker, then
`study_relocate()` again if this folder is still the right one.

## A copy

A copy stays flagged, and its held checkpoints are never sent. There is no
command to declare a folder a copy; deleting the copy is the fix. If copies
turn out to be common and long-lived, a `study_detach()` that marks a folder
as a working copy can be added then.

## What the qhsprograms layer does

- Write `tracker_path` from `GET /topics/{stId}/folder` in `study-setup`
  (registration) and `study-setup --verify` (refresh); leave it empty on
  `404 folder_not_found`.
- Post the Relocation entry to `POST /topics/{stId}/folder/relocations`.
- Honour the `folder mismatch` hold when posting outbox entries.

## Tests

All on temp studies; no network.

- **Normalising**: `/Volumes/qhsstudies/x` and `/studies/x` agree; a symlink
  to the folder agrees; a trailing `/` agrees; a case difference disagrees.
- **Each state**: `agrees`, `unknown` (absent and empty key), `disagrees`,
  and `exploration` (never compared, no status line).
- **`study_status()`**: the line's mark and detail in each state.
- **Hold and release**: a checkpoint recorded while the folder disagrees is
  committed and tagged, warns once, and is held with reason
  `folder mismatch`; `study_checkpoint_push()` refuses; after
  `study_relocate()` the outbox holds the Relocation ahead of the released
  checkpoint, and `tracker_path` is the new folder.
- **Refusals** (exploration, empty `tracker_path`, already agrees) leave every
  file byte-identical.
- **Stale `from_path`**: a mocked `409` on the Relocation stops delivery at
  that entry and leaves the later ones pending.

## Out of scope

- Detecting a copy automatically (a second folder with the same ST): the
  Tracker records one folder, so a copy is simply a folder that disagrees.
- Moving folders on disk. Nothing here moves anything.
- Shared dataset folders, which have no Tracker record in the MVP.
