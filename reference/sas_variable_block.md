# Read a variable list out of a SAS job

The SAS jobs this package's callers reproduce specify their variables as
blocks in the `.sas`: a phase name on its own line, then comma-separated
names, terminated by a bare `;`.

Reading them rather than transcribing them is the point. A transcribed
list drifts from the job it claims to reproduce, and nothing catches it.

## Usage

``` r
sas_variable_block(lines, marker, after = NULL, what = "block")
```

## Arguments

- lines:

  Character vector: the `.sas` file, as from
  [`readLines()`](https://rdrr.io/r/base/readLines.html).

- marker:

  Regular expression matching the line that opens the block, e.g.
  `"^\\s*early\\s*$"`.

- after:

  Optional regular expression. When given, the search starts at the
  first line matching it, so a block can be located inside one
  particular macro rather than the first one in the file.

- what:

  Character label for the block, used in error messages.

## Value

A character vector of unique variable names, lowercased, in the order
they appear in the block.

## Details

**Comment handling is the whole difficulty, and getting it wrong is
silent in both directions.** Measured on a real screen
(`bh.dead_s3_JR.sas`):

- Stripping `/*...*/` line by line leaves banner comments intact,
  because `/***** Patient Variables *****/` contains `*` and so does not
  match a `[^*]*` body. The banner text then glues onto the **first**
  name on the next line and that name vanishes: `female`, `afib_pr`,
  `plvidd` and `size` were all lost this way.

- A `/* ... */` spanning two lines is never stripped at all, so a
  commented-**out** variable is read as live: `avet_con` entered a
  screen that way.

Collapsing the block first and stripping lazily handles both, and that
is what this function does.

Three name forms are normalised. `name=value` appears where a job
carries starting or converged estimates; only the name is taken, because
a job's converged values are its answer for its own study and must not
be inherited by a copy of it. `name/I` marks a variable forced into the
model, and the suffix is an option on the name rather than part of it.
Names are lowercased, because SAS variable names are case-insensitive
and
[`read_clinical_data`](https://ehrlinger.github.io/hvtiRutilities/reference/read_clinical_data.md)
lowercases them.

## See also

[`sas_path`](https://ehrlinger.github.io/hvtiRutilities/reference/sas_path.md),
[`covariate_audit`](https://ehrlinger.github.io/hvtiRutilities/reference/covariate_audit.md)

## Examples

``` r
sas <- c("%macro final;", "  early", "    age, ln_age, /* dropped */",
         "    bsa=0.31", "  ;", "%mend;")
sas_variable_block(sas, "^\\s*early\\s*$", after = "^\\s*%macro\\s+final")
#> [1] "age"    "ln_age" "bsa"   
```
