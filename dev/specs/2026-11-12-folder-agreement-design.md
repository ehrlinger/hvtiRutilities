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
blocking the queue. **Revised again** after the re-review at `0d1de3e`: the
Tracker read-then-write window is stated (a read before every post, and a
folder precondition raised as an open API question), and the remote's
`FOLDER.yml` moves by one defined compare-and-set transition.

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

- **The Tracker channel (qhsprograms).** Before **each** post, the flush
  reads `GET /topics/{stId}/folder`, rewrites `tracker_path` from the answer,
  and applies the comparison. A read per entry rather than per flush keeps
  the window below to one request, not a whole batch; flushes are a handful
  of entries, so the cost is small.
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
  says, **except for the one authorised transition in "Moving the Git
  record"** below. Absent (before the API, or a remote that predates this
  design) means `unknown`, not a hold.

So in the reviewer's case (folder A copied to B, B confirmed as the topic's
folder), A's cache still says A, but A's next flush reads B from the Tracker
and A's next push reads B from the remote's `FOLDER.yml`, and both hold.

**The guarantee, narrowed.** A stray copy cannot deliver to a channel that
already recorded the move before the copy checked it. Two windows remain,
one per channel, and this design states them rather than closing them:

- **Tracker: read, then write.** The folder read and the post are two
  requests, and `POST /topics/{stId}/checkpoints` (and the closure and
  reopening posts) take no folder precondition. If B's Relocation is
  accepted between A's read and A's post, the Tracker records A's event
  after the move. The window is one request's round trip, because the read
  is repeated before every post. The consequence: one stray event on the
  topic, with document paths relative to a folder that is no longer the
  record, and a `git_commit` that is A's. The next read before A's next post
  sees B and holds the rest. Closing this window needs the server to check a
  folder precondition atomically with each write (for example an
  `expected_folder` field answered by `409 folder_moved`). That is a change
  to the Topic API and is left as an open question for the Tracker
  maintainers, not assumed here.
- **Git: acceptance, then push.** After the Tracker accepts B's Relocation
  and before B's push moves `FOLDER.yml`, a push from A finds the remote
  still naming A and goes through. The window is the time B is offline after
  confirming. The stray commits it admits are A's own snapshots, visible in
  the remote's history and tagged as A's. Closing it would need the Git
  remote to ask the Tracker, which it cannot.

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
   `delivery: { st: pending, git: pending }`. Its `git` field tracks only
   whether it has moved the remote's `FOLDER.yml` (see "Moving the Git
   record"); a Relocation is never a snapshot. When a `conflicted` Relocation to
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

Then the flush runs Git delivery, which moves the remote's `FOLDER.yml` by
the transition below, ahead of the held snapshots in the same push. Then the
held entries go to the Tracker in log order.

### Moving the Git record

The remote's `FOLDER.yml` changes in exactly two ways, and only inside a Git
delivery that the qhsprograms flush starts immediately after a folder read.
The flush passes that read's answer to `.cp_deliver()` (an internal argument,
`tracker_confirmed`); a delivery started any other way, such as
`study_checkpoint()` or `study_checkpoint_push()` on its own, never moves the
record and holds with `folder mismatch` while the remote names another
folder.

**Registration.** The remote has no `FOLDER.yml` and `tracker_confirmed` is
this folder: write `{ path: this folder, relocation_id: null }`.

**Relocation.** Every condition holds, checked after the fetch:

1. the log has a Relocation `R` with `to_path` equal to this folder, whose
   `delivery.st` is `delivered`, or `superseded` with
   `superseded_reason: already recorded`, and whose `delivery.git` is
   `pending`;
2. `tracker_confirmed` equals `R.to_path`;
3. the remote's `FOLDER.yml` names `R.from_path` (the record `R` moved away
   from).

Then delivery commits `FOLDER.yml` `{ path: R.to_path, relocation_id:
R.relocation_id }` on top of the fetched `main`, puts the held snapshots
after it, and pushes `main` as it does today, without force. Git refuses a
push that is not a fast-forward, so if the remote moved between the fetch
and the push, the push is rejected, nothing is written, and the next
delivery fetches and checks again. That rejection is the compare-and-set: a
stale copy cannot overwrite a newer record, because a newer record means a
different `FOLDER.yml` than the one its condition 3 matched.

`R.delivery.git` becomes `delivered` once the push succeeds, so each
Relocation moves the Git record at most once.

What the fetched remote can say, and what happens:

| Remote `FOLDER.yml` | Tracker read | Result |
|---|---|---|
| this folder | this folder | nothing to write; `R.delivery.git` is `delivered`; held snapshots go out |
| `R.from_path` | `R.to_path` | write it, as above |
| `R.from_path` | another folder | hold; `R.delivery.git` becomes `superseded` (the Tracker has moved on, so `R` may never move the Git record) |
| a third folder | `R.to_path` | hold, and report both: the remote and the Tracker disagree, so the remote was moved by a copy inside the Git window. Repair is by hand; this design does not guess which to trust |
| a third folder | that folder | hold; this folder is now a copy; `R.delivery.git` becomes `superseded` |

**The already-recorded branch.** When a `409` finds the Tracker already
recording this folder, `R` is `superseded` on the Tracker side but the
Tracker *did* confirm the move to `R.to_path`, so condition 1 accepts it and
`R` moves the Git record exactly as a delivered one would. If some other
Relocation in another folder's log already moved the remote to this folder,
the first row applies and nothing is written.

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
| after `tracker_path`, before the `FOLDER.yml` commit | cache agrees, remote does not | Git delivery holds (the remote names `R.from_path`); the next flush reads the Tracker and makes the transition |
| after the local `FOLDER.yml` commit, before the push | an unpushed commit | the commit is dropped; the next transition starts again from a fresh fetch, so it never replays onto a remote that has moved |
| push sent, answer lost | remote may or may not hold it | the next fetch shows which: this folder (first row, mark `delivered`) or `R.from_path` (write again) |
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
  (registration), `study-setup --verify` (refresh) and before every post in
  an outbox flush; leave it empty on `404 folder_not_found` when it was
  empty, and hold everything without clearing it when it was not.
- Start Git delivery with `tracker_confirmed` set to the folder read's
  answer, so the remote's `FOLDER.yml` can move only right after a Tracker
  read.
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
- **Read-then-write race** (re-review finding 1): the mock accepts B's
  Relocation between A's folder read and A's first post; the test asserts
  the documented window (exactly that one post lands) and that A's next read
  holds every later entry.
- **Moving the Git record** (re-review finding 4), on a local bare remote:
  one test per row of the remote-state table, recording the actual fetch,
  compare and push sequence; a remote advanced between fetch and push
  (planted by a second clone) rejects the push and leaves `FOLDER.yml`
  unchanged; the already-recorded branch moves the record with a superseded
  `R`; a delivery without `tracker_confirmed` never moves it.
- **Interruptions**: one test per row of the interruption table, stopping
  after each write and rerunning, asserting one Relocation per move, one
  `FOLDER.yml` change per move and the final log.
- **Refusals** (exploration, empty `tracker_path`, already agrees) leave every
  file byte-identical; a second `study_relocate()` with one pending returns
  it and leaves the log byte-identical.

## Out of scope

- Detecting a copy automatically (a second folder with the same ST): the
  Tracker records one folder, so a copy is simply a folder that disagrees.
- Closing either window in "The guarantee, narrowed". The Tracker one needs
  a folder precondition on the write endpoints, an open question for the
  Tracker maintainers; the Git one needs the remote to ask the Tracker.
- Moving folders on disk. Nothing here moves anything.
- Shared dataset folders, which have no Tracker record in the MVP.
