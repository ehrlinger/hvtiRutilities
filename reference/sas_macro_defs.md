# Extract every macro definition from a SAS file

Scans a `.sas` file and returns one row for each `%macro`...`%mend` pair
it contains. SAS files in the legacy CORR library are macro
*collections*, not single macros, so a file routinely defines several.

## Usage

``` r
sas_macro_defs(file)
```

## Arguments

- file:

  Character. Path to a `.sas` file.

## Value

A `data.frame` with one row per macro definition and columns `file`,
`macro`, `params`, `body_hash`, `line_start`, and `line_end`. Macro and
parameter names are lowercased.

## Details

Matching is case-insensitive: SAS macro names are case-insensitive and
the legacy corpus mixes `%macro skip;` with `%MACRO MRG;` freely. Nested
definitions are handled by depth counting, so an inner `%mend` does not
terminate an outer macro.

The body hash is a SHA-256 digest of the definition with case folded and
whitespace runs collapsed. Two definitions with the same hash are
semantically identical up to formatting.

An unmatched `%macro` is an error, never a silently truncated body. A
file containing no `%macro` at all is likewise an error.

## Examples

``` r
f <- system.file("extdata", "example_macro.sas", package = "hvtiRutilities")
if (nzchar(f)) sas_macro_defs(f)
```
