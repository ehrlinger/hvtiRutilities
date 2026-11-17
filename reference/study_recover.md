# Recover a missing `_study.yml` from CORR_STUDIES

Restores a study's `_study.yml`, and a missing `README.md`, from the
study's repository in the CORR_STUDIES project.

## Usage

``` r
study_recover(st_id = NULL, root = getwd(), yes = FALSE)
```

## Arguments

- st_id:

  The Study Tracker ID, a whole number. Leave it `NULL` when the command
  can infer it from the study's repository.

- root:

  The study root. Defaults to the working directory.

- yes:

  `TRUE` to restore without asking. Defaults to `FALSE`.

## Value

`TRUE`, invisibly, once the files are restored; `FALSE`, invisibly, when
the restore is declined. Stops with an error otherwise.

## Details

Runs the qhsprograms `study-setup --recover` command on the LRI servers.
It first runs a dry run that prints what it would restore, then writes
only with consent: `yes = TRUE`, or a yes to the question it asks in an
interactive session. A non-interactive call without `yes = TRUE` stops
after the dry run and writes nothing. Recovery from CORR_STUDIES is
planned and not yet available; until it is, the command stops with its
reason.

## See also

[`study_config()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md),
[`study_status()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# On the LRI servers, from inside the study:
study_recover()
study_recover(42)
} # }
```
