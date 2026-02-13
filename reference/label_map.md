# Build a lookup map of data labels

Extracts variable labels from a labeled dataset and returns them as a
data frame with variable names (keys) and their corresponding labels.
This is particularly useful when working with SAS datasets that include
variable labels.

## Usage

``` r
label_map(data)
```

## Arguments

- data:

  A data frame, tibble, or similar object with variable labels
  (typically created using the `labelled` package or imported from SAS).

## Value

A data frame with two columns:

- key:

  Character vector of variable names from the input dataset

- label:

  Character vector of variable labels. For unlabeled variables, the
  variable name is used as the label (due to `null_action = "fill"`)

## Examples

``` r
# Create a dataset with labels
library(labelled)
dta <- data.frame(
  age = c(25, 30, 35),
  sex = c("M", "F", "M")
)
var_label(dta$age) <- "Patient Age"
var_label(dta$sex) <- "Patient Sex"

# Build the label map
label_lookup <- label_map(dta)
print(label_lookup)
#>     key       label
#> age age Patient Age
#> sex sex Patient Sex

# Use for matching in summary tables
summary <- data.frame(variable = c("age", "sex"))
summary$description <- label_lookup$label[match(summary$variable, label_lookup$key)]
```
