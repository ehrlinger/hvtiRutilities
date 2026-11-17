# Verify a hand-entered study identity against Study Tracker

Compares the identity typed into `_study.yml` with the study's Study
Tracker record and, when they agree, records it as verified with
[`study_update_identity()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_update_identity.md).
Checkpoints held back for an unverified identity are then delivered by
[`study_checkpoint_push()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_checkpoint_push.md).

## Usage

``` r
study_verify(root = getwd())
```

## Arguments

- root:

  The study root. Defaults to the working directory.

## Value

`TRUE`, invisibly, once the identity is verified. Stops with an error
otherwise.

## Details

Runs the qhsprograms `study-setup --verify` command on the LRI servers,
which reads Study Tracker with the credentials in
`~/.config/study-setup/tracker.env`. Those credentials are loaded into
that command's process only. Verification against Study Tracker is
planned and not yet available to every account; without the credentials
file the function stops and says so.

When the typed identity differs from the record, the differences are
printed. The command offers to replace the typed identity only when it
can ask at a terminal: in R started from a terminal it asks; in RStudio
it cannot, and nothing changes. Correct `_study.yml` to match the record
and call again.

## See also

[`study_update_identity()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_update_identity.md),
[`study_checkpoint_push()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_checkpoint_push.md),
[`study_status()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# On the LRI servers, from inside the study:
study_verify()
} # }
```
