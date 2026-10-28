fixture <- function() {
  data.frame(
    id = c("PRINTME-A1", "PRINTME-B2", "PRINTME-C3", "PRINTME-D4"),
    age = c(45, 101, NA, 70),
    dead = c(0, 1, 1, 0),
    stringsAsFactors = FALSE
  )
}

test_that("proc_print counts matches and undecided rows per condition", {
  out <- suppressWarnings(capture.output(
    res <- proc_print(fixture(),
                      where = list(age > 100 ~ "Implausible age",
                                   dead == 1 ~ "Died",
                                   age < 0 ~ "Negative age")),
    type = "message"
  ))
  expect_identical(res$label, c("Implausible age", "Died", "Negative age"))
  expect_identical(res$n, c(1L, 2L, 0L))
  expect_identical(res$n_missing, c(1L, 0L, 1L))
  expect_type(res$n, "integer")
})

test_that("proc_print accepts a single formula", {
  capture.output(res <- proc_print(fixture(), dead == 1 ~ "Died"), type = "message")
  expect_identical(res$n, 2L)
})

test_that("matching rows go to stderr, not stdout", {
  d <- fixture()
  err <- capture.output(
    out <- capture.output(proc_print(d, age > 100 ~ "Implausible age", var = c("id", "age"))),
    type = "message"
  )
  expect_true(any(grepl("PRINTME-B2", err, fixed = TRUE)))
  expect_false(any(grepl("PRINTME", out, fixed = TRUE)))
})

test_that("var limits the printed columns and max_rows the printed rows", {
  err <- capture.output(
    invisible(proc_print(fixture(), !is.na(age) ~ "Has age", var = "age", max_rows = 1L)),
    type = "message"
  )
  expect_false(any(grepl("PRINTME", err, fixed = TRUE)))
  expect_true(any(grepl("2 more not shown", err, fixed = TRUE)))
})

test_that("a knitted report carries the counts and none of the rows", {
  skip_if_not_installed("knitr")
  d <- fixture()
  rmd <- withr::local_tempfile(fileext = ".Rmd")
  md <- withr::local_tempfile(fileext = ".md")
  writeLines(c(
    "```{r}",
    "proc_print(d, where = list(age > 100 ~ \"Implausible age\", dead == 1 ~ \"Died\"), var = c(\"id\", \"age\"))",
    "```"
  ), rmd)
  env <- new.env(parent = asNamespace("hvtiRutilities"))
  env$d <- d
  capture.output(invisible(knitr::knit(rmd, md, envir = env, quiet = TRUE)), type = "message")
  html <- readLines(md)
  expect_true(any(grepl("Implausible age", html, fixed = TRUE)))
  expect_false(any(grepl("PRINTME", html, fixed = TRUE)))
})

test_that("a warning or message from a condition goes to stderr, not the knitted report", {
  skip_if_not_installed("knitr")
  rmd <- withr::local_tempfile(fileext = ".Rmd")
  md <- withr::local_tempfile(fileext = ".md")
  writeLines(c(
    "```{r}",
    "proc_print(d, where = list({ warning(id[[2]]); age > 100 } ~ \"Warns\",",
    "                           { message(id[[3]]); dead == 1 } ~ \"Says\"), var = \"age\")",
    "```"
  ), rmd)
  env <- new.env(parent = asNamespace("hvtiRutilities"))
  env$d <- fixture()
  err <- capture.output(invisible(knitr::knit(rmd, md, envir = env, quiet = TRUE)), type = "message")
  html <- readLines(md)
  expect_true(any(grepl("Warns", html, fixed = TRUE)))
  expect_false(any(grepl("PRINTME", html, fixed = TRUE)))
  expect_true(any(grepl("PRINTME-B2", err, fixed = TRUE)))
  expect_true(any(grepl("PRINTME-C3", err, fixed = TRUE)))
})

test_that("malformed conditions are refused", {
  d <- fixture()
  expect_error(proc_print(d, list(TRUE)), "condition 1 is not written")
  expect_error(proc_print(d, list(~ "No condition")), "condition 1 is not written")
  expect_error(proc_print(d, list(age > 100 ~ "")), "condition 1 is not written")
  expect_error(proc_print(d, list(age > 100 ~ label)), "condition 1 is not written")
  expect_error(proc_print(d, list()), "non-empty list")
  expect_error(proc_print(d, list(age > 1 ~ "A", dead == 1 ~ "A")), "repeats a label: A")
  expect_error(proc_print(list(a = 1), age > 1 ~ "A"), "'data' must be a data frame")
})

test_that("a failing condition names its label and withholds R's message", {
  d <- fixture()
  expect_error(proc_print(d, no_such_col > 1 ~ "Bad column"),
               "condition \"Bad column\" could not be evaluated")
  err <- tryCatch(proc_print(d, stop("PRINTME-A1") ~ "Leaks"), error = conditionMessage)
  expect_false(grepl("PRINTME", err, fixed = TRUE))
  expect_error(proc_print(d, age ~ "Not logical"), "one TRUE, FALSE or NA per row")
  expect_error(proc_print(d, TRUE ~ "Scalar"), "one TRUE, FALSE or NA per row")
})

test_that("var and max_rows are validated", {
  d <- fixture()
  expect_error(proc_print(d, dead == 1 ~ "Died", var = "nope"), "not found in 'data': nope")
  expect_error(proc_print(d, dead == 1 ~ "Died", var = character()), "'var' must be NULL")
  expect_error(proc_print(d, dead == 1 ~ "Died", max_rows = 0), "'max_rows'")
  expect_error(proc_print(d, dead == 1 ~ "Died", max_rows = 1.5), "'max_rows'")
})

test_that("console = FALSE writes nothing and still counts", {
  d <- fixture()
  err <- capture.output(
    out <- capture.output(
      res <- proc_print(d, list({
        warning(id[[2]])
        age > 100
      } ~ "Warns", dead == 1 ~ "Died"), console = FALSE)
    ),
    type = "message"
  )
  expect_length(err, 0L)
  expect_length(out, 0L)
  expect_identical(res$n, c(1L, 2L))
  expect_error(proc_print(d, dead == 1 ~ "Died", console = NA), "'console' must be a single TRUE or FALSE")
})
