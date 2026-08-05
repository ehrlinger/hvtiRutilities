# Summarise numeric variables, in the style of SAS PROC MEANS

Produces the table SAS `PROC MEANS` prints: one row per analysis
variable, one column per requested statistic, in the order requested.

## Usage

``` r
proc_means(
  data,
  vars = NULL,
  class = NULL,
  stats = c("n", "mean", "std", "min", "max")
)
```

## Arguments

- data:

  A data frame, tibble, or similar tabular object.

- vars:

  Character vector of columns to analyse. `NULL` (default) selects every
  numeric column not named in `class`.

- class:

  Character vector of grouping columns, prepended to the result as
  leading columns. Rows with a missing value in any class variable are
  dropped, matching SAS's default.

- stats:

  Character vector of SAS statistic keywords: `"n"`, `"nmiss"`,
  `"mean"`, `"std"`, `"min"`, `"max"`, `"sum"`, `"range"`, `"stderr"`,
  `"cv"`, `"median"`, `"q1"`, `"q3"`, or any `"pNN"` for `NN` between 1
  and 99. Defaults to SAS's own default five.

## Value

A data frame with one row per analysis variable per class combination.
Columns are the `class` variables (when supplied), then `variable`,
`label`, then one column per requested statistic in the order given by
`stats`. Count statistics (`n`, `nmiss`) are integer; all others are
numeric.

## Details

Quantiles use `stats::quantile(type = 2)`, which is the R equivalent of
SAS's default `QNTLDEF=5`. This matters: R's own default is `type = 7`,
a different estimator that disagrees with SAS on the small and
even-numbered samples clinical subgroups produce. For `c(1, 2, 3, 4)`,
the first quartile is `1.5` in SAS and `1.75` under R's default. The
median agrees, which is why the discrepancy hides.

With `vars = NULL` all numeric columns are analysed, matching SAS's
behaviour when the `VAR` statement is omitted. Logical columns are not
[`is.numeric()`](https://rdrr.io/r/base/numeric.html) in R and so are
excluded from that default set; naming one in `vars` coerces it to 0/1,
making `mean` a proportion as `PROC MEANS` would give.

Rows are ordered by analysis variable first, then by class level. A
factor class variable orders by its declared level order rather than
alphabetically, matching SAS's default `ORDER=INTERNAL`; this keeps
ordered clinical scales such as NYHA class in their clinical sequence.

## See also

[`proc_contents`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_contents.md)
for variable metadata.

## Examples

``` r
dta <- generate_survival_data(n = 200, seed = 42)

# SAS default statistics over every numeric variable
head(proc_means(dta))
#>      variable                                          label   n        mean
#> 1 origin_year                 Calendar year for iv_opyrs = 0 200 2008.110000
#> 2    iv_opyrs Observation interval (years) since origin_year 200    7.947450
#> 3     iv_dead                Follow-up time to death (years) 200    4.887950
#> 4        dead           Death indicator (1=dead, 0=censored) 200    0.540000
#> 5        reop                      Reoperation (1=yes, 0=no) 200    0.165000
#> 6     iv_reop          Follow-up time to reoperation (years)  33    1.732727
#>         std     min     max
#> 1 5.8299090 1998.00 2018.00
#> 2 4.0759650    1.06   14.99
#> 3 3.1987862    0.25   13.98
#> 4 0.4996481    0.00    1.00
#> 5 0.3721120    0.00    1.00
#> 6 1.9354171    0.04    9.92

# Named variables and an explicit statistic list
proc_means(dta, vars = c("age", "bmi"),
           stats = c("n", "mean", "median", "p15"))
#>   variable                   label   n    mean median  p15
#> 1      age  Age at surgery (years) 200 44.5890  44.75 29.3
#> 2      bmi Body mass index (kg/m2) 200 26.7885  26.65 21.9
```
