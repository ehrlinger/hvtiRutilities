# Triage a directory of legacy SAS macro files

Applies an ordered rule ladder to every SAS source file in `dir` and
returns one row per macro definition, each carrying a `decision` and the
`evidence` that justifies it.

## Usage

``` r
sas_triage(dir, overrides = NULL)
```

## Arguments

- dir:

  Character. Path to a directory of SAS source files. Use a local clone;
  the canonical library lives on a network volume where file operations
  are slow.

- overrides:

  Character or `NULL`. Path to a `macro_overrides.yaml` recording human
  decisions. Each entry requires `macro`, `canonical_file`, `rationale`,
  `decided_by`, and `decided_on`.

## Value

A `data.frame` with one row per macro definition and columns `file`,
`macro`, `params`, `body_hash`, `line_start`, `line_end`, `visibility`,
`decision`, `rule`, and `evidence`. Rows are sorted by `macro` then
`file`, so the result is deterministic.

## Details

Only the top level of `dir` is scanned; subdirectories are ignored.

Candidate files are selected by excluding known non-source suffixes
(logs, listings, documents, binary data sets, numbered RCS backups)
rather than by matching `.sas`. The library names files with dots as
word separators – `deciles.hazard` and `lm.cprobs` are names, not stems
with extensions – and many macro files carry no extension at all, so a
`.sas`-only pattern silently omits them.

File-level rules, applied first, in order:

1.  `Copy of *` – drop, as a filename-prefix duplicate.

2.  `*.sas~` – drop, as an editor backup superseded by construction.

3.  Fails `.sas_lint()` – drop, citing the specific lint failure.

Definition-level rules, applied per macro name across surviving files:

- **4.** Defined in exactly one file – canonical.

- **5.** Defined in several files, all bodies hashing identically –
  canonical, recording every defining file.

- **6.** Defined in several files with two or more distinct bodies –
  **ambiguous**. No canonical file is chosen.

Rule 6 never auto-resolves. Modification dates and visibility are
attached as evidence for a human, never consumed as a tiebreaker,
because a tool that silently picks a winner launders a coin-flip into a
committed artifact. Filesystem mtime is deliberately never consulted:
the corpus froze in 2019 and lives on a network volume where timestamps
do not survive copies.

Ambiguity is resolved by a human writing an entry into `overrides` and
re-running. This makes the result reproducible and auditable.

## Examples

``` r
d <- tempfile("macros")
dir.create(d)
writeLines(c("%macro hello(x);", "  %put &x;", "%mend hello;"),
           file.path(d, "hello.sas"))
sas_triage(d)
#>        file macro params
#> 1 hello.sas hello      x
#>                                                          body_hash line_start
#> 1 ded3cd363b9234ffbe919780e5848d5bcfcdf6d31fc357561bc2509cdeebfa5e          1
#>   line_end visibility  decision rule     evidence
#> 1        3     public canonical    4 defined once
unlink(d, recursive = TRUE)
```
