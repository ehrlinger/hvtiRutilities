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

test_that("read_clinical_data applies type conversion when convert_types = TRUE", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  write.csv(mtcars, tmp, row.names = FALSE)

  result <- read_clinical_data(tmp, convert_types = TRUE)

  # vs has 2 unique values → logical

  expect_true(is.logical(result$vs))
})

test_that("read_clinical_data passes ... to r_data_types", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  write.csv(mtcars, tmp, row.names = FALSE)

  result <- read_clinical_data(tmp, convert_types = TRUE, skip_vars = c("vs", "am"))

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

# convert_types default ----

test_that("a 0/1 column is not converted to logical by default", {
  tmp <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(dead = c(1, 0, 1, 0), x = c(2, 4, 6, 8)),
            tmp, row.names = FALSE)

  d <- suppressWarnings(read_clinical_data(tmp))

  expect_false(is.logical(d$dead))
  expect_equal(d$dead, c(1, 0, 1, 0))
})

test_that("relying on the old convert_types default warns once per session", {
  tmp <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(dead = c(1, 0)), tmp, row.names = FALSE)

  # The one-shot flag is session state; reset it so this test is order-independent.
  # `pkg:::name$field <- value` is not valid R -- the replacement-function
  # desugaring tries to reassign the bare symbol `pkg`, which is never a
  # bound variable. Use assign() against the (reference-semantics)
  # environment instead. Capture and restore the prior value so this reset
  # doesn't leak into tests in other files that run later in the session.
  env <- hvtiRutilities:::.hvti_deprecated
  prior <- if (exists("convert_types", envir = env, inherits = FALSE)) {
    get("convert_types", envir = env, inherits = FALSE)
  } else {
    NULL
  }
  withr::defer(assign("convert_types", prior, envir = env))
  assign("convert_types", NULL, envir = env)

  expect_warning(read_clinical_data(tmp), "convert_types")
  expect_silent(read_clinical_data(tmp))
})

test_that("passing convert_types explicitly never warns", {
  tmp <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(dead = c(1, 0)), tmp, row.names = FALSE)

  # `pkg:::name$field <- value` is not valid R -- the replacement-function
  # desugaring tries to reassign the bare symbol `pkg`, which is never a
  # bound variable. Use assign() against the (reference-semantics)
  # environment instead. Capture and restore the prior value so this reset
  # doesn't leak into tests in other files that run later in the session.
  env <- hvtiRutilities:::.hvti_deprecated
  prior <- if (exists("convert_types", envir = env, inherits = FALSE)) {
    get("convert_types", envir = env, inherits = FALSE)
  } else {
    NULL
  }
  withr::defer(assign("convert_types", prior, envir = env))
  assign("convert_types", NULL, envir = env)

  expect_silent(read_clinical_data(tmp, convert_types = FALSE))
  # convert_types = TRUE reaches r_data_types(), which has a one-shot warning
  # of its own. Naming use_value_labels here keeps this assertion about
  # convert_types rather than about which test file ran first.
  expect_silent(read_clinical_data(tmp, convert_types = TRUE,
                                   use_value_labels = FALSE))
})

test_that("convert_types = TRUE still converts", {
  tmp <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(dead = c(1, 0, 1, 0)), tmp, row.names = FALSE)

  d <- read_clinical_data(tmp, convert_types = TRUE)

  expect_true(is.logical(d$dead))
})
