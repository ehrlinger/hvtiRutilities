# Install a package a study needs, or say how

Called where a function needs a package the study may not have, such as
arrow for registered data. In the study's active renv project the
packages are declared (see
[`study_declare`](https://ehrlinger.github.io/hvtiRutilities/reference/study_declare.md));
a missing one is installed into the study's library after one question,
when the session is interactive, and recorded in `renv.lock`. Otherwise
the call stops and names `hvtiR::setup()`, which installs everything a
study needs.

Nothing is declared until every package is installed: if the user
declines the install, or it fails, the study's `DESCRIPTION` is left as
it was.

A package that is installed but absent from `renv.lock` is declared and
recorded too, because a restore would not bring it back otherwise.
Recording takes one question, since the snapshot also moves every other
package in the lock to the version in the library. The caller already
has what it needs, so when the package cannot be recorded (the session
is not interactive, the question is declined,
[`guard_snapshot`](https://ehrlinger.github.io/hvtiRutilities/reference/guard_snapshot.md)
refuses, or the snapshot fails) the call warns and carries on. Base
packages, which renv never locks, are left out.

An installed package is never upgraded, whatever its version: moving a
study's package versions is `hvtiR::update()`'s job.

## Usage

``` r
study_need(
  packages,
  root = NULL,
  caller = "study_need",
  note = NULL,
  only_in_renv = FALSE,
  r_upgrade = FALSE
)
```

## Arguments

- packages:

  Character. Package names.

- root:

  Character(1). The study root; by default the study enclosing the
  working directory, if any.

- caller:

  Character(1). The function that needs the packages, named in the
  question and the error.

- note:

  Character(1) or `NULL`. Appended to the error.

- only_in_renv:

  Logical(1). Do nothing outside an active renv study.

- r_upgrade:

  Logical(1). Leave `FALSE`. A `renv.lock` snapshot is refused from an R
  whose major.minor differs from the R the lockfile records (see
  [`guard_snapshot`](https://ehrlinger.github.io/hvtiRutilities/reference/guard_snapshot.md)).
  Set `TRUE` only when you are deliberately moving the study to this
  session's R.

## Value

The names of the packages installed, invisibly.

## Examples

``` r
# Nothing to install, and nothing written, outside a study:
study_need("stats")
```
