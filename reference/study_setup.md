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

## Usage

``` r
study_setup(
  root,
  study,
  study_tracker_id,
  umbrella = NULL,
  owner = NULL,
  irb_number = NULL,
  cvir_no = NULL,
  study_creation_date = NULL,
  adopt = FALSE,
  identity_source = c("tracker", "manual")
)
```

## Arguments

- root:

  Character. Study root to create or adopt.

- study:

  Character(1). Study title.

- study_tracker_id:

  Integer(1). Study Tracker topic ID.

- umbrella, owner, irb_number, cvir_no:

  Optional identity values.

- study_creation_date:

  Optional Study Tracker creation date.

- adopt:

  Logical. Permit additive setup in an existing root.

- identity_source:

  Character(1). Where the identity values came from: `"tracker"` (the
  default), for a Study Tracker record, or `"manual"`, for values typed
  by hand while the Tracker was unavailable. A new `_study.yml` records
  it as `identity_source`, with `identity_verified` set to `TRUE` for
  `"tracker"` and `FALSE` for `"manual"`. An existing `_study.yml` is
  not rewritten, so adoption keeps the recorded source.

## Value

An object of class `"study_status"`, returned visibly.

## See also

[`study_status`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md),
[`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md),
[`study_dir`](https://ehrlinger.github.io/hvtiRutilities/reference/study_dir.md)
