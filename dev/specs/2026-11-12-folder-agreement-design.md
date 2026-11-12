# Folder agreement: flag, then confirm

**Status: designed, held.** Approved by John on 2026-11-12. The check needs
the Tracker's recorded folder, which only the StudyTracker Topic API can
supply; until it is live the check is inert. Companion to the
`study_migrate()` design (`2026-11-11-study-migrate-design.md`). The API side
is the TopicFolder and Relocation of the Topic API first look sent to the
Tracker maintainers on 2026-11-12 (vault: `Projects/StudyTracker Topic
API.md`); this design needs nothing new from them.

**Revised 2026-11-12** after the design review on PR #293 (head `b3b1c9f`):
the cache is now last-known only and each delivery channel revalidates
before it writes; a relocation releases nothing until the Tracker accepts it;
relocations are a barrier rather than relying on log order; and a relocation
has durable states, so a conflict or an interruption settles instead of
blocking the queue.

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

- It is the topic folder **the Tracker last recorded, as of the last Tracker
  read**, always a `/studies/...` path. It is a cache, not an authority: a
  copy keeps the value it had when it was copied, so a matching cache shows
  only that the folder agreed the last time anyone looked.
- **Only the qhsprograms layer writes it, from a Tracker read**:
  `study-setup` when it registers the folder, `study-setup --verify`, and the
  folder read before every outbox flush (below), all from
  `GET /topics/{stId}/folder`. It is also written when a Relocation is
  accepted (below). It is **never** written with a path the Tracker has not
  confirmed.
- **hvtiRutilities only reads it.** It never talks to the Tracker; the
  comparison is offline and instant.
- An absent or empty `tracker_path` means "not known": before the API, or a
  topic whose folder the Tracker has not recorded.

**Before the API** (John, 2026-11-12), `tracker_path` is left empty
everywhere. The legacy `Topics` data-path column is not used: it often names
a data folder or a stale path, and copying it would raise false alarms. The
check switches on at API cutover with no code change.

## The comparison

`.study_folder_agreement(root)` returns one of five states:

| State | When |
|---|---|
| `agrees` | the normalised folder equals the normalised `tracker_path`, and no relocation is unsettled |
| `unknown` | `tracker_path` is absent or empty |
| `disagrees` | both are known, they differ, and no relocation to this folder is unsettled |
| `relocating` | a Relocation to this folder is `pending` or `conflicted` (see below) |
| `exploration` | `.study_identity_state()` is `provisional`; explorations register nothing and are never compared |

**Normalising** both sides before comparing:

- map a desktop mount to the server root: `/Volumes/qhsstudies/...` to
  `/studies/...` (the one mapping in use; kept in one internal table so a
  second mount is a one-line addition);
- resolve symlinks (`normalizePath()`), then re-apply the mount mapping;
- drop a trailing `/`.

Comparison is exact after that: no case folding, since the LRI filesystem is
case-sensitive.

This comparison is offline, so it can only report **last known** agreement.
It is enough for `study_status()` and for the local warning. It is not enough
to release an external write, so each delivery channel revalidates first.

### Revalidating before an external write

Both channels refuse to deliver on the cache alone; each checks the authority
it is about to write to, at the moment it writes.

- **The Tracker channel (qhsprograms).** Before it posts any entry, the flush
  reads `GET /topics/{stId}/folder` and rewrites `tracker_path` from the
  answer, then applies the comparison. This is one cheap read per flush, not
  per entry.
  - Offline, or the sign-in has expired: nothing is posted, as today. The
    entries wait in the outbox; there is nothing to revalidate against and
    nothing to send.
  - `200`: `tracker_path` is the answer, and the comparison decides.
  - `404 folder_not_found` with an empty cache: `unknown`; entries post as
    today (the folder has not been registered yet).
  - `404 folder_not_found` with a non-empty cache: the API has no way to
    delete a folder record, so this is an anomaly. Nothing is posted, the
    cache is **not** cleared, and the flush reports it. Clearing the cache
    here would turn an unexplained answer into `unknown` and release a copy.
- **The Git channel (hvtiRutilities).** The checkpoint repository's `main`
  carries one more file, `FOLDER.yml`, `{ path, relocation_id }`: the folder
  the topic's history was last delivered from, with the accepted Relocation
  that set it (`relocation_id` is empty for the registration). `.cp_deliver()`
  already fetches the remote before pushing (`.cp_push()`); after that fetch
  it reads the remote's `FOLDER.yml`. If it names a folder other than this
  one, delivery is held with reason `folder mismatch`, whatever the cache
  says. Absent (before the API, or a remote that predates this design) means
  `unknown`, not a hold. The first delivery after `tracker_path` agrees
  writes `FOLDER.yml` if it is absent, and an accepted Relocation rewrites it
  (below).

So in the reviewer's case (folder A copied to B, B confirmed as the topic's
folder), A's cache still says A, but A's next flush reads B from the Tracker
and A's next push reads B from the remote's `FOLDER.yml`, and both hold.

**The guarantee, narrowed.** A stray copy cannot deliver to a channel that
already records the move. One window remains: after the Tracker accepts B's
Relocation and before B's next push writes `FOLDER.yml`, a push from A finds
the remote still naming A and goes through. B delivers `FOLDER.yml` in the
same delivery that settles the Relocation, so the window is the time B is
offline after confirming, and the stray commits it admits are A's own
snapshots, visible in the remote's history and tagged as A's. The Tracker
channel has no such window, because it reads the Tracker itself. This design
does not try to close the Git window: doing so would need the Git remote to
ask the Tracker, which it cannot.

## Where it shows

### `study_status()`

A new checklist line, `folder`, using the existing marks:

| State | Status | Mark | Detail |
|---|---|---|---|
| `agrees` | `OK` | `[x]` | matched the Tracker at its last read (dated from the last flush or `--verify`) |
| `unknown` | `PENDING` | `[~]` | not checked: the Tracker records no folder yet |
| `disagrees` | `MISSING` | `[ ]` | names both paths; "if the study moved here, run `study_relocate()`; if this is a copy, its checkpoints are held and never sent" |
| `relocating`, pending | `PENDING` | `[~]` | "move to this folder is waiting for the Tracker to accept it; checkpoints are held until then" |
| `relocating`, conflicted | `MISSING` | `[ ]` | names the path the Tracker records now; "run `study-setup --verify`, then `study_relocate()` if this folder is still the right one" |
| `exploration` | (no line) | | |

### Checkpoints: record locally, hold delivery

`study_checkpoint()`, `study_close()` and `study_reopen()` warn once when the
folder `disagrees` or is `relocating`, naming both paths, then **commit and
tag locally as usual**. Delivery is held: `.cp_deliver()` gains a reason in
its existing precedence chain, after `provisional` and `identity unverified`:

```r
} else if (.study_folder_agreement(root) %in% c("disagrees", "relocating")) {
  "folder mismatch"
```

so the entry stays `delivery: git: pending` with reason `folder mismatch`,
and the qhsprograms layer applies the same rule (after its own revalidating
read) when it posts outbox entries. Work is never blocked, and a copy's
events never reach the Tracker or the topic's remote. The same reason is set
after the fetch when the remote's `FOLDER.yml` names another folder.

A hold is not a stored state that needs releasing. `.cp_deliver()` computes
the reason afresh on every call, so a held entry is simply a pending one that
the comparison has not yet let through; it goes out on the first delivery
after the comparison says `agrees`.

`study_checkpoint_push()` refuses with the same message while the folder
disagrees or is relocating, as it already refuses an exploration.

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
3. **Returns the existing entry, writing nothing**, when a Relocation to this
   folder is already `pending`. A retry after an interruption therefore never
   queues a second UUID for the same move.
4. **Queues a Relocation** in the outbox: `relocation_id` (a new UUID),
   `from_path` = the cached `tracker_path`, `to_path` = this folder
   (normalised), `reason`, `occurred_at`, with
   `delivery: { st: pending, git: none }`. When a `conflicted` Relocation to
   this folder exists, this step also marks it `superseded`, with
   `superseded_by` naming the new one (both in one atomic log rewrite).

That is the whole of `study_relocate()`: **one atomic write, to the
outbox**. It does not touch `tracker_path`, and it releases nothing. The
folder is now `relocating`, and every checkpoint stays held until the
Tracker accepts the move.

Returns the Relocation entry, invisibly.

### Relocation states

A Relocation's state lives in its `delivery.st` field, under the log's
existing rule that entries are appended and only their delivery fields
change, so the audit stays append-only:

| `delivery.st` | Meaning | Next |
|---|---|---|
| `pending` | queued, not yet accepted | posted on the next flush |
| `delivered` | the Tracker accepted it (`201`, or `200` for a replay of the same ID) | `tracker_path` is `to_path`; holds lift |
| `conflicted` | the Tracker answered `409 stale_from_path` | not retried; waits for the analyst or for a refresh |
| `superseded` | settled without being accepted: replaced by a later Relocation (`superseded_by`), or the Tracker already records `to_path` | never posted again |

Only `pending` entries are ever posted. A `conflicted` or `superseded` entry
stays in the log as the record of what was attempted.

### Delivery order: relocations are a barrier

The outbox is not delivered in plain append order. A checkpoint made while
the folder disagreed is already in `.checkpoint/log.yml` before the
Relocation that will release it, so append order would send it first.
Instead:

- **The qhsprograms flush posts every `pending` Relocation first**, oldest
  first, before any other entry, wherever it sits in the log.
- A Relocation is **exempt** from the `folder mismatch` hold (it is the entry
  that resolves the mismatch; holding it would deadlock).
- **No other entry is posted or pushed while any Relocation is `pending` or
  `conflicted`.** This follows from the comparison already (the state is
  `relocating`), and the flush checks it directly as well, so the barrier
  does not depend on the cache being current.
- Other entries keep their log order among themselves, so a held
  checkpoint, then a closure, then a reopening still reach the Tracker in
  that order once the barrier lifts.

### Acceptance

When the post answers `201`, or `200` for a replay (the API's idempotency
rule: same ID, same body returns the stored record), the qhsprograms layer,
in this order:

1. sets the Relocation's `delivery.st` to `delivered`;
2. rewrites `tracker_path` to `to_path` (atomic rewrite of `_study.yml`).

The next `.cp_deliver()` sees `agrees`, commits `FOLDER.yml`
`{ path: to_path, relocation_id }` to the checkpoint repository and pushes
it ahead of the held snapshots in the same push. Then the held entries go to
the Tracker in log order.

**An ambiguous network outcome** (timeout, dropped connection, no response
read) leaves the entry `pending`. The next flush posts the same
`relocation_id` with the same body, and the API's idempotency rule makes
that safe: `201` if the first request never arrived, `200` if it did. A
`409 idempotency_conflict` cannot arise, because the entry's body never
changes after it is queued.

### Conflict: `409 stale_from_path`

Someone else moved the record first. The flush sets the Relocation to
`conflicted`, stops posting (the barrier holds everything else), reads
`GET /topics/{stId}/folder`, and rewrites `tracker_path` from it. Then one of
two things is true:

- **The Tracker already records this folder** (someone relocated it here, or
  registered it here, by another route). The conflicted entry is set to
  `superseded` with `superseded_reason: already recorded`. The folder now
  `agrees`, the barrier lifts, and the held entries go out. No second
  Relocation is posted, which is why step 1's "already agrees" refusal is
  right here and not a dead end.
- **The Tracker records a third folder.** The entry stays `conflicted`;
  `study_status()` names the recorded path. If this folder is still the
  right one, the analyst runs `study_relocate()` again: step 4 queues a new
  Relocation from the refreshed `tracker_path` and marks the conflicted one
  `superseded`. If the other folder is the right one, this folder is a copy
  and stays held.

Either way the conflicted entry is never posted again, so it cannot return
`409` forever.

### Interruptions

Every step writes one file atomically, and each boundary has a defined
recovery:

| Interrupted | State left | Recovery |
|---|---|---|
| before step 4's write | nothing | rerun `study_relocate()` |
| after step 4's write | a `pending` Relocation | rerun returns it (step 3); the next flush posts it |
| after the POST is sent, before its answer is recorded | `pending` | replay of the same ID; `200` returns the stored record |
| after `delivered`, before `tracker_path` is rewritten | `delivered`, stale cache | the next flush's revalidating read rewrites `tracker_path` from the Tracker; until then the comparison says `disagrees` and nothing goes out, which errs safe |
| after `tracker_path`, before `FOLDER.yml` is pushed | cache agrees, remote does not | the next `.cp_deliver()` writes and pushes `FOLDER.yml` (the absent-or-stale case), ahead of the held snapshots |
| after `409`, before the refresh | `conflicted`, stale cache | the next flush or `study-setup --verify` refreshes and applies the conflict rules above |

The lock in step 2 covers the hvtiRutilities writes; the qhsprograms flush
takes the same lock, so `study_relocate()` and a flush never interleave on
the log.

## A copy

A copy stays flagged, and its held checkpoints are never sent. There is no
command to declare a folder a copy; deleting the copy is the fix. If copies
turn out to be common and long-lived, a `study_detach()` that marks a folder
as a working copy can be added then.

## What the qhsprograms layer does

- Write `tracker_path` from `GET /topics/{stId}/folder` in `study-setup`
  (registration), `study-setup --verify` (refresh) and at the start of every
  outbox flush; leave it empty on `404 folder_not_found` when it was empty,
  and hold everything without clearing it when it was not.
- Post every `pending` Relocation to `POST /topics/{stId}/folder/relocations`
  before any other entry, and apply the acceptance, ambiguous-outcome and
  `409` rules above.
- Post nothing else while a Relocation is `pending` or `conflicted`, and
  honour the `folder mismatch` hold.
- Take `.checkpoint/lock` for the flush.

## Tests

All on temp studies; no network (the Tracker is mocked, and the Git remote is
a local bare repository).

- **Normalising**: `/Volumes/qhsstudies/x` and `/studies/x` agree; a symlink
  to the folder agrees; a trailing `/` agrees; a case difference disagrees.
- **Each state**: `agrees`, `unknown` (absent and empty key), `disagrees`,
  `relocating` (pending and conflicted), and `exploration` (never compared,
  no status line).
- **`study_status()`**: the line's mark and detail in each state.
- **Hold**: a checkpoint recorded while the folder disagrees is committed and
  tagged, warns once, and is held with reason `folder mismatch`;
  `study_checkpoint_push()` refuses.
- **The original folder after another copy relocates** (finding 1): copy A to
  B, relocate B and accept it, then in A (cache still says A) make a
  checkpoint. A's flush reads B from the mocked Tracker and posts nothing;
  A's push fetches B's `FOLDER.yml` and is held. A's `study_status()` still
  shows last-known agreement until a flush or `--verify` runs.
- **Revalidation answers**: offline posts nothing; `404` with an empty cache
  posts; `404` with a non-empty cache posts nothing and leaves the cache
  byte-identical.
- **No release before acceptance** (finding 2): after `study_relocate()`,
  `tracker_path` is unchanged and the folder is `relocating`; with the
  Tracker offline, and again with it answering `409`, neither a push nor a
  post happens.
- **Order** (finding 3): with an older held checkpoint, then a closure, then a
  reopening already in the log, `study_relocate()` and an accepting Tracker
  deliver, in the recorded call sequence: the Relocation, then
  `FOLDER.yml` in the push, then the checkpoint, closure and reopening in
  that order.
- **Ambiguous outcome**: the first post times out after the mock records it;
  the replay gets `200` and the entry is `delivered`, with one Relocation on
  the mock.
- **Conflict, both branches** (finding 4): `409` with the Tracker already
  recording this folder ends `superseded` and releases the holds with no
  second post; `409` with a third folder stays `conflicted`, and a second
  `study_relocate()` queues a new Relocation from the refreshed path, marks
  the first `superseded_by` it, and is accepted.
- **Interruptions**: one test per row of the interruption table, stopping
  after each write and rerunning, asserting one Relocation per move and the
  final log.
- **Refusals** (exploration, empty `tracker_path`, already agrees) leave every
  file byte-identical; a second `study_relocate()` with one pending returns
  it and leaves the log byte-identical.

## Out of scope

- Detecting a copy automatically (a second folder with the same ST): the
  Tracker records one folder, so a copy is simply a folder that disagrees.
- Closing the Git window between a Relocation's acceptance and the next
  push of `FOLDER.yml` (see "The guarantee, narrowed").
- Moving folders on disk. Nothing here moves anything.
- Shared dataset folders, which have no Tracker record in the MVP.
