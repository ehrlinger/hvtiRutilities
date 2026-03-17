
# hvtiRutilities

<!-- badges: start -->
  [![CRAN version](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Fehrlinger%2FhvtiRutilities%2Fmain%2FDESCRIPTION&search=Version%3A%20(%5B%5Cd.%5D%2B)&replace=%241&label=package%20version)](https://github.com/ehrlinger/hvtiRutilities/blob/main/DESCRIPTION)

[![Codecov test coverage](https://codecov.io/gh/ehrlinger/hvtiRutilities/graph/badge.svg)](https://app.codecov.io/gh/ehrlinger/hvtiRutilities)

[![active](http://www.repostatus.org/badges/latest/active.svg)](http://www.repostatus.org/badges/latest/active.svg)

[![R-CMD-check](https://github.com/ehrlinger/hvtiRutilities/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/ehrlinger/hvtiRutilities/actions/workflows/R-CMD-check.yaml)

<!-- badges: end -->

## Overview

hvtiRutilities provides utility functions for working with clinical research data at the Cleveland Clinic Heart, Vascular and Thoracic Institute (HVTI) Clinical Outcomes Registries and Research (CORR) department. The package simplifies common data preparation tasks when working with SAS datasets in R.

### Main Functions

- **`r_data_types()`**: Automatically infer and convert data types in a dataset
  - Converts character columns to factors
  - Detects binary numeric variables (0/1) and converts to logical
  - Converts numeric variables with few unique values to factors
  - Handles various NA representations ("NA", "na", etc.)
  - Preserves variable labels from SAS/labelled data

- **`label_map()`**: Extract variable labels from labeled datasets
  - Creates a lookup table mapping variable names to their labels
  - Useful for working with SAS datasets that have variable labels
  - Returns a data frame with `key` (variable name) and `label` columns

- **`sample_data()`**: Generate sample datasets for testing
  - Creates datasets with various column types for testing package functions
  - Useful for examples and unit tests

- **`generate_survival_data()`**: Simulate a cardiac surgery survival cohort
  - Generates realistic patient-level data including demographics, pre-operative labs, cardiac function, and surgical variables
  - Survival times from a Weibull model with clinically-motivated linear predictor (LVEF, age, hemoglobin, NYHA class, eGFR)
  - Includes reoperation outcome and administrative censoring up to 15 years
  - Variable labels attached for compatibility with `haven` and `label_map()`

## Installation

You can install the development version of hvtiRutilities from [GitHub](https://github.com/) with:

``` r
# install.packages("pak")
pak::pak("ehrlinger/hvtiRutilities")
```

## Usage Examples

### Automatic Type Conversion

```r
library(hvtiRutilities)

# Create sample data
dta <- sample_data(n = 100)

# Examine original types
str(dta)
# boolean: int (values: 1, 2)
# logical: chr (values: "F", "T")
# char: chr (values: "male", "female")

# Apply automatic type conversion
dta_converted <- r_data_types(dta)

# Examine converted types
str(dta_converted)
# boolean: logi (binary 1/2 → TRUE/FALSE)
# logical: Factor (character → factor)
# char: Factor (character → factor)
```

### Skip Specific Columns

```r
# Skip conversion for specific variables
dta_partial <- r_data_types(dta, skip_vars = c("boolean", "char"))
# boolean and char remain unchanged, others are converted
```

### Control Factor Creation

```r
# Convert only variables with fewer than 5 unique values to factors
dta_strict <- r_data_types(dta, factor_size = 5)

# Keep binary variables as factors instead of logical
dta_factors <- r_data_types(dta, binary_factor = TRUE)
```

### Working with Variable Labels

```r
# Create labeled data (common with SAS imports)
library(labelled)
dta <- data.frame(
  age = c(25, 30, 35),
  sex = c("M", "F", "M"),
  bp = c(120, 130, 125)
)
var_label(dta$age) <- "Patient Age (years)"
var_label(dta$sex) <- "Patient Sex"
var_label(dta$bp) <- "Systolic Blood Pressure (mmHg)"

# Extract labels as a lookup table
labels <- label_map(dta)
print(labels)
#   key                              label
# 1 age        Patient Age (years)
# 2 sex                    Patient Sex
# 3  bp  Systolic Blood Pressure (mmHg)

# Use for matching/joining
summary_table <- data.frame(variable = c("age", "bp"))
summary_table$label <- labels$label[match(summary_table$variable, labels$key)]
```

### Generating Survival Data

```r
# Simulate a cardiac surgery cohort (reproducible)
dta <- generate_survival_data(n = 500, seed = 1024)

# Event and reoperation rates
mean(dta$dead)   # ~death rate
mean(dta$reop)   # ~reoperation rate

# Integrate with the rest of the package
model_data <- r_data_types(
  dta,
  factor_size = 5,
  skip_vars = c("ccfid", "iv_dead", "iv_reop")
)

# Extract variable labels for reporting
lmap <- label_map(model_data)
```

## Key Features

- **Preserves variable labels**: All functions maintain SAS/labelled variable attributes
- **Handles NA variants**: Automatically converts "NA", "na", "Na", "nA" strings to actual NA values
- **Type-safe**: Returns the same data structure class as input (data.frame, tibble, data.table, etc.)
- **Flexible control**: Multiple parameters to customize type conversion behavior

## Getting Help

- Package documentation: `?r_data_types`, `?label_map`, `?generate_survival_data`
- Vignettes: `vignette("hvtiRutilities")`, `vignette("survival-data")`
- For bug reports and feature requests: [GitHub Issues](https://github.com/ehrlinger/hvtiRutilities/issues)
- For package news and changes: Run `hvtiRutilities.news()` in R

## License

GPL (>= 3)
