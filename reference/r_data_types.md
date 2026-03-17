# Automatically infer and convert data types

Intelligently converts column types in a dataset based on their content.
Handles character-to-factor conversion, binary numeric variables, and
various NA representations. Preserves variable labels from SAS/labelled
data.

## Usage

``` r
r_data_types(
  dataset,
  factor_size = 10,
  skip_vars = NULL,
  binary_factor = FALSE
)
```

## Arguments

- dataset:

  A data frame, tibble, data.table, or similar tabular object

- factor_size:

  Integer threshold for factor conversion. Numeric variables with fewer
  than this many unique values (but more than 2) will be converted to
  factors. Must be between 2 and 50. Default is 10.

- skip_vars:

  Character vector of column names to exclude from conversion. These
  columns will remain unchanged. Default is NULL (convert all columns).

- binary_factor:

  Logical. If TRUE, binary variables are converted to factors instead of
  logical. Default is FALSE (convert to logical).

## Value

An object of the same class as `dataset` with columns converted
according to the function's rules. Variable labels are preserved.

## Details

The function applies the following transformations in order:

1.  Converts character strings "NA", "na", "Na", "nA" to actual NA
    values

2.  Converts numeric/integer columns with exactly 2 unique values to
    logical

3.  Converts remaining character columns to factors

4.  Converts numeric columns with 3 to `factor_size` unique values to
    factors

5.  Optionally converts logical columns to factors if
    `binary_factor = TRUE`

Date, POSIXct, and POSIXlt columns are never altered by type conversion.

## Examples

``` r
# Basic usage with sample data
dta <- sample_data(n = 100)
str(dta)  # Original types
#> 'data.frame':    100 obs. of  7 variables:
#>  $ id     : int  1 2 3 4 5 6 7 8 9 10 ...
#>  $ boolean: int  1 1 2 1 1 2 1 1 1 2 ...
#>  $ logical: chr  "F" "F" "T" "F" ...
#>  $ f_real : num  0.508 0.404 0.806 0.418 0.806 ...
#>  $ float  : num  0.118 -0.284 0.498 1.61 1.861 ...
#>  $ char   : chr  "male" "male" "male" "male" ...
#>  $ factor : Factor w/ 5 levels "C1","C2","C3",..: 3 1 5 1 4 3 1 2 1 1 ...
dta_converted <- r_data_types(dta)
str(dta_converted)  # Converted types
#> 'data.frame':    100 obs. of  7 variables:
#>  $ id     : int  1 2 3 4 5 6 7 8 9 10 ...
#>   ..- attr(*, "label")= chr "id"
#>  $ boolean: logi  TRUE TRUE TRUE TRUE TRUE TRUE ...
#>   ..- attr(*, "label")= chr "boolean"
#>  $ logical: Factor w/ 2 levels "F","T": 1 1 2 1 1 2 1 1 1 2 ...
#>   ..- attr(*, "label")= chr "logical"
#>  $ f_real : Factor w/ 9 levels "0.218431008746848",..: 4 2 8 3 8 7 8 8 9 3 ...
#>   ..- attr(*, "label")= chr "f_real"
#>  $ float  : num  0.118 -0.284 0.498 1.61 1.861 ...
#>   ..- attr(*, "label")= chr "float"
#>  $ char   : Factor w/ 2 levels "female","male": 2 2 2 2 1 2 2 1 2 1 ...
#>   ..- attr(*, "label")= chr "char"
#>  $ factor : Factor w/ 5 levels "C1","C2","C3",..: 3 1 5 1 4 3 1 2 1 1 ...
#>   ..- attr(*, "label")= chr "factor"

# Real data example with mtcars
str(datasets::mtcars$vs)  # numeric (0/1)
#>  num [1:32] 0 0 1 1 0 1 0 1 1 1 ...
mtcars_converted <- r_data_types(datasets::mtcars)
str(mtcars_converted$vs)  # logical (FALSE/TRUE)
#>  logi [1:32] FALSE FALSE TRUE TRUE FALSE TRUE ...
#>  - attr(*, "label")= chr "vs"

# Skip specific columns
mtcars_partial <- r_data_types(datasets::mtcars, skip_vars = c("vs", "am"))
str(mtcars_partial$vs)  # Still numeric (unchanged)
#>  num [1:32] 0 0 1 1 0 1 0 1 1 1 ...
#>  - attr(*, "label")= chr "vs"

# Control factor creation threshold
mtcars_strict <- r_data_types(datasets::mtcars, factor_size = 5)

# Keep binary variables as factors
mtcars_factors <- r_data_types(datasets::mtcars, binary_factor = TRUE)
str(mtcars_factors$vs)  # Factor instead of logical
#>  Factor w/ 2 levels "FALSE","TRUE": 1 1 2 2 1 2 1 2 2 2 ...
#>  - attr(*, "label")= chr "vs"
```
