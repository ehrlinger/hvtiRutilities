# Closure state across copies of a study

**Status:** approved 2026-10-01 — all three decisions in section 7 taken as proposed.
**Resolves:** open item 9 of `2026-09-24-study-checkpoint-design.md` ([#153](https://github.com/ehrlinger/hvtiRutilities/issues/153)).
**Changes:** section 6.4 of that spec, `.cp_is_closed()`, and the guards in
`study_close()`, `study_reopen()` and `study_checkpoint()`.

## 1. The problem

`.cp_is_closed()` counts the `closed-*` and `reopened-*` tags in
`.checkpoint/repo`'s `refs/tags`. Delivery fetches the remote's tags into
`refs/remote-tags`, and those are not counted. So:

1. A copy that already has a `.checkpoint/repo` does not see a closure pushed
   from another copy. It can close the study a second time, and it refuses to
   reopen a study the remote says is closed.
2. A first use while offline creates an empty repository, and the guards see
   no history at all until a fresh clone.

A fresh copy that can reach the remote is already covered, because
`.cp_repo_init()` clones remote tags into `refs/tags` before the guards run.

## 2. Counting remote tags is not enough on its own

The obvious fix is to add the remote tags to the count. It fails on the case
this item exists for. Section 6.4 reads state from counts because, within one
copy, closing needs an open study and reopening needs a closed one, so the
two families alternate. **Across copies they no longer alternate.** Copy A
closes and pushes. Copy B, behind and offline, closes too. Delivery replays
B's closure onto A's and renumbers it, and the remote now holds two closures
and no reopening. One `study_reopen()` leaves the count at 2 to 1, and the
study reads as closed after it was reopened.

Counting by tag name has a second gap. Delivery renames a local tag when it
collides with a remote one, by deleting it and creating it again
(`.cp_retag()`). A crash between those two steps, or an entry still waiting
for its retag, leaves one commit known under two names, one local and one
remote. A count by name sees two closures where there is one.

## 3. Proposal

### 3.1 State is the latest event on `main`, not a count

Use the API spec's own definition: **the study is closed when its latest
`closed-*` tag has no `reopened-*` tag after it.** Section 6.4 replaced "latest"
with counts so that nothing depended on tag timestamps, which can tie. Here,
"latest" means **position on the first-parent history of `main`**, not
time, and that cannot tie in a way that matters:

- Collect the `closed-*` and `reopened-*` tags from both `refs/tags` and
  `refs/remote-tags`, and resolve each to its commit. Drop duplicates by
  `(family, commit)`. This absorbs the renamed-tag gap in section 2 and the
  case where two copies each reopened the same closure.
- Order the events by the position of their commit in
  `git rev-list --first-parent HEAD`.
- Two events on the same commit can only be a closure followed by a
  reopening. A closure always snapshots, so it gets a new commit and can
  never share one with an earlier reopening. A reopening only tags `HEAD`, and
  straight after a close that is the closure's own commit. So order a
  same-commit `reopened` after its `closed`.
- Closed when the last event is a closure.

In the concurrent-closure case above this reads closed after both closures,
and open after the one reopening, which is the right answer.

### 3.2 Sync before the guard, so `main` contains every tag

The ordering needs every tagged commit on `HEAD`'s history. Pushed tags only
ever sit on the remote's `main` (the not-on-main backstop guarantees this),
so once local `main` contains `origin/main`, every tag is on it.

So, when the remote is reachable, the three guards run **after** a sync,
`.cp_sync(root, study)`, which has two cases:

- **Entries pending delivery:** call the existing `.cp_deliver(root, study)`.
  It already fetches `main` and tags, replays unpushed snapshots on top,
  retargets and persists their entries, and pushes. It runs at the end of
  each of these functions anyway, so running it first delivers nothing new.
  If the push half fails, the fetch and replay have still happened, which is
  all the guard needs.
- **Nothing pending:** `.cp_deliver()` returns before fetching in this case,
  and this is the usual state of a stale copy, so it cannot be relied on
  here. Instead, probe the remote, fetch `main` and tags into
  `refs/remotes/origin/main` and `refs/remote-tags` with the same refspecs
  `.cp_push()` uses, and fast-forward `HEAD` to `origin/main` **only when
  `HEAD` is its ancestor**. With nothing pending there is no entry to
  retarget, so a fast-forward cannot leave the log naming a stale commit. A
  `HEAD` that has diverged with nothing pending should not happen. If it
  does, leave it alone and fall back to section 3.3.

This also fixes a quieter bug in `study_reopen()`. Today a copy that is
behind tags its own stale `HEAD`, so the `reopened-*` tag lands on an older
commit than the closure it reopens. After the sync, `HEAD` is the remote's
latest commit.

### 3.3 Offline, and other cases with no sync

No remote, an unverified identity, or an unreachable remote means
`.cp_deliver()` does not fetch. The guard then:

- orders the local tags, plus any cached `refs/remote-tags` whose commits are
  on `HEAD`'s history, by the rule in 3.1;
- ignores cached remote tags whose commits are not on `HEAD`. They cannot be
  placed without a sync;
- **says so**: a one-line `message()` that closure state reflects this copy
  only, because the remote could not be reached. It does not stop.

Remote tags are never moved or deleted (section 6.1), so a cache that is
behind can only show less history than the remote, never history that is
wrong. The fallback can miss a closure, but it cannot make one up.

`study_status()` never syncs, because a status read must not touch the network
or push. It uses the 3.3 rule as it stands and labels the closure row "as of
the last fetch" when a remote is configured.

## 4. What does not change

- Tag names, numbering and the renumbering rules in section 6.1.
- `study_checkpoint()` on a closed study still warns and records. It now sees
  a closure made from another copy.
- No new state file. State is still derived from tags alone.

## 5. Tests (no network, `file://` bare remotes as in `test-checkpoint_deliver.R`)

1. Copy A closes and pushes. Copy B, which has an existing
   `.checkpoint/repo` from before the close, refuses `study_close()` and can
   `study_reopen()`. B's `reopened-*` tag lands on A's closure commit.
2. A and B both close while B is offline. After B delivers, the study reads
   closed. After one `study_reopen()` it reads open. (Under counts it would
   read closed. This is the test that justifies 3.1.)
3. A commit known under two names, one local and one remote, counts as one
   closure.
4. Offline: B with a cached remote closure not on its `HEAD` keeps today's
   answer and prints the "this copy only" message.
5. `study_status()` makes no network call. Assert it with an unreachable
   remote URL and no delay.

## 6. Alternatives considered

- **Count across local and remote, by commit.** This is the issue's
  candidate. It is simpler, but it fails test 2, as section 2 shows.
- **Fetch remote tags into `refs/tags`.** `.cp_repo_init()` does this on a
  fresh clone. On an existing clone it collides with local tags that have not
  been pushed or renumbered yet.
- **A `.cp_sync()` that always fetches and replays itself, and never pushes.**
  This would duplicate the replay-and-retarget half of `.cp_push()`, which
  [#152](https://github.com/ehrlinger/hvtiRutilities/issues/152) is also
  changing. The two-case `.cp_sync()` in 3.2 adds only a fetch and a
  fast-forward, and reuses `.cp_deliver()` for everything that touches entries.

## 7. Decisions for the maintainer

1. Approve **latest-on-`main`** (3.1) over counts. This changes the wording of
   section 6.4.
2. Approve **syncing before the guards** (3.2). The arguments are still
   checked first. But when older entries are pending, `study_close()` and the
   other two push them before deciding whether to refuse. A refused close can
   therefore still have delivered an earlier checkpoint, and may warn if that
   push fails.
3. Offline is **message, not stop** (3.3).
