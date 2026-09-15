# Study setup, legacy adoption, and recovery

**Date:** 2026-09-15
**Status:** Approved design, pending implementation plans
**Repositories:** `qhsprograms` (new Azure DevOps repository),
`hvtiRutilities`, `hvtiRtemplates`, and a small downstream migration in
`hvtiRdatabuild`
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
`hvtiRtemplates::add_job()`, one editable file at a time. Copying the whole
template tree creates files nobody requested, and `cp -R` can replace a file
whose study copy has already diverged from the package source.

There is a second problem underneath the first. `study_init()` cannot run at
study birth: it requires a built dataset and the event and follow-up variables
needed to derive cohort counts. A new study has none of those yet. The current
`_study.yml` therefore records data readiness, but it cannot record identity at
the time identity first becomes known.

This design separates those moments. `study_setup()` records identity and
creates the R environment. `register_data()` records the default study dataset
or an additional named dataset after that dataset exists. `study_init()` is
removed rather than retained as a compatibility entry point because no study
team has adopted it.

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

This work is split across three owning repositories plus one downstream
consumer migration, with the operational boundary kept outside the R packages.

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
- default and named data registration through `register_data()`; and
- the read-only status report consumed by the command.

`hvtiRtemplates` owns template discovery and `add_job()`. It learns how to
place a new work file into either a numbered new-study folder or an unnumbered
legacy folder without creating both forms in one study.

`hvtiRdatabuild` has package-development fixtures and guidance that call
`study_init()`. They move to `study_setup()` plus `register_data()` in the same
coordinated change. The local family scan found no study scripts calling
`study_init()`; historical design notes and NEWS entries remain unchanged as
records of what shipped.

The shell command does not copy work files. Those remain on demand through
`hvtiRtemplates::add_job()`.

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

## `_study.yml` separates identity from default data readiness

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

After the default study dataset is registered, the existing `built` and
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

The default dataset has the reserved logical name `study`. Additional named
datasets are additive. A row subset may carry its own cohort contract:

```yaml
additional_datasets:
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

This first schema has one default dataset and any number of distinctly named
additional datasets. "Default" identifies what functions use when no dataset
is named; it does not claim that every study has one scientifically canonical
source. An additional dataset may be a row subset or an ancillary file with
different observations. Registering one never changes the top-level `built`,
`population`, or `cohort`. An ancillary dataset that has no meaningful event
and time variables records `cohort: ~`.

Existing manifests with no `additional_datasets` key retain their current
meaning. An additional dataset may be registered before the default dataset.
The study then has registered data but is not data-ready under the default
study contract. Supporting more than one default is deferred until a real
study requires the ambiguity to be resolved.

Existing manifests with no Study Tracker fields remain valid. This is an
additive schema change.

`study_config(start, require_data = TRUE)` keeps its current default. Analysis
and provenance calls therefore still fail when `built` or `cohort` is absent.
Callers that only need identity use `require_data = FALSE`. `study_root()` and
`study_status()` use that identity-only path so a new study is recognizable
before its first dataset exists.

`study_status()` reports `_study.yml` as `OK` when the identity state parses.
The default dataset and cohort checks report `MISSING` until they are
registered. The manifest check covers whichever registered files it contains,
and additional datasets receive separate dataset and cohort rows. A named
dataset with `cohort: ~` reports its cohort as `MISSING`, not `FAIL`. A check
that cannot run has not failed.

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
00_datasets/
10_descriptive/
20_distributions/
30_analyses/
40_graphs/
50_documents/
90_estimates/
```

The numbers are assigned identifiers, not positions calculated from the
taxonomy. The gaps allow a future directory to be inserted without renaming
the rest, and `90_estimates` remains last because it holds saved output rather
than work.

It writes the pre-dataset `_study.yml`, `.renvignore`, and `.Renviron` through
temporary files followed by atomic renames. It may create an R project file as
a convenience, but no package function depends on RStudio or that file.

For an existing root, `adopt = FALSE` is read-only. `adopt = TRUE` creates only
missing directories and missing initialization files. It never moves or
renames an existing file or directory. Existing `.Renviron`, `.renvignore`,
`.Rprofile`, `renv/`, `renv.lock`, `_study.yml`, and work files win over
defaults. A conflict is reported and left for a person.

Adoption detects one directory scheme for the study. A study with any of the
established bare working directories remains unnumbered, and missing
directories are created in that scheme. A study with numbered directories
uses the numbered scheme. If any numbered and bare working directories coexist
at the root, setup reports a mixed-layout conflict and creates neither form.
An empty existing target adopted as a study uses the numbered scheme.

The package does not query Study Tracker and does not know Azure DevOps. The
command passes the validated structural record into this function.

All package paths resolve taxonomy names through the detected study layout.
For example, the logical `datasets` directory resolves to `00_datasets` in a
new study and `datasets` in a legacy study. A resolver never falls back from a
missing expected directory to the other spelling, because that would create a
split study silently.

`hvtiRtemplates::add_job()` uses the same rule. It replaces the unused
`new_job()` name before study teams adopt the template API; no deprecation
wrapper is needed. The bare-folder behavior remains for legacy studies, while
a numbered study receives new work in its numbered directory. Detecting both
layout forms at one root is an error. This is a required cross-repository
change; setup cannot adopt numbered folders while the job writer still
promises to use bare ones.

## Human-readable study README

After package-owned setup succeeds, `study-setup` creates `README.md` when it
does not already exist. It is the human landing page for the study repository,
while `_study.yml` remains the machine-readable source for identity and data
contracts.

The initial README contains:

- the Study Tracker topic as its title;
- a zero-padded `STNNNN` label linked to the Tracker topic URL, whose
  `topic_id` query value remains unpadded;
- umbrella, owner, IRB number, CVIR number, and creation date;
- an empty protocol-summary section;
- a link to `_study.yml` for the current data contracts; and
- a link to the protocol document when available.

The established Tracker link is:

```text
http://hviresearch.ccf.org/StudyTracker/index.php?page=Topic&topic_id=42
```

When the protocol arrives, a person adds the study objective or research
question, population, primary outcome or endpoint, and the protocol filename
and version or date. Protocol extraction is not automated in this iteration.
The summary is a finding aid; the protocol remains authoritative for study
intent. The README does not copy mutable Tracker activity or workflow status.

Setup, adoption, and recovery never replace an existing README. Recovery first
uses local and Azure DevOps history, then may regenerate only the Tracker
identity portion when no versioned copy exists. A protocol link is relative
when the document is approved for the repository, or uses its approved
SharePoint URL. It is never an absolute SMB or local filesystem path.

## Completing the data contract

The package adds:

```r
register_data(root = getwd(), built, event = NULL, time = NULL,
              dataset = "study", role = c("study", "named"),
              population = NULL, source = NULL,
              extract_date = NULL)
```

The function requires a valid identity manifest and an existing file under
the study's logical `datasets` directory. It reads the data and prepares the
updated `_study.yml` and `manifest.yaml` before replacing either. It never
accepts caller-supplied counts. `event` and `time` must be supplied together.
When supplied, the function checks both variables and derives the three cohort
counts.

`role = "study"` requires the reserved `dataset = "study"` and writes the
top-level default data contract; it also requires `event` and `time`.
`role = "named"` requires a non-reserved,
non-empty lower-snake-case dataset name and writes that entry beneath
`additional_datasets`. A named dataset may omit `event` and `time` when a
cohort contract has no meaning for that file. Requiring the role makes an
accidental attempt to replace the default study cohort fail rather than
quietly changing its meaning. A second registration of the default dataset or
an existing named dataset is refused. Updating registered data is a separate
operation and is not part of this design.

`built_path()`, `built_manifest()`, `read_built()`, `cohort_counts()`,
`assert_cohort()`, and `record_provenance()` gain `dataset = "study"` as their
last argument. Their default and positional behavior is unchanged. Passing a
named dataset selects its registered file and, when present, its own cohort
gate, and records that logical name in provenance. `assert_cohort()` fails with
an actionable missing-contract error when that dataset has `cohort: ~`. An
unknown name fails and lists the registered choices.

`study_init()` is replaced by `study_setup()` followed by `register_data()` and
is removed from the package exports. There is no deprecated wrapper because no
study team has used the function. Current package-development fixtures and
messages are migrated before removal. The validation guarantee from
`study_init()` carries forward: a failed registration writes neither
`_study.yml` nor `manifest.yaml` changes.

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
`_study.yml`, `README.md`, `.Renviron`, `.renvignore`, `.Rprofile`, and
`renv.lock` are eligible to be tracked because their schemas prohibit secrets
and absolute paths.

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
3. create the README when it is absent;
4. initialize or validate `renv`;
5. connect the study repository when `CORR_STUDIES` is available; and
6. print `study_status()`.

Each completed step is safe to observe on a rerun. A later failure does not
delete an earlier valid step. The next status call reports what remains.

These cases are errors with no write:

- the Tracker ID does not resolve to exactly one row;
- the target exists and neither `--status` nor `--adopt` was requested;
- the target is a file rather than a directory;
- the target cannot be written;
- numbered and bare working directories coexist at the study root;
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

Numbered-folder migration is Level 3 for legacy studies. It may rewrite paths
in SAS and R work, so Level 1 adoption does not perform it. New studies begin
with the numbered layout and need no migration.

## Testing

The `qhsprograms` tests use a fake Tracker adapter, temporary directories, and
a local bare Git repository standing in for Azure DevOps. They cover:

- argument parsing and the optional directory;
- exact-one-row Tracker lookup;
- dry run with zero filesystem and network writes;
- new creation and automatic `renv` invocation;
- numbered directories for new studies;
- initial README content, link formatting, and preservation;
- README recovery from history and identity-only regeneration;
- refusal to mutate an existing target without `--adopt`;
- preservation of every existing environment and work file;
- partial `renv` failure followed by a stable status result;
- repository discovery by `st-<id>-` prefix;
- recovery from local and remote history, including a committed deletion;
- Tracker-only identity recovery; and
- every mismatch and ambiguous-repository refusal above.

The `hvtiRutilities` tests cover:

- identity-only, named-only, and default-data-ready manifests;
- backward compatibility with every current manifest fixture;
- the default data-ready failure of `study_config()`;
- identity-only parsing;
- `study_status()` reporting pre-dataset checks as `MISSING`;
- `study_setup()` creation, adoption, preservation, and atomic writes;
- `register_data()` deriving rather than accepting counts;
- identity and default-cohort preservation during named-data registration;
- any number of uniquely named additional datasets;
- rejection of reserved, empty, duplicate, and unknown dataset names;
- named-data registration before or after the default dataset;
- named data with and without a cohort contract;
- dataset selection by every data-contract and provenance helper;
- numbered creation, legacy resolution, and mixed-layout refusal;
- refusal to replace a default or previously registered dataset;
- removal of the `study_init()` export; and
- equivalent all-or-nothing behavior through setup plus registration.

The `hvtiRtemplates` tests cover the `add_job()` name, numbered and bare study
layouts, and refusal to write when both forms of its destination exist. The
rename removes `new_job()` from the public index because there are no adopted
callers to carry through a deprecation period.

The `hvtiRdatabuild` fixtures and messages use the two-stage API. Its tests
prove that analysis-set behavior is unchanged after the caller migration.

The package definition of done remains `devtools::test()` plus
`devtools::check()` at 0 errors, 0 warnings, and 0 notes, with regenerated
documentation and `_pkgdown.yml` entries for new exports.

The production pilot first runs `--dry-run` against a disposable copy of the
designated legacy study. No `.git` or `templates/` directory is removed during
this work.

## Deferred work

`study_checkpoint()` follows this design but is not part of its implementation
plan. A checkpoint will commit `_study.yml`, `README.md`, the environment lock,
source, and other approved reproducibility metadata to the study repository,
while excluding data, results, credentials, and PHI. Natural events include
first abstract submission and first manuscript submission.

Checkpoint-to-Tracker task updates require a separate design. Tracker
transitions are not linear, the current system does not retain the path taken,
and this setup command is deliberately read-only against it.

## Success criteria

1. The active production command set has a reviewed, checksum-verified Azure
   DevOps source without changing production behavior.
2. `study-setup` can create, inspect, adopt, and recover a study by Study
   Tracker ID without copying work templates or writing absolute paths.
3. A study has valid recorded identity before its first built dataset exists.
4. New studies use the numbered directory scheme, while legacy adoption does
   not rename or split existing directories.
5. `register_data()` records one default study dataset and additional named
   datasets without letting one replace the default cohort.
6. Every new study has a brief README linking its Tracker record and leaving a
   stable place for the later protocol summary.
7. Automatic `renv` setup is rerunnable and never replaces an existing
   environment file silently.
8. A missing `_study.yml` tells a person exactly how to attempt recovery, while
   an analysis never performs that recovery implicitly.
9. The legacy-study dry run reports its current mixed state and changes
   nothing.
