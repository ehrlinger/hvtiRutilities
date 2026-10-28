# Declare the packages a study needs

Records package names in the study's `DESCRIPTION`, the file renv reads
to build the study's `renv.lock` in explicit mode. Declaring rather than
letting renv scan the code means a stale template copy can never put a
package into the lockfile.

Names are only ever added, and an entry already declared stays as
written, version constraint included. Every other field of the file is
kept. The file is rewritten only when the set changes, and a
`DESCRIPTION` that is not a study project's (no `Type: Project`) is
never edited.

## Usage

``` r
study_declare(packages = character(0), root = NULL)
```

## Arguments

- packages:

  Character. Package names to declare.

- root:

  Character(1). The study root. Defaults to the study that contains the
  working directory, found by its `_study.yml`; outside a study the
  function stops and writes nothing.

## Value

The sorted declared package names, invisibly.

## Examples

``` r
root <- file.path(tempdir(), "declare-example")
dir.create(root, showWarnings = FALSE)
study_declare("arrow", root)
```
