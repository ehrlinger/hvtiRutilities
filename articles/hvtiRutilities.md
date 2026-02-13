# Getting Started with hvtiRutilities

## Introduction

The `hvtiRutilities` package provides utility functions for working with
clinical research data at the Cleveland Clinic Heart, Vascular and
Thoracic Institute (HVTI). It simplifies common data preparation tasks
when importing and cleaning datasets, particularly those originating
from SAS.

### Main Functions

- **[`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)**:
  Automatically infer and convert data types based on content
- **[`label_map()`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)**:
  Extract variable labels from labeled datasets into a lookup table
- **[`sample_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/sample_data.md)**:
  Generate sample datasets for testing and examples

### Installation

``` r
# Install from GitHub
# install.packages("pak")
pak::pak("ehrlinger/hvtiRutilities")
```

``` r
library(hvtiRutilities)
#> 
#>  hvtiRutilities 0.1.3 
#>  
#>  Type hvtiRutilities.news() to see new features, changes, and bug fixes. 
#> 
```

## Basic Usage

### Automatic Type Conversion with `r_data_types()`

The
[`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
function intelligently converts column types based on their content:

``` r
# Generate sample data with various types
dta <- sample_data(n = 100)

# Examine original structure
str(dta)
#> 'data.frame':    100 obs. of  7 variables:
#>  $ id     : int  1 2 3 4 5 6 7 8 9 10 ...
#>  $ boolean: int  1 1 2 1 1 2 1 1 1 2 ...
#>  $ logical: chr  "F" "F" "T" "F" ...
#>  $ f_real : num  0.508 0.404 0.806 0.418 0.806 ...
#>  $ float  : num  0.118 -0.284 0.498 1.61 1.861 ...
#>  $ char   : chr  "male" "male" "male" "male" ...
#>  $ factor : Factor w/ 5 levels "C1","C2","C3",..: 3 1 5 1 4 3 1 2 1 1 ...
```

Notice that the sample data has: - `boolean`: integer values (1, 2) -
`logical`: character values (“F”, “T”) - `char`: character values
(“male”, “female”)

Now let’s apply automatic type conversion:

``` r
# Convert types automatically
dta_converted <- r_data_types(dta)

# Examine converted structure
str(dta_converted)
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
```

After conversion: - `boolean`: converted to logical (TRUE/FALSE) because
it has exactly 2 unique values - `logical`: converted to factor
(categorical variable) - `char`: converted to factor (categorical
variable) - Continuous variables (`float`, `f_real`) remain numeric

### Transformation Rules

The function applies transformations in this order:

1.  Character strings “NA”, “na”, “Na”, “nA” → actual `NA` values
2.  Numeric/integer with exactly 2 unique values → `logical`
3.  Character columns → `factor`
4.  Numeric with 3 to `factor_size` unique values → `factor`
5.  Optionally: logical → `factor` (if `binary_factor = TRUE`)

## Working with Real Data

### Example: mtcars Dataset

Let’s apply this to the built-in `mtcars` dataset:

``` r
# Original mtcars
str(mtcars[, 1:5])
#> 'data.frame':    32 obs. of  5 variables:
#>  $ mpg : num  21 21 22.8 21.4 18.7 18.1 14.3 24.4 22.8 19.2 ...
#>  $ cyl : num  6 6 4 6 8 6 8 4 4 6 ...
#>  $ disp: num  160 160 108 258 360 ...
#>  $ hp  : num  110 110 93 110 175 105 245 62 95 123 ...
#>  $ drat: num  3.9 3.9 3.85 3.08 3.15 2.76 3.21 3.69 3.92 3.92 ...
```

``` r
# Apply type conversion
mtcars_clean <- r_data_types(mtcars)
str(mtcars_clean[, 1:5])
#> 'data.frame':    32 obs. of  5 variables:
#>  $ mpg : num  21 21 22.8 21.4 18.7 18.1 14.3 24.4 22.8 19.2 ...
#>   ..- attr(*, "label")= chr "mpg"
#>  $ cyl : Factor w/ 3 levels "4","6","8": 2 2 1 2 3 2 3 1 1 2 ...
#>   ..- attr(*, "label")= chr "cyl"
#>  $ disp: num  160 160 108 258 360 ...
#>   ..- attr(*, "label")= chr "disp"
#>  $ hp  : num  110 110 93 110 175 105 245 62 95 123 ...
#>   ..- attr(*, "label")= chr "hp"
#>  $ drat: num  3.9 3.9 3.85 3.08 3.15 2.76 3.21 3.69 3.92 3.92 ...
#>   ..- attr(*, "label")= chr "drat"
```

Notice: - `cyl` (3 unique values: 4, 6, 8) → factor - `vs` (2 unique
values: 0, 1) → logical - `am` (2 unique values: 0, 1) → logical -
`gear` (3 unique values) → factor - `carb` (6 unique values) → factor

### Controlling Factor Conversion

Use `factor_size` to control when numeric variables become factors:

``` r
# More strict: only convert if < 5 unique values
mtcars_strict <- r_data_types(mtcars, factor_size = 5)

# Check cylinder variable
class(mtcars_clean$cyl)  # factor (3 unique < 10)
#> [1] "factor"
class(mtcars_strict$cyl) # factor (3 unique < 5)
#> [1] "factor"

# Check carb variable
class(mtcars_clean$carb)  # factor (6 unique < 10)
#> [1] "factor"
class(mtcars_strict$carb) # integer (6 unique NOT < 5)
#> [1] "numeric"
```

### Skipping Specific Variables

Sometimes you want to preserve certain variables in their original form:

``` r
# Keep vs and am as numeric instead of converting to logical
mtcars_partial <- r_data_types(mtcars, skip_vars = c("vs", "am"))

# Compare
class(mtcars_clean$vs)    # logical (converted)
#> [1] "logical"
class(mtcars_partial$vs)  # numeric (preserved)
#> [1] "numeric"
```

### Binary Variables as Factors

By default, binary variables become logical. Use `binary_factor = TRUE`
to make them factors instead:

``` r
mtcars_factor <- r_data_types(mtcars, binary_factor = TRUE)

# Compare
class(mtcars_clean$vs)   # logical
#> [1] "logical"
class(mtcars_factor$vs)  # factor
#> [1] "factor"
```

This can be useful for modeling or visualization where factor levels are
preferred.

## Working with Variable Labels

### Creating and Extracting Labels

Variable labels are common in clinical datasets, especially those
imported from SAS. The
[`label_map()`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)
function creates a lookup table:

``` r
library(labelled)

# Create a dataset with labels
patient_data <- data.frame(
  patient_id = 1:5,
  age = c(45, 52, 38, 61, 29),
  sex = c("M", "F", "M", "F", "M"),
  sbp = c(120, 135, 118, 142, 125),
  dbp = c(80, 85, 75, 90, 82),
  stringsAsFactors = FALSE
)

# Add descriptive labels (as would come from SAS)
var_label(patient_data$patient_id) <- "Patient Identifier"
var_label(patient_data$age) <- "Age at Enrollment (years)"
var_label(patient_data$sex) <- "Biological Sex"
var_label(patient_data$sbp) <- "Systolic Blood Pressure (mmHg)"
var_label(patient_data$dbp) <- "Diastolic Blood Pressure (mmHg)"

# Extract labels into a lookup table
labels <- label_map(patient_data)
print(labels)
#>                   key                           label
#> patient_id patient_id              Patient Identifier
#> age               age       Age at Enrollment (years)
#> sex               sex                  Biological Sex
#> sbp               sbp  Systolic Blood Pressure (mmHg)
#> dbp               dbp Diastolic Blood Pressure (mmHg)
```

### Using Labels in Analysis

The label map is useful for creating publication-ready tables and plots:

``` r
# Create a summary statistics table
summary_stats <- data.frame(
  variable = c("age", "sbp", "dbp"),
  mean = c(mean(patient_data$age),
           mean(patient_data$sbp),
           mean(patient_data$dbp)),
  sd = c(sd(patient_data$age),
         sd(patient_data$sbp),
         sd(patient_data$dbp))
)

# Add descriptive labels
summary_stats$description <- labels$label[match(summary_stats$variable, labels$key)]

print(summary_stats)
#>   variable  mean       sd                     description
#> 1      age  45.0 12.34909       Age at Enrollment (years)
#> 2      sbp 128.0 10.22252  Systolic Blood Pressure (mmHg)
#> 3      dbp  82.4  5.59464 Diastolic Blood Pressure (mmHg)
```

### Labels Persist Through Transformations

Labels are preserved when using
[`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md):

``` r
# Convert types
patient_clean <- r_data_types(patient_data, skip_vars = "patient_id")

# Labels are preserved
var_label(patient_clean$age)
#> [1] "Age at Enrollment (years)"
var_label(patient_clean$sex)
#> [1] "Biological Sex"

# Extract labels from converted data
labels_clean <- label_map(patient_clean)
identical(labels, labels_clean)  # TRUE
#> [1] TRUE
```

## Complete Workflow Example

Here’s a complete real-world workflow for preparing clinical data:

``` r
# Step 1: Generate sample clinical data
set.seed(123)
clinical <- data.frame(
  id = 1:50,
  center = sample(c("Site A", "Site B", "Site C"), 50, replace = TRUE),
  treatment = sample(1:4, 50, replace = TRUE),
  age = round(rnorm(50, mean = 55, sd = 12)),
  sex = sample(c("M", "F"), 50, replace = TRUE),
  outcome = sample(0:1, 50, replace = TRUE, prob = c(0.3, 0.7)),
  followup_days = round(runif(50, 30, 730)),
  adverse_event = sample(c("None", "Mild", "Moderate", "Severe", "NA"),
                         50, replace = TRUE),
  stringsAsFactors = FALSE
)

# Step 2: Add variable labels (as from SAS import)
var_label(clinical$id) <- "Patient ID"
var_label(clinical$center) <- "Enrollment Center"
var_label(clinical$treatment) <- "Treatment Arm (1-4)"
var_label(clinical$age) <- "Age at Enrollment (years)"
var_label(clinical$sex) <- "Biological Sex"
var_label(clinical$outcome) <- "Primary Outcome (0=Failure, 1=Success)"
var_label(clinical$followup_days) <- "Days of Follow-up"
var_label(clinical$adverse_event) <- "Most Severe Adverse Event"

# Step 3: Clean and convert types
clinical_clean <- r_data_types(
  clinical,
  factor_size = 5,      # Only convert if < 5 unique values
  skip_vars = "id"      # Keep ID as integer
)

# Step 4: Examine results
str(clinical_clean)
#> 'data.frame':    50 obs. of  8 variables:
#>  $ id           : int  1 2 3 4 5 6 7 8 9 10 ...
#>   ..- attr(*, "label")= chr "Patient ID"
#>  $ center       : Factor w/ 3 levels "Site A","Site B",..: 3 3 3 2 3 2 2 2 3 1 ...
#>   ..- attr(*, "label")= chr "Enrollment Center"
#>  $ treatment    : Factor w/ 4 levels "1","2","3","4": 1 1 4 4 3 1 2 1 1 3 ...
#>   ..- attr(*, "label")= chr "Treatment Arm (1-4)"
#>  $ age          : num  42 49 74 42 75 52 49 46 81 39 ...
#>   ..- attr(*, "label")= chr "Age at Enrollment (years)"
#>  $ sex          : Factor w/ 2 levels "F","M": 1 1 2 2 1 1 1 1 2 1 ...
#>   ..- attr(*, "label")= chr "Biological Sex"
#>  $ outcome      : logi  FALSE FALSE FALSE TRUE FALSE TRUE ...
#>   ..- attr(*, "label")= chr "Primary Outcome (0=Failure, 1=Success)"
#>  $ followup_days: num  375 303 355 529 69 278 592 615 196 278 ...
#>   ..- attr(*, "label")= chr "Days of Follow-up"
#>  $ adverse_event: Factor w/ 4 levels "Mild","Moderate",..: 4 1 NA 3 3 1 3 1 NA 3 ...
#>   ..- attr(*, "label")= chr "Most Severe Adverse Event"

# Step 5: Extract labels for reporting
label_lookup <- label_map(clinical_clean)

# Step 6: Use in analysis
# Count by treatment
table(clinical_clean$treatment)
#> 
#>  1  2  3  4 
#> 15 13 12 10

# Outcome by treatment (using labels)
outcome_summary <- aggregate(
  outcome ~ treatment,
  data = clinical_clean,
  FUN = function(x) c(n = length(x), success = sum(x), rate = mean(x))
)
print(outcome_summary)
#>   treatment  outcome.n outcome.success outcome.rate
#> 1         1 15.0000000       9.0000000    0.6000000
#> 2         2 13.0000000       8.0000000    0.6153846
#> 3         3 12.0000000       9.0000000    0.7500000
#> 4         4 10.0000000       7.0000000    0.7000000
```

### Handling Missing Data

The function automatically handles character NA variants:

``` r
# Data with various NA representations
messy <- data.frame(
  var1 = c("NA", "value1", "na", "value2", "nA"),
  var2 = c("NA", "A", "na", "B", "C"),
  var3 = c(1, 2, NA, 4, 5),
  stringsAsFactors = FALSE
)

clean <- r_data_types(messy)

# Character NAs converted to true NA
sum(is.na(clean$var1))  # 3 NAs
#> [1] 3
levels(clean$var1)       # Only "value1" and "value2"
#> [1] "value1" "value2"

sum(is.na(clean$var2))  # 2 NAs
#> [1] 2
levels(clean$var2)       # "A", "B", "C"
#> [1] "A" "B" "C"
```

## Advanced Usage

### Custom Workflows for Specific Data Types

For datasets with specific requirements:

``` r
# Lab results with reference ranges
labs <- data.frame(
  patient = 1:20,
  test_name = rep(c("Glucose", "HbA1c"), 10),
  value = c(rnorm(10, 100, 15), rnorm(10, 6.5, 1)),
  unit = rep(c("mg/dL", "%"), 10),
  flag = sample(c("Normal", "High", "Low"), 20, replace = TRUE),
  stringsAsFactors = FALSE
)

# Convert with specific settings
labs_clean <- r_data_types(
  labs,
  skip_vars = c("patient", "value"),  # Preserve ID and numeric values
  factor_size = 4                      # Conservative factor conversion
)

str(labs_clean)
#> 'data.frame':    20 obs. of  5 variables:
#>  $ patient  : int  1 2 3 4 5 6 7 8 9 10 ...
#>   ..- attr(*, "label")= chr "patient"
#>  $ test_name: Factor w/ 2 levels "Glucose","HbA1c": 1 2 1 2 1 2 1 2 1 2 ...
#>   ..- attr(*, "label")= chr "test_name"
#>  $ value    : num  85.1 125.1 93.4 89.2 81.5 ...
#>   ..- attr(*, "label")= chr "value"
#>  $ unit     : Factor w/ 2 levels "%","mg/dL": 2 1 2 1 2 1 2 1 2 1 ...
#>   ..- attr(*, "label")= chr "unit"
#>  $ flag     : Factor w/ 3 levels "High","Low","Normal": 1 2 2 3 1 2 3 3 2 1 ...
#>   ..- attr(*, "label")= chr "flag"
```

### Integration with Data Import

Typical workflow when importing from SAS:

``` r
# Read SAS dataset (example - not run)
# library(haven)
# sas_data <- read_sas("path/to/data.sas7bdat")

# Apply type conversion and extract labels
# clean_data <- r_data_types(sas_data, factor_size = 15)
# variable_labels <- label_map(clean_data)

# Save labels for documentation
# write.csv(variable_labels, "data_dictionary.csv", row.names = FALSE)
```

## Best Practices

### When to Use `r_data_types()`

**Use it when:** - Importing data from SAS, SPSS, or other statistical
software - Working with datasets where types aren’t correctly inferred -
You have many categorical variables coded as integers - You need
consistent type handling across multiple datasets

**Skip it when:** - Your data types are already correct - You need very
specific type conversions not covered by the function - Working with
specialized data structures (time series, spatial data, etc.)

### Recommended Settings by Use Case

**Exploratory Analysis:**

``` r
data_clean <- r_data_types(data, factor_size = 10)
```

**Modeling/Regression:**

``` r
data_clean <- r_data_types(data, factor_size = 5, binary_factor = FALSE)
```

**Descriptive Statistics/Tables:**

``` r
data_clean <- r_data_types(data, factor_size = 15, binary_factor = TRUE)
```

### Checking Results

Always verify the conversions make sense:

``` r
# Before
str(original_data)
summary(original_data)

# After
str(clean_data)
summary(clean_data)

# Check specific variables
table(clean_data$categorical_var)
```

## Summary

The `hvtiRutilities` package streamlines data preparation for clinical
research:

- **[`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)**:
  Automatic, intelligent type conversion
- **[`label_map()`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)**:
  Easy extraction of variable labels
- **[`sample_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/sample_data.md)**:
  Generate test data

Key features: - Preserves variable labels through transformations -
Handles multiple NA representations - Flexible control over factor
conversion - Works with data.frames, tibbles, and data.tables

For more information: - Package documentation:
[`?r_data_types`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md),
[`?label_map`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md) -
GitHub: <https://github.com/ehrlinger/hvtiRutilities> - Issues:
<https://github.com/ehrlinger/hvtiRutilities/issues> - Release notes:
Run
[`hvtiRutilities.news()`](https://ehrlinger.github.io/hvtiRutilities/reference/hvtiRutilities.news.md)
in R

## Session Information

``` r
sessionInfo()
#> R version 4.5.2 (2025-10-31)
#> Platform: x86_64-pc-linux-gnu
#> Running under: Ubuntu 24.04.3 LTS
#> 
#> Matrix products: default
#> BLAS:   /usr/lib/x86_64-linux-gnu/openblas-pthread/libblas.so.3 
#> LAPACK: /usr/lib/x86_64-linux-gnu/openblas-pthread/libopenblasp-r0.3.26.so;  LAPACK version 3.12.0
#> 
#> locale:
#>  [1] LC_CTYPE=C.UTF-8       LC_NUMERIC=C           LC_TIME=C.UTF-8       
#>  [4] LC_COLLATE=C.UTF-8     LC_MONETARY=C.UTF-8    LC_MESSAGES=C.UTF-8   
#>  [7] LC_PAPER=C.UTF-8       LC_NAME=C              LC_ADDRESS=C          
#> [10] LC_TELEPHONE=C         LC_MEASUREMENT=C.UTF-8 LC_IDENTIFICATION=C   
#> 
#> time zone: UTC
#> tzcode source: system (glibc)
#> 
#> attached base packages:
#> [1] stats     graphics  grDevices utils     datasets  methods   base     
#> 
#> other attached packages:
#> [1] labelled_2.16.0      hvtiRutilities_0.1.3
#> 
#> loaded via a namespace (and not attached):
#>  [1] vctrs_0.7.1       cli_3.6.5         knitr_1.51        rlang_1.1.7      
#>  [5] xfun_0.56         forcats_1.0.1     haven_2.5.5       generics_0.1.4   
#>  [9] textshaping_1.0.4 jsonlite_2.0.0    glue_1.8.0        htmltools_0.5.9  
#> [13] ragg_1.5.0        sass_0.4.10       hms_1.1.4         rmarkdown_2.30   
#> [17] tibble_3.3.1      evaluate_1.0.5    jquerylib_0.1.4   fastmap_1.2.0    
#> [21] yaml_2.3.12       lifecycle_1.0.5   compiler_4.5.2    dplyr_1.2.0      
#> [25] fs_1.6.6          pkgconfig_2.0.3   systemfonts_1.3.1 digest_0.6.39    
#> [29] R6_2.6.1          tidyselect_1.2.1  pillar_1.11.1     magrittr_2.0.4   
#> [33] bslib_0.10.0      withr_3.0.2       tools_4.5.2       pkgdown_2.2.0    
#> [37] cachem_1.1.0      desc_1.4.3
```
