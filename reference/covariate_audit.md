# Audit what would happen to each covariate in a model

Reports, one row per variable, what a column is and what using it as a
model covariate would do to it – so a job can **report** the decision
rather than make it silently.

## Usage

``` r
covariate_audit(data, vars, max_levels = 12L)
```

## Arguments

- data:

  A data frame.

- vars:

  Character vector of covariate names.

- max_levels:

  Integer. Columns with more distinct values than this are treated as
  continuous and their non-integer levels are reported as `NA`.

## Value

A data frame with columns `variable`, `storage`, `n_levels`,
`noninteger_levels` and `action`. `noninteger_levels` reports
`value (rows)` **per level**: per level rather than as a total because
the total cannot distinguish a mean-imputed binary (one such level, in a
minority of rows) from an inverse transformation whose several
non-integer levels are ordinary data. A blank means "no such level";
`NA` means "not looked for". `action` is what
[`covariates_to_numeric`](https://ehrlinger.github.io/hvtiRutilities/reference/covariates_to_numeric.md)
would do, and an `action` beginning `ERROR` marks a variable that must
not be fitted.

## Details

**The problem this exists for.** `vars.sas` is commonly called as
`%vars(missing=1, impute=1)`, which mean-imputes missing values and adds
a paired `ms_*` missing indicator. So a 0/1 clinical variable arrives
carrying three distinct values: 0, 1, and the cohort mean. One real
example: `hx_htn`'s third value is 0.714047, the prevalence of
hypertension, not any patient's hypertension status.

In SAS these columns are numeric and enter a model **linearly**: an
imputed row contributes the mean, and the `ms_*` indicator carries
whatever the missingness itself is worth. That is the design the `.sas`
job specifies.

Read into R they arrive as **factors**. Put a factor in a model formula
and [`model.matrix()`](https://rdrr.io/r/stats/model.matrix.html) builds
dummies from it, which makes "this value was imputed" its own category
with its own coefficient. **That is a different model, with a different
parameter count, and nothing in the output says so.** Multi-level counts
have the same problem for a different reason: a `surg_num` with levels
1, 2, 3, 4 is a number of previous operations, not four unordered
categories.

`max_levels` bounds where an imputed value is looked for at all. On a
**continuous** covariate every value is its own level and most are
non-integers, so an unbounded search returns the whole column.

That bound is also an honest statement of the limit. Mean imputation
*is* detectable in a discrete column, because the mean is not a value
the column can legitimately take. In a continuous column it is invisible
by construction – an imputed mean looks exactly like a measured value –
and the paired `ms_*` indicator is the only record that it happened. So
`NA` in `noninteger_levels` means **"not knowable here"**, not "none".

## See also

[`covariates_to_numeric`](https://ehrlinger.github.io/hvtiRutilities/reference/covariates_to_numeric.md),
[`imputed_levels`](https://ehrlinger.github.io/hvtiRutilities/reference/imputed_levels.md)

## Examples

``` r
d <- data.frame(hx_htn = factor(c("0", "1", "0.714047")),
                age = c(60, 71, 55))
covariate_audit(d, c("hx_htn", "age"))
#>   variable storage n_levels noninteger_levels
#> 1   hx_htn  factor        3      0.714047 (1)
#> 2      age numeric        3                  
#>                               action
#> 1 factor -> numeric, enters linearly
#> 2                    left as numeric
```
