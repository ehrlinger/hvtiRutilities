library(testthat)
library(hvtiRutilities)

# CSV reading ----

test_that("read_clinical_data reads CSV files", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  write.csv(iris, tmp, row.names = FALSE)

  result <- read_clinical_data(tmp, convert_types = FALSE)

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 150)
  expect_equal(ncol(result), 5)
})

test_that("read_clinical_data applies type conversion by default", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  write.csv(mtcars, tmp, row.names = FALSE)

  result <- read_clinical_data(tmp)

  # vs has 2 unique values → logical

  expect_true(is.logical(result$vs))
})

test_that("read_clinical_data passes ... to r_data_types", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  write.csv(mtcars, tmp, row.names = FALSE)

  result <- read_clinical_data(tmp, skip_vars = c("vs", "am"))

  # Skipped vars stay numeric
  expect_true(is.numeric(result$vs))
  expect_true(is.numeric(result$am))
})

test_that("read_clinical_data skips conversion when convert_types = FALSE", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  write.csv(mtcars, tmp, row.names = FALSE)

  result <- read_clinical_data(tmp, convert_types = FALSE)

  # vs stays numeric (no conversion)
  expect_true(is.numeric(result$vs))
})

# RDS reading ----

test_that("read_clinical_data reads RDS files", {
  tmp <- tempfile(fileext = ".rds")
  on.exit(unlink(tmp))
  saveRDS(iris, tmp)

  result <- read_clinical_data(tmp, convert_types = FALSE)

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 150)
})

# Excel reading ----

test_that("read_clinical_data reads Excel files", {
  skip_if_not_installed("writexl")
  tmp <- tempfile(fileext = ".xlsx")
  on.exit(unlink(tmp))
  writexl::write_xlsx(iris, tmp)

  result <- read_clinical_data(tmp, convert_types = FALSE)

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 150)
})

# Validation ----

test_that("read_clinical_data errors on missing file", {
  expect_error(read_clinical_data("nonexistent.csv"), "File not found")
})

test_that("read_clinical_data errors on unsupported format", {
  tmp <- tempfile(fileext = ".parquet")
  on.exit(unlink(tmp))
  writeLines("dummy", tmp)

  expect_error(read_clinical_data(tmp), "Unsupported file type")
})

test_that("read_clinical_data errors on non-string file path", {
  expect_error(read_clinical_data(42), "single file path")
  expect_error(read_clinical_data(c("a.csv", "b.csv")), "single file path")
})

# Returns plain data.frame ----

test_that("read_clinical_data returns data.frame from tibble sources", {
  skip_if_not_installed("writexl")
  tmp <- tempfile(fileext = ".xlsx")
  on.exit(unlink(tmp))
  writexl::write_xlsx(iris, tmp)

  result <- read_clinical_data(tmp, convert_types = FALSE)

  # readxl returns a tibble; verify the tibble class is fully dropped
  expect_equal(class(result), "data.frame")
})
