# QHS Programs Study-setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Version the production command collection and add a tested
`study-setup` command for new studies, legacy adoption, status, dry runs, and
recovery.

**Architecture:** A small Python command owns user interaction and external
systems. It reads Study Tracker through a read-only adapter, asks
`hvtiRutilities` to create or inspect study state through a file-based R
bridge, and queries Azure DevOps only during explicit recovery. The repository
is the source of truth; `/Volumes/qhsprograms/execs/cmd/` is a deployment
target.

**Tech stack:** Python 3.11+, pytest, pymysql, subprocess, Azure CLI, git,
Rscript, hvtiRutilities, renv.

**Spec:** `2026-09-15-study-setup-legacy-adoption-design.md` in
`hvtiRutilities/dev/specs/`.

## Global constraints

- Never commit credentials, database rows, PHI, production logs, or editor
  debris.
- Never edit `/Volumes/qhsprograms/execs/cmd/` as the implementation source.
- Study Tracker access is read-only and parameterized by integer topic ID.
- Network recovery occurs only after an explicit `--recover` request.
- The command never silently overwrites `_study.yml`, README, renv files, or
  an existing study repository.
- Use environment variables for deployment-specific endpoints and projects.
- Test with synthetic Tracker records and local bare git repositories only.

---

### Task 1: Create and verify the qhsprograms source repository

**Files:**
- Create: `.gitignore`
- Create: `README.md`
- Create: `requirements-dev.txt`
- Create: `scripts/check-production-drift`
- Import: approved files beneath `execs/cmd/`

- [ ] **Step 1: Inventory production without changing it**

Run from an empty local checkout:

```sh
find /Volumes/qhsprograms/execs/cmd -type f -print0 |
  sort -z | xargs -0 shasum -a 256 > /tmp/qhsprograms-cmd.sha256
```

Classify every file as command, required support file, local configuration,
credential, generated output, log, backup, or editor debris. Record the
included command/support paths in `README.md`; record excluded classes, not
their sensitive contents.

- [ ] **Step 2: Initialize the local repository and exclusion rules**

The `.gitignore` must exclude at least:

```gitignore
.DS_Store
*~
*.bak
*.log
*.lst
*.tmp
__pycache__/
.pytest_cache/
.venv/
.env
*.pem
*.key
```

Copy only files classified as commands or required support files into the
matching `execs/cmd/` path. Preserve executable bits.

- [ ] **Step 3: Add a deterministic drift checker**

`scripts/check-production-drift` accepts an optional production root whose
default is `/Volumes/qhsprograms`. It compares relative paths, modes, and
SHA-256 checksums beneath `execs/cmd/`, honoring `.gitignore`, and exits nonzero
for missing, extra, or changed deployed files.

Add pytest coverage using two temporary directory trees. Assert identical
trees pass and each drift class fails with the affected relative path.

- [ ] **Step 4: Run secret and baseline checks**

Run:

```sh
git status --short
git diff --check
pytest -q
gitleaks detect --no-git --source . --redact
```

Expected: tests pass, the diff is clean, and the secret scan reports no
finding. If `gitleaks` is unavailable, stop and install or obtain the approved
scanner before committing; do not substitute a handwritten pattern search.

- [ ] **Step 5: Commit and create the ADO repository**

Require `QHS_ADO_ORG_URL` and `QHS_PROGRAMS_PROJECT` in the operator's
environment, then run:

```sh
az repos create --name qhsprograms \
  --organization "$QHS_ADO_ORG_URL" \
  --project "$QHS_PROGRAMS_PROJECT"
```

Add the returned HTTPS URL as `origin`, push a feature branch, and open the
normal reviewed merge request. Do not seed `main` directly.

Commit: `chore: establish qhsprograms source baseline`

### Task 2: Build the command shell and Tracker adapter

**Files:**
- Create: `execs/cmd/study-setup`
- Create: `execs/cmd/study_setup/__init__.py`
- Create: `execs/cmd/study_setup/cli.py`
- Create: `execs/cmd/study_setup/tracker.py`
- Create: `tests/test_study_setup_cli.py`
- Create: `tests/test_tracker.py`

**Interface:**

```text
study-setup [--status | --adopt] [--dry-run]
            STUDY_TRACKER_ID [DIRECTORY]
study-setup --recover [--dry-run] [--yes]
            [STUDY_TRACKER_ID] [DIRECTORY]
```

`DIRECTORY` defaults to the current directory. A leaf name resolves beneath
the current directory; an explicit path is accepted as supplied. The modes
are mutually exclusive except that `--dry-run` may accompany new, adopt, or
recover mode.

- [ ] **Step 1: Write failing parser and Tracker tests**

Cover integer IDs, omitted directories, conflicting modes, and stable exit
codes. Test an exact single synthetic row, no row, and duplicate rows through
a fake cursor. Assert query parameters are `(study_tracker_id,)` and that no
write method is called.

- [ ] **Step 2: Confirm failure**

Run: `pytest -q tests/test_study_setup_cli.py tests/test_tracker.py`

Expected: FAIL because the modules do not exist.

- [ ] **Step 3: Implement the parser and read-only query**

Read connection settings from `ST_DB_HOST`, `ST_DB_PORT` (default `3306`),
`ST_DB_NAME` (default `Projects`), `ST_DB_USER`, and `ST_DB_PASSWORD`. Select
only the approved stable identity columns from `Topics`, with:

```sql
WHERE t.id = %s
```

Reject zero or multiple rows. Normalize nullable values but do not invent
identity data. Keep connection construction injectable so tests never contact
Study Tracker.

- [ ] **Step 4: Add the executable launcher and run tests**

The launcher imports `study_setup.cli:main`, returns its exit code, and has an
executable mode. Run:

```sh
pytest -q tests/test_study_setup_cli.py tests/test_tracker.py
```

Expected: PASS.

Commit: `feat: add study-setup command shell`

### Task 3: Render the durable README without overwriting it

**Files:**
- Create: `execs/cmd/study_setup/readme.py`
- Create: `tests/test_readme.py`

- [ ] **Step 1: Write exact-output tests**

Given Tracker ID `42`, assert the link is exactly:

```text
http://hviresearch.ccf.org/StudyTracker/index.php?page=Topic&topic_id=42
```

Assert output includes the study title, stable identity fields, a protocol
summary placeholder, `_study.yml`, and the protocol document location. Assert
it excludes Tracker status and absolute filesystem paths. Assert an existing
README is byte-for-byte unchanged.

- [ ] **Step 2: Confirm failure**

Run: `pytest -q tests/test_readme.py`

Expected: FAIL because the renderer does not exist.

- [ ] **Step 3: Implement deterministic rendering**

Render UTF-8 Markdown with these sections: title, Study Tracker, study
identity, protocol summary, and study files. Protocol summary contains fields
for objective or question, population, primary endpoint, and protocol filename
plus version/date. Write through a sibling temporary file and rename only when
`README.md` is absent.

- [ ] **Step 4: Run and commit**

Run: `pytest -q tests/test_readme.py`

Expected: PASS.

Commit: `feat: create study readmes from tracker identity`

### Task 4: Bridge setup and status to hvtiRutilities

**Files:**
- Create: `execs/cmd/study_setup/bridge.R`
- Create: `execs/cmd/study_setup/r_bridge.py`
- Create: `execs/cmd/study_setup/workflow.py`
- Create: `tests/test_r_bridge.py`
- Create: `tests/test_workflow.py`

- [ ] **Step 1: Write failing bridge and workflow tests**

Use a fake command runner to assert new mode sends Tracker identity to
`study_setup(adopt = FALSE)`, adoption sends `adopt = TRUE`, and status calls
`study_config(require_data = FALSE)` plus `study_status()`. Assert dry-run
performs no filesystem write, Git or ADO mutation, or renv initialization.
It may perform read-only Tracker, filesystem, Git, and ADO discovery needed
to report its proposed action.

- [ ] **Step 2: Confirm failure**

Run: `pytest -q tests/test_r_bridge.py tests/test_workflow.py`

Expected: FAIL because the bridge and workflow do not exist.

- [ ] **Step 3: Implement a file-based JSON bridge**

Python writes request JSON to a restrictive temporary file and invokes:

```text
Rscript --vanilla execs/cmd/study_setup/bridge.R REQUEST.json
```

The R bridge parses the request, calls only exported `hvtiRutilities`
functions, emits one JSON response on standard output, and reports diagnostics
on standard error. It never embeds user values in R source text.

- [ ] **Step 4: Implement guarded new and adoption workflows**

New mode refuses a nonempty destination. Adoption requires an existing
destination and refuses a mixed layout. Both create the README only after the
R setup succeeds. If README creation fails, report the partial state and the
exact rerun command; never remove pre-existing files.

- [ ] **Step 5: Run focused tests and commit**

Run: `pytest -q tests/test_r_bridge.py tests/test_workflow.py`

Expected: PASS.

Commit: `feat: create and adopt study workspaces`

### Task 5: Initialize renv automatically under the approved rules

**Files:**
- Modify: `execs/cmd/study_setup/workflow.py`
- Modify: `tests/test_workflow.py`

- [ ] **Step 1: Add failing policy tests**

Assert renv initialization occurs for successful new setup and explicit
adoption, never for status, recover-only inspection, dry-run, or a failed
setup. Assert it runs in a separate R process with the study root as its
working directory.

- [ ] **Step 2: Confirm failure**

Run: `pytest -q tests/test_workflow.py -k renv`

Expected: FAIL because renv is not invoked.

- [ ] **Step 3: Add the separate-process invocation**

Run exactly:

```text
Rscript --vanilla -e renv::init(bare=TRUE,restart=FALSE)
```

Preserve any existing `renv.lock`, `renv/`, `.Rprofile`, `.Renviron`, and
`.renvignore`; if their state makes initialization unsafe, stop with an
actionable message rather than replacing them.

- [ ] **Step 4: Run focused tests and commit**

Run: `pytest -q tests/test_workflow.py`

Expected: PASS.

Commit: `feat: initialize renv during study setup`

### Task 6: Recover missing study identity from CORR_STUDIES

**Files:**
- Create: `execs/cmd/study_setup/ado.py`
- Create: `tests/test_ado.py`
- Create: `tests/test_recovery.py`
- Modify: `execs/cmd/study_setup/workflow.py`

- [ ] **Step 1: Write the recovery precedence tests**

Cover, in order: local git history, the ADO repository
`st-<tracker-id>-<slug>`, and Tracker identity fallback. The numeric ID is not
zero-padded. Assert local success
does not call ADO or Tracker, ADO success does not call Tracker, conflicting
candidate identities stop, and no automatic network call occurs outside
recover mode.

- [ ] **Step 2: Confirm failure**

Run: `pytest -q tests/test_ado.py tests/test_recovery.py`

Expected: FAIL because recovery does not exist.

- [ ] **Step 3: Implement local and ADO lookup**

Require `QHS_ADO_ORG_URL`; default `QHS_CORR_STUDIES_PROJECT` to
`CORR_STUDIES`. Use Azure CLI JSON output to resolve exactly one repository
whose name starts with the unpadded `st-<id>-` identity. Fetch only the
history needed to locate the latest valid `_study.yml`; do not clone study
data. Validate recovered Tracker ID before presenting it.

- [ ] **Step 4: Make recovery an explicit proposal and confirmation**

Show the source, identity fields, and destination before writing. Require an
interactive confirmation unless `--yes` is supplied; add `--yes` to the
parser. After confirmation, restore `_study.yml` atomically. If only Tracker
identity is available, write identity-only state and tell the user that
`register_data()` is still required.

- [ ] **Step 5: Run focused tests and commit**

Run: `pytest -q tests/test_ado.py tests/test_recovery.py`

Expected: PASS.

Commit: `feat: recover study identity from ADO`

### Task 7: Verify, document, and deploy

**Files:**
- Modify: `README.md`
- Modify: `requirements-dev.txt`
- Modify: `scripts/check-production-drift`

- [ ] **Step 1: Document prerequisites and operator examples**

Document new, status, adoption, dry-run, and recovery commands; required
environment variables; recovery precedence; renv policy; numbered new-study
folders; legacy preservation; and how to register the default dataset.

- [ ] **Step 2: Run all local gates**

Run:

```sh
pytest -q
git diff --check
gitleaks detect --no-git --source . --redact
```

Expected: all tests pass, no whitespace errors, no secret findings.

- [ ] **Step 3: Run isolated integration tests**

Use a temporary study root, synthetic Tracker adapter, installed development
`hvtiRutilities`, and local bare git remote. Exercise new, status, adoption,
dry-run, local recovery, and remote recovery. Assert no file outside the
temporary roots changes.

- [ ] **Step 4: Deploy after review**

After the ADO merge is approved, deploy the reviewed commit to
`/Volumes/qhsprograms/execs/cmd/`, preserve executable modes, and run:

```sh
scripts/check-production-drift /Volumes/qhsprograms
```

Expected: no drift. Record the deployed commit SHA in the release record, not
in the production command tree.

Commit: `docs: document study-setup operations`
