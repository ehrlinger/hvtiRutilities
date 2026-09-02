# Roll a job-file inventory up to studies and prefixes

Answers the question the template roadmap keeps needing: for each job
prefix, which studies have run it and how many jobs each.

## Usage

``` r
job_census(x)

# S3 method for class 'hvti_job_census'
print(x, ...)
```

## Arguments

- x:

  Character roots to sweep – see
  [`job_files`](https://ehrlinger.github.io/hvtiRutilities/reference/job_files.md)
  for what a root must be – or a data frame returned by
  [`job_files`](https://ehrlinger.github.io/hvtiRutilities/reference/job_files.md).
  A data frame missing any of that function's 16 columns is an error,
  not a silently empty census.

- ...:

  Ignored; present for S3 consistency with `print`.

## Value

A data frame of class `hvti_job_census` with one row per
`(study, prefix, folder, is_template, is_template_naming)` and columns
`n_jobs` and `n_files`. `is_template_naming` is `TRUE` when the row's
files use the `template` naming convention (section 4.2) – distinct from
`is_template`, which is strictly the legacy `tp.` marker. The
originating
[`job_files()`](https://ehrlinger.github.io/hvtiRutilities/reference/job_files.md)
rows are attached as the `"files"` attribute, and the rows that could
not be rolled up – those with no study or no prefix – as the
`"not_rolled_up"` attribute.

## Details

Two count columns, deliberately. `n_jobs` counts distinct stems and is
the honest unit – the `.lst`, `.sas` and `.log` of one job are one job,
and an editor backup does not create a second. `n_files` counts rows,
and exists because the hand-count this replaces counted files; keeping
both means the new output can be reconciled against the table that
already drove a decision.

**A template is not a job, by either marker.** `is_template` is strictly
the legacy `tp.` prefix (spec section 4); a file written in the
`template` naming convention (section 4.2, e.g. `03.01-ac.qmd`) is
*also* not a job, but with `is_template = FALSE`. `is_template_naming`
carries that second signal, and the roll-up keys on both, so a
template-convention file never shares a row with a genuine job at the
same `(study, prefix, folder)` – if it did, that row could outlive the
genuine job and still read as an attestation the distinct-studies gate
(a prefix needs a second study running the real job before it is
templatable) would wrongly count.

The
[`job_files()`](https://ehrlinger.github.io/hvtiRutilities/reference/job_files.md)
rows are kept on the result as the `"files"` attribute, so the
accounting – unplaced files, unknown prefixes, misfiled jobs – stays
reachable from the summary rather than being computed and thrown away.

**The roll-up cannot key every row**, and says so rather than shrinking
quietly: a file with no study or no prefix has nothing to group by.
Those rows are attached as the `"not_rolled_up"` attribute and counted
on the first line of the print, because what was dropped is the *union*
of the unplaced and the unparsed and a reader cannot compute a union
from two separate totals.

**Subsetting.** A row subset (`x[i, ]`) keeps both attributes. A
*column* subset (`x[, j]`) drops them while leaving the class in place,
so the result still dispatches to this print method with nothing to
print from; [`print()`](https://rdrr.io/r/base/print.html) detects that
and errors rather than reporting zeros. The printed coverage line
(`"Rolled up N of M files"`) always describes the full original sweep,
even from a row-subset `x`: its totals are fixed as an attribute when
`job_census()` builds `x`, not recomputed from `x$n_files` at print
time.

## See also

[`job_files`](https://ehrlinger.github.io/hvtiRutilities/reference/job_files.md)

## Examples

``` r
d <- file.path(tempdir(), "job-census-example")
dir.create(file.path(d, "alpha", "distributions"), recursive = TRUE)
file.create(file.path(d, "alpha", "distributions", "hz.dead.lst"))
#> [1] TRUE
file.create(file.path(d, "alpha", "distributions", "hz.dead.sas"))
#> [1] TRUE
job_census(d)
#> Jobs by prefix -- distinct studies is the column that says whether a
#> template is unblocked (a prefix at 1 study is blocked).
#> 
#>   prefix distinct_studies n_jobs n_files
#> 1     hz                1      1       2
#> 
#> Templates (tp.), counted separately from jobs: 0 files
#> 
#> Rolled up 2 of 2 files; 0 not attributable to a study or a prefix.
#> 
#> Placement:
#>   placed: 2
#>   nested: 0
#>   unplaced: 0
#> 
#> Unknown prefixes (not in hvti_taxonomy(), not in hvti_non_prefixes()): 0 files
#> 
#> Misfiled (prefix outside its taxonomy folder): 0
#> 
#> Unparsed names (no convention matched): 0
#> 
#> Extensions:
#>   lst: 1
#>   sas: 1
unlink(d, recursive = TRUE)
```
