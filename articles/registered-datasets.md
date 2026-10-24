# Registered Datasets: What an Analyst Needs to Know

Open a study’s `datasets` folder and you will find more files than you
expected. Beside `built.sas7bdat` sit `built_20261021.parquet`,
`built_20261021_r2.parquet`, a `.schema.csv` for each, and the same
again for every other dataset the study reads. It is natural to wonder
which of these your job reads, why the dates in the names do not match
the day someone last registered anything, and whether you are supposed
to tidy them up.

The short answer is that you never have to look at them. Your job names
a dataset, and the package hands it the latest registered version of
that dataset. This vignette explains what is underneath, for the day you
want to know. It is written for the analyst running jobs. The
statistical programmer who builds and registers the data will find the
mechanics, and the checksums behind them, in
[`vignette("dataset-versioning")`](https://ehrlinger.github.io/hvtiRutilities/articles/dataset-versioning.md).

## The worked example

We follow one study through the whole vignette. It reads two datasets,
the study dataset `built` and a second dataset named `builtr`, each
built in SAS. Its `datasets` folder held, among others, these files on
2026-10-23:

    built.sas7bdat                   the SAS file the programmer rebuilds
    built_20261021_r2.parquet        the registered version jobs read
    built_20261021_r2.schema.csv     its column record
    builtr.sas7bdat
    builtr_20261021_r3.parquet       the registered version jobs read
    builtr_20261021_r3.schema.csv
    built_20261007.parquet           earlier versions, kept
    built_20261013.parquet
    ...

and its `manifest.yaml` recorded the `builtr` dataset like this, trimmed
to the lines that matter here:

``` yaml
- file: builtr.sas7bdat
  parquet: builtr_20261021_r3.parquet
  extract_date: '2026-10-21'
  n_rows: 5955
  n_cols: 176
  source_mtime: 2026-10-21 22:20:03.141081
  history:
  - parquet: builtr_20261021_r2.parquet
  - parquet: builtr_20261021.parquet
  - parquet: builtr_20261016.parquet
  - parquet: builtr_20261015.parquet
```

Each `history` entry also carries its own checksums and row and column
counts; they are left out above. Every question below is answered from
this example.

## What Does Registering a Dataset Do?

The SAS file in `datasets` is a working file. The programmer rebuilds it
as often as the build needs, and while they do, nothing you run changes.
A job reads data only once it has been *registered* (accepted as a
version of the dataset that jobs may read).

Registering happens once, with
[`register_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/register_data.md),
when a dataset first joins the study. After that the programmer runs one
call from anywhere in the study:

``` r

hvtiRutilities::update_manifest()
```

For each dataset whose SAS file has changed since its last registration,
that call does three things.

1.  Reads the SAS file and writes it once to a dated parquet file beside
    it, such as `builtr_20261021_r3.parquet`. That parquet is the
    registered version. It is never rewritten afterwards.
2.  Writes the column record beside it, `builtr_20261021_r3.schema.csv`:
    each column’s name, type and SAS label.
3.  Records the new version in `manifest.yaml`: the parquet’s name, its
    SHA-256 checksum (a fingerprint that changes if a single byte of the
    file does), the checksum of the SAS file it came from, its date and
    its row and column counts. The version it replaces moves into the
    entry’s `history`.

It prints one line per dataset saying what it did:

    builtr: registered builtr_20261021_r3.parquet (5955 rows, 176 columns); previous version kept as builtr_20261021_r2.parquet

A dataset whose SAS file has not changed is reported as unchanged, and
no new version is written for it.

## Why Is It Named That Way?

A registered version is named `<name>_<YYYYMMDD>.parquet`, where
`<name>` is the SAS file’s name without its extension. A second version
on the same date gets `_r2`, a third `_r3`, and so on.

**The date is the SAS file’s date, not the day it was registered.**
Specifically, it is the date the SAS file was last written (its
modification date, as a file listing shows it), unless the programmer
gave an `extract_date` when registering. The manifest records no
registration date at all.

That explains the two things people notice in the example.

- `builtr_20261021_r3.parquet` says 10-21 because `builtr.sas7bdat` was
  last written on the evening of 2026-10-21. Had nobody registered it
  until a week later, the name would still say 10-21, and so would every
  date the reports give for it.
- `builtr` reached `_r3` while `built` stopped at `_r2`. Each dataset
  counts its own versions. `builtr.sas7bdat` was rebuilt and registered
  three times with a 2026-10-21 date, `built.sas7bdat` twice.

The `_rN` suffix therefore says how many times that dataset was
registered from a SAS file written on that date. It says nothing about
which version is current; the manifest does that.

## Which File Does My Job Read?

A job names its dataset at the top, in its study choices:

``` r

DATASET <- "builtr"
```

and reads it by that name. `"built"` (or leaving the setting at its
default) is the study dataset. The package looks the name up in
`manifest.yaml` and reads the version recorded there, after checking its
checksum. For the example, that is `builtr_20261021_r3.parquet`.

So a job that reads a dataset reads its latest registered version, with
no file name in your code. When the programmer registers
`builtr_20261028.parquet` next week, your next render reads it, and you
change nothing.

Two kinds of job read something else, and say so in their reports.

- A job that sets `ANALYSIS_SET <- "<name>"` reads that analysis set, a
  subset saved from the study dataset by
  `hvtiRdatabuild::write_analysis_set()`. Registering a new version of
  the study dataset makes the set out of date. A draft render still
  reads the old set, with a note saying so; a final render stops until
  the set is written again from the new version.
- A job that reads another job’s saved results, such as an `-explain`
  job reading what its `-fit` job saved, uses the data that job read.
  Its “About this run” table names that version under `Upstream`.
  Re-render the upstream job first to carry new data through.

That is also why nobody needs to open, copy, rename, move or delete a
parquet file by hand. Every read checks the checksum of the version it
reads, and most jobs run
[`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)
before they read anything, which checks every registered version,
current and earlier. A version that has been moved or edited fails those
checks, and the job stops with a message to restore it and tell the
study’s data manager. Leave the files where the package puts them.

## Which Version Did a Report Use?

Every report rendered from a current job names the version it read in
three places. (A job scaffolded before hvtiRtemplates 1.3.1 renders
without the box and the “About this run” table.)

- **The box under the title.** It reads something like
  `` data `builtr` `builtr_20261021_r3.parquet`, dated 2026-10-21 ``. On
  a working read (`HVTI_DATA=working`, below) it names the SAS file
  instead and adds “working read, not a registered version”. A job that
  sets `ANALYSIS_SET` names the analysis set instead, with the day the
  set was `written` (see below).
- **The data table**, captioned “The data this job read”. Its first row,
  `Source`, names the dataset and the version file,
  `` dataset `builtr` (builtr_20261021_r3.parquet) ``, followed by the
  rows read and kept.
- **The “About this run” table** at the end. Under
  `` Dataset `builtr` `` it lists the version file, its `Version date`,
  the source file it came from, the rows and patients kept, the `WHERE`
  conditions, the first 12 characters of the version’s SHA-256, and a
  `Manifest` row that says `current`, `newer file waiting`, or
  `not in the manifest` (the file read is no registered version).

For a registered dataset, the `dated` date in the box and the
`Version date` row give the version’s date, the one in its file name:
the SAS file’s date, as above. An analysis set’s `written` date is
something else: the day `write_analysis_set()` cut the set, which can be
weeks after the version it was cut from. A set written today from
`built_20260915.parquet` reads `written 2026-10-24`, which says nothing
about how fresh the data are. The same facts, with the full checksum,
are written into the report’s embedded provenance record, so a figure
can be traced back to the exact file months later.

Older reports word two of these differently, and their labels tell them
apart. Their box says `registered 2026-10-21` where a newer one says
`dated`, and their “About this run” table has a `Registered` row where a
newer one has `Version date`. (Go by the labels, not by the
hvtiRtemplates version at the end of the box: the version still read
1.5.0 for a while after the new labels arrived.) That date is the same
version date, not the day the version was registered. Their box is also
written before the job reads anything, so on a working read it still
names the registered version while the `Source` row and “About this run”
name the working SAS file. In such a report, believe the `Source` row
and “About this run”.

## What If the SAS File Changes and Nobody Registers It?

Suppose the programmer rebuilds `builtr.sas7bdat` on 2026-10-24 and does
not run
[`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md).
Your job still reads `builtr_20261021_r3.parquet`. Its results are what
they were, because the data it reads have not changed.

The job tells you a newer file is waiting. The data table ends with a
`Note` row. In it, “registered on” gives the version’s date, the SAS
file’s date, not the day it was registered:

    builtr.sas7bdat has changed since it was registered on 2026-10-21. This job used
    the registered version, builtr_20261021_r3.parquet. Review it with
    hvtiRutilities::review_built(), then run hvtiRutilities::update_manifest() to
    register it.

The `Manifest` row in “About this run” says `newer file waiting`, and
[`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)
lists the SAS file as `PENDING`. None of these stops the job, and none
makes the report a draft. The report is a correct report of the
registered version. Whether the rebuild should become the next version
is the programmer’s call, and the note is your cue to ask.

A report is marked a draft for other reasons: an `EDIT:` marker still in
the job, a skipped chunk, or a `stop_here()`. The box under the title
then reads **draft** and counts them. One more case reads the SAS file
itself rather than a registered version, a *working read*:

``` sh
HVTI_DATA=working quarto render 10_descriptive/table1.qmd
```

A dataset that has never been registered is read this way too, whether
or not you asked. A working read is allowed in the interactive console
and in a draft render of a job in any stage folder. It prints “Results
from it are a draft”, and you should treat the report that way. A final
render (`render_job(final = TRUE)`), a script run with `Rscript`, and a
job at the study root or outside the study refuse it and stop. The
message says to unset `HVTI_DATA` when a registered version exists, and
to register the dataset with
[`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)
when none does.

## Where Do the Older Versions Go?

Every registered version is kept, so a manuscript revision can be
reproduced from the version its paper used. Older releases of the
package keep them all beside the SAS file, which is how the example’s
folder filled up.

From the release that carries hvtiRutilities
[\#243](https://github.com/ehrlinger/hvtiRutilities/pull/243),
[`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)
moves the version it replaces, with its `.schema.csv` and build record,
into `datasets/_archive/`. Only the current version of each dataset sits
beside its SAS file, and Quarto skips `_archive/` as it skips every
folder whose name starts with `_`.

- `manifest.yaml` is unchanged. It still lists every version by name and
  checksum, and
  [`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)
  checks each one, beside the SAS file or in `_archive/`.
- A study registered before that release needs nothing done. Its next
  registration moves every earlier version still beside the SAS file.
- Two kinds of file stay beside the SAS file: a version file that is a
  symbolic link, and one that another registered dataset reads as its
  source. The package still finds them there.
- `_archive/` is the package’s to manage, as the `datasets` folder is.
  Do not move files into it or out of it yourself.
- Verify an archived study with that release or a later one. An older
  [`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)
  looks only beside the SAS file and reports the archived versions as
  missing. Studies pin their hvtiRutilities version through renv, so
  this matters only if analysts on one study run different versions.

## In Short

| You want to | Do this |
|----|----|
| Read the data | Set `DATASET <- "<name>"` in the job; it reads the latest registered version |
| Know which version a report used | Read the box under the title, the data table’s `Source` row, or “About this run” |
| Know whether newer data exist | Look for a `Note` row in the data table, or `newer file waiting` in “About this run” |
| Get newer data into your job | Ask the programmer to review and register it with [`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md), then re-render |
| Tidy the `datasets` folder | Nothing; the package manages it |
