# Read and prepare a clinical dataset in one step

A convenience wrapper that detects the file type, reads the data with
the appropriate reader, and optionally runs
[`r_data_types`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
to convert column types. This saves novice users from having to remember
which package reads which format and ensures labels are preserved.

Supported formats:

- `.sas7bdat`:

  SAS datasets via
  [`haven::read_sas()`](https://haven.tidyverse.org/reference/read_sas.html)

- `.csv`:

  Comma-separated files via
  [`utils::read.csv()`](https://rdrr.io/r/utils/read.table.html) with
  `check.names = FALSE`, so column names are preserved exactly as
  written in the file (spaces, hyphens, and special characters are not
  silently converted to `.`).

- `.xlsx`, `.xls`:

  Excel workbooks via
  [`readxl::read_excel()`](https://readxl.tidyverse.org/reference/read_excel.html)

- `.rds`:

  R serialized objects via
  [`readRDS()`](https://rdrr.io/r/base/readRDS.html)

## Usage

``` r
read_clinical_data(file, convert_types = TRUE, ...)
```

## Arguments

- file:

  Character. Path to the dataset file.

- convert_types:

  Logical. If `TRUE` (default), runs
  [`r_data_types`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  on the result.

- ...:

  Additional arguments passed to
  [`r_data_types`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  (e.g., `factor_size`, `skip_vars`, `binary_factor`). Ignored when
  `convert_types = FALSE`.

## Value

A data frame with labels preserved and (optionally) types converted.

## See also

[`r_data_types`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
for details on type conversion,
[`label_map`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)
to extract labels after reading.

## Examples

``` r
# Read a CSV
tmp <- tempfile(fileext = ".csv")
write.csv(mtcars, tmp, row.names = FALSE)
dta <- read_clinical_data(tmp)
str(dta[, 1:5])
#> 'data.frame':    32 obs. of  5 variables:
#>  $ mpg : num  21 21 22.8 21.4 18.7 18.1 14.3 24.4 22.8 19.2 ...
#>   ..- attr(*, "label")= chr "mpg"
#>  $ cyl : Factor w/ 3 levels "4","6","8": 2 2 1 2 3 2 3 1 1 2 ...
#>   ..- attr(*, "label")= chr "cyl"
#>  $ disp: num  160 160 108 258 360 ...
#>   ..- attr(*, "label")= chr "disp"
#>  $ hp  : int  110 110 93 110 175 105 245 62 95 123 ...
#>   ..- attr(*, "label")= chr "hp"
#>  $ drat: num  3.9 3.9 3.85 3.08 3.15 2.76 3.21 3.69 3.92 3.92 ...
#>   ..- attr(*, "label")= chr "drat"
unlink(tmp)

# Read without type conversion
tmp <- tempfile(fileext = ".csv")
write.csv(mtcars, tmp, row.names = FALSE)
dta_raw <- read_clinical_data(tmp, convert_types = FALSE)
str(dta_raw[, 1:5])
#> 'data.frame':    32 obs. of  5 variables:
#>  $ mpg : num  21 21 22.8 21.4 18.7 18.1 14.3 24.4 22.8 19.2 ...
#>  $ cyl : int  6 6 4 6 8 6 8 4 4 6 ...
#>  $ disp: num  160 160 108 258 360 ...
#>  $ hp  : int  110 110 93 110 175 105 245 62 95 123 ...
#>  $ drat: num  3.9 3.9 3.85 3.08 3.15 2.76 3.21 3.69 3.92 3.92 ...
unlink(tmp)

# Read an RDS file
tmp <- tempfile(fileext = ".rds")
saveRDS(iris, tmp)
dta <- read_clinical_data(tmp, factor_size = 5)
str(dta)
#> 'data.frame':    150 obs. of  5 variables:
#>  $ Sepal.Length: num  5.1 4.9 4.7 4.6 5 5.4 4.6 5 4.4 4.9 ...
#>   ..- attr(*, "label")= chr "Sepal.Length"
#>  $ Sepal.Width : num  3.5 3 3.2 3.1 3.6 3.9 3.4 3.4 2.9 3.1 ...
#>   ..- attr(*, "label")= chr "Sepal.Width"
#>  $ Petal.Length: num  1.4 1.4 1.3 1.5 1.4 1.7 1.4 1.5 1.4 1.5 ...
#>   ..- attr(*, "label")= chr "Petal.Length"
#>  $ Petal.Width : num  0.2 0.2 0.2 0.2 0.2 0.4 0.3 0.2 0.2 0.1 ...
#>   ..- attr(*, "label")= chr "Petal.Width"
#>  $ Species     : Factor w/ 3 levels "setosa","versicolor",..: 1 1 1 1 1 1 1 1 1 1 ...
#>   ..- attr(*, "label")= chr "Species"
unlink(tmp)
```
