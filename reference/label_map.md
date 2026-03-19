# Build a lookup map of data labels

Extracts variable labels from a labeled dataset and returns them as a
data frame with variable names (keys) and their corresponding labels.
This is particularly useful when working with SAS datasets that include
variable labels, or any dataset labeled with the `labelled` package.

A warning is issued when more than 50% of columns lack descriptive
labels (i.e., the label is identical to the variable name). This
typically indicates the data was imported from a source without labels
(e.g., plain CSV) and labels should be supplied via
[`add_labels`](https://ehrlinger.github.io/hvtiRutilities/reference/add_labels.md)
or a `labels_overrides.yml` file (see
[`apply_label_overrides`](https://ehrlinger.github.io/hvtiRutilities/reference/apply_label_overrides.md)).

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

## See also

[`get_label`](https://ehrlinger.github.io/hvtiRutilities/reference/get_label.md)
for looking up a single label,
[`add_labels`](https://ehrlinger.github.io/hvtiRutilities/reference/add_labels.md)
for registering labels for derived variables,
[`apply_label_overrides`](https://ehrlinger.github.io/hvtiRutilities/reference/apply_label_overrides.md)
for applying study-specific overrides from a YAML file.

## Examples

``` r
# Generate labeled survival data
dta <- generate_survival_data(n = 50, seed = 42)
lmap <- label_map(dta)
head(lmap)
#>                     key                                          label
#> ccfid             ccfid                                     Patient ID
#> origin_year origin_year                 Calendar year for iv_opyrs = 0
#> iv_opyrs       iv_opyrs Observation interval (years) since origin_year
#> iv_dead         iv_dead                Follow-up time to death (years)
#> dead               dead           Death indicator (1=dead, 0=censored)
#> reop               reop                      Reoperation (1=yes, 0=no)

# Use for publication-ready tables
summary_vars <- c("age", "bmi", "hgb_bs")
tbl <- data.frame(
  variable = summary_vars,
  description = lmap$label[match(summary_vars, lmap$key)],
  mean = sapply(dta[summary_vars], mean)
)
print(tbl)
#>        variable                description   mean
#> age         age     Age at surgery (years) 44.464
#> bmi         bmi    Body mass index (kg/m2) 26.792
#> hgb_bs   hgb_bs Baseline hemoglobin (g/dL) 12.856

# With sample data (has labels)
dta <- sample_data(n = 20)
label_map(dta)
#>             key                label
#> id           id   Patient Identifier
#> boolean boolean     Binary Indicator
#> logical logical       Logical Status
#> f_real   f_real Random Uniform Value
#> float     float  Random Normal Value
#> char       char               Gender
#> factor   factor       Category Group
```
