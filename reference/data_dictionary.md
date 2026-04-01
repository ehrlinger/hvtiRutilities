# Build a data dictionary from a labeled dataset

Creates a summary data frame describing every variable in a dataset:
name, label, R class, number of unique values, percent missing, and a
compact range or level summary.

This is the single most useful artifact for documenting a clinical
dataset. It can be written directly to CSV or included in a Quarto
document as a table.

## Usage

``` r
data_dictionary(data)
```

## Arguments

- data:

  A data frame, tibble, or similar tabular object.

## Value

A data frame with one row per variable and the following columns:

- variable:

  Column name

- label:

  Descriptive label (falls back to variable name if unlabeled)

- class:

  Primary R class of the column

- n_unique:

  Number of unique non-NA values

- pct_missing:

  Percentage of rows that are `NA` (0-100)

- summary:

  Compact summary: min / median / max for numeric, level counts for
  factor/character, TRUE percentage for logical

## See also

[`label_map`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)
for extracting labels only,
[`r_data_types`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
for automatic type conversion before building the dictionary.

## Examples

``` r
# Quick dictionary from synthetic clinical data
dta <- generate_survival_data(n = 100, seed = 42)
dict <- data_dictionary(dta)
head(dict, 10)
#>                variable                                          label
#> ccfid             ccfid                                     Patient ID
#> origin_year origin_year                 Calendar year for iv_opyrs = 0
#> iv_opyrs       iv_opyrs Observation interval (years) since origin_year
#> iv_dead         iv_dead                Follow-up time to death (years)
#> dead               dead           Death indicator (1=dead, 0=censored)
#> reop               reop                      Reoperation (1=yes, 0=no)
#> iv_reop         iv_reop          Follow-up time to reoperation (years)
#> age                 age                         Age at surgery (years)
#> sex                 sex                                            Sex
#> bmi                 bmi                        Body mass index (kg/m2)
#>                 class n_unique pct_missing
#> ccfid       character      100           0
#> origin_year   integer       21           0
#> iv_opyrs      numeric       95           0
#> iv_dead       numeric       97           0
#> dead          integer        2           0
#> reop          integer        2           0
#> iv_reop       numeric       19          80
#> age           numeric       88           0
#> sex            factor        2           0
#> bmi           numeric       84           0
#>                                                                  summary
#> ccfid       100 levels: PT00001, PT00002, PT00003, PT00004, PT00005, ...
#> origin_year                                           1998 / 2009 / 2018
#> iv_opyrs                                            1.07 / 8.315 / 14.93
#> iv_dead                                             0.46 / 4.665 / 13.97
#> dead                                                           0 / 1 / 1
#> reop                                                           0 / 0 / 1
#> iv_reop                                              0.14 / 1.715 / 5.82
#> age                                                      1 / 46.3 / 79.3
#> sex                                               2 levels: Female, Male
#> bmi                                                    17 / 26.85 / 37.3

# After type conversion
dta_clean <- r_data_types(dta,
  factor_size = 5,
  skip_vars = c("ccfid", "iv_dead", "iv_reop", "iv_opyrs")
)
dict_clean <- data_dictionary(dta_clean)
head(dict_clean, 10)
#>                variable                                          label
#> ccfid             ccfid                                     Patient ID
#> origin_year origin_year                 Calendar year for iv_opyrs = 0
#> iv_opyrs       iv_opyrs Observation interval (years) since origin_year
#> iv_dead         iv_dead                Follow-up time to death (years)
#> dead               dead           Death indicator (1=dead, 0=censored)
#> reop               reop                      Reoperation (1=yes, 0=no)
#> iv_reop         iv_reop          Follow-up time to reoperation (years)
#> age                 age                         Age at surgery (years)
#> sex                 sex                                            Sex
#> bmi                 bmi                        Body mass index (kg/m2)
#>                 class n_unique pct_missing
#> ccfid       character      100           0
#> origin_year   integer       21           0
#> iv_opyrs      numeric       95           0
#> iv_dead       numeric       97           0
#> dead          logical        2           0
#> reop          logical        2           0
#> iv_reop       numeric       19          80
#> age           numeric       88           0
#> sex            factor        2           0
#> bmi           numeric       84           0
#>                                                                  summary
#> ccfid       100 levels: PT00001, PT00002, PT00003, PT00004, PT00005, ...
#> origin_year                                           1998 / 2009 / 2018
#> iv_opyrs                                            1.07 / 8.315 / 14.93
#> iv_dead                                             0.46 / 4.665 / 13.97
#> dead                                                           TRUE: 60%
#> reop                                                           TRUE: 20%
#> iv_reop                                              0.14 / 1.715 / 5.82
#> age                                                      1 / 46.3 / 79.3
#> sex                                               2 levels: Female, Male
#> bmi                                                    17 / 26.85 / 37.3

# Write to CSV for documentation
if (FALSE) { # \dontrun{
write.csv(data_dictionary(dta), "data_dictionary.csv", row.names = FALSE)
} # }
```
