# Set up study identity and directories

Creates the numbered directory structure for a new study and writes an
identity-only `_study.yml`. With `adopt = TRUE`, an existing study keeps
its legacy or numbered directory layout and every existing
initialization file.

Data are deliberately not required. Call
[`register_data`](https://ehrlinger.github.io/hvtiRutilities/reference/register_data.md)
after the default or a named dataset exists.

When the root holds no `.Rproj` file, one named for the root directory
is written, so that opening the project and
[`study_root`](https://ehrlinger.github.io/hvtiRutilities/reference/study_root.md)
agree on the study root. An existing project is left unchanged.

With `cleanup = TRUE`, the template copies a legacy study carries are
deleted before anything else reads the study, anywhere in it: every file
whose name starts with `tp.`, every `binder.summaries.doc`, and every
other file whose name and exact content match a file in the template
corpus at `template_dir`. A study's own file that shares a name with a
corpus file but differs from it (an edited `references.bib`, say) is
kept, as are `.renvignore` and `.gitignore`. These files are copied in
when a study is created, months before any analysis, and the corpus they
came from is kept centrally, so no backup is made. A folder the
deletions leave holding nothing (desktop litter such as `Thumbs.db`
aside) is removed, whatever its name, as is an empty `templates` or
`old_RF_templates*` folder; a folder still holding other files stays, as
does one holding any folder the cleanup did not empty, and a top-level
study folder is never removed. Symbolic links are neither followed nor
deleted, and folders named `.git`, `.checkpoint` or `renv` are never
entered, at any depth. The root and `template_dir` must not overlap. A
file that cannot be deleted stops the setup with an error.

With `renv = TRUE`, the study's `renv` environment is set up after any
cleanup, in a separate R process. A complete environment is kept: a
`renv/` folder holding `activate.R`, a `.Rprofile` that sources it, and
a `renv.lock` that parses as a lockfile. One interrupted after
initialization (no lockfile yet) is resumed at the snapshot; any other
partial or invalid environment stops with an error. Otherwise
`renv::init(bare = TRUE)` creates it, and the project is loaded and
snapshotted explicitly. The renv package must be installed.

## Usage

``` r
study_setup(
  root = NULL,
  study,
  study_tracker_id,
  umbrella = NULL,
  owner = NULL,
  irb_number = NULL,
  cvir_no = NULL,
  study_creation_date = NULL,
  adopt = FALSE,
  identity_source = c("tracker", "manual"),
  cleanup = FALSE,
  renv = FALSE,
  template_dir = "/programs/development/template"
)
```

## Arguments

- root:

  Character. Study root to create or adopt. When omitted, the study
  enclosing the working directory (found as
  [`study_root`](https://ehrlinger.github.io/hvtiRutilities/reference/study_root.md)
  finds it) is used, or the working directory itself when no
  `_study.yml` lies above it. An empty working directory is set up as a
  new study.

- study:

  Character(1). Study title.

- study_tracker_id:

  Integer(1). Study Tracker topic ID.

- umbrella, owner, irb_number, cvir_no:

  Optional identity values.

- study_creation_date:

  Optional Study Tracker creation date.

- adopt:

  Logical. Permit additive setup in an existing root. When the root
  already holds a `_study.yml` for the same Study Tracker ID and the
  session is interactive, `study_setup()` asks whether to adopt it
  instead of stopping.

- identity_source:

  Character(1). Where the identity values came from: `"tracker"` (the
  default), for a Study Tracker record, or `"manual"`, for values typed
  by hand while the Tracker was unavailable. A new `_study.yml` records
  it as `identity_source`, with `identity_verified` set to `TRUE` for
  `"tracker"` and `FALSE` for `"manual"`. An existing `_study.yml` is
  not rewritten, so adoption keeps the recorded source.

- cleanup:

  Logical. Delete the study's `tp.*` template copies and
  `binder.summaries.doc`, and remove the template folders they leave
  empty. See Details.

- renv:

  Logical. Initialize and snapshot the study's `renv` environment. See
  Details.

- template_dir:

  Character(1). The template corpus studies were copied from, read when
  `cleanup = TRUE`. Setup stops with an error when it does not exist.

## Value

An object of class `"study_status"`, returned visibly. With
`cleanup = TRUE` it carries a `"cleanup"` attribute, a list of the
`deleted` files and `removed_dirs` folders, relative to the root. With
`renv = TRUE` it carries a `"renv"` attribute, `"initialized"` or
`"retained"`.

## See also

[`study_status`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md),
[`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md),
[`study_dir`](https://ehrlinger.github.io/hvtiRutilities/reference/study_dir.md)
