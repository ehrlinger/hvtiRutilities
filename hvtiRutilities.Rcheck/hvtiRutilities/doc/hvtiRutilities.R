## ----setup, include = FALSE---------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>",
  fig.width = 7,
  fig.height = 5
)

## ----eval=FALSE---------------------------------------------------------------
# # Install from GitHub
# # install.packages("pak")
# pak::pak("ehrlinger/hvtiRutilities")

## -----------------------------------------------------------------------------
library(hvtiRutilities)

## -----------------------------------------------------------------------------
# Generate sample data with various types
dta <- sample_data(n = 100)

# Examine original structure
str(dta)

## -----------------------------------------------------------------------------
# Convert types automatically
dta_converted <- r_data_types(dta)

# Examine converted structure
str(dta_converted)

## -----------------------------------------------------------------------------
# Original mtcars
str(mtcars[, 1:5])

## -----------------------------------------------------------------------------
# Apply type conversion
mtcars_clean <- r_data_types(mtcars)
str(mtcars_clean[, 1:5])

## -----------------------------------------------------------------------------
# More strict: only convert if < 5 unique values
mtcars_strict <- r_data_types(mtcars, factor_size = 5)

# Check cylinder variable
class(mtcars_clean$cyl)  # factor (3 unique < 10)
class(mtcars_strict$cyl) # factor (3 unique < 5)

# Check carb variable
class(mtcars_clean$carb)  # factor (6 unique < 10)
class(mtcars_strict$carb) # integer (6 unique NOT < 5)

## -----------------------------------------------------------------------------
# Keep vs and am as numeric instead of converting to logical
mtcars_partial <- r_data_types(mtcars, skip_vars = c("vs", "am"))

# Compare
class(mtcars_clean$vs)    # logical (converted)
class(mtcars_partial$vs)  # numeric (preserved)

## -----------------------------------------------------------------------------
mtcars_factor <- r_data_types(mtcars, binary_factor = TRUE)

# Compare
class(mtcars_clean$vs)   # logical
class(mtcars_factor$vs)  # factor

## -----------------------------------------------------------------------------
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

## -----------------------------------------------------------------------------
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

## -----------------------------------------------------------------------------
# Convert types
patient_clean <- r_data_types(patient_data, skip_vars = "patient_id")

# Labels are preserved
var_label(patient_clean$age)
var_label(patient_clean$sex)

# Extract labels from converted data
labels_clean <- label_map(patient_clean)
identical(labels, labels_clean)  # TRUE

## -----------------------------------------------------------------------------
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

# Step 5: Extract labels for reporting
label_lookup <- label_map(clinical_clean)

# Step 6: Use in analysis
# Count by treatment
table(clinical_clean$treatment)

# Outcome by treatment (using labels)
outcome_summary <- aggregate(
  outcome ~ treatment,
  data = clinical_clean,
  FUN = function(x) c(n = length(x), success = sum(x), rate = mean(x))
)
print(outcome_summary)

## -----------------------------------------------------------------------------
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
levels(clean$var1)       # Only "value1" and "value2"

sum(is.na(clean$var2))  # 2 NAs
levels(clean$var2)       # "A", "B", "C"

## -----------------------------------------------------------------------------
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

## ----eval=FALSE---------------------------------------------------------------
# # Read SAS dataset (example - not run)
# # library(haven)
# # sas_data <- read_sas("path/to/data.sas7bdat")
# 
# # Apply type conversion and extract labels
# # clean_data <- r_data_types(sas_data, factor_size = 15)
# # variable_labels <- label_map(clean_data)
# 
# # Save labels for documentation
# # write.csv(variable_labels, "data_dictionary.csv", row.names = FALSE)

## ----eval=FALSE---------------------------------------------------------------
# data_clean <- r_data_types(data, factor_size = 10)

## ----eval=FALSE---------------------------------------------------------------
# data_clean <- r_data_types(data, factor_size = 5, binary_factor = FALSE)

## ----eval=FALSE---------------------------------------------------------------
# data_clean <- r_data_types(data, factor_size = 15, binary_factor = TRUE)

## ----eval=FALSE---------------------------------------------------------------
# # Before
# str(original_data)
# summary(original_data)
# 
# # After
# str(clean_data)
# summary(clean_data)
# 
# # Check specific variables
# table(clean_data$categorical_var)

## -----------------------------------------------------------------------------
sessionInfo()

