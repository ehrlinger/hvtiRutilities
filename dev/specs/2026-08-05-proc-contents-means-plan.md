# `proc_contents()` / `proc_means()` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port SAS `PROC CONTENTS` and `PROC MEANS` into `hvtiRutilities` as SAS-shaped data frames, and refactor `data_dictionary()` to sit on top of them.

**Architecture:** Two new primitives in their own files — `proc_contents()` returns a `list(header, variables)` of class `proc_contents`; `proc_means()` returns a plain data frame, one row per variable per class combination. `data_dictionary()` keeps its exact signature and output but is rewritten to call `proc_contents()` and the shared statistic engine. No new package dependencies.

**Tech Stack:** R (>= 4.1.0), `labelled`, `stats`, `testthat` 3rd edition, roxygen2 7.3.3.

**Design spec:** [`dev/specs/2026-08-05-proc-contents-means-design.md`](2026-08-05-proc-contents-means-design.md)

**Branch:** `spec/proc-contents-means`, based on `main` @ 1.0.1.

## Global Constraints

These apply to every task below.

- **No new `Imports`.** `labelled` and `stats` are already dependencies. Do not add `dplyr`, `tibble`, `vctrs`, or anything else.
- **Errors use `stop(..., call. = FALSE)`** — the convention already used by `data_dictionary()` and `compare_datasets()`.
- **Zero-column input returns a correctly-typed zero-row data frame**, never an error. This matches the existing `data_dictionary()` contract.
- **Quantiles use `stats::quantile(type = 2)`** — the SAS `QNTLDEF=5` equivalent. Never R's default `type = 7`.
- **`Len`, `Pos`, `Informat`, and dataset timestamps are never emitted**, not even as inferred or `NA` columns. `haven` cannot recover them.
- **Version is straight three-digit semver.** This work lands as `1.0.2`. No `.9000` suffix, no fourth digit.
- **Test files start with** `library(testthat)` then `library(hvtiRutilities)`, and use `# Section ----` comment banners, matching `tests/testthat/test-data_dictionary.R`.
- **Every exported function needs roxygen `@return`** describing the value, plus runnable `@examples`.

Run tests with, substituting the filter:

```bash
Rscript -e 'testthat::test_local(filter = "proc_contents")'
```

---

### Task 1: `proc_contents()`

**Files:**
- Create: `R/proc_contents.R`
- Create: `tests/testthat/test-proc_contents.R`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `proc_contents(data, order = c("alpha", "varnum"))` → `list(header, variables)` with class `"proc_contents"`.
  - `header` is a one-row data frame: `observations` (integer), `variables` (integer), `label` (character, `NA` when absent).
  - `variables` is a data frame with columns, in this order: `num` (integer), `variable` (character), `type` (character, `"Num"`/`"Char"`), `format` (character, `NA` when absent), `label` (character), `class` (character), `n_unique` (integer), `pct_missing` (numeric).
  - Internal helpers `.sas_type(x)`, `.sas_format(x)`, `.dataset_label(data)`, `.empty_contents()`.
  - `print.proc_contents(x, ...)` S3 method.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-proc_contents.R`:

```r
library(testthat)
library(hvtiRutilities)

# Structure ----

test_that("proc_contents returns header and variables", {
  dta <- sample_data(n = 20)
  pc <- proc_contents(dta)

  expect_s3_class(pc, "proc_contents")
  expect_named(pc, c("header", "variables"))
  expect_equal(pc$header$observations, 20L)
  expect_equal(pc$header$variables, 7L)
  expect_named(pc$variables, c("num", "variable", "type", "format",
                               "label", "class", "n_unique", "pct_missing"))
  expect_equal(nrow(pc$variables), ncol(dta))
})

test_that("proc_contents never emits len, pos or informat", {
  pc <- proc_contents(sample_data(n = 5))
  expect_false(any(c("len", "pos", "informat") %in% names(pc$variables)))
})

# SAS type mapping ----

test_that("proc_contents maps R classes to SAS Num/Char", {
  dta <- data.frame(
    a = 1:3,
    b = c(1.5, 2.5, 3.5),
    c = c("x", "y", "z"),
    d = factor(c("p", "q", "p")),
    e = c(TRUE, FALSE, TRUE),
    f = as.Date(c("2020-01-01", "2020-01-02", "2020-01-03")),
    stringsAsFactors = FALSE
  )
  pc <- proc_contents(dta, order = "varnum")

  expect_equal(pc$variables$type,
               c("Num", "Num", "Char", "Char", "Num", "Num"))
})

test_that("proc_contents reports Date as Num while class shows Date", {
  dta <- data.frame(d = as.Date(c("2020-01-01", "2020-06-01")))
  pc <- proc_contents(dta)

  expect_equal(pc$variables$type, "Num")
  expect_equal(pc$variables$class, "Date")
})

# Formats and labels ----

test_that("proc_contents surfaces the SAS format attribute", {
  dta <- data.frame(d = c(1, 2), x = c(3, 4))
  attr(dta$d, "format.sas") <- "DATE9."
  pc <- proc_contents(dta, order = "varnum")

  expect_equal(pc$variables$format, c("DATE9.", NA_character_))
})

test_that("proc_contents falls back to the variable name when unlabelled", {
  dta <- data.frame(nolabel = 1:3)
  pc <- proc_contents(dta)

  expect_equal(pc$variables$label, "nolabel")
})

test_that("proc_contents reports labels from labelled data", {
  pc <- proc_contents(sample_data(n = 10))
  expect_equal(pc$variables$label[pc$variables$variable == "id"],
               "Patient Identifier")
})

# Ordering ----

test_that("proc_contents sorts alphabetically by default", {
  dta <- data.frame(zeta = 1:3, alpha = 4:6, Mid = 7:9)
  pc <- proc_contents(dta)

  expect_equal(pc$variables$variable, c("alpha", "Mid", "zeta"))
  expect_equal(pc$variables$num, c(2L, 3L, 1L))
})

test_that("proc_contents order = 'varnum' keeps creation order", {
  dta <- data.frame(zeta = 1:3, alpha = 4:6, Mid = 7:9)
  pc <- proc_contents(dta, order = "varnum")

  expect_equal(pc$variables$variable, c("zeta", "alpha", "Mid"))
  expect_equal(pc$variables$num, 1:3)
})

# Counts ----

test_that("proc_contents computes n_unique and pct_missing", {
  dta <- data.frame(a = c(1, 1, 2, 3, NA))
  pc <- proc_contents(dta)

  expect_equal(pc$variables$n_unique, 3L)
  expect_equal(pc$variables$pct_missing, 20)
})

# Edge cases ----

test_that("proc_contents errors on non-data-frame input", {
  expect_error(proc_contents(1:10), "must be a data frame")
})

test_that("proc_contents handles zero-column input", {
  pc <- proc_contents(data.frame())

  expect_equal(pc$header$observations, 0L)
  expect_equal(pc$header$variables, 0L)
  expect_equal(nrow(pc$variables), 0L)
  expect_named(pc$variables, c("num", "variable", "type", "format",
                               "label", "class", "n_unique", "pct_missing"))
})

test_that("print.proc_contents returns its input invisibly", {
  pc <- proc_contents(sample_data(n = 5))
  expect_output(out <- print(pc), "Observations")
  expect_identical(out, pc)
})
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
Rscript -e 'testthat::test_local(filter = "proc_contents")'
```

Expected: FAIL — `could not find function "proc_contents"`.

- [ ] **Step 3: Write the implementation**

Create `R/proc_contents.R`:

```r
#' Describe a dataset's variables, in the style of SAS PROC CONTENTS
#'
#' @description
#' Reports the variable-level metadata that SAS \code{PROC CONTENTS} prints:
#' creation position, name, SAS type, format, and label, alongside the R class
#' and simple completeness counts.
#'
#' @details
#' Reading a \code{.sas7bdat} through \pkg{haven} is lossy. Variable name,
#' label, \code{format.sas}, and creation order survive; SAS storage
#' \code{LENGTH}, \code{POS} (position within the observation), informat, and
#' the dataset's created/modified timestamps do not. Those fields are omitted
#' rather than inferred, because inferred values would look authoritative and
#' would disagree with the source dataset whenever its \code{LENGTH} statement
#' differed from the default.
#'
#' The SAS \code{Type} column is two-valued, so the mapping from R is
#' deliberately lossy: \code{character} and \code{factor} become \code{"Char"};
#' everything else, including \code{logical}, \code{Date}, and \code{POSIXct},
#' becomes \code{"Num"}. A SAS date is a number carrying a date format, so
#' \code{type} reports \code{"Num"} while \code{class} reports \code{"Date"} —
#' keeping the disagreement visible rather than hiding it.
#'
#' @param data A data frame, tibble, or similar tabular object.
#' @param order Variable ordering. \code{"alpha"} (default) sorts
#'   case-insensitively by name, matching SAS's default \emph{Alphabetic List
#'   of Variables and Attributes}; \code{"varnum"} keeps creation order. The
#'   \code{num} column always reports creation position regardless of sort.
#'
#' @return An object of class \code{proc_contents}: a list with two elements.
#' \describe{
#'   \item{header}{One-row data frame with \code{observations} (row count),
#'     \code{variables} (column count), and \code{label} (dataset label, or
#'     \code{NA})}
#'   \item{variables}{Data frame with one row per column and the columns
#'     \code{num} (creation position), \code{variable}, \code{type}
#'     (\code{"Num"}/\code{"Char"}), \code{format} (SAS format, or \code{NA}),
#'     \code{label}, \code{class} (R class), \code{n_unique} (distinct
#'     non-\code{NA} values), and \code{pct_missing} (0-100, 1 decimal place)}
#' }
#'
#' @seealso \code{\link{proc_means}} for numeric summaries,
#'   \code{\link{data_dictionary}} for a flattened documentation table.
#'
#' @export
#'
#' @examples
#' dta <- sample_data(n = 50)
#' pc <- proc_contents(dta)
#' pc$header
#' pc$variables
#'
#' # Creation order rather than alphabetical
#' proc_contents(dta, order = "varnum")$variables
proc_contents <- function(data, order = c("alpha", "varnum")) {
  if (!is.data.frame(data)) {
    stop("'data' must be a data frame.", call. = FALSE)
  }
  ord <- match.arg(order)

  header <- data.frame(
    observations = nrow(data),
    variables    = ncol(data),
    label        = .dataset_label(data),
    stringsAsFactors = FALSE
  )

  if (ncol(data) == 0L) {
    return(structure(list(header = header, variables = .empty_contents()),
                     class = "proc_contents"))
  }

  labels <- labelled::var_label(data, unlist = TRUE, null_action = "fill")

  variables <- data.frame(
    num         = seq_len(ncol(data)),
    variable    = names(data),
    type        = vapply(data, .sas_type, character(1)),
    format      = vapply(data, .sas_format, character(1)),
    label       = unname(labels),
    class       = vapply(data, function(x) class(x)[1L], character(1)),
    n_unique    = vapply(data, function(x) length(unique(x[!is.na(x)])),
                         integer(1)),
    pct_missing = vapply(data, function(x) round(mean(is.na(x)) * 100, 1),
                         numeric(1)),
    stringsAsFactors = FALSE
  )

  if (ord == "alpha") {
    variables <- variables[base::order(tolower(variables$variable)), ,
                           drop = FALSE]
  }
  rownames(variables) <- NULL

  structure(list(header = header, variables = variables),
            class = "proc_contents")
}

#' @export
print.proc_contents <- function(x, ...) {
  cat("Observations: ", x$header$observations, "\n", sep = "")
  cat("Variables:    ", x$header$variables, "\n", sep = "")
  if (!is.na(x$header$label)) {
    cat("Label:        ", x$header$label, "\n", sep = "")
  }
  cat("\n")
  print(x$variables)
  invisible(x)
}

## Internal: SAS two-valued type from an R vector
.sas_type <- function(x) {
  if (is.character(x) || is.factor(x)) "Char" else "Num"
}

## Internal: SAS format attribute, NA when absent
.sas_format <- function(x) {
  fmt <- attr(x, "format.sas", exact = TRUE)
  if (is.null(fmt) || length(fmt) == 0L) NA_character_ else as.character(fmt)[1L]
}

## Internal: dataset-level label attribute, NA when absent
.dataset_label <- function(data) {
  lab <- attr(data, "label", exact = TRUE)
  if (is.null(lab) || length(lab) == 0L) NA_character_ else as.character(lab)[1L]
}

## Internal: zero-row variables frame with the correct column types
.empty_contents <- function() {
  data.frame(
    num         = integer(),
    variable    = character(),
    type        = character(),
    format      = character(),
    label       = character(),
    class       = character(),
    n_unique    = integer(),
    pct_missing = numeric(),
    stringsAsFactors = FALSE
  )
}
```

Note: `base::order()` is written explicitly because `order` is also this function's argument name. R's call-position lookup would find the base function anyway, but the explicit prefix stops a future reader from having to know that rule.

- [ ] **Step 4: Regenerate documentation and run the tests**

```bash
Rscript -e 'roxygen2::roxygenise()' && Rscript -e 'testthat::test_local(filter = "proc_contents")'
```

Expected: PASS, 13 tests. `NAMESPACE` should gain `export(proc_contents)` and `S3method(print,proc_contents)`.

- [ ] **Step 5: Commit**

```bash
git add R/proc_contents.R tests/testthat/test-proc_contents.R NAMESPACE man/
git commit -m "feat: proc_contents() port of SAS PROC CONTENTS"
```

---

### Task 2: `proc_means()` — ungrouped statistics

**Files:**
- Create: `R/proc_means.R`
- Create: `tests/testthat/test-proc_means.R`

**Interfaces:**
- Consumes: nothing from Task 1 at runtime.
- Produces:
  - `proc_means(data, vars = NULL, class = NULL, stats = c("n", "mean", "std", "min", "max"))` → data frame with columns `variable`, `label`, then one column per requested statistic in the order requested.
  - Internal helpers `.compute_stat(x, stat)`, `.quantile_stat(v, stat)`, `.validate_stats(stats)`, `.means_row(x, variable, label, stats)`, `.empty_means(class, stats)`.
  - `.compute_stat()` is the shared statistic engine that Task 4 reuses.
- The `class` argument is accepted and validated in this task but is not yet honoured; Task 3 implements grouping.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-proc_means.R`:

```r
library(testthat)
library(hvtiRutilities)

# Structure ----

test_that("proc_means defaults to SAS's five statistics", {
  dta <- data.frame(a = c(1, 2, 3, 4), b = c(10, 20, 30, 40))
  res <- proc_means(dta)

  expect_s3_class(res, "data.frame")
  expect_named(res, c("variable", "label", "n", "mean", "std", "min", "max"))
  expect_equal(res$variable, c("a", "b"))
})

test_that("proc_means keeps the requested statistic order", {
  dta <- data.frame(a = c(1, 2, 3, 4))
  res <- proc_means(dta, stats = c("max", "n", "mean"))

  expect_named(res, c("variable", "label", "max", "n", "mean"))
})

test_that("proc_means selects only numeric columns by default", {
  dta <- data.frame(num = c(1, 2), chr = c("x", "y"),
                    fct = factor(c("p", "q")), stringsAsFactors = FALSE)
  res <- proc_means(dta)

  expect_equal(res$variable, "num")
})

test_that("proc_means carries variable labels", {
  res <- proc_means(sample_data(n = 20), vars = "float")
  expect_equal(res$label, "Random Normal Value")
})

# Statistic values ----

test_that("proc_means computes the default five correctly", {
  dta <- data.frame(a = c(2, 4, 4, 4, 5, 5, 7, 9))
  res <- proc_means(dta)

  expect_equal(res$n, 8L)
  expect_equal(res$mean, 5)
  expect_equal(res$std, sd(c(2, 4, 4, 4, 5, 5, 7, 9)))
  expect_equal(res$min, 2)
  expect_equal(res$max, 9)
})

test_that("proc_means computes n, nmiss, sum, range, stderr and cv", {
  dta <- data.frame(a = c(1, 2, 3, NA))
  res <- proc_means(dta, stats = c("n", "nmiss", "sum", "range",
                                   "stderr", "cv"))

  expect_equal(res$n, 3L)
  expect_equal(res$nmiss, 1L)
  expect_equal(res$sum, 6)
  expect_equal(res$range, 2)
  expect_equal(res$stderr, sd(c(1, 2, 3)) / sqrt(3))
  expect_equal(res$cv, 100 * sd(c(1, 2, 3)) / 2)
})

# Quantile definition ----

test_that("proc_means uses the SAS QNTLDEF=5 quantile, not R's default", {
  dta <- data.frame(a = c(1, 2, 3, 4))
  res <- proc_means(dta, stats = c("q1", "median", "q3"))

  # SAS QNTLDEF=5 (R type 2) gives 1.5; R's default type 7 would give 1.75.
  expect_equal(res$q1, 1.5)
  expect_equal(res$median, 2.5)
  expect_equal(res$q3, 3.5)
})

test_that("proc_means accepts pNN percentile keywords", {
  dta <- data.frame(a = as.numeric(1:100))
  res <- proc_means(dta, stats = c("p15", "p50", "p99"))

  expect_named(res, c("variable", "label", "p15", "p50", "p99"))
  expect_equal(res$p15, unname(quantile(1:100, 0.15, type = 2)))
})

# Edge cases ----

test_that("proc_means returns NA statistics for an all-NA column", {
  dta <- data.frame(a = as.numeric(c(NA, NA)))
  res <- proc_means(dta, stats = c("n", "nmiss", "mean", "min"))

  expect_equal(res$n, 0L)
  expect_equal(res$nmiss, 2L)
  expect_true(is.na(res$mean))
  expect_true(is.na(res$min))
})

test_that("proc_means returns NA std for a single observation", {
  dta <- data.frame(a = 5)
  res <- proc_means(dta, stats = c("n", "mean", "std"))

  expect_equal(res$n, 1L)
  expect_equal(res$mean, 5)
  expect_true(is.na(res$std))
})

test_that("proc_means summarises a logical column when named explicitly", {
  dta <- data.frame(flag = c(TRUE, TRUE, FALSE, FALSE))
  res <- proc_means(dta, vars = "flag", stats = c("n", "mean"))

  expect_equal(res$n, 4L)
  expect_equal(res$mean, 0.5)
})

test_that("proc_means excludes logical columns from the default var set", {
  dta <- data.frame(num = c(1, 2), flag = c(TRUE, FALSE))
  res <- proc_means(dta)

  expect_equal(res$variable, "num")
})

test_that("proc_means includes labelled numerics and summarises their codes", {
  dta <- data.frame(coded = c(1, 2, 1, 2))
  labelled::val_labels(dta$coded) <- c(no = 1, yes = 2)
  res <- proc_means(dta, stats = c("n", "mean"))

  expect_equal(res$variable, "coded")
  expect_equal(res$n, 4L)
  expect_equal(res$mean, 1.5)
})

# Errors ----

test_that("proc_means errors on non-data-frame input", {
  expect_error(proc_means(1:10), "must be a data frame")
})

test_that("proc_means errors on an unknown statistic keyword", {
  dta <- data.frame(a = c(1, 2))
  expect_error(proc_means(dta, stats = c("mean", "bogus")),
               "Unrecognised statistic keyword")
  expect_error(proc_means(dta, stats = "p100"),
               "Unrecognised statistic keyword")
})

test_that("proc_means errors on a missing column name", {
  dta <- data.frame(a = c(1, 2))
  expect_error(proc_means(dta, vars = "nope"), "not found in 'data'")
  expect_error(proc_means(dta, class = "nope"), "not found in 'data'")
})

test_that("proc_means errors when vars names a non-numeric column", {
  dta <- data.frame(chr = c("x", "y"), stringsAsFactors = FALSE)
  expect_error(proc_means(dta, vars = "chr"), "Non-numeric column")
})

test_that("proc_means warns and returns zero rows when nothing is numeric", {
  dta <- data.frame(chr = c("x", "y"), stringsAsFactors = FALSE)
  expect_warning(res <- proc_means(dta), "No numeric columns")

  expect_equal(nrow(res), 0L)
  expect_named(res, c("variable", "label", "n", "mean", "std", "min", "max"))
})
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
Rscript -e 'testthat::test_local(filter = "proc_means")'
```

Expected: FAIL — `could not find function "proc_means"`.

- [ ] **Step 3: Write the implementation**

Create `R/proc_means.R`:

```r
#' Summarise numeric variables, in the style of SAS PROC MEANS
#'
#' @description
#' Produces the table SAS \code{PROC MEANS} prints: one row per analysis
#' variable, one column per requested statistic, in the order requested.
#'
#' @details
#' Quantiles use \code{stats::quantile(type = 2)}, which is the R equivalent of
#' SAS's default \code{QNTLDEF=5}. This matters: R's own default is
#' \code{type = 7}, a different estimator that disagrees with SAS on the small
#' and even-numbered samples clinical subgroups produce. For
#' \code{c(1, 2, 3, 4)}, the first quartile is \code{1.5} in SAS and
#' \code{1.75} under R's default. The median agrees, which is why the
#' discrepancy hides.
#'
#' With \code{vars = NULL} all numeric columns are analysed, matching SAS's
#' behaviour when the \code{VAR} statement is omitted. Logical columns are not
#' \code{is.numeric()} in R and so are excluded from that default set; naming
#' one in \code{vars} coerces it to 0/1, making \code{mean} a proportion as
#' \code{PROC MEANS} would give.
#'
#' @param data A data frame, tibble, or similar tabular object.
#' @param vars Character vector of columns to analyse. \code{NULL} (default)
#'   selects every numeric column not named in \code{class}.
#' @param class Character vector of grouping columns, prepended to the result
#'   as leading columns. Rows with a missing value in any class variable are
#'   dropped, matching SAS's default.
#' @param stats Character vector of SAS statistic keywords: \code{"n"},
#'   \code{"nmiss"}, \code{"mean"}, \code{"std"}, \code{"min"}, \code{"max"},
#'   \code{"sum"}, \code{"range"}, \code{"stderr"}, \code{"cv"},
#'   \code{"median"}, \code{"q1"}, \code{"q3"}, or any \code{"pNN"} for
#'   \code{NN} between 1 and 99. Defaults to SAS's own default five.
#'
#' @return A data frame with one row per analysis variable per class
#'   combination. Columns are the \code{class} variables (when supplied), then
#'   \code{variable}, \code{label}, then one column per requested statistic in
#'   the order given by \code{stats}. Count statistics (\code{n},
#'   \code{nmiss}) are integer; all others are numeric.
#'
#' @seealso \code{\link{proc_contents}} for variable metadata.
#'
#' @importFrom stats quantile sd complete.cases
#'
#' @export
#'
#' @examples
#' dta <- generate_survival_data(n = 200, seed = 42)
#'
#' # SAS default statistics over every numeric variable
#' head(proc_means(dta))
#'
#' # Named variables and an explicit statistic list
#' proc_means(dta, vars = c("age", "bmi"),
#'            stats = c("n", "mean", "median", "p15"))
proc_means <- function(data, vars = NULL, class = NULL,
                       stats = c("n", "mean", "std", "min", "max")) {
  if (!is.data.frame(data)) {
    stop("'data' must be a data frame.", call. = FALSE)
  }
  .validate_stats(stats)

  if (!is.null(class)) {
    absent <- setdiff(class, names(data))
    if (length(absent) > 0L) {
      stop("Column(s) not found in 'data': ",
           paste(absent, collapse = ", "), call. = FALSE)
    }
  }

  if (is.null(vars)) {
    numeric_cols <- names(data)[vapply(data, is.numeric, logical(1))]
    vars <- setdiff(numeric_cols, class)
  } else {
    absent <- setdiff(vars, names(data))
    if (length(absent) > 0L) {
      stop("Column(s) not found in 'data': ",
           paste(absent, collapse = ", "), call. = FALSE)
    }
    usable <- vapply(data[vars], function(x) is.numeric(x) || is.logical(x),
                     logical(1))
    if (!all(usable)) {
      stop("Non-numeric column(s) named in 'vars': ",
           paste(vars[!usable], collapse = ", "), call. = FALSE)
    }
  }

  if (length(vars) == 0L) {
    warning("No numeric columns to analyse; returning a zero-row result.",
            call. = FALSE)
    return(.empty_means(class, stats))
  }

  labels <- labelled::var_label(data, unlist = TRUE, null_action = "fill")

  rows <- lapply(vars, function(v) {
    .means_row(data[[v]], v, unname(labels[v]), stats)
  })

  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

## Internal: reject unknown statistic keywords
.validate_stats <- function(stats) {
  known <- c("n", "nmiss", "mean", "std", "min", "max", "sum", "range",
             "stderr", "cv", "median", "q1", "q3")
  ok <- stats %in% known | grepl("^p([1-9]|[1-9][0-9])$", stats)
  if (!all(ok)) {
    stop("Unrecognised statistic keyword(s): ",
         paste(stats[!ok], collapse = ", "),
         ". Valid keywords are: ", paste(known, collapse = ", "),
         ", and pNN for NN from 1 to 99.", call. = FALSE)
  }
  invisible(TRUE)
}

## Internal: one statistic from one vector, SAS semantics
.compute_stat <- function(x, stat) {
  x <- as.numeric(x)
  v <- x[!is.na(x)]
  n <- length(v)

  switch(stat,
    n      = n,
    nmiss  = sum(is.na(x)),
    mean   = if (n == 0L) NA_real_ else mean(v),
    std    = if (n < 2L) NA_real_ else stats::sd(v),
    min    = if (n == 0L) NA_real_ else min(v),
    max    = if (n == 0L) NA_real_ else max(v),
    sum    = if (n == 0L) NA_real_ else sum(v),
    range  = if (n == 0L) NA_real_ else max(v) - min(v),
    stderr = if (n < 2L) NA_real_ else stats::sd(v) / sqrt(n),
    cv     = if (n < 2L) NA_real_ else 100 * stats::sd(v) / mean(v),
    .quantile_stat(v, stat)
  )
}

## Internal: quantile statistics at SAS QNTLDEF=5 (R type 2)
.quantile_stat <- function(v, stat) {
  if (length(v) == 0L) {
    return(NA_real_)
  }
  p <- switch(stat,
    median = 0.5,
    q1     = 0.25,
    q3     = 0.75,
    as.numeric(sub("^p", "", stat)) / 100
  )
  stats::quantile(v, probs = p, type = 2, names = FALSE)
}

## Internal: one output row for one variable
.means_row <- function(x, variable, label, stats) {
  vals <- lapply(stats, function(s) .compute_stat(x, s))
  names(vals) <- stats
  cbind(
    data.frame(variable = variable, label = label, stringsAsFactors = FALSE),
    as.data.frame(vals, stringsAsFactors = FALSE)
  )
}

## Internal: zero-row result with the correct columns
.empty_means <- function(class, stats) {
  out <- data.frame(variable = character(), label = character(),
                    stringsAsFactors = FALSE)
  for (s in stats) {
    out[[s]] <- numeric()
  }
  if (!is.null(class) && length(class) > 0L) {
    pre <- as.data.frame(
      stats::setNames(replicate(length(class), character(), simplify = FALSE),
                      class),
      stringsAsFactors = FALSE
    )
    out <- cbind(pre, out)
  }
  out
}
```

Note: `stats::sd` and `stats::quantile` resolve to the package even though `stats` is also an argument name — `::` does not evaluate its left-hand side as a variable.

- [ ] **Step 4: Regenerate documentation and run the tests**

```bash
Rscript -e 'roxygen2::roxygenise()' && Rscript -e 'testthat::test_local(filter = "proc_means")'
```

Expected: PASS, 18 tests. `NAMESPACE` gains `export(proc_means)` and `importFrom(stats,quantile)`, `importFrom(stats,sd)`, `importFrom(stats,complete.cases)`.

- [ ] **Step 5: Commit**

```bash
git add R/proc_means.R tests/testthat/test-proc_means.R NAMESPACE man/
git commit -m "feat: proc_means() port of SAS PROC MEANS, ungrouped"
```

---

### Task 3: `proc_means()` — `CLASS` stratification

**Files:**
- Modify: `R/proc_means.R` (the `proc_means()` body only; helpers are unchanged)
- Modify: `tests/testthat/test-proc_means.R` (append a new section)

**Interfaces:**
- Consumes: `proc_means()`, `.means_row()`, `.empty_means()` from Task 2.
- Produces: `class` argument now honoured. Output gains the class columns as leading columns; row order is `variable` (in `vars` order, varying slowest), then class levels ascending.

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-proc_means.R`:

```r
# CLASS stratification ----

test_that("proc_means prepends class columns and groups rows", {
  dta <- data.frame(
    trt = c("A", "A", "B", "B"),
    val = c(1, 3, 10, 30),
    stringsAsFactors = FALSE
  )
  res <- proc_means(dta, class = "trt", stats = c("n", "mean"))

  expect_named(res, c("trt", "variable", "label", "n", "mean"))
  expect_equal(res$trt, c("A", "B"))
  expect_equal(res$mean, c(2, 20))
})

test_that("proc_means excludes class variables from the default var set", {
  dta <- data.frame(grp = c(1, 1, 2, 2), val = c(1, 2, 3, 4))
  res <- proc_means(dta, class = "grp")

  expect_equal(unique(res$variable), "val")
})

test_that("proc_means drops rows with a missing class value", {
  dta <- data.frame(
    trt = c("A", "A", NA, "B"),
    val = c(1, 3, 100, 5),
    stringsAsFactors = FALSE
  )
  res <- proc_means(dta, class = "trt", stats = c("n", "mean"))

  expect_equal(res$trt, c("A", "B"))
  expect_equal(res$n, c(2L, 1L))
  expect_false(any(is.na(res$trt)))
})

test_that("proc_means orders rows by variable then class level", {
  dta <- data.frame(
    trt = c("B", "A", "B", "A"),
    x = c(1, 2, 3, 4),
    y = c(5, 6, 7, 8),
    stringsAsFactors = FALSE
  )
  res <- proc_means(dta, class = "trt", stats = "n")

  expect_equal(res$variable, c("x", "x", "y", "y"))
  expect_equal(res$trt, c("A", "B", "A", "B"))
})

test_that("proc_means supports two class variables", {
  dta <- data.frame(
    a = c("x", "x", "y", "y"),
    b = c(1, 2, 1, 2),
    val = c(10, 20, 30, 40),
    stringsAsFactors = FALSE
  )
  res <- proc_means(dta, class = c("a", "b"), stats = "mean")

  expect_named(res, c("a", "b", "variable", "label", "mean"))
  expect_equal(nrow(res), 4L)
  expect_equal(res$mean, c(10, 20, 30, 40))
})

test_that("proc_means handles a factor class variable", {
  dta <- data.frame(
    grp = factor(c("lo", "hi", "lo", "hi"), levels = c("lo", "hi")),
    val = c(1, 10, 3, 30)
  )
  res <- proc_means(dta, class = "grp", stats = "mean")

  expect_equal(nrow(res), 2L)
  expect_equal(res$mean[res$grp == "lo"], 2)
  expect_equal(res$mean[res$grp == "hi"], 20)
})
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
Rscript -e 'testthat::test_local(filter = "proc_means")'
```

Expected: FAIL — the new tests report unnamed/missing `trt` column, because `class` is validated but ignored.

- [ ] **Step 3: Replace the tail of `proc_means()`**

In `R/proc_means.R`, replace this block:

```r
  labels <- labelled::var_label(data, unlist = TRUE, null_action = "fill")

  rows <- lapply(vars, function(v) {
    .means_row(data[[v]], v, unname(labels[v]), stats)
  })

  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}
```

with:

```r
  groups <- NULL
  if (!is.null(class) && length(class) > 0L) {
    keep <- stats::complete.cases(data[, class, drop = FALSE])
    data <- data[keep, , drop = FALSE]
    groups <- unique(data[, class, drop = FALSE])
    groups <- groups[do.call(base::order, unname(as.list(groups))), ,
                     drop = FALSE]
    rownames(groups) <- NULL
  }

  labels <- labelled::var_label(data, unlist = TRUE, null_action = "fill")

  rows <- list()
  for (v in vars) {
    if (is.null(groups)) {
      rows[[length(rows) + 1L]] <-
        .means_row(data[[v]], v, unname(labels[v]), stats)
    } else {
      for (i in seq_len(nrow(groups))) {
        idx <- rep(TRUE, nrow(data))
        for (k in class) {
          idx <- idx & (as.character(data[[k]]) == as.character(groups[[k]][i]))
        }
        rows[[length(rows) + 1L]] <- cbind(
          groups[i, , drop = FALSE],
          .means_row(data[[v]][idx], v, unname(labels[v]), stats),
          stringsAsFactors = FALSE
        )
      }
    }
  }

  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}
```

`as.character()` on both sides of the group match keeps factor and numeric class variables comparable without depending on level ordering. Sorting via `do.call(base::order, ...)` on the unique-group frame sorts by the first class variable, then the second, and so on — the SAS row order.

- [ ] **Step 4: Run the full `proc_means` suite**

```bash
Rscript -e 'testthat::test_local(filter = "proc_means")'
```

Expected: PASS, 24 tests — the 18 from Task 2 plus 6 new.

- [ ] **Step 5: Commit**

```bash
git add R/proc_means.R tests/testthat/test-proc_means.R
git commit -m "feat: proc_means() CLASS stratification"
```

---

### Task 4: Refactor `data_dictionary()` onto the primitives

**Files:**
- Modify: `R/data_dictionary.R`
- Modify: `tests/testthat/test-data_dictionary.R`

**Interfaces:**
- Consumes: `proc_contents(data, order = "varnum")$variables` from Task 1; `.compute_stat(x, stat)` from Task 2.
- Produces: `data_dictionary(data)` — unchanged signature, unchanged six output columns `variable`, `label`, `class`, `n_unique`, `pct_missing`, `summary`.

**Why the characterization test is committed separately:** it must be written and committed while the *old* implementation is still in place, so that it demonstrably pins current behaviour rather than being written to match whatever the refactor happens to produce.

- [ ] **Step 1: Write the characterization test against the CURRENT implementation**

Append to `tests/testthat/test-data_dictionary.R`:

```r
# Characterization — pins behaviour across the proc_contents refactor ----

test_that("data_dictionary output is stable for labelled survival data", {
  dict <- data_dictionary(generate_survival_data(n = 100, seed = 42))

  expect_named(dict, c("variable", "label", "class", "n_unique",
                       "pct_missing", "summary"))
  expect_equal(dict$variable, names(generate_survival_data(n = 100, seed = 42)))
  expect_equal(dict$label[dict$variable == "age"], "Age at surgery (years)")
  expect_equal(dict$class[dict$variable == "age"], "numeric")
})

test_that("data_dictionary preserves original column order", {
  dta <- data.frame(zeta = 1:3, alpha = 4:6, Mid = 7:9)
  dict <- data_dictionary(dta)

  expect_equal(dict$variable, c("zeta", "alpha", "Mid"))
})

test_that("data_dictionary summary strings are stable per column type", {
  dta <- data.frame(
    num = c(1, 2, 3, 4),
    lgl = c(TRUE, FALSE, TRUE, TRUE),
    fct = factor(c("a", "b", "a", "c")),
    chr = c("p", "q", "p", "r"),
    empty = as.numeric(c(NA, NA, NA, NA)),
    stringsAsFactors = FALSE
  )
  dict <- data_dictionary(dta)

  expect_equal(dict$summary[dict$variable == "num"], "1 / 2.5 / 4")
  expect_equal(dict$summary[dict$variable == "lgl"], "TRUE: 75%")
  expect_equal(dict$summary[dict$variable == "fct"], "3 levels: a, b, c")
  expect_equal(dict$summary[dict$variable == "chr"], "3 levels: p, q, r")
  expect_equal(dict$summary[dict$variable == "empty"], "all NA")
})

test_that("data_dictionary handles zero-column input", {
  dict <- data_dictionary(data.frame())

  expect_equal(nrow(dict), 0L)
  expect_named(dict, c("variable", "label", "class", "n_unique",
                       "pct_missing", "summary"))
})
```

- [ ] **Step 2: Run against the unmodified implementation to verify it PASSES**

```bash
Rscript -e 'testthat::test_local(filter = "data_dictionary")'
```

Expected: PASS. This is the one step in the plan where a green result on first run is the goal — the test is describing what already exists. If any assertion fails, the assertion is wrong; correct it to match current behaviour rather than changing `R/data_dictionary.R`.

- [ ] **Step 3: Commit the characterization test on its own**

```bash
git add tests/testthat/test-data_dictionary.R
git commit -m "test: pin data_dictionary() behaviour before refactor"
```

- [ ] **Step 4: Refactor `data_dictionary()`**

In `R/data_dictionary.R`, replace the function body (lines 49-76 of the original, from `data_dictionary <- function(data) {` through its closing brace) with:

```r
data_dictionary <- function(data) {
  if (!is.data.frame(data)) {
    stop("'data' must be a data frame.", call. = FALSE)
  }

  contents <- proc_contents(data, order = "varnum")$variables

  if (nrow(contents) == 0L) {
    return(data.frame(
      variable    = character(),
      label       = character(),
      class       = character(),
      n_unique    = integer(),
      pct_missing = numeric(),
      summary     = character(),
      stringsAsFactors = FALSE
    ))
  }

  data.frame(
    variable    = contents$variable,
    label       = contents$label,
    class       = contents$class,
    n_unique    = contents$n_unique,
    pct_missing = contents$pct_missing,
    summary     = vapply(data, .summarise_column, character(1)),
    stringsAsFactors = FALSE
  )
}
```

`order = "varnum"` is required — the original walked `names(data)`, so alphabetical sorting here would silently reorder every existing caller's output.

Then replace the numeric branch of `.summarise_column()`. Change:

```r
  if (is.numeric(vals)) {
    sprintf("%.4g / %.4g / %.4g",
            min(vals), stats::median(vals), max(vals))
  } else if (is.logical(vals)) {
```

to:

```r
  if (is.numeric(vals)) {
    sprintf("%.4g / %.4g / %.4g",
            .compute_stat(vals, "min"),
            .compute_stat(vals, "median"),
            .compute_stat(vals, "max"))
  } else if (is.logical(vals)) {
```

Leave every other branch untouched. Calling `.compute_stat()` directly rather than `proc_means()` avoids building a throwaway data frame per column while still routing through the one statistic engine. `stats::median()` and `type = 2` are the same estimator at *p* = 0.5 for both odd and even *n*, so the pinned strings do not move.

Also add to the roxygen block, after the `@seealso` line:

```r
#' @seealso \code{\link{proc_contents}} for the full SAS-style variable table,
#'   \code{\link{proc_means}} for numeric summaries,
#'   \code{\link{label_map}} for extracting labels only,
#'   \code{\link{r_data_types}} for automatic type conversion before building
#'   the dictionary.
```

replacing the existing `@seealso`.

- [ ] **Step 5: Run the data_dictionary suite and verify it still passes**

```bash
Rscript -e 'roxygen2::roxygenise()' && Rscript -e 'testthat::test_local(filter = "data_dictionary")'
```

Expected: PASS, with the same test count as Step 2. Any failure means the refactor changed observable behaviour and must be corrected — do not edit the characterization test.

- [ ] **Step 6: Run the whole suite to catch downstream callers**

```bash
Rscript -e 'testthat::test_local()'
```

Expected: PASS. `tests/testthat/test-integration.R` exercises `data_dictionary()` alongside other functions and is the most likely place a regression surfaces.

- [ ] **Step 7: Commit**

```bash
git add R/data_dictionary.R man/
git commit -m "refactor: build data_dictionary() on proc_contents() and the shared stat engine"
```

---

### Task 5: Documentation, version, and package check

**Files:**
- Modify: `README.md`
- Modify: `NEWS.md`
- Modify: `DESCRIPTION`
- Modify: `_pkgdown.yml:78-81` (the `Data Documentation` reference section)

**Interfaces:**
- Consumes: `proc_contents()` and `proc_means()` as exported in Tasks 1-3.
- Produces: no code interfaces; this task closes out the release metadata.

- [ ] **Step 1: Add README entries**

In `README.md`, in the `### Main Functions` list, insert these two entries immediately before the existing `- **`label_map()`**:` entry:

```markdown
- **`proc_contents()`**: SAS `PROC CONTENTS` in R
  - One row per variable: creation position, name, SAS type (Num/Char), format, label
  - Plus R class, distinct-value count, and percent missing
  - Alphabetical by default, matching SAS; `order = "varnum"` gives creation order
  - Omits `Len`, `Pos`, and `Informat`, which `haven` cannot recover from a `.sas7bdat`

- **`proc_means()`**: SAS `PROC MEANS` in R
  - SAS statistic keywords (`n`, `nmiss`, `mean`, `std`, `min`, `max`, `median`, `q1`, `q3`, `pNN`, ...), defaulting to SAS's own five
  - `class =` stratification, dropping missing class levels as SAS does
  - Quantiles use SAS's `QNTLDEF=5` definition, not R's default
```

- [ ] **Step 2: Add the new functions to `_pkgdown.yml`**

`_pkgdown.yml` lists reference topics explicitly, so a new export that is not
listed fails the pkgdown build. In the `Data Documentation` section (around
line 78), change:

```yaml
- title: Data Documentation
  desc: Build data dictionaries and compare dataset versions
  contents:
  - data_dictionary
  - compare_datasets
```

to:

```yaml
- title: Data Documentation
  desc: Build data dictionaries, summarise variables, and compare dataset versions
  contents:
  - data_dictionary
  - proc_contents
  - proc_means
  - compare_datasets
```

- [ ] **Step 3: Bump the version**

In `DESCRIPTION`, change line 4 and line 5:

```
Version: 1.0.2
Date: 2026-08-05
```

In `NEWS.md`, insert at the very top, above the existing `# hvtiRutilities 1.0.1` heading:

```markdown
# hvtiRutilities 1.0.2

## New features

- `proc_contents()`: a port of SAS `PROC CONTENTS`. Returns a dataset header
  (observations, variables, label) and a variables table carrying creation
  position, name, SAS type, format, label, R class, distinct-value count, and
  percent missing. `Len`, `Pos`, and `Informat` are deliberately omitted —
  `haven` cannot recover them from a `.sas7bdat`, and inferred values would
  disagree with the source dataset whenever its `LENGTH` statement differed
  from the default.

- `proc_means()`: a port of SAS `PROC MEANS`. Takes SAS statistic keywords
  (`n`, `nmiss`, `mean`, `std`, `min`, `max`, `sum`, `range`, `stderr`, `cv`,
  `median`, `q1`, `q3`, and any `pNN`), defaulting to SAS's own five, and
  supports `CLASS` stratification with SAS's default handling of missing class
  levels. Quantiles use `type = 2`, the R equivalent of SAS `QNTLDEF=5`;
  R's default `type = 7` disagrees with SAS on small and even-numbered samples.

## Internal changes

- `data_dictionary()` is now a thin wrapper over `proc_contents()` and the
  shared statistic engine. Its signature and output are unchanged, pinned by
  characterization tests added before the refactor.
```

- [ ] **Step 4: Run the full check**

```bash
Rscript -e 'devtools::check()' 2>&1 | tail -30
```

Expected: `0 errors | 0 warnings | 0 notes`. If `devtools` is unavailable, use:

```bash
R CMD build . && R CMD check hvtiRutilities_1.0.2.tar.gz
```

Common findings to fix rather than ignore: an undocumented argument (add the `@param`), a missing `@return` on an exported function, or an example that errors.

- [ ] **Step 5: Commit and open the PR**

```bash
git add README.md NEWS.md DESCRIPTION _pkgdown.yml
git commit -m "docs: document proc_contents() and proc_means(); bump to 1.0.2"
git push -u origin spec/proc-contents-means
```

Then open the PR with `gh pr create`, targeting `main`.

---

## Verification checklist

Run before requesting review:

- [ ] `Rscript -e 'testthat::test_local()'` — all tests pass, none skipped
- [ ] `Rscript -e 'devtools::check()'` — 0 errors, 0 warnings, 0 notes
- [ ] `grep -rn "type = 7\|quantile(" R/` — no bare `quantile()` call without `type = 2`
- [ ] `grep -rn "len\|pos\|informat" R/proc_contents.R` — no such output columns
- [ ] `git log --oneline main..HEAD` — the characterization-test commit precedes the `data_dictionary()` refactor commit
