# proc_means() unistats Vocabulary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `proc_means()` with the nine descriptive statistics from the SAS `unistats` macro and a `weights` argument, without changing any existing behaviour.

**Architecture:** A `.STATS` registry replaces the flat keyword vector in `R/proc_means.R`. Each entry declares its compute function, whether it responds to weights, and whether it is integer-typed. `.validate_stats()`, `.compute_stat()` and `.empty_means()` all read from it, so the weighted/unweighted contract lives in one assertable place instead of across nine function bodies.

**Tech Stack:** R (>= 4.1.0), testthat edition 3, roxygen2 8.1.0, `e1071` (new, Suggests-only, tests only).

**Spec:** `specs/2026-08-14-proc-means-unistats-design.md`

## Global Constraints

- Package version is a straight three-digit semver. Bump the patch digit only; never add a fourth component. Current version is `1.0.4` (`DESCRIPTION:4`).
- Every version bump updates both `DESCRIPTION:4` and the top heading of `NEWS.md`.
- `R CMD check --as-cran` must be run from a clean `git archive` export, with the manual (no `--no-manual`), and must end at 0 errors, 0 warnings, and no NOTE beyond the standing "New submission".
- Overall check time stays well inside 10 minutes. All test fixtures are small.
- Quantiles use `stats::quantile(type = 2)`, the R equivalent of SAS `QNTLDEF=5`. Never change this to `type = 7`.
- `e1071` is `Suggests` only. Every test that uses it opens with `skip_if_not_installed("e1071")`.
- Existing exported behaviour must not change when `weights = NULL`.
- `data_dictionary()` calls `.compute_stat()` positionally at `R/data_dictionary.R:88-90`. Any new parameter must be added after `stat` with a default.
- Roxygen: run `devtools::document()` after any change to a roxygen block. Do not hand-edit files in `man/`.
- Branch from `spec/proc-means-unistats`. Never commit to `main`.

---

### Task 1: Introduce the `.STATS` registry with no behaviour change

Rewire the existing thirteen keywords through a registry. Nothing new is added; this is pure restructuring, so every existing test must still pass untouched.

**Files:**
- Modify: `R/proc_means.R:151-183` (replace `.validate_stats()` and `.compute_stat()`)
- Modify: `R/proc_means.R:210-225` (`.empty_means()` reads the `integer` flag)
- Test: `tests/testthat/test-proc_means_registry.R` (create)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `.STATS` — a named `list`. Each element is `list(fun = function(x, v, w) numeric(1), weighted = logical(1), integer = logical(1))`. `x` is the raw vector including `NA`; `v` is `x` with `NA` removed; `w` is a numeric vector aligned to `v`, or `NULL`.
  - `.compute_stat(x, stat, w = NULL)` — unchanged return contract, new third parameter.
  - `.wmean(v, w)` — weighted mean helper, returns `numeric(1)`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-proc_means_registry.R`:

```r
library(testthat)
library(hvtiRutilities)

test_that(".STATS declares every non-quantile keyword", {
  expect_setequal(
    names(hvtiRutilities:::.STATS),
    c("n", "nmiss", "mean", "std", "min", "max", "sum", "range",
      "stderr", "cv", "median", "q1", "q3")
  )
})

test_that("every .STATS name is accepted by .validate_stats", {
  expect_silent(hvtiRutilities:::.validate_stats(names(hvtiRutilities:::.STATS)))
})

test_that(".STATS marks exactly the integer-typed statistics", {
  ints <- Filter(function(s) s$integer, hvtiRutilities:::.STATS)
  expect_setequal(names(ints), c("n", "nmiss"))
})

test_that(".STATS marks exactly the weight-responsive statistics", {
  wtd <- Filter(function(s) s$weighted, hvtiRutilities:::.STATS)
  expect_setequal(names(wtd), c("mean", "std", "sum", "stderr", "cv"))
})

test_that(".compute_stat accepts a weights argument positionally after stat", {
  expect_equal(hvtiRutilities:::.compute_stat(c(1, 2, 3), "mean", NULL), 2)
})

test_that("cv is NA when the mean is zero, matching SAS", {
  # R would return Inf here; SAS emits missing.
  expect_true(is.na(hvtiRutilities:::.compute_stat(c(-2, 0, 2), "cv")))
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Rscript -e 'pkgload::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-proc_means_registry.R")'`

Expected: FAIL with `object '.STATS' not found`.

- [ ] **Step 3: Write the registry and rewire the three consumers**

In `R/proc_means.R`, replace the whole block from `## Internal: reject unknown statistic keywords` through the end of `.compute_stat()` (currently lines 150-183) with:

```r
## Internal: weighted mean, or the plain mean when w is NULL
.wmean <- function(v, w) {
  if (is.null(w)) mean(v) else sum(w * v) / sum(w)
}

## Internal: weighted variance at SAS VARDEF=DF -- the divisor is the count of
## non-missing observations minus one, not the sum of the weights.
.wvar <- function(v, w) {
  n <- length(v)
  if (n < 2L) {
    return(NA_real_)
  }
  m <- .wmean(v, w)
  css <- if (is.null(w)) sum((v - m)^2) else sum(w * (v - m)^2)
  css / (n - 1)
}

## =============================================================================
## Internal: the statistic registry.
##
## Each entry carries its compute function plus two flags. `weighted` is the
## contract from the design: .compute_stat() passes weights to a statistic only
## when its flag is TRUE, so a statistic cannot become weighted by someone
## editing its body. `integer` types the zero-row result.
##
## fun(x, v, w): x is the raw vector including NA, v is x with NA removed, and w
## is a numeric vector aligned to v, or NULL.
.STATS <- list(
  n = list(
    fun = function(x, v, w) length(v),
    weighted = FALSE, integer = TRUE
  ),
  nmiss = list(
    fun = function(x, v, w) sum(is.na(x)),
    weighted = FALSE, integer = TRUE
  ),
  mean = list(
    fun = function(x, v, w) if (length(v) == 0L) NA_real_ else .wmean(v, w),
    weighted = TRUE, integer = FALSE
  ),
  std = list(
    fun = function(x, v, w) sqrt(.wvar(v, w)),
    weighted = TRUE, integer = FALSE
  ),
  min = list(
    fun = function(x, v, w) if (length(v) == 0L) NA_real_ else min(v),
    weighted = FALSE, integer = FALSE
  ),
  max = list(
    fun = function(x, v, w) if (length(v) == 0L) NA_real_ else max(v),
    weighted = FALSE, integer = FALSE
  ),
  sum = list(
    fun = function(x, v, w) {
      if (length(v) == 0L) NA_real_ else if (is.null(w)) sum(v) else sum(w * v)
    },
    weighted = TRUE, integer = FALSE
  ),
  range = list(
    fun = function(x, v, w) if (length(v) == 0L) NA_real_ else max(v) - min(v),
    weighted = FALSE, integer = FALSE
  ),
  stderr = list(
    fun = function(x, v, w) sqrt(.wvar(v, w) / length(v)),
    weighted = TRUE, integer = FALSE
  ),
  cv = list(
    fun = function(x, v, w) {
      s <- sqrt(.wvar(v, w))
      m <- .wmean(v, w)
      # SAS emits missing when the mean is zero; R would give Inf.
      if (is.na(s) || m == 0) NA_real_ else 100 * s / m
    },
    weighted = TRUE, integer = FALSE
  ),
  median = list(
    fun = function(x, v, w) .quantile_stat(v, "median"),
    weighted = FALSE, integer = FALSE
  ),
  q1 = list(
    fun = function(x, v, w) .quantile_stat(v, "q1"),
    weighted = FALSE, integer = FALSE
  ),
  q3 = list(
    fun = function(x, v, w) .quantile_stat(v, "q3"),
    weighted = FALSE, integer = FALSE
  )
)

## Internal: reject unknown statistic keywords
.validate_stats <- function(stats) {
  known <- names(.STATS)
  ok <- stats %in% known | grepl("^p([1-9]|[1-9][0-9])$", stats)
  if (!all(ok)) {
    stop("Unrecognised statistic keyword(s): ",
         paste(stats[!ok], collapse = ", "),
         ". Valid keywords are: ", paste(known, collapse = ", "),
         ", and pNN for NN from 1 to 99.", call. = FALSE)
  }
  invisible(TRUE)
}

## Internal: one statistic from one vector, SAS semantics.
## `w` is a weight vector aligned to `x`, or NULL. Statistics whose registry
## entry is not marked `weighted` never see it.
.compute_stat <- function(x, stat, w = NULL) {
  x <- as.numeric(x)
  keep <- !is.na(x)
  v <- x[keep]

  entry <- .STATS[[stat]]
  if (is.null(entry)) {
    return(.quantile_stat(v, stat))
  }
  wv <- if (isTRUE(entry$weighted) && !is.null(w)) w[keep] else NULL
  entry$fun(x, v, wv)
}
```

Then change `.empty_means()` at `R/proc_means.R:214` from:

```r
    out[[s]] <- if (s %in% c("n", "nmiss")) integer() else numeric()
```

to:

```r
    entry <- .STATS[[s]]
    out[[s]] <- if (isTRUE(entry$integer)) integer() else numeric()
```

- [ ] **Step 4: Run the new test and the full suite**

Run: `Rscript -e 'pkgload::load_all(quiet=TRUE); testthat::set_max_fails(Inf); testthat::test_dir("tests/testthat")'`

Expected: PASS, 0 failures. The pre-existing `proc_means` and `data_dictionary` tests must pass unmodified — this task changes no behaviour.

- [ ] **Step 5: Commit**

```bash
git add R/proc_means.R tests/testthat/test-proc_means_registry.R
git commit -m "refactor: route proc_means() statistics through a registry"
```

---

### Task 2: Add the six formula-only statistics

`nobs`, `var`, `uss`, `css`, `qrange`, `mode`. All are checkable against independent expressions, so no new dependency is needed yet.

**Files:**
- Modify: `R/proc_means.R` (add six `.STATS` entries)
- Test: `tests/testthat/test-proc_means_stats.R` (create)

**Interfaces:**
- Consumes: `.STATS`, `.compute_stat(x, stat, w = NULL)`, `.wmean(v, w)`, `.wvar(v, w)` from Task 1.
- Produces: six new `.STATS` names — `nobs`, `var`, `uss`, `css`, `qrange`, `mode`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-proc_means_stats.R`:

```r
library(testthat)
library(hvtiRutilities)

cs <- function(x, stat, w = NULL) hvtiRutilities:::.compute_stat(x, stat, w)

x9 <- c(2, 4, 4, 4, 5, 5, 7, 9, NA)

test_that("nobs counts every observation including missing", {
  expect_equal(cs(x9, "nobs"), 9L)
  expect_equal(cs(x9, "n"), 8L)
  expect_equal(cs(x9, "nmiss"), 1L)
})

test_that("var matches stats::var", {
  expect_equal(cs(x9, "var"), stats::var(c(2, 4, 4, 4, 5, 5, 7, 9)))
})

test_that("uss is the uncorrected sum of squares", {
  expect_equal(cs(x9, "uss"), sum(c(2, 4, 4, 4, 5, 5, 7, 9)^2))
})

test_that("css is the corrected sum of squares", {
  v <- c(2, 4, 4, 4, 5, 5, 7, 9)
  expect_equal(cs(x9, "css"), sum((v - mean(v))^2))
})

test_that("qrange is q3 minus q1 at QNTLDEF=5", {
  expect_equal(cs(x9, "qrange"), cs(x9, "q3") - cs(x9, "q1"))
})

test_that("mode returns the most frequent value", {
  expect_equal(cs(x9, "mode"), 4)
})

test_that("mode returns the smallest value when modes tie", {
  # 3 and 1 both occur twice; SAS reports the smallest.
  expect_equal(cs(c(3, 3, 1, 1, 5), "mode"), 1)
})

test_that("mode is NA when no value repeats", {
  expect_true(is.na(cs(c(1, 2, 3), "mode")))
})

test_that("var is NA below two observations", {
  expect_true(is.na(cs(c(5), "var")))
})

test_that("uss and css are NA with no observations", {
  expect_true(is.na(cs(c(NA_real_), "uss")))
  expect_true(is.na(cs(c(NA_real_), "css")))
})

test_that("qrange is NA with no observations", {
  expect_true(is.na(cs(c(NA_real_), "qrange")))
})

test_that("the new keywords are accepted by proc_means", {
  d <- data.frame(a = c(1, 2, 2, 8))
  res <- proc_means(d, stats = c("nobs", "var", "uss", "css", "qrange", "mode"))
  expect_equal(nrow(res), 1L)
  expect_true(all(c("nobs", "var", "uss", "css", "qrange", "mode") %in% names(res)))
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Rscript -e 'pkgload::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-proc_means_stats.R")'`

Expected: FAIL with `Unrecognised statistic keyword(s): nobs`.

- [ ] **Step 3: Add the six registry entries**

In `R/proc_means.R`, insert these entries into `.STATS`. Put `nobs` immediately after `nmiss`, and the rest after `cv`:

```r
  nobs = list(
    fun = function(x, v, w) length(x),
    weighted = FALSE, integer = TRUE
  ),
```

```r
  var = list(
    fun = function(x, v, w) .wvar(v, w),
    weighted = TRUE, integer = FALSE
  ),
  uss = list(
    fun = function(x, v, w) {
      if (length(v) == 0L) NA_real_ else if (is.null(w)) sum(v^2) else sum(w * v^2)
    },
    weighted = TRUE, integer = FALSE
  ),
  css = list(
    fun = function(x, v, w) {
      if (length(v) == 0L) {
        return(NA_real_)
      }
      m <- .wmean(v, w)
      if (is.null(w)) sum((v - m)^2) else sum(w * (v - m)^2)
    },
    weighted = TRUE, integer = FALSE
  ),
  qrange = list(
    fun = function(x, v, w) {
      if (length(v) == 0L) {
        return(NA_real_)
      }
      .quantile_stat(v, "q3") - .quantile_stat(v, "q1")
    },
    weighted = FALSE, integer = FALSE
  ),
  mode = list(
    fun = function(x, v, w) {
      if (length(v) == 0L) {
        return(NA_real_)
      }
      tab <- table(v)
      top <- max(tab)
      if (top == 1L) {
        return(NA_real_)          # SAS: no mode when nothing repeats
      }
      # SAS reports the smallest value among tied modes.
      min(as.numeric(names(tab)[tab == top]))
    },
    weighted = FALSE, integer = FALSE
  ),
```

Update the registry-contract test from Task 1 in `tests/testthat/test-proc_means_registry.R` to include the new names:

```r
test_that(".STATS declares every non-quantile keyword", {
  expect_setequal(
    names(hvtiRutilities:::.STATS),
    c("n", "nmiss", "nobs", "mean", "std", "min", "max", "sum", "range",
      "stderr", "cv", "var", "uss", "css", "qrange", "mode",
      "median", "q1", "q3")
  )
})

test_that(".STATS marks exactly the integer-typed statistics", {
  ints <- Filter(function(s) s$integer, hvtiRutilities:::.STATS)
  expect_setequal(names(ints), c("n", "nmiss", "nobs"))
})

test_that(".STATS marks exactly the weight-responsive statistics", {
  wtd <- Filter(function(s) s$weighted, hvtiRutilities:::.STATS)
  expect_setequal(names(wtd),
                  c("mean", "std", "sum", "stderr", "cv", "var", "uss", "css"))
})
```

- [ ] **Step 4: Run the tests**

Run: `Rscript -e 'pkgload::load_all(quiet=TRUE); testthat::set_max_fails(Inf); testthat::test_dir("tests/testthat")'`

Expected: PASS, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add R/proc_means.R tests/testthat/
git commit -m "feat: proc_means() gains nobs, var, uss, css, qrange and mode"
```

---

### Task 3: Add `skewness` and `kurtosis`, cross-validated against `e1071`

**Files:**
- Modify: `R/proc_means.R` (two `.STATS` entries, two helpers)
- Modify: `DESCRIPTION` (add `e1071` to `Suggests`)
- Test: `tests/testthat/test-proc_means_shape.R` (create)

**Interfaces:**
- Consumes: `.STATS`, `.wmean(v, w)`, `.wvar(v, w)`.
- Produces: `.STATS` names `skewness` and `kurtosis`. Both accept `w`; this task exercises only the `w = NULL` path.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-proc_means_shape.R`:

```r
library(testthat)
library(hvtiRutilities)

cs <- function(x, stat, w = NULL) hvtiRutilities:::.compute_stat(x, stat, w)

# A deliberately skewed, non-symmetric sample.
xs <- c(1, 2, 2, 3, 3, 3, 4, 4, 8, 15)

test_that("skewness matches the SAS definition (e1071 type 2)", {
  skip_if_not_installed("e1071")
  expect_equal(cs(xs, "skewness"), e1071::skewness(xs, type = 2))
})

test_that("kurtosis matches the SAS definition (e1071 type 2)", {
  skip_if_not_installed("e1071")
  expect_equal(cs(xs, "kurtosis"), e1071::kurtosis(xs, type = 2))
})

test_that("skewness ignores missing values", {
  skip_if_not_installed("e1071")
  expect_equal(cs(c(xs, NA), "skewness"), e1071::skewness(xs, type = 2))
})

test_that("skewness is NA below three observations", {
  expect_true(is.na(cs(c(1, 2), "skewness")))
})

test_that("kurtosis is NA below four observations", {
  expect_true(is.na(cs(c(1, 2, 3), "kurtosis")))
})

test_that("skewness and kurtosis are NA for a constant column", {
  # s == 0 gives 0/0; SAS returns missing, not NaN.
  k <- rep(4, 10)
  expect_true(is.na(cs(k, "skewness")))
  expect_true(is.na(cs(k, "kurtosis")))
  expect_false(is.nan(cs(k, "skewness")))
})

test_that("proc_means accepts the shape keywords", {
  skip_if_not_installed("e1071")
  d <- data.frame(a = xs)
  res <- proc_means(d, stats = c("skewness", "kurtosis"))
  expect_equal(res$skewness, e1071::skewness(xs, type = 2))
  expect_equal(res$kurtosis, e1071::kurtosis(xs, type = 2))
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Rscript -e 'pkgload::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-proc_means_shape.R")'`

Expected: FAIL with `Unrecognised statistic keyword(s): skewness`.

- [ ] **Step 3: Implement both statistics**

Add these two helpers to `R/proc_means.R`, immediately after `.wvar()`:

```r
## Internal: SAS skewness -- the adjusted Fisher-Pearson standardised third
## moment, not R's naive moment ratio. Equals e1071::skewness(type = 2).
## The weighted form raises each weight to 3/2, per the SAS documentation.
.wskew <- function(v, w) {
  n <- length(v)
  if (n < 3L) {
    return(NA_real_)
  }
  s <- sqrt(.wvar(v, w))
  if (is.na(s) || s == 0) {
    return(NA_real_)
  }
  z <- (v - .wmean(v, w)) / s
  acc <- if (is.null(w)) sum(z^3) else sum(w^(3 / 2) * z^3)
  (n / ((n - 1) * (n - 2))) * acc
}

## Internal: SAS kurtosis -- excess kurtosis, adjusted Fisher-Pearson.
## Equals e1071::kurtosis(type = 2). The weighted form squares each weight.
.wkurt <- function(v, w) {
  n <- length(v)
  if (n < 4L) {
    return(NA_real_)
  }
  s <- sqrt(.wvar(v, w))
  if (is.na(s) || s == 0) {
    return(NA_real_)
  }
  z <- (v - .wmean(v, w)) / s
  acc <- if (is.null(w)) sum(z^4) else sum(w^2 * z^4)
  (n * (n + 1) / ((n - 1) * (n - 2) * (n - 3))) * acc -
    3 * (n - 1)^2 / ((n - 2) * (n - 3))
}
```

Add these entries to `.STATS`, after `css`:

```r
  skewness = list(
    fun = function(x, v, w) .wskew(v, w),
    weighted = TRUE, integer = FALSE
  ),
  kurtosis = list(
    fun = function(x, v, w) .wkurt(v, w),
    weighted = TRUE, integer = FALSE
  ),
```

Update both contract tests in `tests/testthat/test-proc_means_registry.R`:

```r
test_that(".STATS declares every non-quantile keyword", {
  expect_setequal(
    names(hvtiRutilities:::.STATS),
    c("n", "nmiss", "nobs", "mean", "std", "min", "max", "sum", "range",
      "stderr", "cv", "var", "uss", "css", "skewness", "kurtosis",
      "qrange", "mode", "median", "q1", "q3")
  )
})

test_that(".STATS marks exactly the weight-responsive statistics", {
  wtd <- Filter(function(s) s$weighted, hvtiRutilities:::.STATS)
  expect_setequal(names(wtd),
                  c("mean", "std", "sum", "stderr", "cv", "var", "uss", "css",
                    "skewness", "kurtosis"))
})
```

In `DESCRIPTION`, add `e1071` to `Suggests` in alphabetical position (the list is alphabetical; `e1071` goes before `knitr`).

- [ ] **Step 4: Run the tests**

Run: `Rscript -e 'pkgload::load_all(quiet=TRUE); testthat::set_max_fails(Inf); testthat::test_dir("tests/testthat")'`

Expected: PASS, 0 failures. If `e1071` is not installed, install it with `Rscript -e 'install.packages("e1071")'` — the cross-validation is the point of this task, so a skipped test is not an acceptable outcome here.

- [ ] **Step 5: Commit**

```bash
git add R/proc_means.R DESCRIPTION tests/testthat/
git commit -m "feat: proc_means() gains skewness and kurtosis, SAS definitions"
```

---

### Task 4: Add the `weights` argument and `sumwgt`

Plumbing and validation only. No existing statistic changes value yet, because `weights` defaults to `NULL`.

**Files:**
- Modify: `R/proc_means.R:60-138` (signature, validation, row filtering, threading)
- Modify: `R/proc_means.R:200-207` (`.means_row()` gains `w`)
- Modify: `R/proc_means.R` (`sumwgt` registry entry)
- Test: `tests/testthat/test-proc_means_weights.R` (create)

**Interfaces:**
- Consumes: `.STATS`, `.compute_stat(x, stat, w = NULL)`, `.check_columns(cols, data)`.
- Produces:
  - `proc_means(data, vars = NULL, class = NULL, stats = c("n","mean","std","min","max"), weights = NULL)` — `weights` is `NULL` or a `character(1)` naming a numeric column of `data`.
  - `.means_row(x, variable, label, stats, w = NULL)`.
  - `.validate_weights(weights, data)` — returns the weight vector invisibly, or errors.
  - `.STATS` name `sumwgt`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-proc_means_weights.R`:

```r
library(testthat)
library(hvtiRutilities)

d <- data.frame(a = c(1, 2, 3, 4), wt = c(1, 1, 2, 4))

test_that("sumwgt sums the weight column", {
  res <- proc_means(d, vars = "a", stats = "sumwgt", weights = "wt")
  expect_equal(res$sumwgt, 8)
})

test_that("sumwgt equals n when no weights are given", {
  res <- proc_means(d, vars = "a", stats = c("n", "sumwgt"))
  expect_equal(res$sumwgt, res$n)
})

test_that("weights must name a column present in data", {
  expect_error(proc_means(d, vars = "a", stats = "sumwgt", weights = "nope"),
               "Column\\(s\\) not found")
})

test_that("weights must name a numeric column", {
  d2 <- data.frame(a = c(1, 2), g = c("x", "y"))
  expect_error(proc_means(d2, vars = "a", stats = "sumwgt", weights = "g"),
               "must be numeric")
})

test_that("weights must be a single column name", {
  expect_error(proc_means(d, vars = "a", stats = "sumwgt",
                          weights = c("wt", "a")),
               "single column")
})

test_that("a zero weight is an error naming the row", {
  dz <- data.frame(a = c(1, 2, 3), wt = c(1, 0, 2))
  expect_error(proc_means(dz, vars = "a", stats = "sumwgt", weights = "wt"),
               "row\\(s\\): 2")
})

test_that("a negative weight is an error naming the row", {
  dn <- data.frame(a = c(1, 2, 3), wt = c(1, 2, -3))
  expect_error(proc_means(dn, vars = "a", stats = "sumwgt", weights = "wt"),
               "row\\(s\\): 3")
})

test_that("a missing weight excludes that observation", {
  dm <- data.frame(a = c(1, 2, 3), wt = c(1, NA, 2))
  res <- proc_means(dm, vars = "a", stats = c("n", "sumwgt"), weights = "wt")
  expect_equal(res$n, 2L)
  expect_equal(res$sumwgt, 3)
})

test_that("weights apply within each class level", {
  dc <- data.frame(a = c(1, 2, 3, 4),
                   g = c("x", "x", "y", "y"),
                   wt = c(1, 3, 2, 5))
  res <- proc_means(dc, vars = "a", class = "g", stats = "sumwgt",
                    weights = "wt")
  expect_equal(res$sumwgt[res$g == "x"], 4)
  expect_equal(res$sumwgt[res$g == "y"], 7)
})

test_that("the weight column is not itself analysed by default", {
  res <- proc_means(d, stats = "n", weights = "wt")
  expect_equal(res$variable, "a")
})

test_that("naming the weight column in vars is an error", {
  expect_error(proc_means(d, vars = "wt", stats = "n", weights = "wt"),
               "also named in 'vars' or 'class'")
})

test_that("naming the weight column in class is an error", {
  expect_error(proc_means(d, vars = "a", class = "wt", stats = "n",
                          weights = "wt"),
               "also named in 'vars' or 'class'")
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Rscript -e 'pkgload::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-proc_means_weights.R")'`

Expected: FAIL with `unused argument (weights = "wt")`.

- [ ] **Step 3: Implement the argument, validation and threading**

Add the validator to `R/proc_means.R`, immediately after `.check_columns()`:

```r
## Internal: validate the weights argument and return the weight vector.
##
## Non-positive weights are an error rather than a silent coercion. SAS's own
## handling varies across procedures and versions -- "negative treated as zero",
## "non-positive excluded", "excluded from N but not NOBS" -- so failing loudly
## is preferred to encoding a guess and calling it parity. This can be relaxed
## once the Phase 1 SAS oracle can settle it; because the current behaviour is an
## error, no existing result changes silently when it is.
.validate_weights <- function(weights, data) {
  if (is.null(weights)) {
    return(NULL)
  }
  if (!is.character(weights) || length(weights) != 1L) {
    stop("'weights' must be a single column name.", call. = FALSE)
  }
  .check_columns(weights, data)

  w <- data[[weights]]
  if (!is.numeric(w)) {
    stop("Weight column '", weights, "' must be numeric.", call. = FALSE)
  }
  bad <- which(!is.na(w) & w <= 0)
  if (length(bad) > 0L) {
    stop("Weight column '", weights, "' has non-positive value(s) at row(s): ",
         paste(bad, collapse = ", "),
         ". Weights must be positive.", call. = FALSE)
  }
  w
}
```

Change the `proc_means()` signature at `R/proc_means.R:60-61` to:

```r
proc_means <- function(data, vars = NULL, class = NULL,
                       stats = c("n", "mean", "std", "min", "max"),
                       weights = NULL) {
```

Immediately after `.validate_stats(stats)` (line 65), add:

```r
  wvec <- .validate_weights(weights, data)
  if (!is.null(wvec)) {
    keep_w <- !is.na(wvec)
    data <- data[keep_w, , drop = FALSE]
    wvec <- wvec[keep_w]
  }
```

Immediately after the whole `if (is.null(vars)) { ... } else { ... }` block and before the `if (length(vars) == 0L)` check, add the overlap guard:

```r
  if (!is.null(weights) && weights %in% c(vars, class)) {
    stop("Weight column '", weights,
         "' is also named in 'vars' or 'class'. A column cannot be both a ",
         "weight and an analysis or class variable.", call. = FALSE)
  }
```

In the default-`vars` branch, exclude the weight column so it is not analysed as a variable. Change:

```r
    vars <- setdiff(numeric_cols, class)
```

to:

```r
    vars <- setdiff(numeric_cols, c(class, weights))
```

In the `class` branch, subset the weight vector alongside the data. Change:

```r
    keep <- stats::complete.cases(data[, class, drop = FALSE])
    data <- data[keep, , drop = FALSE]
```

to:

```r
    keep <- stats::complete.cases(data[, class, drop = FALSE])
    data <- data[keep, , drop = FALSE]
    if (!is.null(wvec)) {
      wvec <- wvec[keep]
    }
```

Thread the weights into both `.means_row()` calls. Change:

```r
      rows[[length(rows) + 1L]] <-
        .means_row(data[[v]], v, unname(labels[v]), stats)
```

to:

```r
      rows[[length(rows) + 1L]] <-
        .means_row(data[[v]], v, unname(labels[v]), stats, wvec)
```

and change:

```r
          .means_row(data[[v]][grp_idx[[i]]], v, unname(labels[v]), stats),
```

to:

```r
          .means_row(data[[v]][grp_idx[[i]]], v, unname(labels[v]), stats,
                     if (is.null(wvec)) NULL else wvec[grp_idx[[i]]]),
```

Change `.means_row()` to accept and forward the weights:

```r
## Internal: one output row for one variable
.means_row <- function(x, variable, label, stats, w = NULL) {
  vals <- lapply(stats, function(s) .compute_stat(x, s, w))
  names(vals) <- stats
  cbind(
    data.frame(variable = variable, label = label, stringsAsFactors = FALSE),
    as.data.frame(vals, stringsAsFactors = FALSE)
  )
}
```

Add the `sumwgt` registry entry after `nobs`:

```r
  sumwgt = list(
    fun = function(x, v, w) {
      if (length(v) == 0L) NA_real_ else if (is.null(w)) length(v) else sum(w)
    },
    weighted = TRUE, integer = FALSE
  ),
```

Update both contract tests in `tests/testthat/test-proc_means_registry.R` to add `sumwgt` to the keyword list and to the weighted set.

- [ ] **Step 4: Run the tests**

Run: `Rscript -e 'pkgload::load_all(quiet=TRUE); testthat::set_max_fails(Inf); testthat::test_dir("tests/testthat")'`

Expected: PASS, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add R/proc_means.R tests/testthat/
git commit -m "feat: proc_means() gains a weights argument and sumwgt"
```

---

### Task 5: Verify the weighted statistics and the unweighted contract

No production code changes are expected here — Tasks 1-4 already wrote the weighted forms. This task proves they are right and pins the contract that unweighted statistics ignore weights.

**Files:**
- Test: `tests/testthat/test-proc_means_weighted_values.R` (create)
- Modify: `R/proc_means.R` only if a test exposes a defect.

**Interfaces:**
- Consumes: everything from Tasks 1-4.
- Produces: no new interface.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-proc_means_weighted_values.R`:

```r
library(testthat)
library(hvtiRutilities)

cs <- function(x, stat, w = NULL) hvtiRutilities:::.compute_stat(x, stat, w)

# Worked by hand:
#   v = 1, 2, 3, 4   w = 1, 1, 2, 4
#   sum(w)            = 8
#   sum(w*v)          = 1 + 2 + 6 + 16 = 25
#   xbar_w            = 25 / 8 = 3.125
#   sum(w*v^2)        = 1 + 4 + 18 + 64 = 87            (uss)
#   css = sum(w*(v - 3.125)^2)
#       = 1*(-2.125)^2 + 1*(-1.125)^2 + 2*(-0.125)^2 + 4*(0.875)^2
#       = 4.515625 + 1.265625 + 0.03125 + 3.0625 = 8.875
#   var = css / (n - 1) = 8.875 / 3 = 2.9583333...
v <- c(1, 2, 3, 4)
w <- c(1, 1, 2, 4)

test_that("weighted sum and sumwgt match the hand calculation", {
  expect_equal(cs(v, "sum", w), 25)
  expect_equal(cs(v, "sumwgt", w), 8)
})

test_that("weighted mean matches the hand calculation", {
  expect_equal(cs(v, "mean", w), 3.125)
})

test_that("weighted uss and css match the hand calculation", {
  expect_equal(cs(v, "uss", w), 87)
  expect_equal(cs(v, "css", w), 8.875)
})

test_that("weighted var uses the VARDEF=DF divisor n-1, not sum(w)-1", {
  expect_equal(cs(v, "var", w), 8.875 / 3)
  expect_false(isTRUE(all.equal(cs(v, "var", w), 8.875 / 7)))
})

test_that("weighted std, stderr and cv follow from weighted var", {
  vw <- 8.875 / 3
  expect_equal(cs(v, "std", w), sqrt(vw))
  expect_equal(cs(v, "stderr", w), sqrt(vw / 4))
  expect_equal(cs(v, "cv", w), 100 * sqrt(vw) / 3.125)
})

test_that("equal weights reproduce the unweighted values", {
  ones <- rep(1, length(v))
  for (s in c("mean", "var", "std", "css", "uss", "cv", "stderr",
              "skewness", "kurtosis")) {
    expect_equal(cs(v, s, ones), cs(v, s), info = s)
  }
})

# ---------------------------------------------------------------------------
# The contract from the design: PROC MEANS does not weight these.
# ---------------------------------------------------------------------------

test_that("unweighted statistics ignore weights entirely", {
  for (s in c("n", "nmiss", "nobs", "min", "max", "range", "mode",
              "median", "q1", "q3", "p90", "qrange")) {
    expect_equal(cs(v, s, w), cs(v, s), info = s)
  }
})

test_that("proc_means reports unweighted quantiles when weights are given", {
  d <- data.frame(a = v, wt = w)
  wt  <- proc_means(d, vars = "a", stats = c("median", "q1", "q3"),
                    weights = "wt")
  raw <- proc_means(d, vars = "a", stats = c("median", "q1", "q3"))
  expect_equal(wt$median, raw$median)
  expect_equal(wt$q1, raw$q1)
  expect_equal(wt$q3, raw$q3)
})
```

- [ ] **Step 2: Run the test**

Run: `Rscript -e 'pkgload::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-proc_means_weighted_values.R")'`

Expected: PASS. Tasks 1-4 already implement these. If anything fails, the defect is in the earlier task's implementation — fix it in `R/proc_means.R` rather than adjusting the expected values, which were derived by hand above.

- [ ] **Step 3: Run the full suite**

Run: `Rscript -e 'pkgload::load_all(quiet=TRUE); testthat::set_max_fails(Inf); testthat::test_dir("tests/testthat")'`

Expected: PASS, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add tests/testthat/test-proc_means_weighted_values.R R/proc_means.R
git commit -m "test: pin weighted statistic values and the unweighted contract"
```

---

### Task 6: Pin weighted skewness and kurtosis, and mark the oracle gap

`e1071` takes no weights, so these two have no independent oracle. Pin them and make the gap visible in the test file, not only in the spec.

**Files:**
- Test: `tests/testthat/test-proc_means_weighted_shape.R` (create)

**Interfaces:**
- Consumes: `.wskew(v, w)`, `.wkurt(v, w)` from Task 3.
- Produces: no new interface.

- [ ] **Step 1: Write the test**

Create `tests/testthat/test-proc_means_weighted_shape.R`:

```r
library(testthat)
library(hvtiRutilities)

cs <- function(x, stat, w = NULL) hvtiRutilities:::.compute_stat(x, stat, w)

# ---------------------------------------------------------------------------
# KNOWN VALIDATION GAP -- see specs/2026-08-14-proc-means-unistats-design.md
#
# e1071 takes no weights, so the WEIGHTED forms of skewness and kurtosis have no
# independent oracle available today. The expected values below are computed
# from the SAS documented formulas -- weights raised to 3/2 for skewness and
# squared for kurtosis -- and are pinned here to catch drift, NOT to prove SAS
# agreement. Confirm them against the Phase 1 SAS oracle when it exists.
#
# The UNWEIGHTED forms are cross-validated against e1071 in
# tests/testthat/test-proc_means_shape.R and are not affected by this gap.
# ---------------------------------------------------------------------------

v <- c(1, 2, 3, 4, 8)
w <- c(1, 1, 2, 4, 2)

# The expected values below are FROZEN LITERALS, not expressions recomputed
# from the same formula the implementation uses. A test that recomputes the
# formula silently follows any edit to it and so cannot detect drift; a frozen
# number breaks loudly. These were computed once from the SAS documented
# formulas for v and w above:
#   sum(w) = 10, xbar_w = 4.1, s_w = sqrt(sum(w*(v-xbar_w)^2)/(n-1)) = 3.4241787337
# They pin the current arithmetic against accidental change. They do NOT
# establish SAS agreement -- see the gap notice at the top of this file.

test_that("weighted skewness is stable at its documented value", {
  expect_equal(cs(v, "skewness", w), 1.2967986106, tolerance = 1e-8)
})

test_that("weighted kurtosis is stable at its documented value", {
  expect_equal(cs(v, "kurtosis", w), 1.4838139488, tolerance = 1e-8)
})

test_that("weighted skewness and kurtosis actually respond to the weights", {
  # Guards the w^(3/2) and w^2 exponents. At w = 1 both collapse to 1, so an
  # equal-weights test cannot distinguish a correct weighting from none at all.
  expect_false(isTRUE(all.equal(cs(v, "skewness", w), cs(v, "skewness"))))
  expect_false(isTRUE(all.equal(cs(v, "kurtosis", w), cs(v, "kurtosis"))))
})

test_that("weighted skewness and kurtosis honour the minimum-n rules", {
  expect_true(is.na(cs(c(1, 2), "skewness", c(1, 2))))
  expect_true(is.na(cs(c(1, 2, 3), "kurtosis", c(1, 2, 3))))
})

test_that("weighted skewness and kurtosis are NA for a constant column", {
  k <- rep(4, 8)
  kw <- c(1, 2, 1, 2, 1, 2, 1, 2)
  expect_true(is.na(cs(k, "skewness", kw)))
  expect_true(is.na(cs(k, "kurtosis", kw)))
})
```

- [ ] **Step 2: Run the test**

Run: `Rscript -e 'pkgload::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-proc_means_weighted_shape.R")'`

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/testthat/test-proc_means_weighted_shape.R
git commit -m "test: pin weighted skewness and kurtosis, marking the oracle gap"
```

---

### Task 7: Documentation, NEWS, version, and the release gate

**Files:**
- Modify: `R/proc_means.R:1-59` (roxygen block)
- Modify: `DESCRIPTION:4` (version)
- Modify: `NEWS.md` (new top section)
- Regenerate: `man/proc_means.Rd` via `devtools::document()`

**Interfaces:**
- Consumes: everything from Tasks 1-6.
- Produces: no new interface.

- [ ] **Step 1: Update the roxygen block**

In `R/proc_means.R`, replace the `@param stats` block with:

```r
#' @param stats Character vector of SAS statistic keywords. Counts:
#'   \code{"n"}, \code{"nmiss"}, \code{"nobs"}, \code{"sumwgt"}. Location:
#'   \code{"mean"}, \code{"median"}, \code{"mode"}. Spread: \code{"std"},
#'   \code{"var"}, \code{"stderr"}, \code{"cv"}, \code{"min"}, \code{"max"},
#'   \code{"range"}, \code{"qrange"}, \code{"q1"}, \code{"q3"}, or any
#'   \code{"pNN"} for NN from 1 to 99. Sums: \code{"sum"}, \code{"uss"},
#'   \code{"css"}. Shape: \code{"skewness"}, \code{"kurtosis"}.
```

Add after the `@param stats` block:

```r
#' @param weights Character or \code{NULL}. Name of a single numeric column of
#'   \code{data} to use as an observation weight, mirroring the SAS
#'   \code{WEIGHT} statement. Observations whose weight is missing are excluded.
#'   A zero or negative weight is an error naming the offending rows: SAS's own
#'   handling of non-positive weights varies across procedures and versions, so
#'   this fails loudly rather than encode a guess.
```

Add to `@details`:

```r
#' Weights do not apply uniformly, and this follows \code{PROC MEANS} rather
#' than being a simplification. Weighted: \code{mean}, \code{std}, \code{var},
#' \code{cv}, \code{stderr}, \code{sum}, \code{uss}, \code{css},
#' \code{skewness}, \code{kurtosis}, \code{sumwgt}. Unweighted: \code{n},
#' \code{nmiss}, \code{nobs}, \code{min}, \code{max}, \code{range},
#' \code{mode}, and every quantile -- \code{median}, \code{q1}, \code{q3},
#' \code{pNN} and \code{qrange}. \code{PROC MEANS} does not compute weighted
#' quantiles at all; that is \code{PROC UNIVARIATE}. So
#' \code{proc_means(d, stats = "median", weights = "wt")} returns the
#' \emph{unweighted} median.
#'
#' \code{mode} returns the smallest value among tied modes, and \code{NA} when
#' no value repeats, both matching SAS. \code{skewness} and \code{kurtosis} are
#' the adjusted Fisher-Pearson forms SAS uses, not R's naive moment ratios, and
#' are \code{NA} for a constant column rather than \code{NaN}.
#'
#' The \code{PROC UNIVARIATE} inference statistics (\code{NORMAL}, \code{PROBN},
#' \code{T}, \code{PROBT}, \code{MSIGN}, \code{PROBM}, \code{SIGNRANK},
#' \code{PROBS}) are deliberately absent: they would make this a
#' hypothesis-testing function rather than a summary one. \code{CLM}, the
#' confidence limits of the mean, is absent for the same reason.
#'
#' \code{cv} is \code{NA} when the mean is zero, matching SAS; R's arithmetic
#' would give \code{Inf}.
```

Add a `@examples` entry showing weighting:

```r
#' dta <- data.frame(age = c(51, 63, 47, 72), wt = c(1, 2, 1, 4))
#' proc_means(dta, vars = "age", stats = c("n", "sumwgt", "mean"),
#'            weights = "wt")
```

- [ ] **Step 2: Regenerate the documentation**

Run: `Rscript -e 'devtools::document()'`

Expected: `Writing 'proc_means.Rd'`. If `DESCRIPTION` or `NAMESPACE` also change, inspect the diff — roxygen2 must be 8.1.0 to match the repo pin, and any reformatting churn beyond your edit should be reverted with `git checkout DESCRIPTION NAMESPACE` and re-applied by hand.

- [ ] **Step 3: Bump the version and write NEWS**

In `DESCRIPTION:4`, change `Version: 1.0.4` to `Version: 1.0.5`.

At the top of `NEWS.md`, add:

```markdown
# hvtiRutilities 1.0.5

## New features

- `proc_means()` gains nine statistics from the SAS `unistats` vocabulary:
  `nobs`, `var`, `uss`, `css`, `skewness`, `kurtosis`, `sumwgt`, `qrange` and
  `mode`. `skewness` and `kurtosis` are the adjusted Fisher-Pearson forms SAS
  uses, cross-validated in the test suite against `e1071` with `type = 2`.
  `mode` returns the smallest of tied modes and `NA` when no value repeats,
  matching SAS.

- `proc_means()` gains a `weights` argument naming a numeric column, mirroring
  the SAS `WEIGHT` statement. Weights apply within each `class` level.

  Weighting is not uniform, following `PROC MEANS`: `mean`, `std`, `var`, `cv`,
  `stderr`, `sum`, `uss`, `css`, `skewness`, `kurtosis` and `sumwgt` respond to
  weights; `n`, `nmiss`, `nobs`, `min`, `max`, `range`, `mode` and every
  quantile do not. `PROC MEANS` computes no weighted quantiles; that is
  `PROC UNIVARIATE`.

  A zero or negative weight raises an error naming the offending rows. SAS's own
  handling of non-positive weights differs across procedures and versions, so
  this fails loudly rather than encode a guess.

  The `PROC UNIVARIATE` inference statistics remain out of scope. See
  `specs/2026-08-14-proc-means-unistats-design.md`.

## Internal changes

- `proc_means()` statistics are dispatched through a `.STATS` registry that
  declares, per statistic, whether it responds to weights and whether it is
  integer-typed. The weighted set is asserted directly in the test suite.
```

- [ ] **Step 4: Run the full suite**

Run: `Rscript -e 'pkgload::load_all(quiet=TRUE); testthat::set_max_fails(Inf); testthat::test_dir("tests/testthat")'`

Expected: PASS, 0 failures.

- [ ] **Step 5: Run the release gate from a clean export**

```bash
SP=$(mktemp -d)
git archive HEAD | tar -x -C "$SP"
cd "$SP" && R CMD build . && R CMD check --as-cran hvtiRutilities_1.0.5.tar.gz
```

Expected: `Status: 1 NOTE`, the note being `New submission`. Zero errors, zero warnings. `checking examples ... OK` and `checking tests ... OK`. Total time well under 10 minutes.

Do not use `--no-manual` or `--no-build-vignettes`, and do not build from the working tree — an empty `inst/doc` fabricates vignette warnings.

- [ ] **Step 6: Commit and open the pull request**

```bash
git add R/proc_means.R man/proc_means.Rd DESCRIPTION NEWS.md
git commit -m "docs: document the unistats statistics and weights; bump to 1.0.5"
git push -u origin spec/proc-means-unistats
gh pr create --base spec/sas-macro-canonicalization \
  --title "feat: extend proc_means() to the unistats descriptive vocabulary"
```

The PR body must state: the nine statistics added, the weighting split and that it follows `PROC MEANS`, the non-positive-weight error and why it is stricter than SAS, and the known validation gap on weighted `skewness`/`kurtosis`.

---

## Self-Review

**Spec coverage.** Every section maps to a task: architecture → Task 1; the nine statistics → Tasks 2, 3, 4 (`sumwgt`); the `weights` argument, validation and non-positive error → Task 4; validation strategy including `e1071` → Task 3, with the weighted gap → Task 6; testing groups 1-5 → Tasks 1, 2, 3, 5, 6; documentation → Task 7; success criteria 1-3 → Task 7 steps 4-5; success criterion 4 (`data_dictionary()` unchanged) → Task 1 step 4, which requires the pre-existing tests to pass unmodified.

**Type consistency.** `.compute_stat(x, stat, w = NULL)` keeps that signature from Task 1 onward. Registry `fun` is `function(x, v, w)` everywhere. `.means_row(x, variable, label, stats, w = NULL)` gains its parameter only in Task 4 and is called consistently after. `.wmean`, `.wvar`, `.wskew`, `.wkurt` are defined once and referenced by those names throughout.

**Registry list churn is deliberate.** The keyword-set assertion in `tests/testthat/test-proc_means_registry.R` is rewritten in Tasks 2, 3 and 4 as statistics are added. Each task shows the full replacement list rather than saying "add to the list", so a task can be implemented without reading its neighbours.

**One known ordering constraint.** Task 5 asserts weighted values that Tasks 1-4 implement, so it must run after Task 4. It is written to expect a passing test on first run, and says explicitly that a failure means fixing the implementation rather than the hand-derived expectations.
