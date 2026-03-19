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
#>  $ boolean: int  2 1 1 1 2 2 1 1 1 1 ...
#>   ..- attr(*, "label")= chr "Binary Indicator"
#>  $ logical: chr  "T" "F" "F" "F" ...
#>   ..- attr(*, "label")= chr "Logical Status"
#>  $ f_real : num  0.8457 0.7837 0.0381 0.9514 0.7837 ...
#>   ..- attr(*, "label")= chr "Random Uniform Value"
#>  $ float  : num  -0.5134 0.1015 -0.0562 -2.4321 -0.6256 ...
#>   ..- attr(*, "label")= chr "Random Normal Value"
#>  $ char   : chr  "female" "female" "male" "female" ...
#>   ..- attr(*, "label")= chr "Gender"
#>  $ factor : Factor w/ 5 levels "C1","C2","C3",..: 2 4 2 4 1 2 3 5 5 5 ...
#>   ..- attr(*, "label")= chr "Category Group"
label_map(dta)
#>             key                label
#> id           id   Patient Identifier
#> boolean boolean     Binary Indicator
#> logical logical       Logical Status
#> f_real   f_real Random Uniform Value
#> float     float  Random Normal Value
#> char       char               Gender
#> factor   factor       Category Group

# Full workflow: generate, convert types, extract labels
dta <- sample_data(n = 100)
dta_clean <- r_data_types(dta, skip_vars = "id")
lmap <- label_map(dta_clean)
print(lmap)
#>             key                label
#> id           id   Patient Identifier
#> boolean boolean     Binary Indicator
#> logical logical       Logical Status
#> f_real   f_real Random Uniform Value
#> float     float  Random Normal Value
#> char       char               Gender
#> factor   factor       Category Group
```
