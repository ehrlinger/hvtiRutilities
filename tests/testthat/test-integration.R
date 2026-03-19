library(testthat)
library(hvtiRutilities)

# Integration tests - workflows combining multiple functions ----

test_that("complete workflow: sample_data -> r_data_types -> label_map", {
  # Generate sample data (now includes labels)
  dta <- sample_data(n = 50)

  # Convert types
  dta_converted <- r_data_types(dta)

  # Extract labels
  label_lookup <- label_map(dta_converted)

  # Verify workflow
  expect_equal(nrow(dta_converted), 50)
  expect_equal(nrow(label_lookup), ncol(dta))
  expect_equal(label_lookup$key, names(dta))
  expect_true("Patient Identifier" %in% label_lookup$label)
  expect_true("Gender" %in% label_lookup$label)
})

test_that("r_data_types then label_map preserves all labels", {
  dta <- data.frame(
    a = c("x", "y", "z"),
    b = c(1, 0, 1),
    c = 1:3,
    stringsAsFactors = FALSE
  )

  labelled::var_label(dta$a) <- "Variable A"
  labelled::var_label(dta$b) <- "Variable B"
  labelled::var_label(dta$c) <- "Variable C"

  # Convert types
  converted <- r_data_types(dta)

  # Check labels preserved
  expect_equal(labelled::var_label(converted$a), "Variable A")
  expect_equal(labelled::var_label(converted$b), "Variable B")
  expect_equal(labelled::var_label(converted$c), "Variable C")

  # Extract label map
  labels <- label_map(converted)

  expect_equal(labels$label[labels$key == "a"], "Variable A")
  expect_equal(labels$label[labels$key == "b"], "Variable B")
  expect_equal(labels$label[labels$key == "c"], "Variable C")
})

test_that("label_map works on both original and converted data", {
  dta <- sample_data(n = 30)

  # Label map on original
  labels_orig <- label_map(dta)

  # Convert and get labels
  converted <- r_data_types(dta)
  labels_conv <- label_map(converted)

  # Should be identical
  expect_equal(labels_orig, labels_conv)
})

test_that("skip_vars maintains label mapping consistency", {
  dta <- data.frame(
    keep = c("a", "b", "c"),
    skip = c(1, 0, 1),
    convert = c("x", "y", "z"),
    stringsAsFactors = FALSE
  )

  labelled::var_label(dta$keep) <- "Keep Label"
  labelled::var_label(dta$skip) <- "Skip Label"
  labelled::var_label(dta$convert) <- "Convert Label"

  converted <- r_data_types(dta, skip_vars = "skip")
  labels <- label_map(converted)

  expect_equal(nrow(labels), 3)
  expect_true("Keep Label" %in% labels$label)
  expect_true("Skip Label" %in% labels$label)
  expect_true("Convert Label" %in% labels$label)
})

test_that("binary_factor workflow maintains consistency", {
  dta <- sample_data(n = 40)

  # Convert with binary_factor = TRUE
  converted_factor <- r_data_types(dta, binary_factor = TRUE)

  # Convert with binary_factor = FALSE
  converted_logical <- r_data_types(dta, binary_factor = FALSE)

  # Different types
  expect_s3_class(converted_factor$boolean, "factor")
  expect_type(converted_logical$boolean, "logical")

  # But same number of rows/columns
  expect_equal(dim(converted_factor), dim(converted_logical))
})

test_that("multiple sequential conversions are idempotent", {
  dta <- sample_data(n = 25)

  # First conversion
  conv1 <- r_data_types(dta)

  # Second conversion on already converted data
  conv2 <- r_data_types(conv1)

  # Values and types must be identical, not just class names
  expect_equal(conv1, conv2)
})

test_that("real-world workflow with messy data", {
  # Simulate messy data from SAS
  messy <- data.frame(
    patient_id = 1:20,
    gender = c("M", "F", "M", "F", "NA", rep(c("M", "F"), 7), "na"),
    treatment = rep(c(1, 2, 3, 4), 5),
    outcome = rep(c(0, 1), 10),
    age_group = rep(c("young", "middle", "old", "NA"), 5),
    score = rnorm(20),
    stringsAsFactors = FALSE
  )

  # Add labels
  labelled::var_label(messy$patient_id) <- "Patient Identifier"
  labelled::var_label(messy$gender) <- "Patient Gender"
  labelled::var_label(messy$treatment) <- "Treatment Group"
  labelled::var_label(messy$outcome) <- "Treatment Outcome (0=Fail, 1=Success)"
  labelled::var_label(messy$age_group) <- "Age Category"
  labelled::var_label(messy$score) <- "Composite Score"

  # Clean and convert
  clean <- r_data_types(messy, factor_size = 5, skip_vars = "patient_id")

  # Verify conversions
  expect_type(clean$patient_id, "integer")  # Skipped
  expect_s3_class(clean$gender, "factor")  # Character with NAs handled
  expect_s3_class(clean$treatment, "factor")  # 4 unique values
  expect_type(clean$outcome, "logical")  # Binary
  expect_s3_class(clean$age_group, "factor")  # Character with NAs
  expect_type(clean$score, "double")  # Continuous

  # Check NA handling
  expect_equal(sum(is.na(clean$gender)), 2)  # "NA" and "na"
  expect_equal(sum(is.na(clean$age_group)), 5)  # "NA" strings

  # Extract labels
  labels <- label_map(clean)

  expect_equal(nrow(labels), 6)
  expect_true(all(c("Patient Identifier", "Patient Gender") %in% labels$label))

  # Verify label matching works
  summary_df <- data.frame(
    variable = c("gender", "treatment", "outcome"),
    stringsAsFactors = FALSE
  )
  summary_df$description <- labels$label[match(summary_df$variable, labels$key)]

  expect_equal(summary_df$description[1], "Patient Gender")
  expect_equal(summary_df$description[2], "Treatment Group")
  expect_equal(summary_df$description[3], "Treatment Outcome (0=Fail, 1=Success)")
})
