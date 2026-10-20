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

An installed package is never upgraded, whatever its version: moving a
study's package versions is `hvtiR::update()`'s job.

## Usage

``` r
study_need(
  packages,
  root = NULL,
  caller = "study_need",
  note = NULL,
  only_in_renv = FALSE
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

## Value

The names of the packages installed, invisibly.

## Examples

``` r
# Nothing to install, and nothing written, outside a study:
study_need("stats")
```
