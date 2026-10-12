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
  binary_factor = FALSE,
  use_value_labels = FALSE
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

- use_value_labels:

  Logical. If TRUE, a column carrying value labels – what haven reads
  from a SAS numeric-plus-format variable – is converted through
  [`to_factor`](https://larmarange.github.io/labelled/reference/to_factor.html),
  so the level text is kept. If FALSE the value labels are dropped and
  the numeric codes are converted instead. Default is FALSE, which warns
  once per session; the default becomes TRUE in a later release.

## Value

An object of the same class as `dataset` with columns converted
according to the function's rules. Variable labels are preserved. The
result carries a per-column conversion report, read with
[`type_conversion_report`](https://ehrlinger.github.io/hvtiRutilities/reference/type_conversion_report.md).

## Details

Each column is converted by the first rule that matches, in this order:

1.  When `use_value_labels = TRUE` and the column carries value labels,
    they become the factor levels. This runs ahead of every rule below:
    a declared type is not subject to a threshold on distinct values.

2.  Character strings "NA", "na", "Na" and "nA" become `NA`.

3.  Numeric or integer columns with exactly 2 distinct values become
    logical, or factors when `binary_factor = TRUE`.

4.  Remaining character columns become factors.

5.  Numeric columns with 3 to `factor_size` distinct values become
    factors.

6.  Logical columns become factors when `binary_factor = TRUE`.

Date, POSIXct, and POSIXlt columns are never altered by type conversion.

Which rule fired on which column is recorded on the result and read back
with
[`type_conversion_report`](https://ehrlinger.github.io/hvtiRutilities/reference/type_conversion_report.md).

## See also

[`type_conversion_report`](https://ehrlinger.github.io/hvtiRutilities/reference/type_conversion_report.md)
for the record of which rule fired on which column.

## Examples

``` r
# Basic usage with sample data
dta <- sample_data(n = 100)
str(dta)  # Original types
#> 'data.frame':    100 obs. of  7 variables:
#>  $ id     : int  1 2 3 4 5 6 7 8 9 10 ...
#>   ..- attr(*, "label")= chr "Patient Identifier"
#>  $ boolean: int  2 1 1 1 1 2 1 1 2 2 ...
#>   ..- attr(*, "label")= chr "Binary Indicator"
#>  $ logical: chr  "T" "F" "F" "F" ...
#>   ..- attr(*, "label")= chr "Logical Status"
#>  $ f_real : num  0.572 0.373 0.373 0.356 0.572 ...
#>   ..- attr(*, "label")= chr "Random Uniform Value"
#>  $ float  : num  -0.6179 0.2207 1.1279 1.8135 -0.0838 ...
#>   ..- attr(*, "label")= chr "Random Normal Value"
#>  $ char   : chr  "male" "female" "female" "female" ...
#>   ..- attr(*, "label")= chr "Gender"
#>  $ factor : Factor w/ 5 levels "C1","C2","C3",..: 2 4 5 2 3 3 2 2 4 2 ...
#>   ..- attr(*, "label")= chr "Category Group"
dta_converted <- r_data_types(dta, use_value_labels = FALSE)
str(dta_converted)  # Converted types
#> 'data.frame':    100 obs. of  7 variables:
#>  $ id     : int  1 2 3 4 5 6 7 8 9 10 ...
#>   ..- attr(*, "label")= chr "Patient Identifier"
#>  $ boolean: logi  TRUE TRUE TRUE TRUE TRUE TRUE ...
#>   ..- attr(*, "label")= chr "Binary Indicator"
#>  $ logical: Factor w/ 2 levels "F","T": 2 1 1 1 1 2 1 1 2 2 ...
#>   ..- attr(*, "label")= chr "Logical Status"
#>  $ f_real : Factor w/ 9 levels "0.0729944417253137",..: 6 5 5 4 6 6 9 7 8 2 ...
#>   ..- attr(*, "label")= chr "Random Uniform Value"
#>  $ float  : num  -0.6179 0.2207 1.1279 1.8135 -0.0838 ...
#>   ..- attr(*, "label")= chr "Random Normal Value"
#>  $ char   : Factor w/ 2 levels "female","male": 2 1 1 1 1 1 2 2 2 2 ...
#>   ..- attr(*, "label")= chr "Gender"
#>  $ factor : Factor w/ 5 levels "C1","C2","C3",..: 2 4 5 2 3 3 2 2 4 2 ...
#>   ..- attr(*, "label")= chr "Category Group"
#>  - attr(*, "hvti_type_conversion")='data.frame': 7 obs. of  6 variables:
#>   ..$ variable    : chr [1:7] "id" "boolean" "logical" "f_real" ...
#>   ..$ storage_in  : chr [1:7] "integer" "integer" "character" "numeric" ...
#>   ..$ rule        : chr [1:7] "unchanged" "binary_logical" "character_factor" "n_distinct_factor" ...
#>   ..$ level_source: chr [1:7] NA NA "inference" "inference" ...
#>   ..$ n_levels    : int [1:7] NA NA 2 9 NA 2 5
#>   ..$ storage_out : chr [1:7] "integer" "logical" "factor" "factor" ...

# Real data example with mtcars
str(datasets::mtcars$vs)  # numeric (0/1)
#>  num [1:32] 0 0 1 1 0 1 0 1 1 1 ...
mtcars_converted <- r_data_types(datasets::mtcars,
                                 use_value_labels = FALSE)
str(mtcars_converted$vs)  # logical (FALSE/TRUE)
#>  logi [1:32] FALSE FALSE TRUE TRUE FALSE TRUE ...
#>  - attr(*, "label")= chr "vs"

# Skip specific columns
mtcars_partial <- r_data_types(datasets::mtcars,
                               skip_vars = c("vs", "am"),
                               use_value_labels = FALSE)
str(mtcars_partial$vs)  # Still numeric (unchanged)
#>  num [1:32] 0 0 1 1 0 1 0 1 1 1 ...
#>  - attr(*, "label")= chr "vs"

# Control factor creation threshold
mtcars_strict <- r_data_types(datasets::mtcars, factor_size = 5,
                              use_value_labels = FALSE)

# Keep binary variables as factors
mtcars_factors <- r_data_types(datasets::mtcars, binary_factor = TRUE,
                               use_value_labels = FALSE)
str(mtcars_factors$vs)  # Factor instead of logical
#>  Factor w/ 2 levels "FALSE","TRUE": 1 1 2 2 1 2 1 2 2 2 ...
#>  - attr(*, "label")= chr "vs"

# Keep the level text of a SAS formatted variable
disp <- haven::labelled(c(1, 2, 1, 3),
                        labels = c(Home = 1, Rehab = 2, SNF = 3),
                        label  = "Discharge disposition")
converted <- r_data_types(data.frame(disp = disp), use_value_labels = TRUE)
levels(converted$disp)
#> [1] "Home"  "Rehab" "SNF"  
type_conversion_report(converted)
#>   variable     storage_in         rule level_source n_levels storage_out
#> 1     disp haven_labelled value_labels value labels        3      factor
```
