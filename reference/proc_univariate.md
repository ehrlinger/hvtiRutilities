# Summarise and test numeric variables, in the style of SAS PROC UNIVARIATE

Produces the statistics data set SAS `PROC UNIVARIATE` writes with
`OUTPUT OUT=`: one row per analysis variable (per class level), one
column per requested statistic in the order requested, then one column
per `PCTLPTS=` percentile. Beyond
[`proc_means`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md)
it adds weighted and decimal percentiles, `VARDEF=`, and the tests for
location and normality.

## Usage

``` r
proc_univariate(
  data,
  vars = NULL,
  class = NULL,
  stats = c("n", "median", "mean", "std", "cv", "min", "max"),
  weights = NULL,
  pctlpts = NULL,
  pctlpre = "p",
  mu0 = 0,
  vardef = c("df", "n", "wdf", "weight")
)
```

## Arguments

- data:

  A data frame, tibble, or similar tabular object.

- vars:

  Character vector of columns to analyse. `NULL` (default) selects every
  numeric column not named in `class` or `weights`.

- class:

  Character vector of grouping columns, prepended to the result as
  leading columns. Rows with a missing value in any class variable are
  dropped, and levels follow `ORDER=INTERNAL`, as in
  [`proc_means`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md).
  Unlike
  [`proc_means()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md),
  a level whose every weight is missing has no row, as in SAS.

- stats:

  Character vector of SAS statistic keywords: every keyword
  [`proc_means`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md)
  accepts, plus `"stdmean"`, `"t"`, `"probt"`, `"msign"`, `"probm"`,
  `"signrank"`, `"probs"`, `"normal"` and `"probn"`.

- weights:

  Character or `NULL`. Name of a single numeric column of `data` to use
  as an observation weight, SAS `WEIGHT`. Observations whose weight is
  missing are excluded from every statistic except `nobs`, which counts
  them.

- pctlpts:

  Numeric vector of percentile points in `[0, 100]`, decimals allowed,
  or `NULL`. SAS `PCTLPTS=`.

- pctlpre:

  Single string prefixed to the `pctlpts` column names. SAS `PCTLPRE=`.
  The point follows with `.` replaced by `_`, so `2.5` gives `p2_5`.

- mu0:

  Single finite number, the null value for `t`, `msign` and `signrank`.
  SAS `MU0=`.

- vardef:

  The variance divisor: `"df"` (default), `"n"`, `"wdf"` or `"weight"`.
  SAS `VARDEF=`.

## Value

A data frame with one row per analysis variable per class combination.
Columns are the `class` variables (when supplied), then `variable`,
`label`, then one column per `stats` keyword in the order given, then
one column per `pctlpts` point in the order given. `n`, `nmiss` and
`nobs` are integer; all others are numeric.

## Details

**Weighting.** Weights apply as in
[`proc_means`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md),
except that the quantiles are weighted: `median`, `q1`, `q3`, `qrange`,
`pNN` and the `pctlpts` columns. The weighted percentile sorts the
values with their cumulative weights \\S_i\\; the 0th percentile is the
minimum and the 100th the maximum; otherwise, when \\S_i = pW\\ the
result is the mean of \\x_i\\ and \\x\_{i+1}\\, else the first \\x_i\\
with \\S_i \> pW\\. Unweighted quantiles use
`stats::quantile(type = 2)`, SAS's default `PCTLDEF=5`. `mode` stays
unweighted, as in SAS. `stderr` and `stdmean` divide the standard
deviation by the square root of the sum of the weights. A zero or
negative weight is an error; SAS instead treats a negative weight as
zero and still counts the observation.

**VARDEF.** The variance divisor is \\n - 1\\ (`"df"`), \\n\\ (`"n"`),
\\W - 1\\ (`"wdf"`) or \\W\\ (`"weight"`), where \\W\\ is the sum of the
weights (\\n\\ without weights). It changes `var`, `std` and `cv`. Under
`"n"`, `skewness` and `kurtosis` are the moment forms rather than the
adjusted ones.

**Statistics SAS does not compute are NA**, as SAS writes missing:

- `msign`, `probm`, `signrank`, `probs`, `normal`, `probn` when
  `weights` is given;

- `t`, `probt`, `stderr` and `stdmean` when `vardef` is not `"df"`;

- `skewness` and `kurtosis` when `vardef` is `"wdf"` or `"weight"`;

- `normal` and `probn` above 2000 observations, with one warning per
  call: SAS switches to a Kolmogorov D test there, which is not ported;

- `std`, `var`, `cv`, `stderr`, `stdmean`, `t`, `probt` at one
  observation, `skewness` below three and `kurtosis` below four;

- `t`, `probt`, `skewness`, `kurtosis`, `normal`, `probn` when every
  value is equal (`cv` is then `0` unless the mean is zero, where it is
  `NA`);

- `msign`, `probm`, `signrank`, `probs` when no value differs from
  `mu0`;

- `mode` when no value repeats among two or more values.

**Tests.** `t` is Student's t for the mean against `mu0`; `msign` the
sign statistic; `signrank` the Wilcoxon signed rank statistic, with an
exact p-value for 20 or fewer non-zero differences and SAS's t
approximation above that. `normal` is the Shapiro-Wilk \\W\\, from
[`stats::shapiro.test()`](https://rdrr.io/r/stats/shapiro.test.html),
which implements Royston's 1995 algorithm; SAS implements Royston's 1992
one, so `normal` and `probn` agree with SAS to about \\10^{-8}\\, not to
machine precision. At two observations both are `1`, as SAS reports.

## See also

[`proc_means`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md)
for the descriptive statistics alone.

## Examples

``` r
dta <- generate_survival_data(n = 200, seed = 42)

# SAS unistats default statistics over every numeric variable
head(proc_univariate(dta))
#>      variable                                          label   n  median
#> 1 origin_year                 Calendar year for iv_opyrs = 0 200 2008.00
#> 2    iv_opyrs Observation interval (years) since origin_year 200    7.87
#> 3     iv_dead                Follow-up time to death (years) 200    4.10
#> 4        dead           Death indicator (1=dead, 0=censored) 200    1.00
#> 5        reop                      Reoperation (1=yes, 0=no) 200    0.00
#> 6     iv_reop          Follow-up time to reoperation (years)  33    1.29
#>          mean       std          cv     min     max
#> 1 2008.110000 5.8299090   0.2903182 1998.00 2018.00
#> 2    7.947450 4.0759650  51.2864500    1.06   14.99
#> 3    4.887950 3.1987862  65.4422866    0.25   13.98
#> 4    0.540000 0.4996481  92.5274291    0.00    1.00
#> 5    0.165000 0.3721120 225.5224211    0.00    1.00
#> 6    1.732727 1.9354171 111.6977318    0.04    9.92

# Decimal percentiles, as for a bootstrap interval
proc_univariate(dta, vars = "age", stats = "n",
                pctlpts = c(2.5, 50, 97.5))
#>   variable                  label   n  p2_5   p50 p97_5
#> 1      age Age at surgery (years) 200 16.45 44.75 72.45

# Tests for location and normality
proc_univariate(dta, vars = "bmi",
                stats = c("mean", "t", "probt", "normal", "probn"),
                mu0 = 25)
#>   variable                   label    mean        t        probt    normal
#> 1      bmi Body mass index (kg/m2) 26.7885 5.324349 2.722644e-07 0.9954021
#>       probn
#> 1 0.8071198
```
