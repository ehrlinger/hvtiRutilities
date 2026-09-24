# Study checkpoints and closure to CORR_STUDIES: design

- **Date:** 2026-09-24
- **Status:** design approved in session; awaiting written-spec review
- **Scope:** `study_checkpoint()`, `study_close()` and `study_reopen()` in
  hvtiRutilities (core) and the `study-setup`, `study-checkpoint`,
  `study-close` and `study-reopen` commands in the `qhsprograms` ADO repo (institution layer)
- **Companion spec:** `Projects/StudyTracker Workspace API - Spec.md` in the
  Obsidian vault (confirmed 2026-09-22). This design supplies the `git_commit`
  field of that spec's Checkpoint record, follows its Closure and Reopening
  rules (§3.4), and shares its checkpoint vocabulary and outbox. Where the two disagree, the API spec wins on anything the ST
  server sees; this spec wins on what goes into git.

## 1. Goal

At each checkpoint in a study's life (an abstract submitted, a manuscript
submitted, a revision), commit the study's **source code, identity,
reproducibility files and submitted documents** to a per-study repository in
the `CORR_STUDIES` Azure DevOps project, and tag the commit with the event.
When a study closes (published, not published, superseded, abandoned), take
a final snapshot and tag it with the outcome, so the state that stands behind
the outcome is frozen. Users do not need to understand git: they name the
event or the outcome, and the tooling does the rest.

**Non-goals.** Data, results and PHI never enter git. No commits between
checkpoints are expected or supported by the tooling. No branching, no pull
requests, no review step.

## 2. Decisions and their reasons

| # | Decision | Reason |
|---|---|---|
| D1 | **Snapshot export**, not git in the study root | A `.git` whose working tree is the study invites any tool (RStudio Git pane, VS Code, `git add .`) to stage the data next to the code. A separate clone that holds only allow-listed files cannot commit what is not there. (The share itself is not the problem: the server reaches ADO directly.) |
| D2 | **Straight to `main`, annotated tag per checkpoint** | A snapshot records what already happened; there is nothing for a pull request to decide. History stays linear because the study only moves forward. |
| D3 | **Append-only `main`** | ADO: no minimum-reviewer branch policy on these repos (it would block the push); deny force push and branch deletion through repository security. Tamper evidence without PR ceremony. |
| D4 | **One repo per study** | Per-study access, clean tags, one place for `study-setup --recover` to look. |
| D5 | **Users push as themselves** on the LRI server | Git Credential Manager with Entra ID holds each user's token; the commit author is the analyst. No PATs (standard since the 2026-05-19 incident). |
| D6 | **Repo created at `study-setup`**, including `--adopt` | Every study with a `_study.yml` has a repo, so recovery is reliable. The first commit carries `_study.yml` and the scaffolding, tagged `workspace_created`. |
| D7 | **Core in hvtiRutilities, institution specifics in `qhsprograms`** | The public package stays institution-neutral and testable against a local bare repo; ADO REST calls, the CCF URL and ST delivery stay in the ADO repo. |
| D8 | **Allow-list plus a hard deny that no configuration can override** | Per-study `include:` patterns for unusual script types, without letting any YAML admit data. |
| D9 | **`50_documents/` admitted, folder-scoped** | Manuscripts belong in the checkpoint: the tag then binds the claim to the code, data hashes and package versions behind it. |
| D10 | **Commit locally first, deliver second** | An unreachable ADO or ST never loses a checkpoint. |
| D11 | **Vocabulary = the ST Workspace API's `lk_checkpoint_kinds`** | Already designed, event-shaped (distinguishes `manuscript_submitted` from `manuscript_accepted`), maps to ST task status, extensible by ST administrators, supports retirement. |
| D12 | **Closing takes a final snapshot and a closure tag; the repo stays writable** | Code edited after the last checkpoint is still captured, and the closure tag is the study's "release". Locking the repo read-only would make every reopening an admin round-trip. |

## 3. Architecture

| Layer | Lives in | Knows about | Never knows about |
|---|---|---|---|
| **Core** | hvtiRutilities (public) | selection rules, `.checkpoint/` repo, commit and tag, `CHECKPOINT.yml`, the outbox log, push to any git URL, the base vocabulary | ADO, CCF, ST |
| **Institution** | `qhsprograms` (ADO) | `CORR_STUDIES` URL and repo naming, repo creation through the ADO REST API, ST delivery, the live vocabulary | selection internals |

The two layers share exactly two things:

1. **The remote URL**, in `_study.yml` under `checkpoint: remote:`. `study-setup`
   writes it after creating the repo. The core only reads it. A study with no
   remote still checkpoints locally.
2. **The outbox log**, `.checkpoint/log.yml`, append-only. The core writes each
   entry and marks git delivery; the institution layer marks ST delivery.

### 3.1 User surface

- `study_checkpoint(kind, note = NULL, attributes = NULL, occurred_at = Sys.Date())`
- `study_close(outcome, reason = NULL, publication = NULL, superseded_by = NULL, closed_at = Sys.Date())`
- `study_reopen(reason, new_lead = NULL, reopened_at = Sys.Date())`
- `study_checkpoint_push()`: retry every pending delivery.
- `study_status()` gains one line, for example
  `checkpoints: 4 (last manuscript_submitted-1, 2026-09-24); 1 not pushed; 2 not in ST`.
- `study_status()` also reports closure, for example `closed: published (2026-11-14)`.
- Command line (`qhsprograms`): `study-checkpoint <kind> [--note ...]`,
  `study-close <outcome> ...`, `study-reopen --reason ...`.

### 3.2 Repository naming

`st-<st_id, zero-padded to 5>-<slug of the study root folder name>`, for example
`st-01267-virtual-twins`. The ST number is the key; the slug is for people. A
renamed folder does not rename the repo.

## 4. Vocabulary

- **Kinds are the ST Workspace API's `lk_checkpoint_kinds`** (API spec §3.6,
  §6). The package ships the initial §6 rows as its base vocabulary, since they
  are generic. `qhsprograms` fetches the live table from the API when it can
  and caches it in the study; the live table overrides the base.
- **Tags are the kind verbatim plus a sequence number**: `manuscript_submitted-1`,
  `revision_submitted-2`. `workspace_created` is unnumbered: it happens once.
- **The sequence number is derived from the tags**, `max(existing <kind>-n) + 1`,
  never from a counter file, so a re-cloned `.checkpoint/` cannot reuse one.
- **An unknown kind is an error** that lists the valid kinds. A **retired**
  kind is rejected for new checkpoints and stays valid for existing tags.
- **No ordering is enforced.** The API spec never rejects a checkpoint for its
  order; neither does the core.
- **There are no study-level kinds.** Extension happens in the ST table.
- **Snapshots by trigger.** Manual kinds always take a git snapshot. Automatic
  kinds (`data_received`, `analysis_dataset_frozen`, `analysis_started`) do
  **not** by default: tooling fires them, and they would produce many
  near-identical commits. They still produce an outbox entry, with
  `git_commit: null`.

## 5. Snapshot contents

Selection runs three passes in order. **A deny always beats an allow.**

1. **Allow**
   - by extension, anywhere: `.R .Rmd .qmd .sas .sh .py .sql`, `*.Rproj`, `_quarto.yml`
   - always: `_study.yml`, `renv.lock`, `renv/activate.R`, `.Rprofile`, `manifest.yaml`
   - per study: the `checkpoint: include:` patterns in `_study.yml`
   - inside `50_documents/` only: `.docx .pptx .pdf .qmd .bib .png .tiff`
2. **Hard deny** (not configurable)
   - paths: `00_datasets/`, `90_estimates/`, `.checkpoint/`, `renv/library/`, `.git/`
   - anywhere, including `50_documents/`: `.sas7bdat .xpt .parquet .rds .RData .csv .xlsx .xls .lst .log`
     (SAS `.lst` and `.log` echo data values, so they are data)
   - outside `50_documents/`: `.html .pdf .docx .pptx .png .tiff` (there they are outputs)
3. **Size cap:** a file over 50 MB is skipped with a warning that names it.

Paths are mirrored: `.checkpoint/` reproduces the study's relative paths, so a
file deleted from the study appears as a deletion in the next snapshot's diff.

### 5.1 `CHECKPOINT.yml`

Generated at the root of every snapshot:

- `checkpoint_id` (UUID), `kind`, `seq`, `tag`, `note`, `attributes`,
  `occurred_at`, `committed_at` (UTC), `user`, `st_id`, `workspace_id`
- R version, platform, the installed version of every `hvtiR*` package, and the
  sha256 of `renv.lock` and `manifest.yaml`
- `files:` path to sha256 for every copied file
- `skipped:` each file dropped by the size cap, with its size
- `denied:` a **count per rule** of hard-denied files. Denied files are never
  named, because dataset filenames can carry cohort-identifying fragments.
- `manifest_check:` the result of `verify_manifest()` when `manifest.yaml`
  exists. A mismatch warns and is recorded; it does not block the checkpoint.
  An entry without `n_rows` (which `verify_manifest()` reports as `OK` without
  checking) is recorded as `unchecked`.

### 5.2 ADO repository settings

- **Maximum file size** policy on, at 50 MB, matching the size cap.
- No minimum-reviewer policy on `main`.
- Force push and branch deletion denied on `main`.
- No Git LFS: at checkpoint cadence a study stays far below the 10 GB
  recommended ceiling, and LFS needs client setup.

## 6. Lifecycle

`study_checkpoint(kind, ...)`:

1. **Validate.** The kind is in the vocabulary and not retired. `_study.yml`
   carries the ST number. If `.checkpoint/` is missing it is initialised, by
   cloning the remote first when one is set, so the history continues.
2. **Select and copy** (section 5). Tracked files in `.checkpoint/` are
   cleared and the working tree refilled.
3. **Write `CHECKPOINT.yml`** and run the manifest check.
4. **Commit and tag locally.** The author is the user's git identity. The tag
   is annotated; its message carries kind, note, ST number and `checkpoint_id`.
   If nothing changed since the last checkpoint, the tag goes on the existing
   commit and no empty commit is made.
5. **Append to `.checkpoint/log.yml`** an entry in the API Checkpoint shape
   (section 7), with `git: pending` and `st: pending`.
6. **Deliver**, each channel independent:
   - `git push origin main --follow-tags`; success marks `git: delivered`,
     failure leaves it `pending` and warns with the tag and the reason;
   - ST delivery runs only when `qhsprograms` supplies a delivery hook.
     Without one, `st` stays `pending`, which is expected, not an error.
7. **Return** a `study_checkpoint` object (tag, commit, file count, skipped
   files, delivery states) with a compact print method.

### 6.1 Failure rules

- **Steps 1 to 5 are all-or-nothing.** A failure before the commit leaves no
  tag and no log entry.
- **Step 6 never undoes step 4.** A local checkpoint is a checkpoint; delivery
  is replication.
- **Retries are idempotent.** `study_checkpoint_push()`, and the start of every
  `study_checkpoint()` call, retry every pending entry in log order. A tag the
  remote already has counts as delivered. The ST side is idempotent through the
  client-generated `checkpoint_id` (API spec §4.2).
- **Divergence.** When the remote `main` has commits the local clone lacks
  (someone checkpointed from a second copy), the push is rejected as
  non-fast-forward. The core fetches, rebases the unpushed snapshot commits on
  top, **moves their local tags** to the new commits (safe: they were never
  pushed), and pushes again. If the remote already holds the same tag name,
  the local one is renumbered to the next free number and the log entry
  records `renumbered_from:`. A pushed tag is never moved. There is no force
  push, and ADO would refuse one.

### 6.2 Closing

`study_close(outcome, ...)` follows the API spec's Closure rules (§3.4) and
the checkpoint lifecycle above, with these differences:

- **Outcomes:** `published`, `not_published`, `superseded`, `abandoned`.
  `unrecorded` is rejected here: it exists for the legacy migration only
  (API spec §10).
- **Guards, checked locally before anything is written**, so an offline close
  fails early instead of being rejected at delivery:
  - `published` needs `publication` (`title`, `journal`, `accepted_on`,
    `published_on`, and at least one of `doi` and `pmid`) **and** an existing
    `manuscript_published-n` tag;
  - `superseded` needs `superseded_by`, an ST number;
  - an already closed study (section 6.4) cannot be closed again; reopen first.
- **Always snapshots**, whatever changed.
- **Tag:** `closed-<outcome>-<n>`, where `n` counts every closure of the study
  regardless of outcome: `closed-not_published-1`, then after a reopening,
  `closed-published-2`. The tag message carries the outcome, reason,
  publication details and `superseded_by`.
- **Outbox:** a Closure entry (section 7).
- **Not automatic.** After `manuscript_published`, `study_checkpoint()` prints
  a hint that `study_close("published", ...)` is now possible. It never closes
  the study itself, because a published study may be about to spawn a
  continuation.

### 6.3 Reopening

`study_reopen(reason, new_lead = NULL)`:

- Needs a closed study and a `reason`.
- **No snapshot.** It tags the current `.checkpoint/` `main` as `reopened-<n>`,
  where `n` counts reopenings, and appends a Reopening entry to the outbox.
- The next checkpoint or closure snapshots as usual.

### 6.4 Closure state

**A study is closed when its latest `closed-*` tag has no `reopened-*` tag
after it**, the same definition as the API spec, read from tag dates. There
is no separate state file. A checkpoint on a closed study is allowed, since
checkpoints are never rejected for their order, but it warns that the study
is closed.

## 7. The outbox entry

One entry per event, with a `type` of `checkpoint`, `closure` or `reopening`,
in the matching API shape so the institution layer posts it unchanged. A
checkpoint:

```yaml
- type: checkpoint
  checkpoint_id: 5b7e...        # UUID, client-generated
  st_id: 1267
  workspace_id: 7c1e2b0a-...
  kind: manuscript_submitted
  occurred_at: 2026-10-02
  trigger: manual
  artifact: null               # optional; path relative to the study root, plus sha256
  git_commit: 3f320a7
  note: Submitted to JTCVS
  attributes: { journal: JTCVS }
  tag: manuscript_submitted-1   # local only, not sent
  delivery:
    git: delivered
    st: pending
```

A closure (a reopening has the same envelope with `reopening_id`,
`reopened_at`, `reason` and `new_lead`):

```yaml
- type: closure
  closure_id: 9c41...
  st_id: 1267
  outcome: published
  closed_at: 2026-11-14
  reason: null
  publication:
    title: ...
    journal: JTCVS
    accepted_on: 2026-05-26
    published_on: 2026-06-12
    doi: 10.1016/j.jtcvs.2026.05.027
    pmid: "42285288"
  superseded_by: null
  git_commit: 8d02e11           # not in the API Closure shape; see open item 6
  tag: closed-published-1
  delivery:
    git: delivered
    st: pending
```

## 8. Testing

### 8.1 Core (hvtiRutilities, testthat edition 3, no network)

Each test builds a temporary study with `study_setup()` and a local bare repo
(`git init --bare` under `tempdir()`) as the remote, so CI runs the full path,
push included, on all five platforms. Tests needing git skip with
`skip_if_not(nzchar(Sys.which("git")))`.

| Area | Asserted |
|---|---|
| **PHI boundary** | A fixture with a `.csv`, a `.sas7bdat`, an `.xlsx` inside `50_documents/`, a `.log`, a `.docx` outside `50_documents/`, files under `00_datasets/` and `90_estimates/`, and `include: ["**/*.csv"]` in `_study.yml`. **None reach the tagged tree**, read with `git ls-tree -r <tag>`, not from the selector's return value. |
| Allow-list | Every base extension, the always set and the `50_documents/` exceptions are present; an oversize file is skipped and listed. |
| `CHECKPOINT.yml` | Every committed file's sha256 matches; denied files appear only as counts. |
| Vocabulary | Unknown kind errors with the valid list; retired kind rejected; `workspace_created` unnumbered; live table overrides base. |
| Sequencing | Two checkpoints give `-1` and `-2`; deleting and re-cloning `.checkpoint/` continues at `-3`. |
| No change | Tagging an unchanged state adds a tag and no commit. |
| Offline | An unreachable remote gives a local tag, `git: pending` and a warning; once reachable, `study_checkpoint_push()` delivers; a second call is a no-op. |
| Divergence | A second clone pushes first: rebase, retag, `renumbered_from`, no force push. |
| Manifest | A mismatch warns and is recorded; missing `n_rows` is recorded `unchecked`. |
| Atomicity | An error forced between copy and commit leaves no tag and no log entry. |
| Automatic kinds | No commit, an outbox entry with `git_commit: null`. |
| `study_status()` | The checkpoint line reports pending counts correctly. |
| Close guards | `published` without a `manuscript_published` tag, or without DOI and PMID, errors before any write; `superseded` without `superseded_by` errors; `unrecorded` is rejected; closing a closed study errors. |
| Close and reopen | Close always commits and tags `closed-<outcome>-n`; reopen tags without committing; close, reopen, close gives `closed-...-1`, `reopened-1`, `closed-...-2`; closure state follows the latest tags. |
| Closed study | A checkpoint on a closed study succeeds and warns. |

### 8.2 Institution (`qhsprograms`)

- Repo naming and creation against a mocked ADO REST response;
  `study-setup --dry-run` prints the repo it would create.
- ST delivery against an outbox fixture with a stubbed writer: pending entries
  delivered in order; a failure leaves them pending.
- **One manual acceptance run** on the LRI server under a real Entra identity:
  `study-setup` on a scratch study, then `study-checkpoint data_request_submitted`
  (a manual kind), then confirm the tag is visible in ADO, a force push is
  rejected, and the commit author is the user.

## 9. Open items

1. **`_study.yml` key names.** hvtiRutilities writes `study_tracker_id`; the API
   spec §9 uses `st_id` and adds `workspace_id`. Decide the canonical keys (and
   a reader that accepts both) before implementation.
2. **An `adhoc` kind.** §6 of the API spec has no kind for a checkpoint that
   matches no event. Propose adding `adhoc` (no task) to `lk_checkpoint_kinds`.
3. **ST write path.** ST access today is a read-only lookup; the API does not
   exist yet. Until it does, ST delivery only queues and reports (API spec §2,
   "the interim period"). Not a blocker for git checkpoints.
4. **Create-repository permission.** `study-setup` users need the project-level
   Create repository permission in `CORR_STUDIES`, and the institution layer
   needs a token for the ADO REST API (from Git Credential Manager, not a PAT).
   Confirm both are grantable.
5. **Legacy estate.** `study-setup --adopt` creates a repo per adopted study.
   Confirm that the count of legacy studies adopted in the first pass (API spec
   §10) is acceptable as a repo count in `CORR_STUDIES`.
6. **`git_commit` on Closure.** The API spec's Closure record has no
   `git_commit` field. Propose adding it (optional), so the ST record of a
   published study points at the frozen code behind the paper.
