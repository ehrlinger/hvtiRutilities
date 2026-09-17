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
  adopt = FALSE
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

## Value

An object of class `"study_status"`, returned visibly.

## See also

[`study_status`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md),
[`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md),
[`study_dir`](https://ehrlinger.github.io/hvtiRutilities/reference/study_dir.md)
