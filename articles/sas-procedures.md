# PROC CONTENTS and PROC MEANS in R

``` r

if (requireNamespace("hvtiRutilities", quietly = TRUE)) {
  library("hvtiRutilities")
} else {
  pkgload::load_all(export_all = FALSE, helpers = FALSE, quiet = TRUE)
}
#> 
#>  hvtiRutilities 1.0.5 
#>  
#>  Type hvtiRutilities.news() to see new features, changes, and bug fixes. 
#> 
```

## Two Procedures You Already Run

Open a new extract in SAS and you almost certainly run two things before
anything else. `PROC CONTENTS` to see what arrived: how many
observations, how many variables, what each one is called and how it is
stored. Then `PROC MEANS` to see whether the numbers are plausible:
means, ranges, how much is missing.

Neither is a modelling step. They are the sanity check you do before you
trust the file enough to analyse it.
[`proc_contents()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_contents.md)
and
[`proc_means()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md)
are those two habits, kept intact in R.

The point is not that R lacks a way to describe a data frame. It has
several. The point is that you already know what these two tables should
look like, and when the R version prints the same numbers in the same
shape, you can tell at a glance whether the extract is right. A
different summary in a different layout makes you re-learn what “normal”
looks like.

We will use the simulated cardiac surgery cohort that ships with the
package, so every example here runs as written:

``` r

dta <- generate_survival_data(n = 200, seed = 42)
```

## What Arrived? `proc_contents()`

In SAS you would write:

``` sas
proc contents data=cohort;
run;
```

In R:

``` r

pc <- proc_contents(dta)
pc$header
#>   observations variables label
#> 1          200        24  <NA>
```

The header is the block SAS prints at the top: observation count,
variable count, and the dataset label if the file carries one. Our
simulated cohort has no dataset label, so it reports `NA`.

The variables table is the *Alphabetic List of Variables and
Attributes*. Like SAS, it sorts by name by default:

``` r

head(proc_contents(dta)$variables, 6)
#>   num    variable type format                                label     class
#> 1   8         age  Num   <NA>               Age at surgery (years)   numeric
#> 2  10         bmi  Num   <NA>              Body mass index (kg/m2)   numeric
#> 3  20 bypass_time  Num   <NA>    Cardiopulmonary bypass time (min)   numeric
#> 4   1       ccfid Char   <NA>                           Patient ID character
#> 5   5        dead  Num   <NA> Death indicator (1=dead, 0=censored)   integer
#> 6  23    diabetes Char   <NA>                    Diabetes mellitus    factor
#>   n_unique pct_missing
#> 1      165           0
#> 2      123           0
#> 3      100           0
#> 4      200           0
#> 5        2           0
#> 6        2           0
```

Pass `order = "varnum"` for creation order, the equivalent of the SAS
`VARNUM` option:

``` r

head(proc_contents(dta, order = "varnum")$variables, 8)
#>   num    variable type format                                          label
#> 1   1       ccfid Char   <NA>                                     Patient ID
#> 2   2 origin_year  Num   <NA>                 Calendar year for iv_opyrs = 0
#> 3   3    iv_opyrs  Num   <NA> Observation interval (years) since origin_year
#> 4   4     iv_dead  Num   <NA>                Follow-up time to death (years)
#> 5   5        dead  Num   <NA>           Death indicator (1=dead, 0=censored)
#> 6   6        reop  Num   <NA>                      Reoperation (1=yes, 0=no)
#> 7   7     iv_reop  Num   <NA>          Follow-up time to reoperation (years)
#> 8   8         age  Num   <NA>                         Age at surgery (years)
#>       class n_unique pct_missing
#> 1 character      200         0.0
#> 2   integer       21         0.0
#> 3   numeric      183         0.0
#> 4   numeric      184         0.0
#> 5   integer        2         0.0
#> 6   integer        2         0.0
#> 7   numeric       31        83.5
#> 8   numeric      165         0.0
```

Note that `num` always reports creation position, whichever sort you
asked for. Sorting alphabetically does not renumber the variables, so
you can read a name off the alphabetical list and still know where it
sits in the record.

### Reading the Extra Columns

Three columns are not in the SAS output, and they are the reason to run
this in R rather than reading a `PROC CONTENTS` listing:

- **`class`** is the R class, sitting next to the SAS `type`. You want
  both, for reasons covered in the next section.
- **`n_unique`** counts distinct non-missing values. A numeric column
  with two distinct values is a flag someone forgot to declare; a
  character column with 199 distinct values out of 200 rows is an
  identifier, not a category.
- **`pct_missing`** is completeness, and it is often the most useful
  number on the page. In our cohort:

``` r

pcv <- proc_contents(dta)$variables
pcv[pcv$pct_missing > 0, c("variable", "label", "pct_missing")]
#>    variable                                 label pct_missing
#> 12  iv_reop Follow-up time to reoperation (years)        83.5
```

`iv_reop` is 83.5% missing, and that is correct rather than broken: it
is time-to-reoperation, which only exists for the patients who had one.
But you want to *see* that before you put the variable in a model, not
discover it when the model silently drops 167 rows.

### Where the SAS Original Has More

[`proc_contents()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_contents.md)
does not report `Len`, `Pos`, or `Informat`, and it omits the created
and modified timestamps. This is a deliberate omission, not an
oversight.

Reading a `.sas7bdat` through `haven` is lossy. Variable name, label,
`format.sas`, and creation order survive the trip. Storage `LENGTH`,
position within the observation, and informat do not. We could infer a
length from the data, but an inferred value would look authoritative and
would disagree with the source dataset every time its `LENGTH` statement
differed from the default. A missing column is easier to work around
than a wrong one that looks right.

So if you need the storage layout of the original file, read it from
SAS. For everything you actually use `PROC CONTENTS` for day to day, it
is here.

### `Type` Is Two-Valued, and That Hides Things

SAS has two variable types, `Num` and `Char`. R has many. The mapping is
therefore lossy in the honest direction: `character` and `factor` report
`Char`, and everything else, including `logical`, `Date`, and `POSIXct`,
reports `Num`.

A SAS date *is* a number carrying a date format, so this is faithful.
But it means `type` alone cannot tell you a date from a lab value. That
is exactly why `class` sits beside it:

``` r

dates <- data.frame(
  visit = as.Date(c("2024-01-15", "2024-02-20")),
  flag  = c(TRUE, FALSE),
  score = c(2.5, 3.1)
)
proc_contents(dates)$variables[, c("variable", "type", "class")]
#>   variable type   class
#> 1     flag  Num logical
#> 2    score  Num numeric
#> 3    visit  Num    Date
```

Read the two columns together. `type` tells you what SAS would call it;
`class` tells you what R will actually do with it.

One edge case worth knowing before you hit it: for a data frame with
columns but zero rows, a fully filtered cohort say, `pct_missing` is
`NaN` rather than `0`. The proportion of missing values among no values
is undefined, and reporting `0` would claim that nothing is missing. If
you are formatting this column for a report, handle `NaN` explicitly.

## Do the Numbers Look Right? `proc_means()`

The SAS default:

``` sas
proc means data=cohort;
run;
```

gives you N, mean, standard deviation, minimum, and maximum over every
numeric variable. So does the R default:

``` r

proc_means(dta, vars = c("age", "bmi", "gfr_bs"))
#>   variable                         label   n    mean       std  min   max
#> 1      age        Age at surgery (years) 200 44.5890 14.595538  1.0  85.0
#> 2      bmi       Body mass index (kg/m2) 200 26.7885  4.750479 15.0  41.8
#> 3   gfr_bs Baseline eGFR (mL/min/1.73m2) 200 76.1505 19.392901 25.9 120.0
```

Omit `vars` and every numeric column is analysed, matching SAS’s
behaviour when you leave out the `VAR` statement. Ask for specific
statistics and you get them in the order you asked, the same way a
`PROC MEANS` statistic list works:

``` r

proc_means(dta, vars = c("age", "bmi"),
           stats = c("n", "nmiss", "mean", "median", "q1", "q3"))
#>   variable                   label   n nmiss    mean median    q1    q3
#> 1      age  Age at surgery (years) 200     0 44.5890  44.75 35.85 54.50
#> 2      bmi Body mass index (kg/m2) 200     0 26.7885  26.65 23.65 30.15
```

The keywords are SAS keywords: `n`, `nmiss`, `mean`, `std`, `min`,
`max`, `sum`, `range`, `stderr`, `cv`, `median`, `q1`, `q3`, and any
`pNN` for a percentile between 1 and 99.

``` r

proc_means(dta, vars = "bypass_time", stats = c("p5", "p50", "p95"))
#>      variable                             label p5  p50   p95
#> 1 bypass_time Cardiopulmonary bypass time (min) 40 88.5 143.5
```

### Stratifying with `class`

The `CLASS` statement becomes the `class` argument:

``` sas
proc means data=cohort;
  class nyha_class;
  var age;
run;
```

``` r

proc_means(dta, vars = "age", class = "nyha_class",
           stats = c("n", "mean", "std", "median", "q1", "q3"))
#>   nyha_class variable                  label  n     mean      std median   q1
#> 1          I      age Age at surgery (years) 46 44.60870 14.43548  44.75 37.7
#> 2         II      age Age at surgery (years) 70 43.24857 12.87698  43.90 34.1
#> 3        III      age Age at surgery (years) 66 46.09394 16.96583  46.75 35.0
#> 4         IV      age Age at surgery (years) 18 44.23333 12.33651  42.40 32.8
#>     q3
#> 1 52.2
#> 2 51.8
#> 3 56.4
#> 4 53.9
```

Two behaviours here are inherited from SAS on purpose.

Rows with a missing value in any class variable are dropped, which is
what `PROC MEANS` does unless you add `MISSING`. And the class levels
come out in declared order rather than alphabetically, matching SAS’s
default `ORDER=INTERNAL`. That is why NYHA class reads I, II, III, IV
above instead of sorting to I, II, III, IV by luck. Give the function an
ordered factor and your clinical scales stay in clinical sequence.

Rows are ordered by analysis variable first, then by class level, so a
multi-variable request stays readable:

``` r

proc_means(dta, vars = c("age", "bmi"), class = "sex",
           stats = c("n", "mean", "std"))
#>      sex variable                   label   n     mean       std
#> 1 Female      age  Age at surgery (years)  77 45.07143 14.800443
#> 2   Male      age  Age at surgery (years) 123 44.28699 14.518428
#> 3 Female      bmi Body mass index (kg/m2)  77 27.05325  4.889747
#> 4   Male      bmi Body mass index (kg/m2) 123 26.62276  4.673729
```

### The Quartile Trap

This is the one thing in this vignette that will silently change your
numbers, so it gets its own section.

SAS and R do not compute quantiles the same way. There are nine
defensible estimators for a sample quantile; SAS defaults to
`QNTLDEF=5`, and R’s
[`quantile()`](https://rdrr.io/r/stats/quantile.html) defaults to
`type = 7`. They are different estimators, and they disagree.

Watch what happens on four observations:

``` r

x <- c(1, 2, 3, 4)

# SAS QNTLDEF=5, which is what proc_means() uses
quantile(x, c(0.25, 0.5, 0.75), type = 2, names = FALSE)
#> [1] 1.5 2.5 3.5

# R's default
quantile(x, c(0.25, 0.5, 0.75), type = 7, names = FALSE)
#> [1] 1.75 2.50 3.25
```

The first quartile is 1.5 in SAS and 1.75 under R’s default. The median
agrees. That is precisely why the discrepancy hides: you check the
median, it matches, you conclude the port is fine, and the quartiles in
your Table 1 are quietly off.

[`proc_means()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md)
uses `type = 2` throughout, so its `q1`, `q3`, `median`, and any `pNN`
reproduce SAS. On our cohort the gap is small but real:

``` r

proc_means(dta, vars = "age", stats = c("q1", "median", "q3"))
#>   variable                  label    q1 median   q3
#> 1      age Age at surgery (years) 35.85  44.75 54.5

quantile(dta$age, c(0.25, 0.5, 0.75), type = 7, names = FALSE)
#> [1] 35.875 44.750 54.500
```

35.85 against 35.875. Small enough to survive rounding in a manuscript
table, large enough to fail a `PROC COMPARE` against the SAS baseline.
The divergence grows on small and even-numbered samples, which is to say
on subgroups.

If you compute a quantile yourself anywhere else in the analysis, pass
`type = 2` and you will stay consistent with both
[`proc_means()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md)
and the SAS original.

### Logical Columns

R logicals are not
[`is.numeric()`](https://rdrr.io/r/base/numeric.html), so they are left
out of the default variable set. Name one in `vars` and it is coerced to
0/1, which makes `mean` a proportion, as `PROC MEANS` would report for a
0/1 numeric flag:

``` r

flags <- data.frame(complication = c(TRUE, FALSE, TRUE, TRUE, FALSE))
proc_means(flags, vars = "complication", stats = c("n", "mean", "sum"))
#>       variable        label n mean sum
#> 1 complication complication 5  0.6   3
```

## Did the Extract Change? `compare_datasets()`

`PROC CONTENTS` on the old file, `PROC CONTENTS` on the new one, then
read the two listings side by side looking for what moved.
[`compare_datasets()`](https://ehrlinger.github.io/hvtiRutilities/reference/compare_datasets.md)
does the reading for you:

``` r

v1 <- generate_survival_data(n = 100, seed = 1)
v2 <- generate_survival_data(n = 120, seed = 2)

# Pretend the new extract gained a variable and lost one
v2$creatinine <- rnorm(120, 1.1, 0.3)
v2$reop <- NULL

compare_datasets(v1, v2)
#> Dataset Comparison
#>   Rows: 100 -> 120
#>   Columns added:    creatinine 
#>   Columns dropped:  reop
```

It reports four kinds of drift: row count, columns added or dropped,
class changes on shared columns, and label changes on shared columns.
The last one matters more than it sounds. A label that changes from
“Baseline eGFR” to “eGFR at discharge” is the same column name measuring
a different thing, and nothing but the label will tell you.

The full result is a list, so you can act on any piece programmatically:

``` r

diff <- compare_datasets(v1, v2)
diff$cols_added
#> [1] "creatinine"
diff$cols_dropped
#> [1] "reop"
diff$type_changes
#> [1] variable  old_class new_class
#> <0 rows> (or 0-length row.names)
```

This pairs directly with the manifest system described in the [Dataset
Version
Tracking](https://ehrlinger.github.io/hvtiRutilities/articles/dataset-versioning.md)
vignette. The manifest tells you *that* a file changed, by checksum.
[`compare_datasets()`](https://ehrlinger.github.io/hvtiRutilities/reference/compare_datasets.md)
tells you *what* changed inside it.

## Where the R Version Differs

A summary of every place these functions depart from the SAS original,
so you can check the list rather than discover an entry mid-analysis.

| Behaviour | SAS | `hvtiRutilities` |
|----|----|----|
| Quantile estimator | `QNTLDEF=5` | `type = 2`, the same estimator |
| Default `PROC MEANS` statistics | N, Mean, Std Dev, Min, Max | Same five |
| Variables with no `VAR` statement | All numeric | All numeric (logicals excluded unless named) |
| Missing class levels | Dropped unless `MISSING` | Dropped |
| Class level order | `ORDER=INTERNAL` | Factor level order |
| `PROC CONTENTS` sort | Alphabetic by default | `order = "alpha"` by default |
| `Len`, `Pos`, `Informat` | Reported | Omitted, not recoverable through `haven` |
| Created / modified timestamps | Reported | Omitted, not recoverable through `haven` |
| `Type` for dates | `Num` | `Num`, with the R class in `class` |
| `pct_missing` on a zero-row table | n/a | `NaN`, not `0` |

## Checklist

Run
[`proc_contents()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_contents.md)
on every new extract before analysing it, the same way you would run
`PROC CONTENTS`.

Read `pct_missing` before choosing model variables, and confirm that any
high-missing column is missing *by design*.

Read `type` and `class` together; `type` alone cannot distinguish a date
from a number.

Use
[`proc_means()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md)
quartiles rather than a bare
[`quantile()`](https://rdrr.io/r/stats/quantile.html) call, and pass
`type = 2` anywhere else you compute one.

Declare ordered clinical scales as ordered factors so `class` output
keeps its clinical sequence.

Run
[`compare_datasets()`](https://ehrlinger.github.io/hvtiRutilities/reference/compare_datasets.md)
on every re-pull, and check `label_changes`, not just the column counts.

## See Also

- [`?proc_contents`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_contents.md),
  [`?proc_means`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md),
  [`?compare_datasets`](https://ehrlinger.github.io/hvtiRutilities/reference/compare_datasets.md)
- [Dataset Version
  Tracking](https://ehrlinger.github.io/hvtiRutilities/articles/dataset-versioning.md)
  for the manifest system that pairs with
  [`compare_datasets()`](https://ehrlinger.github.io/hvtiRutilities/reference/compare_datasets.md)
- [Data Label Handling Best
  Practices](https://ehrlinger.github.io/hvtiRutilities/articles/data-labels.md)
  for the labels these functions report
- [Reproducible Seeds in R and
  SAS](https://ehrlinger.github.io/hvtiRutilities/articles/reproducible-seeds.md)
  for the other half of keeping an R analysis reconcilable against SAS
