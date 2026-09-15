# Study setup, legacy adoption, and recovery

**Date:** 2026-09-15
**Status:** Approved design, pending implementation plans
**Repositories:** `qhsprograms` (new Azure DevOps repository) and
`hvtiRutilities`
**Production destination:** `/programs/execs/cmd/`

## Context

The production `mkdirs` command starts from a directory name. It creates the
directory, copies the whole legacy template tree, runs `fixtemplates`, and
initializes a local Git repository. That was a useful contract when every new
study began by copying SAS work files. It is the wrong contract for the R
template system.

The Study Tracker record now exists before the study directory. It already
holds the project number and the identity metadata we otherwise ask a person
to type again. Work files come later through
`hvtiRtemplates::new_job()`, one editable file at a time. Copying the whole
template tree creates files nobody requested, and `cp -R` can replace a file
whose study copy has already diverged from the package source.

There is a second problem underneath the first. `study_init()` cannot run at
study birth: it requires a built dataset and the event and follow-up variables
needed to derive cohort counts. A new study has none of those yet. The current
`_study.yml` therefore records data readiness, but it cannot record identity at
the time identity first becomes known.

This design separates those moments. `study_setup()` records identity and
creates the R environment. `register_data()` records the canonical study
dataset or a named subset after that dataset exists. The old `study_init()`
name is retained only as a deprecated compatibility entry point.

## Evidence read for this design

The current production files were inspected in place and not modified:

- `/programs/execs/cmd/mkdirs`
- `/programs/execs/cmd/cptemplates`
- `/programs/execs/cmd/organize_templates.sh`

The designated legacy pilot already has the seven working directories, an R
project, `renv`, a lockfile, `.Renviron`, `.renvignore`, and a local-only Git
repository. It also has copied `templates/` directories in each working
directory. That is exactly the mixed state adoption must report without
rewriting.

Study Tracker access already has a working precedent in `pub_kb`: a read-only
MySQL connection, credentials supplied through environment variables, and a
parameterized lookup on `Topics.id`. Its structural query provides the topic,
activity, umbrella, status, owner, IRB number, CVIR number, data path,
SharePoint URL, and creation date. This design reuses the interface and the
field names, not the `pub_kb` source tree.

## Alternatives considered

**Extend production `mkdirs` in place.** This keeps one command name, but it
mixes the old copy-everything behavior with a new identity-driven workflow and
leaves the source on the production share. A failed edit would affect the
current command before the replacement had completed a pilot. The production
file remains unchanged.

**Put the whole workflow in `hvtiRutilities`.** This gives the R package one
entry point, but it makes a portable data utility depend on the Tracker schema,
Azure DevOps authentication, and one server's deployment paths. Those are
operational dependencies rather than study semantics.

**Split orchestration from the study contract.** This is the chosen approach.
The versioned command owns external systems and calls package functions for
the files and states an R study understands. The boundary costs one small
interface, but neither side has to impersonate the other.

## Scope

This work is split across two repositories, with one boundary between them.

The new Azure DevOps `qhsprograms` repository owns:

- the versioned baseline of the production command directory;
- the `study-setup` command and its argument parsing;
- read-only Study Tracker access;
- target-directory resolution;
- Azure DevOps repository discovery and recovery;
- the dry-run, status, new-study, adoption, and recovery workflows; and
- deployment to `/programs/execs/cmd/`.

`hvtiRutilities` owns:

- the pre-dataset `_study.yml` schema;
- creation and validation of the standard study directory structure;
- safe creation of R environment files;
- the distinction between identity-ready and data-ready studies;
- registration of the canonical study dataset and named subsets through
  `register_data()`; and
- the read-only status report consumed by the command.

The shell command does not copy work files. Those remain on demand through
`hvtiRtemplates::new_job()`.

## The `qhsprograms` source repository

The first commit imports the meaningful current contents of
`/programs/execs/cmd/` without changing their behavior or layout. The
repository mirrors that path under `execs/cmd/` so a deployed file has one
obvious source.

The import preserves executable bits and records SHA-256 checksums against the
production files. It excludes filesystem debris such as AppleDouble `._*`
files, `.smbdelete*` files, `.DS_Store`, and editor temporary files. Source,
documentation, archived scripts, and platform variants remain in their
current relative locations for the baseline. Reorganizing history is a later
change, not part of establishing it.

Before anything is committed, the candidate import is scanned for credentials
and other secrets. A production file containing a secret is recorded by path
and checksum but is not committed until the secret has been removed or the
file has an approved protected home.

The second change adds `study-setup`, its tests, and deployment instructions.
Production is a deployment destination after that point. A file is reviewed
in Azure DevOps and then promoted to the share; it is not edited there as the
authoritative copy.

## Command interface

The ordinary command is:

```text
study-setup [options] STUDY_TRACKER_ID [DIRECTORY]
```

Recovery may omit `STUDY_TRACKER_ID` when it can be inferred from the local
repository name or remote:

```text
study-setup --recover [DIRECTORY]
```

`DIRECTORY` defaults to the current directory. A leaf name is resolved beneath
the current directory; an explicit path is also accepted. The command never
writes an absolute path into a study file.

The supported modes are:

```text
study-setup 42 example_study
study-setup 42 --status
study-setup 42 --adopt
study-setup 42 --recover
study-setup 42 example_study --dry-run
```

An absent target selects new-study creation. An existing target is read-only
unless `--adopt` is present. An initialized target runs status and changes
nothing. `--recover` is the only mode that restores or recreates a missing
`_study.yml`.

`--dry-run` reports the Study Tracker record, resolved target, detected state,
files that would be created, `renv` action, Azure DevOps action, and any
conflict. It does not create a directory, connect a Git remote, initialize
`renv`, or write a file.

The production command runs in the Unix environment where Study Tracker paths
normally begin with `/studies/`. Windows and macOS clients may mount the same
tree under another root. The command treats `DIRECTORY` as the caller supplied
it and does not translate the Tracker path. Neither path is stored in
`_study.yml`.

## Study Tracker boundary

Study Tracker is read-only for this workflow. The command queries one exact
`Topics.id` using a parameterized statement. It never creates a topic, changes
`data_path`, advances a task, or updates status.

The lookup must return exactly one topic. Missing and duplicate results are
errors. Credentials come from the approved runtime credential mechanism and
never from a committed file, command argument, log, or study manifest.

`Topics.data_path` is Tracker evidence, but it does not drive or validate
creation. The command may display it beside the requested target. It does not
translate, compare, correct, or write either path into the study.

The identity written at setup is drawn from stable or identifying fields:

- Study Tracker ID;
- topic;
- umbrella;
- owner;
- IRB number;
- CVIR number; and
- Study Tracker creation date.

Activity, workflow status, and SharePoint URL remain live Tracker state. They
may be displayed by `--status`, but are not frozen into `_study.yml` as study
identity.

## `_study.yml` has two valid states

A pre-dataset manifest is valid identity, not a failed data contract:

```yaml
study: "Example aortopathy study"
study_tracker_id: 42
umbrella: "Example program"
owner: "Analyst Name"
irb_number: "IRB 00-000"
cvir_no: ~
study_creation_date: "2026-07-21"
population: ~
built: ~
citation: ~
cohort: ~
```

After the canonical study dataset is registered, the existing `built` and
`cohort` shape is retained:

```yaml
built: "built.sas7bdat"
cohort:
  n: 3049
  n_events: 1032
  n_censored: 2017
  event: "dead"
  time: "iv_dead"
```

The canonical dataset has the reserved logical name `study`. Named subsets
are additive and carry their own file and cohort contract:

```yaml
subsets:
  analysis_cohort:
    built: "analysis_cohort.sas7bdat"
    population: "Eligible patients with complete imaging"
    cohort:
      n: 812
      n_events: 211
      n_censored: 601
      event: "dead"
      time: "iv_dead"
```

There is exactly one canonical study dataset and any number of distinctly
named subsets. Registering a subset never changes the top-level `built`,
`population`, or `cohort`. Existing manifests with no `subsets` key retain
their current meaning. A subset may be registered before the canonical
dataset. The study then has registered data but is not data-ready under the
default study contract.

Existing manifests with no Study Tracker fields remain valid. This is an
additive schema change.

`study_config(start, require_data = TRUE)` keeps its current default. Analysis
and provenance calls therefore still fail when `built` or `cohort` is absent.
Callers that only need identity use `require_data = FALSE`. `study_root()` and
`study_status()` use that identity-only path so a new study is recognizable
before its first dataset exists.

`study_status()` reports `_study.yml` as `OK` when the identity state parses.
The canonical dataset and cohort checks report `MISSING` until they are
registered. The manifest check covers whichever registered files it contains,
and registered subsets receive separate dataset and cohort rows. A check that
cannot run has not failed.

## Package-owned setup

The package adds:

```r
study_setup(root, study, study_tracker_id,
            umbrella = NULL, owner = NULL,
            irb_number = NULL, cvir_no = NULL,
            study_creation_date = NULL,
            adopt = FALSE)
```

For a new root it creates the standard directories:

```text
analyses/
datasets/
descriptive/
distributions/
documents/
estimates/
graphs/
```

It writes the pre-dataset `_study.yml`, `.renvignore`, and `.Renviron` through
temporary files followed by atomic renames. It may create an R project file as
a convenience, but no package function depends on RStudio or that file.

For an existing root, `adopt = FALSE` is read-only. `adopt = TRUE` creates only
missing directories and missing initialization files. It never moves or
renames an existing file or directory. Existing `.Renviron`, `.renvignore`,
`.Rprofile`, `renv/`, `renv.lock`, `_study.yml`, and work files win over
defaults. A conflict is reported and left for a person.

The package does not query Study Tracker and does not know Azure DevOps. The
command passes the validated structural record into this function.

## Completing the data contract

The package adds:

```r
register_data(root = getwd(), built, event, time,
              dataset = "study", role = c("study", "subset"),
              population = NULL, source = NULL,
              extract_date = NULL)
```

The function requires a valid identity manifest and an existing file under
`datasets/`. It reads the data, checks the event and time variables, derives
the three cohort counts, and prepares the updated `_study.yml` and
`manifest.yaml` before replacing either. It never accepts caller-supplied
counts.

`role = "study"` requires the reserved `dataset = "study"` and writes the
top-level study data contract. `role = "subset"` requires a non-reserved,
non-empty lower-snake-case dataset name and writes that entry beneath
`subsets`. Requiring the role makes an accidental attempt to replace the study
cohort fail rather than quietly changing its meaning. A second registration
of the canonical dataset or an existing subset name is refused. Updating
registered data is a separate operation and is not part of this design.

`built_path()`, `built_manifest()`, `read_built()`, `cohort_counts()`,
`assert_cohort()`, and `record_provenance()` gain `dataset = "study"` as their
last argument. Their default and positional behavior is unchanged. Passing a
subset name selects its registered file and its own cohort gate, and records
that logical name in provenance. An unknown name fails and lists the
registered choices.

`study_init()` is deprecated in favor of `study_setup()` followed by
`register_data()`. It remains through the 1.x series as a compatibility
wrapper. It emits the package's standard deprecation warning, but its files,
return value, and failure guarantees do not change. Internally it may compose
the new primitives, but a failure before data validation must still write
nothing.

## Automatic `renv` initialization

`study-setup` runs `renv` in a separate R process after package-owned
scaffolding succeeds. It never restarts the caller's R session.

For a new study, initialization is automatic. For a legacy study it is
automatic only under explicit `--adopt`. Existing environment files are
authoritative:

- a complete existing `renv` environment is retained;
- absent environment files may be created;
- an existing file is never replaced silently; and
- a partial or conflicting environment is reported as incomplete rather than
  repaired by guesswork.

If `renv` fails, the directory structure and identity manifest remain. The
command exits unsuccessfully and reports the exact partial state.
`study-setup --status` gives the same result on the next run, so recovery does
not depend on remembering console output.

## Azure DevOps study repositories

The setup design does not require `CORR_STUDIES` to be live. When it is live,
each repository name begins with its unpadded Study Tracker ID:

```text
st-42-example_study
```

The ID is the lookup key. The suffix is for people and may differ from the
folder name without breaking discovery. More than one repository beginning
with the same `st-<id>-` prefix is an error to resolve in Azure DevOps.

Study repositories contain source and reproducibility metadata only. Data,
results, PHI, credentials, and the copied legacy template corpus are excluded.
`_study.yml`, `.Renviron`, `.renvignore`, `.Rprofile`, and `renv.lock` are
eligible to be tracked because their schemas prohibit secrets and absolute
paths.

## Recovery

A missing manifest does not trigger network activity from an analysis. A
function that needs data-ready configuration fails with an actionable message:

```text
No _study.yml was found.

Recovery may be available from CORR_STUDIES:
  study-setup --recover

If the Study Tracker ID cannot be determined from this repository:
  study-setup 42 --recover
```

`study_status()` reports the same action as a `MISSING` detail. Batch work and
Quarto rendering fail rather than waiting at an interactive prompt.

The explicit recovery ladder is:

1. Restore the most recent `_study.yml` from the local Git history.
2. Locate the one `CORR_STUDIES` repository whose name begins with the Study
   Tracker ID, fetch its history, and restore the most recent committed copy.
3. Validate the recovered schema and require its `study_tracker_id` to match.
4. If no versioned copy exists, recreate the identity state from Study Tracker.
5. Report that `register_data()` is required when no recoverable data-ready
   manifest exists.

Recovery searches file history, not only the current branch tip, because a
deletion may itself have been committed. It writes through a temporary file
and atomic rename and refuses to overwrite an existing manifest. Dry run names
the repository, commit, and proposed recovery source before any write.

## Failure and rerun rules

The command validates before writing wherever it can. In particular, it
resolves one Tracker record, the target, the mode, and conflicts before it
creates a new root.

Operations then proceed in this order:

1. create or select the target;
2. create missing package-owned structure and identity;
3. initialize or validate `renv`;
4. connect the study repository when `CORR_STUDIES` is available; and
5. print `study_status()`.

Each completed step is safe to observe on a rerun. A later failure does not
delete an earlier valid step. The next status call reports what remains.

These cases are errors with no write:

- the Tracker ID does not resolve to exactly one row;
- the target exists and neither `--status` nor `--adopt` was requested;
- the target is a file rather than a directory;
- the target cannot be written;
- an existing identity carries a different Study Tracker ID;
- a recovery source carries a different Study Tracker ID; or
- Azure DevOps contains more than one repository for the ID.

## Legacy adoption

Level 1 adoption keeps every study file and directory where it is. It adds the
identity and reproducibility infrastructure that is missing, and reports old
local Git and copied template directories as migration findings.

Removing `.git` or any `templates/` directory is a separate, recoverable
migration. `--adopt` does not remove either. Before the legacy-study pilot,
the exact directories, file counts, and repository state are recorded, and a
backup destination is chosen. Removal requires a distinct command and a
second approval after the inventory is shown.

Numbered-folder migration is Level 3. It may rewrite paths in SAS and R work,
so setup and Level 1 adoption do not perform it.

## Testing

The `qhsprograms` tests use a fake Tracker adapter, temporary directories, and
a local bare Git repository standing in for Azure DevOps. They cover:

- argument parsing and the optional directory;
- exact-one-row Tracker lookup;
- dry run with zero filesystem and network writes;
- new creation and automatic `renv` invocation;
- refusal to mutate an existing target without `--adopt`;
- preservation of every existing environment and work file;
- partial `renv` failure followed by a stable status result;
- repository discovery by `st-<id>-` prefix;
- recovery from local and remote history, including a committed deletion;
- Tracker-only identity recovery; and
- every mismatch and ambiguous-repository refusal above.

The `hvtiRutilities` tests cover:

- both valid `_study.yml` states;
- backward compatibility with every current manifest fixture;
- the default data-ready failure of `study_config()`;
- identity-only parsing;
- `study_status()` reporting pre-dataset checks as `MISSING`;
- `study_setup()` creation, adoption, preservation, and atomic writes;
- `register_data()` deriving rather than accepting counts;
- identity and canonical-cohort preservation during subset registration;
- any number of uniquely named subsets;
- rejection of reserved, empty, duplicate, and unknown dataset names;
- subset registration before or after the canonical dataset;
- dataset selection by every data-contract and provenance helper;
- refusal to replace a canonical or previously registered dataset; and
- the `study_init()` warning with otherwise unchanged files, return value, and
  failure behavior.

The package definition of done remains `devtools::test()` plus
`devtools::check()` at 0 errors, 0 warnings, and 0 notes, with regenerated
documentation and `_pkgdown.yml` entries for new exports.

The production pilot first runs `--dry-run` against a disposable copy of the
designated legacy study. No `.git` or `templates/` directory is removed during
this work.

## Deferred work

`study_checkpoint()` follows this design but is not part of its implementation
plan. A checkpoint will commit `_study.yml`, the environment lock, source, and
other approved reproducibility metadata to the study repository, while
excluding data, results, credentials, and PHI. Natural events include first
abstract submission and first manuscript submission.

Checkpoint-to-Tracker task updates require a separate design. Tracker
transitions are not linear, the current system does not retain the path taken,
and this setup command is deliberately read-only against it.

## Success criteria

1. The active production command set has a reviewed, checksum-verified Azure
   DevOps source without changing production behavior.
2. `study-setup` can create, inspect, adopt, and recover a study by Study
   Tracker ID without copying work templates or writing absolute paths.
3. A study has valid recorded identity before its first built dataset exists.
4. `register_data()` records one canonical study dataset and named subsets,
   each with derived cohort and manifest evidence, without letting a subset
   replace the study cohort.
5. Automatic `renv` setup is rerunnable and never replaces an existing
   environment file silently.
6. A missing `_study.yml` tells a person exactly how to attempt recovery, while
   an analysis never performs that recovery implicitly.
7. The legacy-study dry run reports its current mixed state and changes
   nothing.
