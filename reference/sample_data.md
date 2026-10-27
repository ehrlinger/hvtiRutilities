# Generate a sample dataset for testing

Creates a data frame with labeled columns of various types, suitable for
demonstrating
[`r_data_types`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
and
[`label_map`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md).

## Usage

``` r
sample_data(n = 100)
```

## Arguments

- n:

  Number of records to generate. Default `100`.

## Value

A data frame with `n` rows and 7 labeled columns:

- id:

  Integer sequence (Patient Identifier)

- boolean:

  Integer 1/2 (Binary Indicator)

- logical:

  Character "F"/"T" (Logical Status)

- f_real:

  Uniform random values (Random Uniform Value)

- float:

  Normal random values (Random Normal Value)

- char:

  Character "male"/"female" (Gender)

- factor:

  Factor C1-C5 (Category Group)

## Examples

``` r
# Create and inspect labeled data
dta <- sample_data(n = 20)
str(dta)
#> 'data.frame':    20 obs. of  7 variables:
#>  $ id     : int  1 2 3 4 5 6 7 8 9 10 ...
#>   ..- attr(*, "label")= chr "Patient Identifier"
#>  $ boolean: int  1 2 2 1 1 2 2 1 2 2 ...
#>   ..- attr(*, "label")= chr "Binary Indicator"
#>  $ logical: chr  "F" "T" "T" "F" ...
#>   ..- attr(*, "label")= chr "Logical Status"
#>  $ f_real : num  0.7233 0.7431 0.9398 0.0316 0.2384 ...
#>   ..- attr(*, "label")= chr "Random Uniform Value"
#>  $ float  : num  -0.808 -0.557 -1.086 -0.72 -0.693 ...
#>   ..- attr(*, "label")= chr "Random Normal Value"
#>  $ char   : chr  "female" "female" "female" "female" ...
#>   ..- attr(*, "label")= chr "Gender"
#>  $ factor : Factor w/ 5 levels "C1","C2","C3",..: 2 4 3 2 5 5 2 5 2 2 ...
#>   ..- attr(*, "label")= chr "Category Group"
label_map(dta)
#>       key                label           label_full truncated over_cap
#> 1      id   Patient Identifier   Patient Identifier     FALSE    FALSE
#> 2 boolean     Binary Indicator     Binary Indicator     FALSE    FALSE
#> 3 logical       Logical Status       Logical Status     FALSE    FALSE
#> 4  f_real Random Uniform Value Random Uniform Value     FALSE    FALSE
#> 5   float  Random Normal Value  Random Normal Value     FALSE    FALSE
#> 6    char               Gender               Gender     FALSE    FALSE
#> 7  factor       Category Group       Category Group     FALSE    FALSE

# Full workflow: generate, convert types, extract labels
dta <- sample_data(n = 100)
dta_clean <- r_data_types(dta, skip_vars = "id")
lmap <- label_map(dta_clean)
print(lmap)
#>       key                label           label_full truncated over_cap
#> 1      id   Patient Identifier   Patient Identifier     FALSE    FALSE
#> 2 boolean     Binary Indicator     Binary Indicator     FALSE    FALSE
#> 3 logical       Logical Status       Logical Status     FALSE    FALSE
#> 4  f_real Random Uniform Value Random Uniform Value     FALSE    FALSE
#> 5   float  Random Normal Value  Random Normal Value     FALSE    FALSE
#> 6    char               Gender               Gender     FALSE    FALSE
#> 7  factor       Category Group       Category Group     FALSE    FALSE
```
