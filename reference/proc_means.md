# Summarise numeric variables, in the style of SAS PROC MEANS

Produces the table SAS `PROC MEANS` prints: one row per analysis
variable, one column per requested statistic, in the order requested.

## Usage

``` r
proc_means(
  data,
  vars = NULL,
  class = NULL,
  stats = c("n", "mean", "std", "min", "max"),
  weights = NULL
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

  Character vector of SAS statistic keywords. Counts: `"n"`, `"nmiss"`,
  `"nobs"`, `"sumwgt"`. Location: `"mean"`, `"median"`, `"mode"`.
  Spread: `"std"`, `"var"`, `"stderr"`, `"cv"`, `"min"`, `"max"`,
  `"range"`, `"qrange"`, `"q1"`, `"q3"`, or any `"pNN"` for NN from 1
  to 99. Sums: `"sum"`, `"uss"`, `"css"`. Shape: `"skewness"`,
  `"kurtosis"`.

- weights:

  Character or `NULL`. Name of a single numeric column of `data` to use
  as an observation weight, mirroring the SAS `WEIGHT` statement.
  Observations whose weight is missing are excluded. A zero or negative
  weight is an error naming the offending rows: SAS's own handling of
  non-positive weights varies across procedures and versions, so this
  fails loudly rather than encode a guess.

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

Weights do not apply uniformly, and this follows `PROC MEANS` rather
than being a simplification. Weighted: `mean`, `std`, `var`, `cv`,
`stderr`, `sum`, `uss`, `css`, `skewness`, `kurtosis`, `sumwgt`.
Unweighted: `n`, `nmiss`, `nobs`, `min`, `max`, `range`, `mode`, and
every quantile – `median`, `q1`, `q3`, `pNN` and `qrange`. `PROC MEANS`
does not compute weighted quantiles at all; that is `PROC UNIVARIATE`.
So `proc_means(d, stats = "median", weights = "wt")` returns the
*unweighted* median.

`mode` returns the smallest value among tied modes, and `NA` when no
value repeats, both matching SAS. `skewness` and `kurtosis` are the
adjusted Fisher-Pearson forms SAS uses, not R's naive moment ratios, and
are `NA` for a constant column rather than `NaN`.

The `PROC UNIVARIATE` inference statistics (`NORMAL`, `PROBN`, `T`,
`PROBT`, `MSIGN`, `PROBM`, `SIGNRANK`, `PROBS`) are deliberately absent:
they would make this a hypothesis-testing function rather than a summary
one. `CLM`, the confidence limits of the mean, is absent for the same
reason.

`cv` is `NA` when the mean is zero, matching SAS; R's arithmetic would
give `Inf`.

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

# Weighted statistics
dta <- data.frame(age = c(51, 63, 47, 72), wt = c(1, 2, 1, 4))
proc_means(dta, vars = "age", stats = c("n", "sumwgt", "mean"),
           weights = "wt")
#>   variable label n sumwgt mean
#> 1      age   age 4      8   64
```
