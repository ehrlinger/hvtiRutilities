# Parse the documentation header of a legacy SAS macro file

Legacy CORR macros carry a structured comment block naming the macro,
its purpose, its documented call signature, and a modification log. This
function extracts those fields. They are used as evidence during human
review of divergent macro redefinitions, and the documented call is a
direct input to the Phase 1 SAS harness.

## Usage

``` r
sas_macro_signature(file)
```

## Arguments

- file:

  Character. Path to a \`.sas\` file.

## Value

A one-row `data.frame` with columns `file`, `macro_name`, `short_desc`,
`created_on`, `modified_on`, and `documented_call`. Absent fields are
`NA_character_`. `macro_name` is lowercased.

## Details

All fields are optional. A file with no header block yields a row of
`NA`s rather than an error, because an undocumented macro is a normal
occurrence in this corpus and not a defect.

When several `MODIFIED BY` lines are present, the **last** date is
returned. Note that this date is advisory evidence only;
[`sas_triage()`](https://ehrlinger.github.io/hvtiRutilities/reference/sas_triage.md)
never uses it to choose between competing macro definitions.

## Examples

``` r
f <- system.file("extdata", "example_macro.sas", package = "hvtiRutilities")
if (nzchar(f)) sas_macro_signature(f)
```
