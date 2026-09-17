# `proc_freq()` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `proc_freq()`, a port of SAS `PROC FREQ` one-way and n-way frequency tables, to `hvtiRutilities`.

**Architecture:** One new source file, `R/proc_freq.R`, holding the exported function and five small internal helpers. It reuses `.check_columns()` and `.validate_weights()` from `R/proc_means.R` (same namespace, no import needed). Grouping uses `dplyr::group_by()` / `group_indices()` / `group_keys()` on exact values; row order uses `base::order(method = "radix", na.last = FALSE)` to reproduce SAS `ORDER=INTERNAL` with missing first.

**Tech Stack:** R, `dplyr`, `haven`, `labelled` (all already in `Imports`), `testthat` edition 3, roxygen2 (Rd markup), pkgdown, quarto vignettes.

**Spec:** `dev/specs/2026-09-16-proc-freq-design.md`

**Verified:** the final code and all five test files below were prototyped against `devtools::load_all()` on 2026-09-16: 87 expectations pass and `lintr` reports no lints in any of the six files.

## Global Constraints

- Signature (final): `proc_freq(data, tables, missing = FALSE, list = FALSE, weights = NULL)`.
- Result is always a plain `data.frame` (not a tibble), row names `1..n`.
- Statistic columns: one-way or `list = TRUE` gives `Frequency`, `Percent`, `Cum_Frequency`, `Cum_Percent`; an n-way crosstab gives `Frequency`, `Percent`, `Row_Percent`, `Col_Percent`.
- Percentages are never rounded.
- `attr(result, "frequency_missing")` is always present: integer unweighted, double weighted.
- Roxygen is **Rd markup, not markdown** (`\code{}`, `\itemize{}`, `\emph{}`); `DESCRIPTION` has no `Roxygen: list(markdown = TRUE)`.
- Lines at most 80 characters; add no lints.
- `man/` and `NAMESPACE` are generated: edit roxygen, run `devtools::document()`, never hand-edit.
- Every export must appear in `_pkgdown.yml` (pkgdown errors otherwise).
- No `Version:` bump. `NEWS.md` entry goes under `# hvtiRutilities (unreleased)`.
- Test expectations are hand-computed frozen literals, never recomputed with `dplyr` inside a test.
- Error messages use `call. = FALSE`.
- Work on branch `feat/proc-freq` (already created; the spec is committed there).

## File Map

| file | action | responsibility |
|---|---|---|
| `R/proc_freq.R` | create | `proc_freq()` and helpers `.check_flag()`, `.strip_labels()`, `.group_ids()`, `.pct_within()`, `.add_value_label_columns()` |
| `tests/testthat/test-proc_freq_values.R` | create | counts, percentages, ordering, the denominator trap |
| `tests/testthat/test-proc_freq_missing.R` | create | `missing`, `frequency_missing`, zero-row results |
| `tests/testthat/test-proc_freq_shape.R` | create | column layout, class, variable and value labels |
| `tests/testthat/test-proc_freq_weights.R` | create | `weights` |
| `tests/testthat/test-proc_freq_errors.R` | create | argument validation |
| `_pkgdown.yml` | modify | add `proc_freq` after `proc_means` |
| `NAMESPACE`, `man/proc_freq.Rd` | regenerate | via `devtools::document()` |
| `vignettes/sas-procedures.qmd` | modify | `proc_freq()` section |
| `NEWS.md` | modify | unreleased entry |

---

### Task 1: One-way and n-way tables with missing values

**Files:**
- Create: `R/proc_freq.R`
- Create: `tests/testthat/test-proc_freq_values.R`
- Create: `tests/testthat/test-proc_freq_missing.R`
- Create: `tests/testthat/test-proc_freq_shape.R`
- Modify: `_pkgdown.yml` (Data Documentation section)
- Regenerate: `NAMESPACE`, `man/proc_freq.Rd`

**Interfaces:**
- Consumes: `.check_columns(cols, data)` from `R/proc_means.R`. It stops with `"Column(s) not found in 'data': <cols>"`.
- Produces: `proc_freq(data, tables, missing = FALSE, list = FALSE)`; helpers `.strip_labels(x)` returning the vector without labels; `.group_ids(keys)` returning `list(id = integer, keys = data.frame)`; `.pct_within(freq, keys)` returning numeric.

- [ ] **Step 1: Write the failing value tests**

Create `tests/testthat/test-proc_freq_values.R`:

```r
library(testthat)
library(hvtiRutilities)

## Expected values in this file are hand-computed and frozen as literals. No
## SAS listing exists for these fixtures yet; they await the Phase 1 oracle.

test_that("a one-way table counts, percents and cumulates", {
  d <- data.frame(dead = c(1, 0, 0, 0, 1))
  res <- proc_freq(d, "dead")
  expect_equal(res$dead, c(0, 1))
  expect_equal(res$Frequency, c(3L, 2L))
  expect_equal(res$Percent, c(60, 40))
  expect_equal(res$Cum_Frequency, c(3L, 5L))
  expect_equal(res$Cum_Percent, c(60, 100))
})

test_that("unweighted frequencies are integers", {
  res <- proc_freq(data.frame(g = c("a", "b", "a")), "g")
  expect_type(res$Frequency, "integer")
  expect_type(res$Cum_Frequency, "integer")
})

test_that("percentages are not rounded", {
  res <- proc_freq(data.frame(g = c("a", "b", "b")), "g")
  expect_equal(res$Percent, c(100 / 3, 200 / 3))
})

test_that("character levels sort by byte value, as SAS does", {
  res <- proc_freq(data.frame(g = c("b", "B", "a", "b")), "g")
  expect_equal(res$g, c("B", "a", "b"))
  expect_equal(res$Frequency, c(1L, 1L, 2L))
})

test_that("factor levels keep declared order and drop unused levels", {
  f <- factor(c("III", "I", "II", "I"), levels = c("I", "II", "III", "IV"))
  res <- proc_freq(data.frame(nyha = f), "nyha")
  expect_equal(as.character(res$nyha), c("I", "II", "III"))
  expect_equal(res$Frequency, c(2L, 1L, 1L))
})

test_that("doubles that print alike are not merged", {
  res <- proc_freq(data.frame(x = c(0.1 + 0.2, 0.3, 0.3)), "x")
  expect_equal(nrow(res), 2L)
  expect_equal(res$Frequency, c(2L, 1L))
})

test_that("a two-way crosstab gives cell, row and column percents", {
  d <- data.frame(a = c("x", "x", "x", "y", "y"),
                  b = c(0, 1, 1, 0, 0))
  res <- proc_freq(d, c("a", "b"))
  expect_equal(res$a, c("x", "x", "y"))
  expect_equal(res$b, c(0, 1, 0))
  expect_equal(res$Frequency, c(1L, 2L, 2L))
  expect_equal(res$Percent, c(20, 40, 40))
  expect_equal(res$Row_Percent, c(100 / 3, 200 / 3, 100))
  expect_equal(res$Col_Percent, c(100 / 3, 100, 200 / 3))
})

test_that("a two-way list table cumulates over the grand total", {
  d <- data.frame(a = c("x", "x", "x", "y", "y"),
                  b = c(0, 1, 1, 0, 0))
  res <- proc_freq(d, c("a", "b"), list = TRUE)
  expect_equal(res$Percent, c(20, 40, 40))
  expect_equal(res$Cum_Frequency, c(1L, 3L, 5L))
  expect_equal(res$Cum_Percent, c(20, 60, 100))
})

test_that("three-way percent is within stratum, but list is of the total", {
  d <- data.frame(s = c(1, 1, 1, 2),
                  a = c("x", "x", "y", "x"),
                  b = c(0, 1, 0, 0))
  cross <- proc_freq(d, c("s", "a", "b"))
  expect_equal(cross$Percent, c(100 / 3, 100 / 3, 100 / 3, 100))
  expect_equal(cross$Row_Percent, c(50, 50, 100, 100))
  expect_equal(cross$Col_Percent, c(50, 100, 50, 100))

  listed <- proc_freq(d, c("s", "a", "b"), list = TRUE)
  expect_equal(listed$Percent, c(25, 25, 25, 25))
  expect_equal(listed$Cum_Percent, c(25, 50, 75, 100))
})

test_that("list = TRUE on a one-way table changes nothing", {
  d <- data.frame(g = c("a", "b", "b"))
  expect_identical(proc_freq(d, "g", list = TRUE), proc_freq(d, "g"))
})
```

Hand-check of the three-way fixture, the spec's central trap. Sorted cells: `(1,x,0)`, `(1,x,1)`, `(1,y,0)`, `(2,x,0)`, each with frequency 1. Crosstab `Percent` is within stratum `s`: stratum 1 has 3, so 33.3 each; stratum 2 has 1, so 100. `Row_Percent` is within `(s, a)`: `(1,x)` has 2, giving 50 and 50; `(1,y)` and `(2,x)` give 100. `Col_Percent` is within `(s, b)`: `(1,0)` has 2, so `(1,x,0)` and `(1,y,0)` are 50 each; `(1,1)` and `(2,0)` give 100. With `list = TRUE` every cell is 1 of 4, so 25.

- [ ] **Step 2: Write the failing missing-value tests**

Create `tests/testthat/test-proc_freq_missing.R`:

```r
library(testthat)
library(hvtiRutilities)

d <- data.frame(dead = c(1, 0, NA, 0, 1, 0))

test_that("missing = FALSE drops NA and reports frequency_missing", {
  res <- proc_freq(d, "dead")
  expect_equal(res$dead, c(0, 1))
  expect_equal(res$Frequency, c(3L, 2L))
  expect_equal(res$Percent, c(60, 40))
  expect_identical(attr(res, "frequency_missing"), 1L)
})

test_that("missing = TRUE counts NA as a level that sorts first", {
  res <- proc_freq(d, "dead", missing = TRUE)
  expect_equal(res$dead, c(NA, 0, 1))
  expect_equal(res$Frequency, c(1L, 3L, 2L))
  expect_equal(res$Percent, c(100 / 6, 50, 100 / 3))
  expect_equal(res$Cum_Frequency, c(1L, 4L, 6L))
  expect_equal(res$Cum_Percent, c(100 / 6, 200 / 3, 100))
  expect_identical(attr(res, "frequency_missing"), 0L)
})

test_that("frequency_missing is 0, not absent, when nothing is missing", {
  res <- proc_freq(data.frame(g = c("a", "b")), "g")
  expect_identical(attr(res, "frequency_missing"), 0L)
})

test_that("a row missing in any table variable is dropped from n-way tables", {
  d2 <- data.frame(a = c("x", "x", NA, "y"),
                   b = c(0, NA, 1, 1))
  res <- proc_freq(d2, c("a", "b"), list = TRUE)
  expect_equal(res$Frequency, c(1L, 1L))
  expect_equal(res$Percent, c(50, 50))
  expect_identical(attr(res, "frequency_missing"), 2L)
})

test_that("missing = TRUE keeps partial-NA combinations in n-way tables", {
  d2 <- data.frame(a = c("x", "x", NA, "y"),
                   b = c(0, NA, 1, 1))
  res <- proc_freq(d2, c("a", "b"), missing = TRUE, list = TRUE)
  expect_equal(res$a, c(NA, "x", "x", "y"))
  expect_equal(res$b, c(1, NA, 0, 1))
  expect_equal(res$Percent, c(25, 25, 25, 25))
})

test_that("a table with every row missing returns zero rows, not an error", {
  res <- proc_freq(data.frame(g = c(NA, NA)), "g")
  expect_equal(nrow(res), 0L)
  expect_named(res, c("g", "Frequency", "Percent", "Cum_Frequency",
                      "Cum_Percent"))
  expect_identical(attr(res, "frequency_missing"), 2L)
})

test_that("an all-missing two-way crosstab keeps its columns", {
  res <- proc_freq(data.frame(a = c(NA, "x"), b = c(1, NA)), c("a", "b"))
  expect_equal(nrow(res), 0L)
  expect_named(res, c("a", "b", "Frequency", "Percent", "Row_Percent",
                      "Col_Percent"))
})
```

- [ ] **Step 3: Write the failing shape tests**

Create `tests/testthat/test-proc_freq_shape.R` (Task 3 appends label tests to this file):

```r
library(testthat)
library(hvtiRutilities)

test_that("columns lead with table variables in the order given", {
  d <- data.frame(b = c(1, 2), a = c("x", "y"))
  expect_named(proc_freq(d, c("a", "b")),
               c("a", "b", "Frequency", "Percent", "Row_Percent",
                 "Col_Percent"))
  expect_named(proc_freq(d, c("a", "b"), list = TRUE),
               c("a", "b", "Frequency", "Percent", "Cum_Frequency",
                 "Cum_Percent"))
})

test_that("the result is a plain data frame with sequential row names", {
  res <- proc_freq(data.frame(g = c("b", "a", "b")), "g")
  expect_s3_class(res, "data.frame")
  expect_false(inherits(res, "tbl_df"))
  expect_equal(rownames(res), c("1", "2"))
})
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "proc_freq")'`
Expected: every test FAILs with `could not find function "proc_freq"`.

- [ ] **Step 5: Implement**

Create `R/proc_freq.R`. The roxygen block is minimal here and completed in Task 5.

```r
#' Frequency tables, in the style of SAS PROC FREQ
#'
#' @export
proc_freq <- function(data, tables, missing = FALSE, list = FALSE) {
  if (!is.data.frame(data)) {
    stop("'data' must be a data frame.", call. = FALSE)
  }
  .check_columns(tables, data)

  keys <- as.data.frame(lapply(data[tables], .strip_labels),
                        stringsAsFactors = FALSE)
  names(keys) <- tables

  is_missing <- Reduce(`|`, lapply(keys, is.na))
  if (missing) {
    frequency_missing <- 0L
  } else {
    frequency_missing <- sum(is_missing)
    keys <- keys[!is_missing, , drop = FALSE]
  }

  grouped <- .group_ids(keys)
  n_groups <- nrow(grouped$keys)
  out <- grouped$keys
  out$Frequency <- tabulate(grouped$id, nbins = n_groups)

  ## SAS ORDER=INTERNAL: missing sorts first, factors by level, characters
  ## by byte value (radix sorts in the C locale, as SAS does).
  ord <- do.call(base::order, c(unname(as.list(out[tables])),
                                list(na.last = FALSE, method = "radix")))
  out <- out[ord, , drop = FALSE]
  rownames(out) <- NULL

  freq <- out$Frequency
  n_vars <- length(tables)
  if (n_vars == 1L || list) {
    total <- sum(freq)
    out$Percent <- 100 * freq / total
    out$Cum_Frequency <- cumsum(freq)
    out$Cum_Percent <- 100 * out$Cum_Frequency / total
  } else {
    strata <- tables[seq_len(n_vars - 2L)]
    row_var <- tables[n_vars - 1L]
    col_var <- tables[n_vars]
    out$Percent <- .pct_within(freq, out[strata])
    out$Row_Percent <- .pct_within(freq, out[c(strata, row_var)])
    out$Col_Percent <- .pct_within(freq, out[c(strata, col_var)])
  }

  attr(out, "frequency_missing") <- frequency_missing
  out
}

## Internal: the stored values of a column, without value or variable labels.
## A haven_labelled vector becomes its underlying numeric or character vector;
## a factor stays a factor so its level order drives the sort.
.strip_labels <- function(x) {
  if (inherits(x, "haven_labelled")) {
    x <- haven::zap_labels(x)
  }
  attr(x, "label") <- NULL
  x
}

## Internal: integer group id per row, and one row of keys per group.
## Groups on exact values (not as.character()), so doubles that agree to 15
## significant digits are not merged. Unused factor levels form no group.
.group_ids <- function(keys) {
  g <- dplyr::group_by(keys, dplyr::across(dplyr::everything()))
  list(id = dplyr::group_indices(g),
       keys = as.data.frame(dplyr::group_keys(g)))
}

## Internal: 100 * freq as a share of its total within each group of keys.
## With no key columns the whole table is one group.
.pct_within <- function(freq, keys) {
  if (length(freq) == 0L) {
    return(numeric(0))
  }
  if (ncol(keys) == 0L) {
    return(100 * freq / sum(freq))
  }
  id <- .group_ids(keys)$id
  100 * freq / as.vector(rowsum(freq, id))[id]
}
```

Why these choices (for the implementer):
- `.group_ids()` groups with `dplyr` rather than `paste()` or `table()` keys. Keying on `as.character()` merges `0.1 + 0.2` with `0.3`; that exact defect shipped once in `proc_means()`'s `mode`. The "doubles that print alike" test pins it.
- `dplyr::group_by()` sorts NA **last**; the explicit `order(na.last = FALSE)` afterwards restores SAS's missing-first order, which the cumulative columns depend on.
- `rowsum(freq, id)` returns one row per sorted group id; ids are `1..k`, so indexing by `id` maps each cell to its group total.

- [ ] **Step 6: Add the export to the pkgdown index and regenerate**

In `_pkgdown.yml`, under `- title: Data Documentation`, change:

```yaml
  - proc_contents
  - proc_means
  - compare_datasets
```

to:

```yaml
  - proc_contents
  - proc_means
  - proc_freq
  - compare_datasets
```

Run: `Rscript -e 'devtools::document()'`
Expected: `Writing 'proc_freq.Rd'`, and `NAMESPACE` gains `export(proc_freq)`.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "proc_freq")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 56 ]` (values 29, missing 22, shape 5).

- [ ] **Step 8: Commit**

```bash
git add R/proc_freq.R tests/testthat/test-proc_freq_values.R tests/testthat/test-proc_freq_missing.R tests/testthat/test-proc_freq_shape.R _pkgdown.yml NAMESPACE man/proc_freq.Rd
git commit -m "feat: proc_freq() one-way and n-way tables with SAS missing handling

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Weights

**Files:**
- Modify: `R/proc_freq.R` (`proc_freq()` signature and body)
- Create: `tests/testthat/test-proc_freq_weights.R`

**Interfaces:**
- Consumes: `.validate_weights(weights, data)` from `R/proc_means.R`. It returns `NULL` when `weights` is `NULL`, otherwise the numeric weight vector. It stops on a name that is not a single string, an absent or non-numeric column, and on non-positive values with `"has non-positive value(s) at row(s): <rows>"`.
- Produces: `proc_freq(data, tables, missing = FALSE, list = FALSE, weights = NULL)`.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-proc_freq_weights.R`:

```r
library(testthat)
library(hvtiRutilities)

test_that("weighted frequency is the sum of weights", {
  d <- data.frame(g = c("a", "a", "b"), wt = c(1, 2.5, 4))
  res <- proc_freq(d, "g", weights = "wt")
  expect_equal(res$Frequency, c(3.5, 4))
  expect_equal(res$Percent, c(3.5 / 7.5 * 100, 4 / 7.5 * 100))
  expect_equal(res$Cum_Frequency, c(3.5, 7.5))
})

test_that("weighted frequency_missing sums the weights of dropped rows", {
  d <- data.frame(g = c("a", NA, "b"), wt = c(1, 2, 3))
  res <- proc_freq(d, "g", weights = "wt")
  expect_equal(res$Frequency, c(1, 3))
  expect_equal(res$Percent, c(25, 75))
  expect_identical(attr(res, "frequency_missing"), 2)
})

test_that("a missing weight excludes the row entirely", {
  d <- data.frame(g = c("a", "a", "b"), wt = c(1, NA, 3))
  res <- proc_freq(d, "g", weights = "wt")
  expect_equal(res$Frequency, c(1, 3))
  expect_identical(attr(res, "frequency_missing"), 0)
})

test_that("weights apply to crosstab denominators", {
  d <- data.frame(a = c("x", "x", "y"), b = c(0, 1, 0), wt = c(1, 3, 4))
  res <- proc_freq(d, c("a", "b"), weights = "wt")
  expect_equal(res$Percent, c(12.5, 37.5, 50))
  expect_equal(res$Row_Percent, c(25, 75, 100))
  expect_equal(res$Col_Percent, c(20, 100, 80))
})

test_that("a non-positive weight is an error naming the row", {
  d <- data.frame(g = c("a", "b"), wt = c(1, 0))
  expect_error(proc_freq(d, "g", weights = "wt"), "row\\(s\\): 2")
})
```

Hand-check of the crosstab fixture: total weight 8. Cells `(x,0)=1`, `(x,1)=3`, `(y,0)=4` give Percent 12.5, 37.5, 50. Row `x` totals 4, giving 25 and 75; row `y` gives 100. Column `0` totals 5, so `(x,0)` is 20 and `(y,0)` is 80; column `1` gives 100.

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'devtools::test(filter = "proc_freq_weights")'`
Expected: FAIL with `unused argument (weights = "wt")`.

- [ ] **Step 3: Implement**

In `R/proc_freq.R`, replace the signature line:

```r
proc_freq <- function(data, tables, missing = FALSE, list = FALSE) {
```

with:

```r
proc_freq <- function(data, tables, missing = FALSE, list = FALSE,
                      weights = NULL) {
```

Replace:

```r
  .check_columns(tables, data)

  keys <- as.data.frame(lapply(data[tables], .strip_labels),
                        stringsAsFactors = FALSE)
  names(keys) <- tables

  is_missing <- Reduce(`|`, lapply(keys, is.na))
  if (missing) {
    frequency_missing <- 0L
  } else {
    frequency_missing <- sum(is_missing)
    keys <- keys[!is_missing, , drop = FALSE]
  }

  grouped <- .group_ids(keys)
  n_groups <- nrow(grouped$keys)
  out <- grouped$keys
  out$Frequency <- tabulate(grouped$id, nbins = n_groups)
```

with:

```r
  .check_columns(tables, data)

  wvec <- .validate_weights(weights, data)
  if (!is.null(weights) && weights %in% tables) {
    stop("Weight column '", weights, "' is also named in 'tables'. A column ",
         "cannot be both a weight and a table variable.", call. = FALSE)
  }

  keys <- as.data.frame(lapply(data[tables], .strip_labels),
                        stringsAsFactors = FALSE)
  names(keys) <- tables

  if (!is.null(wvec)) {
    keep <- !is.na(wvec)
    keys <- keys[keep, , drop = FALSE]
    wvec <- wvec[keep]
  }

  is_missing <- Reduce(`|`, lapply(keys, is.na))
  if (missing) {
    frequency_missing <- if (is.null(wvec)) 0L else 0
  } else {
    frequency_missing <- if (is.null(wvec)) {
      sum(is_missing)
    } else {
      sum(wvec[is_missing])
    }
    keys <- keys[!is_missing, , drop = FALSE]
    wvec <- wvec[!is_missing]
  }

  grouped <- .group_ids(keys)
  n_groups <- nrow(grouped$keys)
  out <- grouped$keys
  out$Frequency <- if (is.null(wvec)) {
    tabulate(grouped$id, nbins = n_groups)
  } else if (n_groups == 0L) {
    numeric(0)
  } else {
    as.vector(rowsum(wvec, grouped$id))
  }
```

Notes: a missing weight drops the row **before** the table-variable NA check, so it counts toward neither the table nor `frequency_missing` (the "missing weight" test pins this). `wvec[!is_missing]` on `NULL` is `NULL`, so the unweighted path is unchanged. The `n_groups == 0L` branch avoids `rowsum()` on empty input.

- [ ] **Step 4: Run to verify pass**

Run: `Rscript -e 'devtools::test(filter = "proc_freq")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 68 ]` (Task 1's 56 plus 12 new).

- [ ] **Step 5: Commit**

```bash
git add R/proc_freq.R tests/testthat/test-proc_freq_weights.R
git commit -m "feat: weights argument for proc_freq()

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Variable and value labels

**Files:**
- Modify: `R/proc_freq.R`
- Modify: `tests/testthat/test-proc_freq_shape.R` (append)

**Interfaces:**
- Consumes: `labelled::var_label(x)` (label string or `NULL`), `labelled::val_labels(x)` (named vector `c(Label = value)` or `NULL`).
- Produces: helper `.add_value_label_columns(out, tables, val_labels)` returning a `data.frame`.

- [ ] **Step 1: Append the failing tests**

Append to `tests/testthat/test-proc_freq_shape.R`:

```r

test_that("variable labels survive, including after rows are dropped", {
  d <- data.frame(dead = c(1, 0, NA))
  labelled::var_label(d$dead) <- "Death indicator"
  res <- proc_freq(d, "dead")
  expect_equal(labelled::var_label(res$dead), "Death indicator")
})

test_that("variable labels survive weighting", {
  d <- data.frame(g = c("a", "b"), wt = c(1, NA))
  labelled::var_label(d$g) <- "Group"
  res <- proc_freq(d, "g", weights = "wt")
  expect_equal(labelled::var_label(res$g), "Group")
})

test_that("value-labelled variables gain a label column beside them", {
  d <- data.frame(status = haven::labelled(c(2, 1, 3, 2),
                                           labels = c(Alive = 1, Dead = 2)),
                  arm = c("a", "a", "b", "b"))
  res <- proc_freq(d, c("status", "arm"), list = TRUE)
  expect_named(res, c("status", "status_label", "arm", "Frequency",
                      "Percent", "Cum_Frequency", "Cum_Percent"))
  expect_false(inherits(res$status, "haven_labelled"))
  expect_equal(res$status, c(1, 2, 2, 3))
  expect_equal(res$status_label, c("Alive", "Dead", "Dead", NA))
})

test_that("a missing value-labelled value has an NA label", {
  d <- data.frame(status = haven::labelled(c(1, NA), labels = c(Alive = 1)))
  res <- proc_freq(d, "status", missing = TRUE)
  expect_equal(res$status_label, c(NA, "Alive"))
})

test_that("variables without value labels get no label column", {
  res <- proc_freq(data.frame(g = c("a", "b")), "g")
  expect_false("g_label" %in% names(res))
})
```

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'devtools::test(filter = "proc_freq_shape")'`
Expected: FAILs in the two variable-label tests (`var_label` is `NULL`) and the two value-label-column tests (column absent). "no label column" already passes; that is expected.

- [ ] **Step 3: Implement**

In `R/proc_freq.R`, insert immediately **before** `keys <- as.data.frame(...)`:

```r
  ## Read labels before any row subsetting: subsetting strips them.
  var_labels <- lapply(data[tables], labelled::var_label)
  val_labels <- lapply(data[tables], labelled::val_labels)

```

Replace:

```r
  attr(out, "frequency_missing") <- frequency_missing
  out
}
```

with:

```r
  for (v in tables) {
    labelled::var_label(out[[v]]) <- var_labels[[v]]
  }
  out <- .add_value_label_columns(out, tables, val_labels)

  attr(out, "frequency_missing") <- frequency_missing
  out
}
```

Append at the end of the file:

```r

## Internal: insert a <var>_label column after each variable that carried
## value labels, holding the label for each stored value (NA when none).
.add_value_label_columns <- function(out, tables, val_labels) {
  for (v in rev(tables)) {
    labs <- val_labels[[v]]
    if (is.null(labs)) {
      next
    }
    lab_col <- names(labs)[match(out[[v]], unname(labs))]
    pos <- match(v, names(out))
    out <- cbind(out[seq_len(pos)],
                 stats::setNames(data.frame(lab_col, stringsAsFactors = FALSE),
                                 paste0(v, "_label")),
                 out[-seq_len(pos)])
  }
  out
}
```

Notes: labels are reapplied after grouping and ordering, because `group_keys()` and row subsetting both drop the `label` attribute. This is the same trap that once dropped every label from weighted `proc_means()` calls. Iterating `rev(tables)` keeps `match(v, names(out))` correct while columns are inserted. `var_label<-` with `NULL` is a no-op, so unlabelled columns are unaffected.

- [ ] **Step 4: Run to verify pass**

Run: `Rscript -e 'devtools::test(filter = "proc_freq")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 76 ]` (68 plus 8 new).

- [ ] **Step 5: Commit**

```bash
git add R/proc_freq.R tests/testthat/test-proc_freq_shape.R
git commit -m "feat: proc_freq() keeps variable labels and reports value labels

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Argument validation

**Files:**
- Modify: `R/proc_freq.R`
- Create: `tests/testthat/test-proc_freq_errors.R`

**Interfaces:**
- Produces: helper `.check_flag(x, name)`, returning `invisible(TRUE)` or stopping with `"'<name>' must be a single TRUE or FALSE."`.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-proc_freq_errors.R`:

```r
library(testthat)
library(hvtiRutilities)

d <- data.frame(g = c("a", "b"), h = c(1, 2), wt = c(1, 2))

test_that("data must be a data frame", {
  expect_error(proc_freq(list(g = "a"), "g"), "must be a data frame")
})

test_that("tables must be a non-empty character vector", {
  expect_error(proc_freq(d, character(0)), "non-empty character vector")
  expect_error(proc_freq(d, 1), "non-empty character vector")
  expect_error(proc_freq(d, NA_character_), "non-empty character vector")
})

test_that("tables may not repeat a column", {
  expect_error(proc_freq(d, c("g", "g")), "more than once: g")
})

test_that("tables must name columns present in data", {
  expect_error(proc_freq(d, c("g", "nope")), "not found in 'data': nope")
})

test_that("missing and list must be a single TRUE or FALSE", {
  expect_error(proc_freq(d, "g", missing = "yes"),
               "'missing' must be a single TRUE or FALSE")
  expect_error(proc_freq(d, "g", list = NA),
               "'list' must be a single TRUE or FALSE")
  expect_error(proc_freq(d, "g", list = c(TRUE, FALSE)),
               "'list' must be a single TRUE or FALSE")
})

test_that("a weight column cannot also be a table variable", {
  expect_error(proc_freq(d, c("g", "wt"), weights = "wt"),
               "also named in 'tables'")
})

test_that("weights must name a numeric column", {
  expect_error(proc_freq(d, "h", weights = "g"), "must be numeric")
})
```

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'devtools::test(filter = "proc_freq_errors")'`
Expected: FAILs for "non-empty character vector", "more than once" and "single TRUE or FALSE". The other four already pass, because Tasks 1 and 2 implemented them; they stay as regression guards.

- [ ] **Step 3: Implement**

In `R/proc_freq.R`, replace:

```r
  .check_columns(tables, data)

  wvec <- .validate_weights(weights, data)
```

with:

```r
  if (!is.character(tables) || length(tables) == 0L || anyNA(tables)) {
    stop("'tables' must be a non-empty character vector of column names.",
         call. = FALSE)
  }
  if (anyDuplicated(tables) > 0L) {
    stop("'tables' names a column more than once: ",
         paste(unique(tables[duplicated(tables)]), collapse = ", "),
         call. = FALSE)
  }
  .check_columns(tables, data)
  .check_flag(missing, "missing")
  .check_flag(list, "list")

  wvec <- .validate_weights(weights, data)
```

Insert this helper directly after the closing `}` of `proc_freq()` (before `.strip_labels`):

```r

## Internal: stop unless x is a single TRUE or FALSE
.check_flag <- function(x, name) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    stop("'", name, "' must be a single TRUE or FALSE.", call. = FALSE)
  }
  invisible(TRUE)
}
```

- [ ] **Step 4: Run to verify pass**

Run: `Rscript -e 'devtools::test(filter = "proc_freq")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 87 ]` (76 plus 11 new).

- [ ] **Step 5: Commit**

```bash
git add R/proc_freq.R tests/testthat/test-proc_freq_errors.R
git commit -m "feat: argument validation for proc_freq()

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Documentation

**Files:**
- Modify: `R/proc_freq.R` (roxygen block only)
- Modify: `vignettes/sas-procedures.qmd`
- Modify: `NEWS.md`
- Regenerate: `man/proc_freq.Rd`

- [ ] **Step 1: Replace the roxygen block**

In `R/proc_freq.R`, replace:

```r
#' Frequency tables, in the style of SAS PROC FREQ
#'
#' @export
```

with:

```r
#' Frequency tables, in the style of SAS PROC FREQ
#'
#' @description
#' Produces the table SAS \code{PROC FREQ} prints for a \code{TABLES}
#' statement: one row per observed combination of levels, with frequencies
#' and percentages. One call is one table; a SAS step with several
#' \code{TABLES} statements is several calls.
#'
#' @details
#' The last name in \code{tables} is the column variable, the one before it
#' the row variable, and any earlier names are strata, as in SAS
#' \code{TABLES a*b*c}.
#'
#' \strong{Percentages depend on \code{list}, not only the columns shown.}
#' For a crosstab of three or more variables, SAS prints one row-by-column
#' table per stratum and computes \code{Percent} within that stratum. With
#' \code{list = TRUE}, \code{Percent} is of the grand total. The two agree for
#' one- and two-way tables and disagree from three variables on.
#'
#' \strong{Missing values sort first.} SAS treats missing as the smallest
#' value, so under \code{missing = TRUE} the missing level heads the table and
#' the cumulative columns count it first. \code{dplyr::count()} places
#' \code{NA} last, which moves every cumulative value.
#'
#' Rows follow SAS \code{ORDER=INTERNAL}: factors in declared level order,
#' numbers by value, character values by byte value (the C locale, so
#' \code{"B"} sorts before \code{"a"}). Unused factor levels are omitted, as
#' SAS omits zero-count levels without \code{SPARSE}.
#'
#' A \code{haven_labelled} variable is grouped on its stored value, and a
#' \code{<var>_label} column holding the value label follows it, as SAS groups
#' on the internal value and prints the formatted one. Variable labels on the
#' \code{tables} columns are kept.
#'
#' Percentages are not rounded. SAS rounds only for display, and a rounded
#' result would fail \code{\link{compare_parity}} against SAS output.
#'
#' Tests of association (\code{CHISQ}, \code{FISHER}, \code{MEASURES} and the
#' rest) are deliberately absent, for the same reason \code{\link{proc_means}}
#' has no inference statistics.
#'
#' @param data A data frame.
#' @param tables Character vector of one or more column names defining the
#'   table.
#' @param missing Logical. \code{FALSE} (the SAS default) excludes rows with a
#'   missing value in any \code{tables} variable from the table and from every
#'   denominator, and reports their count in the \code{frequency_missing}
#'   attribute. \code{TRUE}, SAS \code{/ MISSING}, treats missing as a level.
#' @param list Logical. \code{TRUE}, SAS \code{/ LIST}, gives cumulative
#'   columns and percentages of the grand total for an n-way table. It has no
#'   effect on a one-way table.
#' @param weights Character or \code{NULL}. Name of a single numeric column of
#'   weights, SAS \code{WEIGHT}. \code{Frequency} becomes the sum of weights.
#'   Rows with a missing weight are excluded entirely; non-positive weights
#'   are an error, as in \code{\link{proc_means}}.
#'
#' @return A data frame with one column per \code{tables} variable (each
#'   followed by a \code{<var>_label} column when the variable carries value
#'   labels), then:
#'   \itemize{
#'     \item for a one-way table, or \code{list = TRUE}: \code{Frequency},
#'       \code{Percent}, \code{Cum_Frequency}, \code{Cum_Percent};
#'     \item for an n-way crosstab: \code{Frequency}, \code{Percent} (within
#'       stratum), \code{Row_Percent}, \code{Col_Percent}.
#'   }
#'   \code{Frequency} is integer when unweighted and double when weighted.
#'   The attribute \code{frequency_missing} holds the count (or weight) of
#'   excluded missing rows, and is \code{0} when none were excluded. A table
#'   with no remaining rows is returned with zero rows, not an error.
#'
#' @seealso \code{\link{proc_means}}, \code{\link{proc_contents}}
#'
#' @export
#'
#' @examples
#' dta <- generate_survival_data(n = 200, seed = 42)
#'
#' # proc freq; table dead / missing;
#' proc_freq(dta, "dead", missing = TRUE)
#'
#' # proc freq; table sex * dead;
#' proc_freq(dta, c("sex", "dead"))
#'
#' # proc freq; table sex * dead / list;
#' proc_freq(dta, c("sex", "dead"), list = TRUE)
```

- [ ] **Step 2: Regenerate and check the help page**

Run: `Rscript -e 'devtools::document()'`
Expected: `Writing 'proc_freq.Rd'`.

Run: `grep -n '\*\*\|`' man/proc_freq.Rd`
Expected: no output. Markdown syntax in the `.Rd` means a roxygen line used markdown.

- [ ] **Step 3: Update the vignette**

In `vignettes/sas-procedures.qmd`:

(a) Replace both title occurrences (lines 2 and 7):

```
title: "PROC CONTENTS and PROC MEANS in R"
```

becomes

```
title: "PROC CONTENTS, PROC MEANS and PROC FREQ in R"
```

and

```
  %\VignetteIndexEntry{PROC CONTENTS and PROC MEANS in R}
```

becomes

```
  %\VignetteIndexEntry{PROC CONTENTS, PROC MEANS and PROC FREQ in R}
```

(b) Replace the heading and first two paragraphs of `## Two Procedures You Already Run`:

```
## Two Procedures You Already Run

Open a new extract in SAS and you almost certainly run two things before
anything else. `PROC CONTENTS` to see what arrived: how many observations, how
many variables, what each one is called and how it is stored. Then `PROC MEANS`
to see whether the numbers are plausible: means, ranges, how much is missing.

Neither is a modelling step. They are the sanity check you do before you trust
the file enough to analyse it. `proc_contents()` and `proc_means()` are those
two habits, kept intact in R.
```

with:

```
## Three Procedures You Already Run

Open a new extract in SAS and you almost certainly run three things before
anything else. `PROC CONTENTS` to see what arrived: how many observations, how
many variables, what each one is called and how it is stored. `PROC MEANS` to
see whether the numbers are plausible: means, ranges, how much is missing. And
`PROC FREQ` to see whether the categories are: how many died, how the cohort
splits across the groups you will compare.

None of them is a modelling step. They are the sanity check you do before you
trust the file enough to analyse it. `proc_contents()`, `proc_means()` and
`proc_freq()` are those three habits, kept intact in R.
```

(c) Insert this new section immediately before `## Did the Extract Change? \`compare_datasets()\``:

````
## Do the Categories Look Right? `proc_freq()`

The SAS step

```sas
proc freq data=cohort;
  table dead / missing;
  table sex * dead;
run;
```

is two calls in R, one per `TABLES` statement:

```{r freq-oneway}
proc_freq(dta, "dead", missing = TRUE)
```

```{r freq-twoway}
proc_freq(dta, c("sex", "dead"))
```

The result is always a data frame with one row per combination of levels, so
you can filter or join it. For a crosstab, `Row_Percent` and `Col_Percent`
replace the cumulative columns. Add `list = TRUE` for the `/ LIST` layout:

```{r freq-list}
proc_freq(dta, c("sex", "dead"), list = TRUE)
```

### Missing Values

Without `missing = TRUE`, rows with a missing value in any table variable are
left out of the table and out of every percentage, as in SAS. SAS prints how
many it dropped as "Frequency Missing". `proc_freq()` keeps that count in an
attribute, so it is not lost:

```{r freq-missing}
dta_na <- dta
dta_na$nyha_class[c(3, 17, 40)] <- NA

res <- proc_freq(dta_na, "nyha_class")
res
attr(res, "frequency_missing")
```

With `missing = TRUE`, the missing level comes **first**, because SAS sorts
missing below every other value. `dplyr::count()` puts `NA` last, which
changes every cumulative column in a hand translation.

### The Denominator Trap

This is the `proc_freq()` counterpart of the quartile trap: the numbers move
and nothing warns you.

For two variables, `Percent` is out of the table total whichever layout you
ask for. From three variables on, a SAS crosstab prints one table per level of
the first variable and computes `Percent` **within** that table. `/ LIST`
computes it out of the grand total. Four patients show it:

```{r freq-trap}
d <- data.frame(site = c(1, 1, 1, 2),
                arm  = c("x", "x", "y", "x"),
                dead = c(0, 1, 0, 0))

proc_freq(d, c("site", "arm", "dead"))

proc_freq(d, c("site", "arm", "dead"), list = TRUE)
```

The same site 2 patient is 100 percent of the crosstab and 25 percent of the
list. Both are what SAS prints; they answer different questions. Match the
option in the SAS step you are reproducing.

````

(d) In the `## Where the R Version Differs` table, insert after the row that begins `| Class level order |`:

```
| `PROC FREQ` missing values | Dropped unless `MISSING`; count printed | Dropped unless `missing = TRUE`; count in `attr(, "frequency_missing")` |
| `PROC FREQ` level order | `ORDER=INTERNAL`, missing first | Same, missing first |
| `PROC FREQ` percentages | Rounded for display | Unrounded |
| `PROC FREQ` tests (`CHISQ`, `FISHER`, ...) | Available | Not ported |
```

(e) In `## Checklist`, insert after the item that begins `- [ ] Declare ordered clinical scales`:

```
- [ ] Set `list` to match the SAS step you are reproducing; from three
      variables on it changes `Percent`, not just the layout.
- [ ] Read `attr(, "frequency_missing")` when you leave `missing = FALSE`.
```

(f) In `## See Also`, replace:

```
- `?proc_contents`, `?proc_means`, `?compare_datasets`
```

with:

```
- `?proc_contents`, `?proc_means`, `?proc_freq`, `?compare_datasets`
```

- [ ] **Step 4: Render the vignette**

The vignette loads the installed package when there is one, so install first:

Run: `Rscript -e 'devtools::install(quick = TRUE, upgrade = "never"); quarto::quarto_render("vignettes/sas-procedures.qmd", quiet = TRUE)'`
Expected: renders without error. In the HTML, the `freq-trap` crosstab shows `Percent` 33.33, 33.33, 33.33, 100, the list shows 25 four times, and the `freq-missing` attribute prints `3`. Then remove the render output:

```bash
rm -f vignettes/sas-procedures.html && rm -rf vignettes/sas-procedures_files
```

- [ ] **Step 5: Add the NEWS entry**

`NEWS.md` currently begins with `# hvtiRutilities 1.1.12`. Insert above it:

```markdown
# hvtiRutilities (unreleased)

## New features

* **`proc_freq()` ports SAS `PROC FREQ` frequency tables.** One-way and n-way
  tables with the `MISSING` and `LIST` options, cell, row and column
  percentages, cumulative columns, and `WEIGHT`. Missing values sort first and
  character levels by byte value, as in SAS. From three variables on, a
  crosstab computes `Percent` within stratum and a list table out of the grand
  total, so `list` changes the numbers, not only the layout. Excluded missing
  rows are counted in `attr(, "frequency_missing")`. Tests of association are
  not ported.

```

- [ ] **Step 6: Commit**

```bash
git add R/proc_freq.R man/proc_freq.Rd vignettes/sas-procedures.qmd NEWS.md
git commit -m "docs: document proc_freq() in help, vignette and NEWS

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Full verification and pull request

**Files:** none changed unless a check fails.

- [ ] **Step 1: Full test suite**

Run: `Rscript -e 'devtools::test()'`
Expected: `FAIL 0`. Record the total PASS count for the PR body.

- [ ] **Step 2: Docs are current**

Run: `Rscript -e 'roxygen2::roxygenise()' && git diff --exit-code man/ NAMESPACE DESCRIPTION`
Expected: exit 0 (this is the CI docs-current job).

- [ ] **Step 3: Lint adds nothing**

Run: `Rscript -e 'l <- lintr::lint_package(); print(l[grepl("proc_freq", vapply(l, function(x) x$filename, ""))])'`
Expected: `No lints found`.

- [ ] **Step 4: R CMD check at 0/0/0, with the manual**

Run:

```bash
rm -rf /tmp/hvti-check && mkdir -p /tmp/hvti-check && git archive HEAD | tar -x -C /tmp/hvti-check && cd /tmp/hvti-check && R CMD build . && R CMD check --as-cran hvtiRutilities_*.tar.gz
```

Expected: `Status: OK` (0 errors, 0 warnings, 0 notes). Build from `git archive`, not the working tree, which can add spurious vignette and hidden-file notes. If a NOTE appears, fix it; do not accept it.

- [ ] **Step 5: pkgdown reference index**

Run: `Rscript -e 'pkgdown::check_pkgdown()'`
Expected: `No problems found.`

- [ ] **Step 6: Push and open the PR**

```bash
git push -u origin feat/proc-freq
gh pr create --title "feat: proc_freq(), a port of SAS PROC FREQ" --body "$(cat <<'EOF'
Ports SAS `PROC FREQ` frequency tables as `proc_freq()`.

Design: `dev/specs/2026-09-16-proc-freq-design.md`
Plan: `dev/specs/2026-09-16-proc-freq-plan.md`

- One-way and n-way tables; `missing`, `list`, `weights`
- Always a long data frame; missing sorts first; unrounded percentages
- `frequency_missing` attribute mirrors SAS's "Frequency Missing"
- Crosstab `Percent` is within stratum, `list` is of the grand total (differs from 3 variables on)
- Tests of association not ported (same rule as `proc_means()`)

Verification: `devtools::test()` FAIL 0; `R CMD check --as-cran` with manual 0/0/0; docs current; no new lints; `pkgdown::check_pkgdown()` clean.

Expected values are hand-computed; no SAS listing exists yet for these fixtures.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: a PR URL. The PR needs one approving review from someone other than the author before it can merge; Copilot reviews once on open.
