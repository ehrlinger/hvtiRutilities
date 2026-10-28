# Targeted prints of matching rows, in the style of SAS PROC PRINT with WHERE

Counts the rows that match each of a set of named conditions, and prints
the matching rows to the console. It is the checking step a programmer
runs after a build: write the build, cross-tab, spot a discrepancy,
print the rows that look wrong. One call takes several conditions, as
several SAS `PROC PRINT; WHERE` steps would.

## Usage

``` r
proc_print(data, where, var = NULL, max_rows = 25L)
```

## Arguments

- data:

  A data frame.

- where:

  A list of conditions, each `condition ~ "Label"` with a single
  non-empty quoted label, or one such formula. Labels must be unique.

- var:

  Character or `NULL`. Columns to print for the matching rows, SAS
  `VAR`. `NULL` prints every column.

- max_rows:

  A single positive whole number. At most this many matching rows are
  printed per condition; the count is always the full count.

## Value

A data frame with one row per condition and the columns `label`, `n`
(rows matching) and `n_missing` (rows for which the condition was `NA`).
Both counts are integer. The matching rows are written to
[`stderr()`](https://rdrr.io/r/base/showConnections.html) as a side
effect and are not part of the result.

## Details

**Matching rows go to the console, and only counts reach a report.** A
targeted print shows patient rows, and a rendered report gets shared. So
the rows are written to
[`stderr()`](https://rdrr.io/r/base/showConnections.html), which knitr
and Quarto do not capture: an interactive session shows them, and a
render leaves them out of the HTML whatever the chunk's `message` or
`warning` options say. What the function returns, and what a report
prints, is one count per condition. This is where it differs from SAS,
whose `PROC PRINT` output is the listing.

Each condition is written `condition ~ "Label"`, the shape of a `bd`
job's `EXCLUDE` rules, and is evaluated with the columns of `data` in
scope, then the formula's environment. A condition that evaluates to
`NA` for a row does not match it; those rows are counted in `n_missing`,
so a check that cannot be decided for some patients says so instead of
reading as clean. A condition that fails is an error naming its label.
The error does not repeat R's own message, which can quote a data value.
Warnings and messages raised while a condition is evaluated (a date
parser listing the value it could not read, say) go to
[`stderr()`](https://rdrr.io/r/base/showConnections.html) with the rows,
for the same reason.

## See also

[`proc_freq`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_freq.md),
[`followup_check`](https://ehrlinger.github.io/hvtiRutilities/reference/followup_check.md)

## Examples

``` r
dta <- generate_survival_data(n = 200, seed = 42)

# proc print; where age > 80; var age dead;
proc_print(dta,
  where = list(age > 80 ~ "Older than 80",
               dead == 1 & iv_dead < 1 ~ "Death in the first year"),
  var = c("age", "dead", "iv_dead"))
#>                     label n n_missing
#> 1           Older than 80 1         0
#> 2 Death in the first year 5         0
```
