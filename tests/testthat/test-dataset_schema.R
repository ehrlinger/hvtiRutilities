test_that("dataset_schema records absent labels as NA, not the variable name", {
  d <- data.frame(labelled_var = 1:3, bare_var = 4:6)
  attr(d$labelled_var, "label") <- "A real label"
  attr(d$labelled_var, "format.sas") <- "BEST12"

  s <- dataset_schema(d)

  expect_equal(s$num, 1:2)
  expect_equal(s$variable, c("labelled_var", "bare_var"))
  expect_equal(s$label, c("A real label", NA_character_))
  expect_equal(s$format, c("BEST12", NA_character_))
})

test_that("dataset_schema reports SAS two-valued type and R class separately", {
  d <- data.frame(num_var = 1.5, chr_var = "a", stringsAsFactors = FALSE)
  d$fct_var <- factor("b")
  d$when <- as.POSIXct("2020-01-01", tz = "UTC")

  s <- dataset_schema(d)

  expect_equal(s$type, c("Num", "Char", "Char", "Num"))
  expect_equal(s$class, c("numeric", "character", "factor", "POSIXct"))
})

test_that("dataset_schema returns a zero-row frame for a frame with no columns", {
  s <- dataset_schema(data.frame())

  expect_equal(nrow(s), 0L)
  expect_equal(names(s),
               c("num", "variable", "class", "type", "format", "label"))
})

test_that("dataset_schema rejects a non-data-frame", {
  expect_error(dataset_schema(1:10), "must be a data frame")
})
