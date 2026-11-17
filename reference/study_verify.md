# Verify a hand-entered study identity against Study Tracker

Compares the identity typed into `_study.yml` with the study's Study
Tracker record and, when they agree, records it as verified with
[`study_update_identity()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_update_identity.md).
Checkpoints held back for an unverified identity are then delivered by
[`study_checkpoint_push()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_checkpoint_push.md).

## Usage

``` r
study_verify(root = getwd(), replace = FALSE)
```

## Arguments

- root:

  The study root. Defaults to the working directory.

- replace:

  `TRUE` to replace a typed identity that differs from the Study Tracker
  record with that record. Defaults to `FALSE`.

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
printed and, by default, nothing changes. Check them, then call again
with `replace = TRUE` to take the Study Tracker record in place of the
typed identity; the differences are printed again first. This works in
RStudio, where the command cannot ask. In R started from a terminal the
command also offers the replacement itself (`[y/N]`, default no).
`replace = TRUE` needs the qhsprograms `study-setup` that has
`--accept-tracker`.

## See also

[`study_update_identity()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_update_identity.md),
[`study_checkpoint_push()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_checkpoint_push.md),
[`study_status()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# On the LRI servers, from inside the study:
study_verify()
# After checking the differences it printed:
study_verify(replace = TRUE)
} # }
```
