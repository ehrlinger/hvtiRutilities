# `proc_univariate()` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the SAS `PROC UNIVARIATE` `OUTPUT OUT=` statistics to `proc_univariate()` in hvtiRutilities: every `proc_means()` keyword plus weighted and decimal percentiles (`pctlpts`, `pctlpre`), `vardef`, `mu0`, `stdmean`, the location tests (`t`, `probt`, `msign`, `probm`, `signrank`, `probs`) and Shapiro-Wilk (`normal`, `probn`), matching SAS 9.4 output in all 25 oracle scenarios.

**Architecture:** The statistic registry, dispatcher and weighted helpers move out of `R/proc_means.R` into `R/stat_engine.R`, which both procedures share. A context from `.stat_ctx(procedure, vardef, mu0)` selects per-procedure behaviour: which keywords are accepted (`procedures`), whether a statistic sees the weights (`weighted`, a single logical or `c(means = , univariate = )`), the VARDEF divisor and the null value. `.STATS` stays as `proc_means()`'s resolved view of the registry, so the existing registry tests keep passing unchanged. The body of `proc_means()` becomes `.summary_table()`, a driver shared by a thin `proc_means()` wrapper and `proc_univariate()`. Percentile points travel through the driver as internal `.pctl:<point>` keywords with their own output column names.

**Tech Stack:** R (>= the package's `Depends`), base `stats` (`quantile(type = 2)`, `pt`, `pbinom`, `shapiro.test`), `labelled` (already imported), roxygen2 with Rd markup, testthat edition 3, pkgdown, quarto vignettes, lintr.

**Spec:** `dev/specs/2026-09-17-proc-univariate-design.md`

**Verified:** Every embedded file and replacement below was applied in order to a scratch copy of `main` at 8cf9eae with the prerequisites simulated: #119's class-level commit f291b39 applied verbatim, and #120 as weighted `stderr` divided by `sqrt(sum(w))` and `mode` of a single observation returning its value, with the matching test edits. After each task `devtools::test()` was run and the counts recorded here are measured, not estimated: 2123 expectations before Task 1, then 2123, 2184, 2227, 2318, 4444 and 4444 (FAIL 0, WARN 7, SKIP 0 throughout). Each task's red step was also run and its failure is quoted. On the final state: parity 25/25 scenarios and 1025/1025 columns; `roxygen2::roxygenise()` then `git diff --exit-code man/ NAMESPACE DESCRIPTION` exits 0; `lintr::lint()` on the touched files gives no new lints; `pkgdown::check_pkgdown()` reports no problems; `R CMD check --as-cran` on a `git archive` tarball, with the PDF manual and vignettes, gives `Status: OK` (run with `_R_CHECK_CRAN_INCOMING_REMOTE_=false` because the sandbox had no network, which is why the environmental "New submission" NOTE did not appear). The statistics themselves were verified in a prototype against the committed SAS output in `dev/oracle/proc_univariate/out/`.

## Prerequisites

PR B branches from `main` only after all three of these have merged:

1. **#118**: the spec, the oracle kit and the SAS output (`dev/oracle/proc_univariate/`).
2. **#119**: `proc_means()` counts missing-weight rows in `nobs`, and keeps a class level whose every weight is missing (N = 0), as SAS `PROC MEANS` does.
3. **#120**: weighted `stderr` as `std / sqrt(W)` and `mode` of a single observation, both confirmed on SAS 9.4 `PROC MEANS` (2026-09-17).

This plan does **not** change `mode` and does not add a `mode` test: Task 1 moves `main`'s registry verbatim, whatever #120 left there, and the `mode` entry embedded in Task 2 is the one #120 introduces (a single observation is its own mode). It also takes the weighted `stderr` rule from `main`.

> **Dependency note: two places follow #120, one follows #119.**
>
> 1. `R/stat_engine.R`, the line `.stderr_sqrt_w <- c(means = TRUE, univariate = TRUE)` (Task 2) and the comment above it. `means = TRUE` matches #120, which SAS `PROC MEANS` confirmed divides by `sqrt(W)`.
> 2. The `mode` entry of the registry in Task 2. It must behave as `main`'s entry after #120.
>
> 3. Task 2, Step 4, Replace 3 starts from #119's class-level lines as merged (commit f291b39). If review changed their wording before merge, match `main`'s text in the `Replace` block; the `with` block does not change. Task 1, Step 1 prints all three.

## Global Constraints

- Signature: `proc_univariate(data, vars = NULL, class = NULL, stats = c("n", "median", "mean", "std", "cv", "min", "max"), weights = NULL, pctlpts = NULL, pctlpre = "p", mu0 = 0, vardef = c("df", "n", "wdf", "weight"))`.
- Result columns: `class` columns (if any), `variable`, `label`, one per `stats` keyword in order, then one per `pctlpts` point in order.
- Percentile column name: `pctlpre` + the point formatted alone by `format(p, digits = 15, scientific = FALSE, drop0trailing = TRUE, trim = TRUE)` with `.` replaced by `_` (`2.5` -> `p2_5`, `0` -> `p0`, `100` -> `p100`).
- Parity tolerances (relative): `1e-10` for every column, `normal` `1e-7`, `probn` `1e-6` (R `shapiro.test()` is Royston 1995, SAS is Royston 1992; 4.5e-7 observed at n = 12).
- NA under `weights`: `msign`, `probm`, `signrank`, `probs`, `normal`, `probn`.
- NA unless `vardef = "df"`: `t`, `probt`, `stdmean`, `stderr`.
- NA under `vardef` `"wdf"` or `"weight"`: `skewness`, `kurtosis`.
- NA at n = 1: `std`, `var`, `cv`, `stdmean`, `t`, `probt`; `skewness` below n = 3; `kurtosis` below n = 4; `normal`/`probn` below n = 2 (both `1` at n = 2).
- NA when every value is equal: `t`, `probt`, `skewness`, `kurtosis`, `normal`, `probn` (`cv` is `0`).
- NA when no value differs from `mu0`: `msign`, `probm`, `signrank`, `probs`.
- NA above 2000 non-missing values: `normal`, `probn`, with exactly one warning per call containing `Kolmogorov D`.
- A class level whose every weight is missing: `proc_means()` keeps its row (`n` 0, `nobs` counts the rows), `proc_univariate()` drops it, both as SAS does; the switch is `ctx$procedure == "means"` in `.summary_table()`.
- Weighted quantiles for `univariate` only (`median`, `q1`, `q3`, `qrange`, `pNN`, `pctlpts`); `mode` is unweighted everywhere; weighted `stderr`/`stdmean` divide by `sqrt(sum(w))`.
- `proc_means()` accepts none of `stdmean`, `t`, `probt`, `msign`, `probm`, `signrank`, `probs`, `normal`, `probn`, and all its messages stay word for word.
- Errors use `call. = FALSE`.
- Roxygen is Rd markup (`\code{}`, `\itemize{}`, `\strong{}`, `\eqn{}`), never markdown; `DESCRIPTION` has no `Roxygen: list(markdown = TRUE)`.
- Lines at most 80 characters in R code and tests.
- No new lints: compare `lintr::lint()` counts on touched files against `main`; `object_usage_linter` warnings about functions added in the same change are artifacts until the package is installed.
- Never hand-edit `man/` or `NAMESPACE`; run `devtools::document()` and commit its output with the source.
- `_pkgdown.yml`: add `  - proc_univariate` directly after `  - proc_means`; pkgdown errors on a missing topic.
- NEWS: one entry under `# hvtiRutilities (unreleased)` / `## New features`; no `Version:` bump in `DESCRIPTION` or `NEWS.md`.
- Every commit message ends with the trailer `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- Test fixtures live in `tests/testthat/fixtures-proc_univariate/`, not `tests/testthat/fixtures/`: `fixtures/` is the `sas_triage()` corpus, and a subdirectory there changes its fingerprint and fails `test-collision_report_provenance.R`.
- Test expectations are literals, independent formulas, or committed SAS output; never recomputed with the function under test.
- No em-dashes in any prose written by this plan.

## File Map

| file | action | responsibility |
|---|---|---|
| `R/stat_engine.R` | Create (Task 1), rewrite (Task 2), extend (Task 3) | Context, registry, per-procedure views, keyword validation, dispatcher, quantiles, weighted helpers, location and normality statistics |
| `R/proc_means.R` | Modify (Tasks 1, 2) | `proc_means()` wrapper, shared `.summary_table()` driver, `.check_columns()`, `.validate_weights()`, `.means_row()`, `.empty_means()` |
| `R/proc_univariate.R` | Create (Task 4) | `proc_univariate()`, argument validation, `.pctl_names()`, the n > 2000 warning, roxygen |
| `man/proc_univariate.Rd`, `NAMESPACE` | Generated (Task 4) | `devtools::document()` output |
| `_pkgdown.yml` | Modify (Task 4) | Reference index entry |
| `tests/testthat/test-stat_engine.R` | Create (Task 2), extend (Task 3) | Engine unit tests: context, views, VARDEF, weighted quantiles, location and normality statistics |
| `tests/testthat/test-proc_univariate_shape.R` | Create (Task 4) | Columns, order, class rows, labels, types, percentile names, zero-row result |
| `tests/testthat/test-proc_univariate_errors.R` | Create (Task 4) | Every error in the spec and the n > 2000 warning |
| `tests/testthat/test-proc_univariate_values.R` | Create (Task 4) | Hand-computed literals through the public function |
| `tests/testthat/test-proc_univariate_parity.R` | Create (Task 5) | Every value of every SAS oracle scenario |
| `tests/testthat/fixtures-proc_univariate/` | Create (Task 5) | Copies of `dev/oracle/proc_univariate/` fixtures, `scenarios.csv` and `out/*.csv` |
| `vignettes/sas-procedures.qmd` | Modify (Task 6) | Title, intro, `proc_univariate()` section, differences table, checklist, See Also |
| `NEWS.md` | Modify (Task 6) | Entry under `# hvtiRutilities (unreleased)` |

## Task 1: Move the statistic engine to `R/stat_engine.R`

A pure move: `.wmean`, `.wvar`, `.wskew`, `.wkurt`, `.STATS`, `.validate_stats`, `.compute_stat` and `.quantile_stat` leave `R/proc_means.R` unchanged. `.check_columns`, `.validate_weights`, `.means_row` and `.empty_means` stay (`proc_freq()` uses the first two). There is no new test: the evidence is that every existing consumer test passes unchanged, before and after, with the same count.

**Files:**
- Create: `R/stat_engine.R`
- Modify: `R/proc_means.R`
- Test: `tests/testthat/test-proc_means*.R`, `tests/testthat/test-data_dictionary.R`, `tests/testthat/test-proc_freq*.R` (unchanged)

**Interfaces:**
- Consumes: `main`'s `R/proc_means.R` after the three prerequisite PRs.
- Produces: the same internal functions, now defined in `R/stat_engine.R`: `.wmean(v, w)`, `.wvar(v, w)`, `.wskew(v, w)`, `.wkurt(v, w)`, `.STATS`, `.validate_stats(stats)`, `.compute_stat(x, stat, w = NULL)`, `.quantile_stat(v, stat)`.

- [ ] **Step 1: Confirm the prerequisites and branch.**

```bash
git checkout main && git pull --ff-only
for pr in 118 119 120; do gh pr view "$pr" --json state --jq .state; done
sed -n '/excl_cls <- excluded/,/groups <- unique(rbind/p' R/proc_means.R
sed -n '/^  stderr = list(/,/^  ),/p' R/proc_means.R
sed -n '/^  mode = list(/,/^  ),/p' R/proc_means.R
git checkout -b feat/proc-univariate
```

  Expected: all three `MERGED`. The first `sed` prints the `#119` class-level lines (`excl_cls`, then `groups <- unique(rbind(...))`); Task 2, Step 4, Replace 3 matches them exactly. The `stderr` entry divides the weighted variance by `sum(w)` when weights are given, and the `mode` entry returns `NA` only when no value repeats and there is more than one value (the simulated `main` used for this plan reads `if (top == 1L && length(v) > 1L)`). If `stderr` still divides by `length(v)` under weights, #120 kept `sqrt(n)`: follow Dependency note 1 in Task 2. If any of the three is missing, stop: a prerequisite has not landed.

- [ ] **Step 2: Record the baseline for the engine's consumers.**

```bash
Rscript -e 'devtools::test(filter = "proc_means|data_dictionary|proc_freq")'
```

  Expected: `[ FAIL 0 | WARN 1 | SKIP 0 | PASS 381 ]` (measured on the simulated `main`; the warning is the pre-existing `r_data_types()` one in `test-data_dictionary.R`). If `main`'s count differs, record `main`'s number and expect exactly that number in Step 5.

- [ ] **Step 3: Move the code.** The script cuts from the `.wmean` comment up to the `.means_row` comment, drops trailing blank lines, and prepends a two-line header.

```bash
f=$(mktemp) && cat > "$f" <<'EOF'
src <- readLines("R/proc_means.R")
from <- grep("^## Internal: weighted mean, or the plain mean when w is NULL$",
             src)
to <- grep("^## Internal: one output row for one variable$", src) - 1L
stopifnot(length(from) == 1L, length(to) == 1L, from < to)
body <- src[from:to]
while (!nzchar(body[length(body)])) body <- body[-length(body)]
header <- c(
  "## Internal: the statistic engine, moved unchanged from R/proc_means.R: the",
  "## weighted helpers, the statistic registry and the dispatcher.",
  ""
)
writeLines(c(header, body), "R/stat_engine.R")
writeLines(src[-(from:to)], "R/proc_means.R")
EOF
Rscript "$f" && rm "$f"
```

- [ ] **Step 4: Prove nothing but the header changed.**

```bash
diff <(git show HEAD:R/proc_means.R | sort) \
     <(cat R/proc_means.R R/stat_engine.R | sort)
```

  Expected output, exactly (the line numbers may differ):

```text
389a390
> ## Internal: the statistic engine, moved unchanged from R/proc_means.R: the
408a410
> ## weighted helpers, the statistic registry and the dispatcher.
```

- [ ] **Step 5: Run the consumer tests and the full suite.**

```bash
Rscript -e 'devtools::test(filter = "proc_means|data_dictionary|proc_freq")'
Rscript -e 'devtools::test()'
```

  Expected: `[ FAIL 0 | WARN 1 | SKIP 0 | PASS 381 ]`, then `[ FAIL 0 | WARN 7 | SKIP 0 | PASS 2116 ]` (2123 expectations), both identical to `main`. No roxygen changed, so `devtools::document()` is not needed.

- [ ] **Commit.**

```bash
git add R/proc_means.R \
  R/stat_engine.R
git commit -F - <<'EOF'
refactor: move the statistic engine to R/stat_engine.R

A pure move with no behaviour change, so proc_univariate() can share the
registry. Every proc_means, data_dictionary and proc_freq test passes
unchanged.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

## Task 2: Per-procedure registry, context and the shared driver

The registry gains `procedures` and per-procedure `weighted`; every compute function takes `ctx`; VARDEF, weighted quantiles and the `sqrt(W)` standard error are in place; `proc_means()` becomes a wrapper over `.summary_table()`, which keeps #119's class levels for `means` only. `proc_means()` output does not change: the existing tests pass unchanged, and the new engine test pins the univariate side.

**Files:**
- Modify: `R/stat_engine.R` (full replacement)
- Modify: `R/proc_means.R`
- Test: `tests/testthat/test-stat_engine.R` (create)

**Interfaces:**
- Consumes: Task 1's `R/stat_engine.R` and `R/proc_means.R`; `.check_columns(cols, data)`, `.validate_weights(weights, data)`.
- Produces:
  - `.stat_ctx(procedure = "means", vardef = "df", mu0 = 0)` returning `list(procedure, vardef, mu0, flags = <environment>)`
  - `.stderr_sqrt_w` (named logical, `means`, `univariate`)`
  - `.wmean(v, w)`, `.wcss(v, w)`, `.wvar(v, w, vardef = "df")`, `.wskew(v, w, vardef = "df")`, `.wkurt(v, w, vardef = "df")`
  - `.stderr_stat(v, w, ctx)` (the variance of the mean, before `sqrt()`)`
  - `.stat(fun, weighted, integer = FALSE, procedures = c("means", "univariate"))`, `.resolve_weighted(weighted, procedure)`, `.quantile_weighted`
  - `.stat_registry` (entries `fun(x, v, w, ctx)`, `weighted`, `integer`, `procedures`)`
  - `.stats_for(procedure)`, `.STATS <- .stats_for("means")`
  - `.validate_stats(stats, procedure = "means")`
  - `.compute_stat(x, stat, w = NULL, ctx = .stat_ctx())`
  - `.quantile_stat(v, stat, w = NULL)`, `.wquantile(v, w, p)`
  - `.summary_table(data, vars, class, stats, weights, ctx, col_names = stats)`
  - `.means_row(x, variable, label, stats, w = NULL, n_excluded = 0L, ctx = .stat_ctx(), col_names = stats)`, `.empty_means(class, stats, col_names = stats)`

- [ ] **Step 1: Write the failing engine test.** Create `tests/testthat/test-stat_engine.R`:

```r
library(testthat)
library(hvtiRutilities)

# The shared statistic engine: the context, the per-procedure registry views
# and the statistics whose behaviour depends on the procedure or VARDEF=.
# Expected values are hand-computed literals or independent formulas.

eng <- function(name) utils::getFromNamespace(name, "hvtiRutilities")
ctx <- function(...) eng(".stat_ctx")(...)
cs <- function(x, stat, w = NULL, ...) {
  eng(".compute_stat")(x, stat, w, ctx(...))
}

test_that(".stat_ctx() defaults are proc_means()'s", {
  k <- ctx()
  expect_equal(k$procedure, "means")
  expect_equal(k$vardef, "df")
  expect_equal(k$mu0, 0)
  expect_true(is.environment(k$flags))
})

test_that(".STATS is the means view of the registry", {
  expect_identical(names(eng(".STATS")), names(eng(".stats_for")("means")))
  for (e in eng(".stat_registry")) {
    expect_true(all(e$procedures %in% c("means", "univariate")))
  }
})

test_that("quantiles are weighted for univariate and not for means", {
  means <- eng(".stats_for")("means")
  uni <- eng(".stats_for")("univariate")
  for (k in c("median", "q1", "q3", "qrange")) {
    expect_false(means[[k]]$weighted, info = k)
    expect_true(uni[[k]]$weighted, info = k)
  }
  expect_false(uni$mode$weighted)
})

test_that("a weighted median is weighted only for univariate", {
  # S = 1, 4, 5, 6 and pW = 3: the first S_i above 3 is S_2, so 2.
  x <- c(1, 2, 3, 4)
  w <- c(1, 3, 1, 1)
  expect_equal(cs(x, "median", w), 2.5)
  expect_equal(cs(x, "median", w, procedure = "univariate"), 2)
  expect_equal(cs(x, "p50", w, procedure = "univariate"), 2)
})

test_that("weighted percentile points follow the PROC UNIVARIATE rule", {
  x <- c(4, 1, 3, 2)
  w <- c(1, 1, 1, 1)
  pct <- function(p) cs(x, p, w, procedure = "univariate")
  expect_equal(pct(".pctl:0"), 1)
  expect_equal(pct(".pctl:100"), 4)
  expect_equal(pct(".pctl:50"), 2.5)   # S_2 = 2 equals pW = 2
  expect_equal(pct(".pctl:30"), 2)     # first S_i above pW = 1.2
  expect_equal(cs(x, ".pctl:2.5"), 1)  # unweighted, PCTLDEF=5
})

test_that("each VARDEF divisor", {
  # x = 1, 2, 3, 4: CSS = 5; w = 1, 1, 1, 2: W = 5, weighted CSS = 6.8.
  x <- c(1, 2, 3, 4)
  w <- c(1, 1, 1, 2)
  uv <- function(vardef, w = NULL) {
    cs(x, "var", w, procedure = "univariate", vardef = vardef)
  }
  expect_equal(uv("df"), 5 / 3)
  expect_equal(uv("n"), 5 / 4)
  expect_equal(uv("df", w), 6.8 / 3)
  expect_equal(uv("n", w), 6.8 / 4)
  expect_equal(uv("wdf", w), 6.8 / 4)
  expect_equal(uv("weight", w), 6.8 / 5)
  expect_equal(cs(x, "std", w, procedure = "univariate", vardef = "n"),
               sqrt(6.8 / 4))
})

test_that("VARDEF=N skewness and kurtosis are the moment forms", {
  x <- c(1, 2, 3, 10)
  z <- (x - mean(x)) / sqrt(mean((x - mean(x))^2))
  expect_equal(cs(x, "skewness", procedure = "univariate", vardef = "n"),
               mean(z^3))
  expect_equal(cs(x, "kurtosis", procedure = "univariate", vardef = "n"),
               mean(z^4) - 3)
})

test_that("skewness, kurtosis and stderr are NA where SAS omits them", {
  x <- c(1, 2, 3, 10)
  w <- c(1, 2, 1, 1)
  for (vd in c("wdf", "weight")) {
    expect_true(is.na(cs(x, "skewness", w, procedure = "univariate",
                         vardef = vd)))
    expect_true(is.na(cs(x, "kurtosis", w, procedure = "univariate",
                         vardef = vd)))
  }
  expect_true(is.na(cs(x, "stderr", procedure = "univariate",
                       vardef = "n")))
})

test_that("weighted stderr divides by sqrt(sum of weights)", {
  x <- c(1, 2, 3, 4)
  w <- c(1, 1, 1, 2)
  expect_equal(cs(x, "stderr", w, procedure = "univariate"),
               sqrt(6.8 / 3) / sqrt(5))
})

test_that(".validate_stats() lists the keywords of the procedure", {
  expect_silent(eng(".validate_stats")(c("mean", "p5"), "univariate"))
  expect_error(eng(".validate_stats")("bogus", "univariate"),
               "Unrecognised statistic keyword\\(s\\): bogus")
})
```

- [ ] **Step 2: Run it and watch it fail.**

```bash
Rscript -e 'devtools::test(filter = "stat_engine")'
```

  Expected: 10 errored tests, 0 passes, with errors including `object '.stat_ctx' not found`, `object '.stats_for' not found`, `unused argument (ctx(...))` and `unused argument ("univariate")`.

- [ ] **Step 3: Replace `R/stat_engine.R` entirely** with the following. See Dependency note 1 for the `.stderr_sqrt_w` line and Dependency note 2 for the `mode` entry.

```r
## =============================================================================
## Internal: the statistic engine shared by proc_means() and proc_univariate().
##
## One registry of SAS statistic keywords, one dispatcher (.compute_stat()) and
## the weighted helpers. A procedure selects its keywords and its weighting
## rules through a context built by .stat_ctx(); the defaults reproduce
## proc_means() exactly, so data_dictionary()'s positional calls are unchanged.
## =============================================================================

## Internal: the calling context for .compute_stat().
##
## procedure: "means" or "univariate". vardef: the SAS VARDEF= divisor, always
## "df" under "means". mu0: the null value for the location tests. flags: an
## environment a statistic can write to, so the caller can warn once per call
## rather than once per cell (normality requested above n = 2000).
.stat_ctx <- function(procedure = "means", vardef = "df", mu0 = 0) {
  list(procedure = procedure, vardef = vardef, mu0 = mu0,
       flags = new.env(parent = emptyenv()))
}

## Internal: does stderr divide by sqrt(sum of weights) rather than sqrt(n)?
## Kept per procedure so each follows its own SAS oracle. PROC UNIVARIATE
## divides by sqrt(W) (oracle, 2026-09-17), and so does PROC MEANS.
.stderr_sqrt_w <- c(means = TRUE, univariate = TRUE)

## Internal: weighted mean, or the plain mean when w is NULL
.wmean <- function(v, w) {
  if (is.null(w)) mean(v) else sum(w * v) / sum(w)
}

## Internal: weighted corrected sum of squares
.wcss <- function(v, w) {
  m <- .wmean(v, w)
  if (is.null(w)) sum((v - m)^2) else sum(w * (v - m)^2)
}

## Internal: weighted variance at SAS VARDEF=. Under "df" (the only divisor
## proc_means() uses) the divisor is the count of non-missing observations
## minus one, not the sum of the weights.
.wvar <- function(v, w, vardef = "df") {
  n <- length(v)
  if (n < 2L) {
    return(NA_real_)
  }
  big_w <- if (is.null(w)) n else sum(w)
  d <- switch(vardef,
    df     = n - 1,
    n      = n,
    wdf    = big_w - 1,
    weight = big_w
  )
  if (d <= 0) {
    return(NA_real_)
  }
  .wcss(v, w) / d
}

## Internal: SAS skewness. Under VARDEF=DF, the adjusted Fisher-Pearson
## standardised third moment, not R's naive moment ratio; equals
## e1071::skewness(type = 2). Under VARDEF=N, the moment form with
## s^2 = CSS / n. SAS computes neither under WDF or WEIGHT. The weighted forms
## raise each weight to 3/2, per the SAS documentation.
.wskew <- function(v, w, vardef = "df") {
  n <- length(v)
  if (n < 3L || !vardef %in% c("df", "n")) {
    return(NA_real_)
  }
  s <- sqrt(.wvar(v, w, vardef))
  if (is.na(s) || s == 0) {
    return(NA_real_)
  }
  z <- (v - .wmean(v, w)) / s
  acc <- if (is.null(w)) sum(z^3) else sum(w^(3 / 2) * z^3)
  if (vardef == "n") {
    return(acc / n)
  }
  (n / ((n - 1) * (n - 2))) * acc
}

## Internal: SAS kurtosis, excess. Under VARDEF=DF the adjusted Fisher-Pearson
## form, equal to e1071::kurtosis(type = 2); under VARDEF=N the moment form.
## The weighted forms square each weight.
.wkurt <- function(v, w, vardef = "df") {
  n <- length(v)
  if (n < 4L || !vardef %in% c("df", "n")) {
    return(NA_real_)
  }
  s <- sqrt(.wvar(v, w, vardef))
  if (is.na(s) || s == 0) {
    return(NA_real_)
  }
  z <- (v - .wmean(v, w)) / s
  acc <- if (is.null(w)) sum(z^4) else sum(w^2 * z^4)
  if (vardef == "n") {
    return(acc / n - 3)
  }
  (n * (n + 1) / ((n - 1) * (n - 2) * (n - 3))) * acc -
    3 * (n - 1)^2 / ((n - 2) * (n - 3))
}

## Internal: standard error of the mean. NA unless VARDEF=DF, as in SAS.
.stderr_stat <- function(v, w, ctx) {
  if (ctx$vardef != "df") {
    return(NA_real_)
  }
  use_w <- !is.null(w) && isTRUE(.stderr_sqrt_w[[ctx$procedure]])
  .wvar(v, w) / (if (use_w) sum(w) else length(v))
}

## Internal: build one registry entry. `weighted` is a single logical, or a
## named logical giving the flag per procedure.
.stat <- function(fun, weighted, integer = FALSE,
                  procedures = c("means", "univariate")) {
  list(fun = fun, weighted = weighted, integer = integer,
       procedures = procedures)
}

## Internal: the weighted flag of an entry for one procedure
.resolve_weighted <- function(weighted, procedure) {
  if (length(weighted) == 1L && is.null(names(weighted))) {
    return(isTRUE(weighted))
  }
  isTRUE(weighted[[procedure]])
}

## Quantiles are unweighted under PROC MEANS and weighted under PROC
## UNIVARIATE.
.quantile_weighted <- c(means = FALSE, univariate = TRUE)

## =============================================================================
## Internal: the statistic registry.
##
## Each entry carries its compute function plus three flags. `weighted` is the
## contract from the design: .compute_stat() passes weights to a statistic only
## when its flag is TRUE for the calling procedure, so a statistic cannot
## become weighted by someone editing its body. The location and normality
## tests are flagged weighted only so that they see the weights and return NA
## under them, as SAS does. `integer` types the zero-row result. `procedures`
## lists the procedures that accept the keyword.
##
## fun(x, v, w, ctx): x is the raw vector including NA, v is x with NA removed,
## w is a numeric vector aligned to v or NULL, and ctx is from .stat_ctx().
.stat_registry <- list(
  n = .stat(function(x, v, w, ctx) length(v), FALSE, integer = TRUE),
  nmiss = .stat(function(x, v, w, ctx) sum(is.na(x)), FALSE, integer = TRUE),
  nobs = .stat(function(x, v, w, ctx) length(x), FALSE, integer = TRUE),
  sumwgt = .stat(
    function(x, v, w, ctx) {
      # Both branches coerce to double. `length()` is integer, and `sum()` of
      # an integer weight column stays integer -- either would make the column
      # type depend on the weights supplied, contradicting `integer = FALSE`
      # and the zero-row path. Coercing before the sum also avoids integer
      # overflow.
      if (length(v) == 0L) {
        NA_real_
      } else if (is.null(w)) {
        as.numeric(length(v))
      } else {
        sum(as.numeric(w))
      }
    },
    TRUE
  ),
  mean = .stat(
    function(x, v, w, ctx) if (length(v) == 0L) NA_real_ else .wmean(v, w),
    TRUE
  ),
  std = .stat(function(x, v, w, ctx) sqrt(.wvar(v, w, ctx$vardef)), TRUE),
  min = .stat(
    function(x, v, w, ctx) if (length(v) == 0L) NA_real_ else min(v),
    FALSE
  ),
  max = .stat(
    function(x, v, w, ctx) if (length(v) == 0L) NA_real_ else max(v),
    FALSE
  ),
  sum = .stat(
    function(x, v, w, ctx) {
      if (length(v) == 0L) NA_real_ else if (is.null(w)) sum(v) else sum(w * v)
    },
    TRUE
  ),
  range = .stat(
    function(x, v, w, ctx) {
      if (length(v) == 0L) NA_real_ else max(v) - min(v)
    },
    FALSE
  ),
  stderr = .stat(function(x, v, w, ctx) sqrt(.stderr_stat(v, w, ctx)), TRUE),
  cv = .stat(
    function(x, v, w, ctx) {
      s <- sqrt(.wvar(v, w, ctx$vardef))
      # Return before computing the mean: .wvar() is NA below two
      # observations, and .wmean() of an empty vector is a NaN nothing would
      # use.
      if (is.na(s)) {
        return(NA_real_)
      }
      m <- .wmean(v, w)
      # SAS emits missing when the mean is zero; R would give Inf.
      if (m == 0) NA_real_ else 100 * s / m
    },
    TRUE
  ),
  var = .stat(function(x, v, w, ctx) .wvar(v, w, ctx$vardef), TRUE),
  uss = .stat(
    function(x, v, w, ctx) {
      if (length(v) == 0L) {
        NA_real_
      } else if (is.null(w)) {
        sum(v^2)
      } else {
        sum(w * v^2)
      }
    },
    TRUE
  ),
  css = .stat(
    function(x, v, w, ctx) if (length(v) == 0L) NA_real_ else .wcss(v, w),
    TRUE
  ),
  skewness = .stat(function(x, v, w, ctx) .wskew(v, w, ctx$vardef), TRUE),
  kurtosis = .stat(function(x, v, w, ctx) .wkurt(v, w, ctx$vardef), TRUE),
  qrange = .stat(
    function(x, v, w, ctx) {
      if (length(v) == 0L) {
        return(NA_real_)
      }
      .quantile_stat(v, "q3", w) - .quantile_stat(v, "q1", w)
    },
    .quantile_weighted
  ),
  mode = .stat(
    function(x, v, w, ctx) {
      if (length(v) == 0L) {
        return(NA_real_)
      }
      u <- unique(v)
      counts <- tabulate(match(v, u))
      top <- max(counts)
      # SAS: no mode when nothing repeats, except that a single observation
      # is its own mode (oracle, 2026-09-17).
      if (top == 1L && length(v) > 1L) {
        return(NA_real_)
      }
      # SAS reports the smallest value among tied modes.
      min(u[counts == top])
    },
    FALSE
  ),
  median = .stat(
    function(x, v, w, ctx) .quantile_stat(v, "median", w),
    .quantile_weighted
  ),
  q1 = .stat(
    function(x, v, w, ctx) .quantile_stat(v, "q1", w),
    .quantile_weighted
  ),
  q3 = .stat(
    function(x, v, w, ctx) .quantile_stat(v, "q3", w),
    .quantile_weighted
  )
)

## Internal: the registry as one procedure sees it -- only the keywords it
## accepts, with `weighted` resolved to a single logical.
.stats_for <- function(procedure) {
  keep <- Filter(function(e) procedure %in% e$procedures, .stat_registry)
  lapply(keep, function(e) {
    e$weighted <- .resolve_weighted(e$weighted, procedure)
    e
  })
}

## Internal: proc_means()'s view of the registry
.STATS <- .stats_for("means")

## Internal: reject unknown statistic keywords
.validate_stats <- function(stats, procedure = "means") {
  known <- names(.stats_for(procedure))
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
## entry is not marked `weighted` for ctx$procedure never see it. A keyword
## not in the registry is a quantile: pNN, or the internal ".pctl:" prefix
## followed by a PCTLPTS= point.
.compute_stat <- function(x, stat, w = NULL, ctx = .stat_ctx()) {
  x <- as.numeric(x)
  keep <- !is.na(x)
  v <- x[keep]

  entry <- .stat_registry[[stat]]
  weighted <- if (is.null(entry)) .quantile_weighted else entry$weighted
  wv <- if (.resolve_weighted(weighted, ctx$procedure) && !is.null(w)) {
    w[keep]
  } else {
    NULL
  }
  if (is.null(entry)) {
    return(.quantile_stat(v, stat, wv))
  }
  entry$fun(x, v, wv, ctx)
}

## Internal: quantile statistics. Unweighted at SAS QNTLDEF=5 (R type 2);
## weighted by the PROC UNIVARIATE weighted definition.
.quantile_stat <- function(v, stat, w = NULL) {
  if (length(v) == 0L) {
    return(NA_real_)
  }
  p <- if (startsWith(stat, ".pctl:")) {
    as.numeric(sub("^\\.pctl:", "", stat)) / 100
  } else {
    switch(stat,
      median = 0.5,
      q1     = 0.25,
      q3     = 0.75,
      as.numeric(sub("^p", "", stat)) / 100
    )
  }
  if (is.null(w)) {
    return(stats::quantile(v, probs = p, type = 2, names = FALSE))
  }
  .wquantile(v, w, p)
}

## Internal: SAS PROC UNIVARIATE weighted percentile. Sort ascending with
## cumulative weights S_i. p = 0 is the minimum and p = 1 the maximum;
## otherwise the mean of x_i and x_(i+1) when S_i equals pW (within a relative
## tolerance), else x_i for the first S_i above pW. PCTLDEF= does not apply.
.wquantile <- function(v, w, p) {
  o <- order(v)
  v <- v[o]
  cum <- cumsum(w[o])
  big_w <- cum[length(cum)]
  if (p <= 0) {
    return(v[1L])
  }
  if (p >= 1) {
    return(v[length(v)])
  }
  target <- p * big_w
  hit <- which(abs(cum - target) <= 1e-12 * big_w)
  if (length(hit) > 0L && hit[1L] < length(v)) {
    i <- hit[1L]
    return((v[i] + v[i + 1L]) / 2)
  }
  above <- which(cum > target)
  if (length(above) == 0L) v[length(v)] else v[above[1L]]
}
```

- [ ] **Step 4: Turn `proc_means()` into a wrapper over the shared driver.** Apply these replacements to `R/proc_means.R`. Replace 2 occurs twice in the file (both zero-row returns); replace both occurrences. Replace 3 keeps #119's class levels for `proc_means()` and drops a level whose every weight is missing for `proc_univariate()`, which SAS `PROC UNIVARIATE` does (SAS evidence in `dev/oracle/proc_means/` from #119).

  Replace 1 in `R/proc_means.R`:

```r
proc_means <- function(data, vars = NULL, class = NULL,
                       stats = c("n", "mean", "std", "min", "max"),
                       weights = NULL) {
  if (!is.data.frame(data)) {
    stop("'data' must be a data frame.", call. = FALSE)
  }
  .validate_stats(stats)

  labels <- labelled::var_label(data, unlist = TRUE, null_action = "fill")

  wvec <- .validate_weights(weights, data)
  # Rows dropped for a missing weight still count toward nobs, as in SAS.
  excluded <- data[0, , drop = FALSE]
  if (!is.null(wvec)) {
    keep_w <- !is.na(wvec)
    excluded <- data[!keep_w, , drop = FALSE]
    data <- data[keep_w, , drop = FALSE]
    wvec <- wvec[keep_w]
  }
```

  with:

```r
proc_means <- function(data, vars = NULL, class = NULL,
                       stats = c("n", "mean", "std", "min", "max"),
                       weights = NULL) {
  if (!is.data.frame(data)) {
    stop("'data' must be a data frame.", call. = FALSE)
  }
  .validate_stats(stats)
  .summary_table(data, vars, class, stats, weights, .stat_ctx("means"))
}

## Internal: the driver shared by proc_means() and proc_univariate().
##
## Validates vars, class and weights; drops rows with a missing weight (they
## still count toward nobs, per class level); groups by class; and assembles
## one row per analysis variable per class level. `stats` are engine keywords
## and `col_names` the output column names, one per keyword.
.summary_table <- function(data, vars, class, stats, weights, ctx,
                           col_names = stats) {
  labels <- labelled::var_label(data, unlist = TRUE, null_action = "fill")

  wvec <- .validate_weights(weights, data)
  # Rows dropped for a missing weight still count toward nobs, as in SAS.
  excluded <- data[0, , drop = FALSE]
  if (!is.null(wvec)) {
    keep_w <- !is.na(wvec)
    excluded <- data[!keep_w, , drop = FALSE]
    data <- data[keep_w, , drop = FALSE]
    wvec <- wvec[keep_w]
  }
```

  Replace 2 in `R/proc_means.R` (both occurrences):

```r
    return(.empty_means(class, stats))
```

  with:

```r
    return(.empty_means(class, stats, col_names))
```

  Replace 3 in `R/proc_means.R` (the class levels: #119's rule, now for proc_means() only):

```r
    # Levels come from every row with a complete class value, including rows
    # dropped for a missing weight: SAS PROC MEANS still prints a level whose
    # every weight is missing (N = 0, with its rows counted in nobs).
    excl_cls <- excluded[, class, drop = FALSE]
    excl_cls <- excl_cls[stats::complete.cases(excl_cls), , drop = FALSE]
    groups <- unique(rbind(data[, class, drop = FALSE], excl_cls))
```

  with:

```r
    # Levels come from every row with a complete class value. Under
    # proc_means() that includes rows dropped for a missing weight: SAS PROC
    # MEANS still prints a level whose every weight is missing (N = 0, with
    # its rows counted in nobs). SAS PROC UNIVARIATE drops such a level.
    groups <- data[, class, drop = FALSE]
    if (ctx$procedure == "means") {
      excl_cls <- excluded[, class, drop = FALSE]
      excl_cls <- excl_cls[stats::complete.cases(excl_cls), , drop = FALSE]
      groups <- rbind(groups, excl_cls)
    }
    groups <- unique(groups)
```

  Replace 4 in `R/proc_means.R`:

```r
        .means_row(data[[v]], v, unname(labels[v]), stats, wvec,
                   n_excluded = nrow(excluded))
```

  with:

```r
        .means_row(data[[v]], v, unname(labels[v]), stats, wvec,
                   n_excluded = nrow(excluded), ctx = ctx,
                   col_names = col_names)
```

  Replace 5 in `R/proc_means.R`:

```r
                     n_excluded = grp_excluded[i]),
```

  with:

```r
                     n_excluded = grp_excluded[i], ctx = ctx,
                     col_names = col_names),
```

  Replace 6 in `R/proc_means.R`:

```r
.means_row <- function(x, variable, label, stats, w = NULL,
                       n_excluded = 0L) {
  vals <- lapply(stats, function(s) .compute_stat(x, s, w))
  names(vals) <- stats
```

  with:

```r
.means_row <- function(x, variable, label, stats, w = NULL,
                       n_excluded = 0L, ctx = .stat_ctx(),
                       col_names = stats) {
  vals <- lapply(stats, function(s) .compute_stat(x, s, w, ctx))
  names(vals) <- col_names
```

  Replace 7 in `R/proc_means.R`:

```r
.empty_means <- function(class, stats) {
  out <- data.frame(variable = character(), label = character(),
                    stringsAsFactors = FALSE)
  for (s in stats) {
    entry <- .STATS[[s]]
    out[[s]] <- if (isTRUE(entry$integer)) integer() else numeric()
  }
```

  with:

```r
.empty_means <- function(class, stats, col_names = stats) {
  out <- data.frame(variable = character(), label = character(),
                    stringsAsFactors = FALSE)
  for (i in seq_along(stats)) {
    entry <- .stat_registry[[stats[i]]]
    out[[col_names[i]]] <- if (isTRUE(entry$integer)) integer() else numeric()
  }
```

- [ ] **Step 5: Run the engine test, the consumers and the full suite.**

```bash
Rscript -e 'devtools::test(filter = "stat_engine")'
Rscript -e 'devtools::test(filter = "proc_means|data_dictionary|proc_freq")'
Rscript -e 'devtools::test()'
```

  Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 61 ]`; `[ FAIL 0 | WARN 1 | SKIP 0 | PASS 381 ]` (unchanged); `[ FAIL 0 | WARN 7 | SKIP 0 | PASS 2177 ]` (2184 expectations). No roxygen changed.

- [ ] **Commit.**

```bash
git add R/stat_engine.R \
  R/proc_means.R \
  tests/testthat/test-stat_engine.R
git commit -F - <<'EOF'
refactor: give the statistic engine a per-procedure context

Registry entries declare the procedures that accept them and whether they
are weighted per procedure; .stat_ctx() carries the procedure, VARDEF and
MU0. proc_means() is now a wrapper over the shared .summary_table()
driver. Its results and messages are unchanged.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

## Task 3: The univariate-only statistics

Adds `stdmean`, `t`, `probt`, `msign`, `probm`, `signrank`, `probs`, `normal` and `probn` to the engine, for `univariate` only. The signed rank exact p-value (20 or fewer non-zero differences) counts sign assignments by dynamic programming over doubled ranks, which are integers even with ties; above 20 it uses the spec's tie-corrected t approximation.

**Files:**
- Modify: `R/stat_engine.R`
- Test: `tests/testthat/test-stat_engine.R` (append)

**Interfaces:**
- Consumes: `.stat_ctx()`, `.wvar()`, `.wmean()`, `.stat()`, `.stats_for()`, `.validate_stats()` from Task 2.
- Produces: `.t_test_stat(v, w, ctx, what)`, `.sign_test_stat(v, w, ctx, what)`, `.signrank_stat(v, w, ctx, what)`, `.normal_stat(v, w, ctx, what)` (sets `ctx$flags$normal_n2000`), and registry entries `stdmean`, `t`, `probt`, `msign`, `probm`, `signrank`, `probs`, `normal`, `probn` with `procedures = "univariate"`.

- [ ] **Step 1: Append the failing tests** to the end of `tests/testthat/test-stat_engine.R`:

```r

test_that("the univariate keywords belong to univariate only", {
  kw <- c("stdmean", "t", "probt", "msign", "probm", "signrank", "probs",
          "normal", "probn")
  expect_silent(eng(".validate_stats")(kw, "univariate"))
  for (k in kw) {
    expect_error(eng(".validate_stats")(k), "Unrecognised statistic")
  }
  expect_false(any(kw %in% names(eng(".STATS"))))
})

test_that("stdmean and t use sqrt(W) and mu0", {
  # Weighted mean 14 / 5 = 2.8, CSS = 6.8, std = sqrt(6.8 / 3), W = 5.
  x <- c(1, 2, 3, 4)
  w <- c(1, 1, 1, 2)
  se <- sqrt(6.8 / 3) / sqrt(5)
  expect_equal(cs(x, "stdmean", w, procedure = "univariate"), se)
  expect_equal(cs(x, "t", w, procedure = "univariate", mu0 = 1), 1.8 / se)
  expect_equal(cs(x, "probt", w, procedure = "univariate", mu0 = 1),
               2 * stats::pt(-1.8 / se, 3))
  expect_true(is.na(cs(x, "t", procedure = "univariate", vardef = "n")))
  expect_true(is.na(cs(rep(2, 3), "t", procedure = "univariate")))
})

test_that("sign test drops values equal to mu0", {
  # x - 2 = -1, 0, 1, 2, 3: 3 above and 1 below.
  x <- c(1, 2, 3, 4, 5)
  expect_equal(cs(x, "msign", procedure = "univariate", mu0 = 2), 1)
  # Twice the binomial probability of one or fewer in four: 2 * 5 / 16.
  expect_equal(cs(x, "probm", procedure = "univariate", mu0 = 2), 0.625)
})

test_that("signed rank exact p matches full enumeration with ties", {
  x <- c(1, -1, 2, 3, -2, 4, 4, -5, 6, 0.5)
  d <- x[x != 0]
  r <- rank(abs(d))
  s_obs <- sum(sign(d) * r) / 2
  signs <- as.matrix(expand.grid(rep(list(c(-1, 1)), length(r))))
  s_all <- as.vector(signs %*% r) / 2
  expect_equal(cs(x, "signrank", procedure = "univariate"), s_obs)
  expect_equal(cs(x, "probs", procedure = "univariate"),
               mean(abs(s_all) >= abs(s_obs)))
})

test_that("signed rank exact p on a small tied sample", {
  # d = 1, -1, 2, 3: ranks 1.5, 1.5, 3, 4, S = 3.5. Positive-rank sums reach
  # 8.5 or more in 3 of 16 assignments and 1.5 or less in 3: p = 6 / 16.
  expect_equal(cs(c(1, -1, 2, 3), "probs", procedure = "univariate"),
               0.375)
})

test_that("the location tests other than t are NA under weights", {
  x <- c(1, 2, 3, 5, 8)
  w <- c(1, 2, 1, 1, 1)
  for (k in c("msign", "probm", "signrank", "probs", "normal", "probn")) {
    expect_true(is.na(cs(x, k, w, procedure = "univariate")), info = k)
  }
})

test_that("normality is W = 1, p = 1 at n = 2 and NA below", {
  expect_equal(cs(c(1, 4), "normal", procedure = "univariate"), 1)
  expect_equal(cs(c(1, 4), "probn", procedure = "univariate"), 1)
  expect_true(is.na(cs(3, "normal", procedure = "univariate")))
})

test_that("normality above 2000 observations is NA and sets the flag", {
  k <- ctx("univariate")
  expect_true(is.na(
    eng(".compute_stat")(sin(seq_len(2001)), "normal", NULL, k)
  ))
  expect_true(isTRUE(k$flags$normal_n2000))
  k2 <- ctx("univariate")
  expect_false(is.na(
    eng(".compute_stat")(sin(seq_len(2000)), "normal", NULL, k2)
  ))
  expect_null(k2$flags$normal_n2000)
})
```

- [ ] **Step 2: Run and watch them fail.**

```bash
Rscript -e 'devtools::test(filter = "stat_engine")'
```

  Expected: 9 failed expectations and 3 errored tests (the new keywords are unknown, so `.validate_stats()` rejects them and `.compute_stat()` sends them down the quantile path: `NAs introduced by coercion` warnings and `missing value where TRUE/FALSE needed`), with the 61 Task 2 expectations still passing.

- [ ] **Step 3: Implement.** Apply to `R/stat_engine.R`:

  Replace 1 in `R/stat_engine.R` (after `.stderr_stat()`):

```r
  .wvar(v, w) / (if (use_w) sum(w) else length(v))
}
```

  with:

```r
  .wvar(v, w) / (if (use_w) sum(w) else length(v))
}

## Internal: Student's t for H0: mean = mu0, and its two-sided p-value
.t_test_stat <- function(v, w, ctx, what) {
  n <- length(v)
  if (ctx$vardef != "df" || n < 2L) {
    return(NA_real_)
  }
  s <- sqrt(.wvar(v, w))
  if (s == 0) {
    return(NA_real_)
  }
  big_w <- if (is.null(w)) n else sum(w)
  t <- (.wmean(v, w) - ctx$mu0) / (s / sqrt(big_w))
  if (what == "t") t else 2 * stats::pt(-abs(t), n - 1)
}

## Internal: the sign test. NA under weights (SAS computes only the t test
## there) and when no value differs from mu0 (SAS behaviour unobserved).
.sign_test_stat <- function(v, w, ctx, what) {
  if (!is.null(w)) {
    return(NA_real_)
  }
  d <- v - ctx$mu0
  n_plus <- sum(d > 0)
  n_minus <- sum(d < 0)
  if (n_plus + n_minus == 0L) {
    return(NA_real_)
  }
  if (what == "msign") {
    return((n_plus - n_minus) / 2)
  }
  min(1, 2 * stats::pbinom(min(n_plus, n_minus), n_plus + n_minus, 0.5))
}

## Internal: the Wilcoxon signed rank test. NA under weights and when no value
## differs from mu0. At 20 or fewer non-zero differences the p-value is exact,
## from the null distribution of the signed rank sum computed by dynamic
## programming over doubled ranks (average ranks are integers once doubled);
## above 20 it is SAS's tie-corrected t approximation.
.signrank_stat <- function(v, w, ctx, what) {
  if (!is.null(w)) {
    return(NA_real_)
  }
  d <- v - ctx$mu0
  d <- d[d != 0]
  n <- length(d)
  if (n == 0L) {
    return(NA_real_)
  }
  r <- rank(abs(d))
  s <- sum(sign(d) * r) / 2
  if (what == "signrank") {
    return(s)
  }
  if (n <= 20L) {
    r2 <- as.integer(round(2 * r))
    total <- sum(r2)
    # Entry k + 1 counts the sign assignments whose positive doubled ranks
    # sum to k.
    counts <- c(1, numeric(total))
    for (ri in r2) {
      counts <- counts + c(numeric(ri), counts[seq_len(total + 1L - ri)])
    }
    pos <- 0:total
    obs <- as.integer(round(4 * s))     # sum(sign * doubled ranks)
    return(sum(counts[abs(2L * pos - total) >= abs(obs)]) / 2^n)
  }
  ties <- table(r)
  v_s <- n * (n + 1) * (2 * n + 1) / 24 - sum(ties^3 - ties) / 48
  t <- s * sqrt((n - 1) / (n * v_s - s^2))
  2 * stats::pt(-abs(t), n - 1)
}

## Internal: the Shapiro-Wilk test. W = 1, p = 1 at n = 2, as SAS reports. NA
## under weights, below two observations, for a constant column, and above
## 2000 observations, where SAS switches to a Kolmogorov D test that is not
## ported; that last case sets ctx$flags$normal_n2000 for the caller to warn.
.normal_stat <- function(v, w, ctx, what) {
  n <- length(v)
  if (!is.null(w) || n < 2L || all(v == v[1L])) {
    return(NA_real_)
  }
  if (n > 2000L) {
    assign("normal_n2000", TRUE, envir = ctx$flags)
    return(NA_real_)
  }
  if (n == 2L) {
    return(1)
  }
  sw <- stats::shapiro.test(v)
  if (what == "normal") unname(sw$statistic) else sw$p.value
}
```

  Replace 2 in `R/stat_engine.R` (the end of the `q3` entry):

```r
  q3 = .stat(
    function(x, v, w, ctx) .quantile_stat(v, "q3", w),
    .quantile_weighted
  )
```

  with:

```r
  q3 = .stat(
    function(x, v, w, ctx) .quantile_stat(v, "q3", w),
    .quantile_weighted
  ),
  stdmean = .stat(
    function(x, v, w, ctx) sqrt(.stderr_stat(v, w, ctx)),
    TRUE, procedures = "univariate"
  ),
  t = .stat(
    function(x, v, w, ctx) .t_test_stat(v, w, ctx, "t"),
    TRUE, procedures = "univariate"
  ),
  probt = .stat(
    function(x, v, w, ctx) .t_test_stat(v, w, ctx, "probt"),
    TRUE, procedures = "univariate"
  ),
  msign = .stat(
    function(x, v, w, ctx) .sign_test_stat(v, w, ctx, "msign"),
    TRUE, procedures = "univariate"
  ),
  probm = .stat(
    function(x, v, w, ctx) .sign_test_stat(v, w, ctx, "probm"),
    TRUE, procedures = "univariate"
  ),
  signrank = .stat(
    function(x, v, w, ctx) .signrank_stat(v, w, ctx, "signrank"),
    TRUE, procedures = "univariate"
  ),
  probs = .stat(
    function(x, v, w, ctx) .signrank_stat(v, w, ctx, "probs"),
    TRUE, procedures = "univariate"
  ),
  normal = .stat(
    function(x, v, w, ctx) .normal_stat(v, w, ctx, "normal"),
    TRUE, procedures = "univariate"
  ),
  probn = .stat(
    function(x, v, w, ctx) .normal_stat(v, w, ctx, "probn"),
    TRUE, procedures = "univariate"
  )
```

- [ ] **Step 4: Run the engine test and the full suite.**

```bash
Rscript -e 'devtools::test(filter = "stat_engine")'
Rscript -e 'devtools::test()'
```

  Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 104 ]`; `[ FAIL 0 | WARN 7 | SKIP 0 | PASS 2220 ]` (2227 expectations).

- [ ] **Commit.**

```bash
git add R/stat_engine.R \
  tests/testthat/test-stat_engine.R
git commit -F - <<'EOF'
feat: add the PROC UNIVARIATE location and normality statistics

stdmean, t, probt, msign, probm, signrank, probs, normal and probn, for
proc_univariate() only. The signed rank exact p-value uses dynamic
programming over doubled ranks. Statistics SAS does not compute are NA.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

## Task 4: `proc_univariate()`

**Files:**
- Create: `R/proc_univariate.R`
- Modify: `_pkgdown.yml`
- Generated: `man/proc_univariate.Rd`, `NAMESPACE`
- Test: `tests/testthat/test-proc_univariate_shape.R`, `tests/testthat/test-proc_univariate_errors.R`, `tests/testthat/test-proc_univariate_values.R` (create)

**Interfaces:**
- Consumes: `.validate_stats(stats, "univariate")`, `.stat_ctx("univariate", vardef, mu0)`, `.summary_table(data, vars, class, stats, weights, ctx, col_names)`.
- Produces: exported `proc_univariate(data, vars = NULL, class = NULL, stats = c("n", "median", "mean", "std", "cv", "min", "max"), weights = NULL, pctlpts = NULL, pctlpre = "p", mu0 = 0, vardef = c("df", "n", "wdf", "weight"))`; internal `.pctl_names(pctlpts, pctlpre, stats)`.

- [ ] **Step 1: Write the failing tests.** Create `tests/testthat/test-proc_univariate_shape.R`:

```r
library(testthat)
library(hvtiRutilities)

dta <- data.frame(g = c("b", "a", "b", "a", NA),
                  x = c(1, 2, 3, 4, 5),
                  y = c(2, 4, 6, 8, 10),
                  w = c(1, 2, 1, 2, 1))

test_that("default statistics are the unistats default, in order", {
  res <- proc_univariate(dta, vars = "x")
  expect_named(res, c("variable", "label", "n", "median", "mean", "std",
                      "cv", "min", "max"))
})

test_that("stats columns come in the order given, then pctlpts columns", {
  res <- proc_univariate(dta, vars = c("x", "y"), stats = c("max", "n"),
                         pctlpts = c(97.5, 0, 50, 100, 2.5))
  expect_named(res, c("variable", "label", "max", "n", "p97_5", "p0",
                      "p50", "p100", "p2_5"))
  expect_equal(res$variable, c("x", "y"))
  expect_equal(res$label, c("x", "y"))
})

test_that("pctlpre prefixes the percentile columns", {
  res <- proc_univariate(dta, vars = "x", stats = "n", pctlpts = 16,
                         pctlpre = "pp_")
  expect_named(res, c("variable", "label", "n", "pp_16"))
})

test_that("count statistics are integer and the rest numeric", {
  res <- proc_univariate(dta, vars = "x",
                         stats = c("n", "nmiss", "nobs", "msign", "t"),
                         pctlpts = 50)
  expect_type(res$n, "integer")
  expect_type(res$nmiss, "integer")
  expect_type(res$nobs, "integer")
  expect_type(res$msign, "double")
  expect_type(res$t, "double")
  expect_type(res$p50, "double")
})

test_that("class rows lead, drop a missing class value, and sort", {
  res <- proc_univariate(dta, vars = "x", class = "g", stats = "n")
  expect_named(res, c("g", "variable", "label", "n"))
  expect_equal(res$g, c("a", "b"))
  expect_equal(res$n, c(2L, 2L))
})

test_that("vars = NULL analyses numeric columns other than weights", {
  res <- proc_univariate(dta, stats = "n", weights = "w")
  expect_equal(res$variable, c("x", "y"))
})

test_that("a zero-row result keeps stats and percentile columns and types", {
  expect_warning(
    res <- proc_univariate(data.frame(g = c("a", "b")), stats = c("n", "t"),
                           pctlpts = 2.5),
    "No numeric columns"
  )
  expect_equal(nrow(res), 0L)
  expect_named(res, c("variable", "label", "n", "t", "p2_5"))
  expect_type(res$n, "integer")
  expect_type(res$p2_5, "double")
})

test_that("a class level whose every weight is missing is dropped", {
  # SAS 9.4 M8 PROC UNIVARIATE (2026-09-17) writes no row for level y.
  # PROC MEANS keeps such a level, with N = 0.
  cw <- data.frame(g = c("x", "x", "y", "y"), a = 1:4,
                   wt = c(1, 2, NA, NA))
  res <- proc_univariate(cw, vars = "a", class = "g",
                         stats = c("n", "nobs"), weights = "wt")
  expect_identical(res$g, "x")
  expect_identical(res$n, 2L)
  expect_identical(res$nobs, 2L)
})
```

  Create `tests/testthat/test-proc_univariate_errors.R`:

```r
library(testthat)
library(hvtiRutilities)

dta <- data.frame(x = c(1, 2, 3, 4), w = c(1, 1, 2, 0.5))

test_that("proc_means() errors and messages carry over", {
  expect_error(proc_univariate(list(x = 1)), "'data' must be a data frame")
  expect_error(proc_univariate(dta, vars = "nope"), "not found in 'data'")
  expect_error(proc_univariate(data.frame(x = "a"), vars = "x"),
               "Non-numeric column")
  expect_error(proc_univariate(dta, weights = "nope"), "not found in 'data'")
  expect_error(proc_univariate(data.frame(x = 1, w = 0), vars = "x",
                               weights = "w"),
               "non-positive value")
  expect_error(proc_univariate(dta, vars = c("x", "w"), weights = "w"),
               "also named in 'vars' or 'class'")
})

test_that("an unknown keyword errors and lists the univariate keywords", {
  expect_error(proc_univariate(dta, stats = "bogus"),
               "Unrecognised statistic keyword\\(s\\): bogus")
  expect_error(proc_univariate(dta, stats = "bogus"), "signrank")
})

test_that("proc_means() does not gain the univariate keywords", {
  for (k in c("stdmean", "t", "probt", "msign", "probm", "signrank",
              "probs", "normal", "probn")) {
    expect_error(proc_means(dta, stats = k), "Unrecognised statistic")
  }
})

test_that("pctlpts is validated", {
  expect_error(proc_univariate(dta, pctlpts = "50"), "must be numeric")
  expect_error(proc_univariate(dta, pctlpts = c(50, NA)), "must not contain NA")
  expect_error(proc_univariate(dta, pctlpts = c(-1, 50)), "\\[0, 100\\]")
  expect_error(proc_univariate(dta, pctlpts = 100.5), "\\[0, 100\\]")
  expect_error(proc_univariate(dta, pctlpts = c(2.5, 2.5)), "duplicated")
})

test_that("pctlpre is validated", {
  expect_error(proc_univariate(dta, pctlpts = 50, pctlpre = ""),
               "single non-empty string")
  expect_error(proc_univariate(dta, pctlpts = 50, pctlpre = c("a", "b")),
               "single non-empty string")
  expect_error(proc_univariate(dta, pctlpts = 50, pctlpre = NA_character_),
               "single non-empty string")
  expect_error(proc_univariate(dta, pctlpts = 50, pctlpre = 1),
               "single non-empty string")
})

test_that("a percentile name that duplicates a stats column errors", {
  expect_error(proc_univariate(dta, stats = c("n", "p50"), pctlpts = 50),
               "duplicate another output column: p50")
})

test_that("mu0 must be a single finite number", {
  expect_error(proc_univariate(dta, mu0 = NA_real_), "single finite number")
  expect_error(proc_univariate(dta, mu0 = Inf), "single finite number")
  expect_error(proc_univariate(dta, mu0 = c(1, 2)), "single finite number")
  expect_error(proc_univariate(dta, mu0 = "1"), "single finite number")
})

test_that("vardef must be one of the four SAS values", {
  expect_error(proc_univariate(dta, vardef = "wgt"), "should be one of")
})

test_that("normality above 2000 observations is NA with one warning", {
  big <- data.frame(x = sin(seq_len(2001)), y = cos(seq_len(2001)))
  expect_warning(
    res <- proc_univariate(big, stats = c("n", "normal", "probn")),
    "Kolmogorov D"
  )
  expect_true(all(is.na(res$normal)))
  expect_true(all(is.na(res$probn)))
  warnings_seen <- 0L
  withCallingHandlers(
    proc_univariate(big, stats = c("normal", "probn")),
    warning = function(w) {
      warnings_seen <<- warnings_seen + 1L
      invokeRestart("muffleWarning")
    }
  )
  expect_equal(warnings_seen, 1L)
})

test_that("no warning at 2000 observations or without a normality keyword", {
  expect_no_warning(
    proc_univariate(data.frame(x = sin(seq_len(2000))), stats = "normal")
  )
  expect_no_warning(
    proc_univariate(data.frame(x = sin(seq_len(2001))), stats = "n")
  )
})
```

  Create `tests/testthat/test-proc_univariate_values.R`:

```r
library(testthat)
library(hvtiRutilities)

# Hand-computed literals, independent of the SAS oracle.

test_that("weighted percentile averages neighbours when S_i equals pW", {
  # w = 1, 1, 1, 1: W = 4, the median's pW = 2 equals S_2, so (2 + 3) / 2.
  d <- data.frame(x = c(4, 1, 3, 2), w = c(1, 1, 1, 1))
  res <- proc_univariate(d, vars = "x", stats = "median", weights = "w",
                         pctlpts = c(0, 30, 100))
  expect_equal(res$median, 2.5)
  # pW = 1.2: the first S_i above it is S_2 = 2, so x_2 = 2.
  expect_equal(res$p30, 2)
  expect_equal(res$p0, 1)
  expect_equal(res$p100, 4)
})

test_that("weighted percentile takes the first S_i above pW", {
  # S = 1, 4, 5, 6 and pW = 3 for the median: first S_i > 3 is S_2, so 2.
  d <- data.frame(x = c(1, 2, 3, 4), w = c(1, 3, 1, 1))
  res <- proc_univariate(d, vars = "x", stats = c("median", "q3", "mode"),
                         weights = "w")
  expect_equal(res$median, 2)
  # pW = 4.5 for q3: S_3 = 5 is the first above it, so 3.
  expect_equal(res$q3, 3)
  # mode stays unweighted: no value repeats.
  expect_true(is.na(res$mode))
})

test_that("unweighted decimal percentiles follow PCTLDEF=5", {
  d <- data.frame(x = c(1, 2, 3, 4))
  res <- proc_univariate(d, stats = "n", pctlpts = c(2.5, 25, 50))
  expect_equal(res$p2_5, 1)
  expect_equal(res$p25, 1.5)
  expect_equal(res$p50, 2.5)
})

test_that("signed rank exact p on a small tied sample", {
  # d = 1, -1, 2, 3: ranks 1.5, 1.5, 3, 4, S = (1.5 - 1.5 + 3 + 4) / 2 = 3.5.
  # Positive-rank sums over the 16 sign assignments reach 8.5 or more in 3
  # (8.5, 8.5, 10) and 1.5 or less in 3 (0, 1.5, 1.5): p = 6 / 16.
  d <- data.frame(x = c(1, -1, 2, 3))
  res <- proc_univariate(d, stats = c("signrank", "probs"))
  expect_equal(res$signrank, 3.5)
  expect_equal(res$probs, 0.375)
})

test_that("sign test drops values equal to mu0", {
  # d = -1, 0, 1, 2, 3 with mu0 = 2: one zero, 3 above, 1 below.
  d <- data.frame(x = c(1, 2, 3, 4, 5))
  res <- proc_univariate(d, stats = c("msign", "probm"), mu0 = 2)
  expect_equal(res$msign, 1)
  # Twice the binomial probability of one or fewer in four: 2 * 5 / 16.
  expect_equal(res$probm, 0.625)
})

test_that("each vardef divisor", {
  # x = 1, 2, 3, 4: CSS = 5; w = 1, 1, 1, 2: W = 5, weighted CSS = 6.8.
  d <- data.frame(x = c(1, 2, 3, 4), w = c(1, 1, 1, 2))
  var_for <- function(vardef, weights = NULL) {
    proc_univariate(d, vars = "x", stats = "var", weights = weights,
                    vardef = vardef)$var
  }
  expect_equal(var_for("df"), 5 / 3)
  expect_equal(var_for("n"), 5 / 4)
  expect_equal(var_for("df", "w"), 6.8 / 3)
  expect_equal(var_for("n", "w"), 6.8 / 4)
  expect_equal(var_for("wdf", "w"), 6.8 / 4)
  expect_equal(var_for("weight", "w"), 6.8 / 5)
})

test_that("stdmean and t divide by sqrt(sum of weights)", {
  # weighted mean 14 / 5 = 2.8, CSS = 6.8, std = sqrt(6.8 / 3), W = 5.
  d <- data.frame(x = c(1, 2, 3, 4), w = c(1, 1, 1, 2))
  res <- proc_univariate(d, vars = "x", stats = c("stdmean", "t"),
                         weights = "w", mu0 = 1)
  expect_equal(res$stdmean, sqrt(6.8 / 3) / sqrt(5))
  expect_equal(res$t, 1.8 / (sqrt(6.8 / 3) / sqrt(5)))
})

test_that("statistics SAS does not compute are NA", {
  d <- data.frame(x = c(1, 2, 3, 5, 8), w = c(1, 2, 1, 1, 1))
  tests <- c("msign", "probm", "signrank", "probs", "normal", "probn")
  wtd <- proc_univariate(d, vars = "x", stats = c(tests, "t"),
                         weights = "w")
  expect_true(all(is.na(unlist(wtd[tests]))))
  expect_false(is.na(wtd$t))

  vn <- proc_univariate(d, vars = "x", vardef = "wdf", weights = "w",
                        stats = c("t", "probt", "stdmean", "skewness",
                                  "kurtosis"))
  expect_true(all(is.na(unlist(vn[-(1:2)]))))

  k <- proc_univariate(data.frame(x = rep(5, 6)),
                       stats = c("t", "probt", "skewness", "kurtosis",
                                 "normal", "probn", "cv"))
  expect_true(all(is.na(unlist(k[3:8]))))
  expect_equal(k$cv, 0)

  zero <- proc_univariate(data.frame(x = c(0, 0)),
                          stats = c("msign", "probm", "signrank", "probs"))
  expect_true(all(is.na(unlist(zero[-(1:2)]))))
})

test_that("normality at n = 2 is W = 1, p = 1", {
  res <- proc_univariate(data.frame(x = c(1, 4)),
                         stats = c("normal", "probn"))
  expect_equal(res$normal, 1)
  expect_equal(res$probn, 1)
})
```

- [ ] **Step 2: Run and watch them fail.**

```bash
Rscript -e 'devtools::test(filter = "proc_univariate")'
```

  Expected: 26 errored tests with `could not find function "proc_univariate"`; 9 expectations pass (the `proc_means()` keyword rejections in the errors file).

- [ ] **Step 3: Implement.** Create `R/proc_univariate.R`:

```r
#' Summarise and test numeric variables, in the style of SAS PROC UNIVARIATE
#'
#' @description
#' Produces the statistics data set SAS \code{PROC UNIVARIATE} writes with
#' \code{OUTPUT OUT=}: one row per analysis variable (per class level), one
#' column per requested statistic in the order requested, then one column per
#' \code{PCTLPTS=} percentile. Beyond \code{\link{proc_means}} it adds weighted
#' and decimal percentiles, \code{VARDEF=}, and the tests for location and
#' normality.
#'
#' @details
#' \strong{Weighting.} Weights apply as in \code{\link{proc_means}}, except
#' that the quantiles are weighted: \code{median}, \code{q1}, \code{q3},
#' \code{qrange}, \code{pNN} and the \code{pctlpts} columns. The weighted
#' percentile sorts the values with their cumulative weights \eqn{S_i}; the
#' 0th percentile is the minimum and the 100th the maximum; otherwise, when
#' \eqn{S_i = pW} the result is the mean of \eqn{x_i} and \eqn{x_{i+1}},
#' else the first \eqn{x_i} with \eqn{S_i > pW}. Unweighted quantiles use
#' \code{stats::quantile(type = 2)}, SAS's default \code{PCTLDEF=5}.
#' \code{mode} stays unweighted, as in SAS. \code{stderr} and \code{stdmean}
#' divide the standard deviation by the square root of the sum of the weights.
#' A zero or negative weight is an error; SAS instead treats a negative weight
#' as zero and still counts the observation.
#'
#' \strong{VARDEF.} The variance divisor is \eqn{n - 1} (\code{"df"}),
#' \eqn{n} (\code{"n"}), \eqn{W - 1} (\code{"wdf"}) or \eqn{W}
#' (\code{"weight"}), where \eqn{W} is the sum of the weights (\eqn{n}
#' without weights). It changes \code{var}, \code{std} and \code{cv}. Under
#' \code{"n"}, \code{skewness} and \code{kurtosis} are the moment forms rather
#' than the adjusted ones.
#'
#' \strong{Statistics SAS does not compute are NA}, as SAS writes missing:
#' \itemize{
#'   \item \code{msign}, \code{probm}, \code{signrank}, \code{probs},
#'     \code{normal}, \code{probn} when \code{weights} is given;
#'   \item \code{t}, \code{probt}, \code{stderr} and \code{stdmean} when
#'     \code{vardef} is not \code{"df"};
#'   \item \code{skewness} and \code{kurtosis} when \code{vardef} is
#'     \code{"wdf"} or \code{"weight"};
#'   \item \code{normal} and \code{probn} above 2000 observations, with one
#'     warning per call: SAS switches to a Kolmogorov D test there, which is
#'     not ported;
#'   \item \code{std}, \code{var}, \code{cv}, \code{stdmean}, \code{t},
#'     \code{probt} at one observation, \code{skewness} below three and
#'     \code{kurtosis} below four;
#'   \item \code{t}, \code{probt}, \code{skewness}, \code{kurtosis},
#'     \code{normal}, \code{probn} when every value is equal (\code{cv} is
#'     then \code{0});
#'   \item \code{msign}, \code{probm}, \code{signrank}, \code{probs} when no
#'     value differs from \code{mu0};
#'   \item \code{mode} when no value repeats among two or more values.
#' }
#'
#' \strong{Tests.} \code{t} is Student's t for the mean against \code{mu0};
#' \code{msign} the sign statistic; \code{signrank} the Wilcoxon signed rank
#' statistic, with an exact p-value for 20 or fewer non-zero differences and
#' SAS's t approximation above that. \code{normal} is the Shapiro-Wilk
#' \eqn{W}, from \code{stats::shapiro.test()}, which implements Royston's 1995
#' algorithm; SAS implements Royston's 1992 one, so \code{normal} and
#' \code{probn} agree with SAS to about \eqn{10^{-8}}, not to machine
#' precision. At two observations both are \code{1}, as SAS reports.
#'
#' @param data A data frame, tibble, or similar tabular object.
#' @param vars Character vector of columns to analyse. \code{NULL} (default)
#'   selects every numeric column not named in \code{class} or
#'   \code{weights}.
#' @param class Character vector of grouping columns, prepended to the result
#'   as leading columns. Rows with a missing value in any class variable are
#'   dropped, and levels follow \code{ORDER=INTERNAL}, as in
#'   \code{\link{proc_means}}. Unlike \code{proc_means()}, a level whose
#'   every weight is missing has no row, as in SAS.
#' @param stats Character vector of SAS statistic keywords: every keyword
#'   \code{\link{proc_means}} accepts, plus \code{"stdmean"}, \code{"t"},
#'   \code{"probt"}, \code{"msign"}, \code{"probm"}, \code{"signrank"},
#'   \code{"probs"}, \code{"normal"} and \code{"probn"}.
#' @param weights Character or \code{NULL}. Name of a single numeric column of
#'   \code{data} to use as an observation weight, SAS \code{WEIGHT}.
#'   Observations whose weight is missing are excluded from every statistic
#'   except \code{nobs}, which counts them.
#' @param pctlpts Numeric vector of percentile points in \code{[0, 100]},
#'   decimals allowed, or \code{NULL}. SAS \code{PCTLPTS=}.
#' @param pctlpre Single string prefixed to the \code{pctlpts} column names.
#'   SAS \code{PCTLPRE=}. The point follows with \code{.} replaced by
#'   \code{_}, so \code{2.5} gives \code{p2_5}.
#' @param mu0 Single finite number, the null value for \code{t},
#'   \code{msign} and \code{signrank}. SAS \code{MU0=}.
#' @param vardef The variance divisor: \code{"df"} (default), \code{"n"},
#'   \code{"wdf"} or \code{"weight"}. SAS \code{VARDEF=}.
#'
#' @return A data frame with one row per analysis variable per class
#'   combination. Columns are the \code{class} variables (when supplied), then
#'   \code{variable}, \code{label}, then one column per \code{stats} keyword in
#'   the order given, then one column per \code{pctlpts} point in the order
#'   given. \code{n}, \code{nmiss} and \code{nobs} are integer; all others are
#'   numeric.
#'
#' @seealso \code{\link{proc_means}} for the descriptive statistics alone.
#'
#' @export
#'
#' @examples
#' dta <- generate_survival_data(n = 200, seed = 42)
#'
#' # SAS unistats default statistics over every numeric variable
#' head(proc_univariate(dta))
#'
#' # Decimal percentiles, as for a bootstrap interval
#' proc_univariate(dta, vars = "age", stats = "n",
#'                 pctlpts = c(2.5, 50, 97.5))
#'
#' # Tests for location and normality
#' proc_univariate(dta, vars = "bmi",
#'                 stats = c("mean", "t", "probt", "normal", "probn"),
#'                 mu0 = 25)
proc_univariate <- function(data, vars = NULL, class = NULL,
                            stats = c("n", "median", "mean", "std", "cv",
                                      "min", "max"),
                            weights = NULL, pctlpts = NULL, pctlpre = "p",
                            mu0 = 0,
                            vardef = c("df", "n", "wdf", "weight")) {
  if (!is.data.frame(data)) {
    stop("'data' must be a data frame.", call. = FALSE)
  }
  .validate_stats(stats, "univariate")
  vardef <- match.arg(vardef)
  if (!is.numeric(mu0) || length(mu0) != 1L || !is.finite(mu0)) {
    stop("'mu0' must be a single finite number.", call. = FALSE)
  }
  pctl_names <- .pctl_names(pctlpts, pctlpre, stats)

  ctx <- .stat_ctx("univariate", vardef = vardef, mu0 = mu0)
  keywords <- c(stats, sprintf(".pctl:%.17g", pctlpts))
  out <- .summary_table(data, vars, class, keywords, weights, ctx,
                        col_names = c(stats, pctl_names))
  if (isTRUE(ctx$flags$normal_n2000)) {
    warning("'normal' and 'probn' are NA for analyses with more than 2000 ",
            "observations: SAS uses a Kolmogorov D test above 2000 ",
            "observations, which is not ported.", call. = FALSE)
  }
  out
}

## Internal: validate pctlpts and pctlpre and return the percentile column
## names. Each point is formatted on its own, so one decimal point does not
## give every name a decimal.
.pctl_names <- function(pctlpts, pctlpre, stats) {
  if (!is.character(pctlpre) || length(pctlpre) != 1L || is.na(pctlpre) ||
        !nzchar(pctlpre)) {
    stop("'pctlpre' must be a single non-empty string.", call. = FALSE)
  }
  if (is.null(pctlpts)) {
    return(character())
  }
  if (!is.numeric(pctlpts)) {
    stop("'pctlpts' must be numeric.", call. = FALSE)
  }
  if (anyNA(pctlpts)) {
    stop("'pctlpts' must not contain NA.", call. = FALSE)
  }
  if (any(pctlpts < 0 | pctlpts > 100)) {
    stop("'pctlpts' must lie in [0, 100]; got: ",
         paste(pctlpts[pctlpts < 0 | pctlpts > 100], collapse = ", "),
         call. = FALSE)
  }
  if (anyDuplicated(pctlpts)) {
    stop("'pctlpts' has duplicated point(s): ",
         paste(unique(pctlpts[duplicated(pctlpts)]), collapse = ", "),
         call. = FALSE)
  }
  pts <- vapply(pctlpts, function(p) {
    format(p, digits = 15, scientific = FALSE, drop0trailing = TRUE,
           trim = TRUE)
  }, character(1))
  nms <- paste0(pctlpre, gsub(".", "_", pts, fixed = TRUE))
  clash <- nms[nms %in% stats | duplicated(nms)]
  if (length(clash) > 0L) {
    stop("Percentile column name(s) duplicate another output column: ",
         paste(unique(clash), collapse = ", "), call. = FALSE)
  }
  nms
}
```

  Replace in `_pkgdown.yml`:

```yaml
  - proc_means
```

  with:

```yaml
  - proc_means
  - proc_univariate
```

- [ ] **Step 4: Document and run.**

```bash
Rscript -e 'devtools::document()'
git status --short man/ NAMESPACE   # M NAMESPACE, ?? man/proc_univariate.Rd
Rscript -e 'devtools::test(filter = "proc_univariate")'
Rscript -e 'devtools::test()'
```

  Expected: `document()` writes `NAMESPACE` (one added `export(proc_univariate)`) and `proc_univariate.Rd` only. Then `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 91 ]` (shape 23, errors 38, values 30); `[ FAIL 0 | WARN 7 | SKIP 0 | PASS 2311 ]` (2318 expectations).

- [ ] **Commit.**

```bash
git add R/proc_univariate.R \
  _pkgdown.yml \
  NAMESPACE \
  man/proc_univariate.Rd \
  tests/testthat/test-proc_univariate_shape.R \
  tests/testthat/test-proc_univariate_errors.R \
  tests/testthat/test-proc_univariate_values.R
git commit -F - <<'EOF'
feat: add proc_univariate(), a port of SAS PROC UNIVARIATE statistics

Weighted and decimal percentiles through pctlpts and pctlpre, VARDEF=,
MU0= and the location and normality tests, in the OUTPUT OUT= shape of
proc_means(). Normality above 2000 observations is NA with one warning.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

## Task 5: Parity with the SAS oracle

**Files:**
- Create: `tests/testthat/fixtures-proc_univariate/scenarios.csv`, `tests/testthat/fixtures-proc_univariate/fixtures/*.csv` (16 files), `tests/testthat/fixtures-proc_univariate/out/*.csv` (25 files)
- Test: `tests/testthat/test-proc_univariate_parity.R` (create)

**Interfaces:**
- Consumes: `proc_univariate()`; `dev/oracle/proc_univariate/{scenarios.csv,fixtures/,out/}` from #118.
- Produces: one `test_that()` per scenario row, comparing every value SAS wrote.

- [ ] **Step 1: Write the parity test.** Create `tests/testthat/test-proc_univariate_parity.R`:

```r
library(testthat)
library(hvtiRutilities)

# Parity with SAS 9.4 M8 PROC UNIVARIATE (oracle run 2026-09-17). Each
# scenario's fixture is analysed with the scenario's WEIGHT, VARDEF=, MU0= and
# CLASS, requesting exactly the columns SAS wrote, and every value is compared.

# Kept out of fixtures/: that directory is the sas_triage() corpus, and a
# subdirectory there changes its fingerprint.
uni_dir <- function(...) test_path("fixtures-proc_univariate", ...)

read_fixture <- function(name) {
  utils::read.csv(uni_dir("fixtures", paste0(name, ".csv")),
                  na.strings = c("", "NA"),
                  colClasses = c(id = "integer", g = "character",
                                 x = "numeric", w = "numeric"))
}

read_sas <- function(name) {
  d <- utils::read.csv(uni_dir("out", paste0(name, ".csv")),
                       na.strings = c("", "NA"))
  names(d) <- tolower(names(d))
  d
}

pp_points <- c(pp_0 = 0, pp_2_5 = 2.5, pp_16 = 16, pp_50 = 50, pp_84 = 84,
               pp_97_5 = 97.5, pp_100 = 100)

# Shapiro-Wilk: R's shapiro.test() implements Royston (1995), SAS Royston
# (1992). W agrees to about 1e-8, so normal uses 1e-7 rather than 1e-10. The
# p-value magnifies the difference: 4.5e-7 relative was observed at n = 12
# (the basic fixture), so probn uses 1e-6.
tolerance_for <- function(col) {
  switch(col, normal = 1e-7, probn = 1e-6, 1e-10)
}

scenarios <- utils::read.csv(uni_dir("scenarios.csv"))

for (i in seq_len(nrow(scenarios))) {
  sc <- scenarios[i, ]
  test_that(paste("proc_univariate matches SAS:", sc$scenario), {
    dta <- read_fixture(sc$fixture)
    sas <- read_sas(sc$scenario)
    class_col <- if (sc$class == 1) "g" else NULL
    cols <- setdiff(names(sas), class_col)
    pp_cols <- cols[startsWith(cols, "pp_")]
    kw <- setdiff(cols, pp_cols)
    expect_setequal(pp_cols, names(pp_points))

    run <- function() {
      proc_univariate(dta, vars = "x", class = class_col, stats = kw,
                      weights = if (sc$weight == 1) "w" else NULL,
                      pctlpts = unname(pp_points[pp_cols]),
                      pctlpre = "pp_", mu0 = sc$mu0,
                      vardef = tolower(sc$vardef))
    }
    if (sc$scenario == "n2001") {
      expect_warning(res <- run(), "Kolmogorov D")
      # Deliberate divergence: SAS writes a Kolmogorov D statistic above 2000
      # observations; proc_univariate() returns NA.
      sas$normal <- NA_real_
      sas$probn <- NA_real_
    } else {
      expect_no_warning(res <- run())
    }

    expect_equal(nrow(res), nrow(sas))
    if (!is.null(class_col)) {
      expect_equal(res$g, sas$g)
    }
    for (col in cols) {
      r <- as.numeric(res[[col]])
      s <- as.numeric(sas[[col]])
      expect_identical(is.na(r), is.na(s),
                       label = paste(sc$scenario, col, "NA pattern"))
      ok <- !is.na(s)
      expect_equal(r[ok], s[ok], tolerance = tolerance_for(col),
                   label = paste(sc$scenario, col))
    }
  })
}
```

- [ ] **Step 2: Run it before the fixtures exist.**

```bash
Rscript -e 'devtools::test(filter = "proc_univariate_parity")'
```

  Expected: `[ FAIL 1 | WARN 1 | SKIP 0 | PASS 0 ]`, `cannot open the connection` on `scenarios.csv`.

- [ ] **Step 3: Copy the oracle fixtures and SAS output.** Only CSVs: `oracle.log` and `sas_version.txt` stay in `dev/`.

```bash
src=dev/oracle/proc_univariate
dst=tests/testthat/fixtures-proc_univariate
mkdir -p "$dst/fixtures" "$dst/out"
cp "$src"/scenarios.csv "$dst"/
cp "$src"/fixtures/*.csv "$dst"/fixtures/
cp "$src"/out/*.csv "$dst"/out/
ls "$dst"/fixtures | wc -l   # 16
ls "$dst"/out | wc -l        # 25
```

- [ ] **Step 4: Run parity and the full suite.**

```bash
Rscript -e 'devtools::test(filter = "proc_univariate_parity")'
Rscript -e 'devtools::test()'
```

  Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 2126 ]` (25 scenarios, 1025 columns, including the two optional ones); `[ FAIL 0 | WARN 7 | SKIP 0 | PASS 4437 ]` (4444 expectations). If `test-collision_report_provenance.R` fails, the fixtures landed under `tests/testthat/fixtures/`; move them.

- [ ] **Commit.**

```bash
git add tests/testthat/test-proc_univariate_parity.R \
  tests/testthat/fixtures-proc_univariate
git commit -F - <<'EOF'
test: check proc_univariate() against SAS 9.4 PROC UNIVARIATE output

Every value of the 25 oracle scenarios, at 1e-10 relative; normal at 1e-7
and probn at 1e-6 because R and SAS implement different revisions of
Royston's Shapiro-Wilk algorithm.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

## Task 6: Vignette and NEWS

**Files:**
- Modify: `vignettes/sas-procedures.qmd`
- Modify: `NEWS.md`

**Interfaces:**
- Consumes: `proc_univariate()`, `proc_means()`, `generate_survival_data()`.
- Produces: documentation only.

- [ ] **Step 1: Check the vignette renders before editing.** Prose has no unit test; the check is that the vignette renders and its new chunks run. Install the branch into a scratch library so the vignette loads this version:

```bash
out=$(mktemp -d); lib=$(mktemp -d)
R CMD INSTALL --no-docs --library="$lib" . > /dev/null 2>&1
R_LIBS="$lib" quarto render vignettes/sas-procedures.qmd \
  --output-dir "$out" > /dev/null 2>&1 && ls "$out"
rm -rf "$out" "$lib" vignettes/.gitignore
```

  Expected: `sas-procedures.html` and `sas-procedures_files` listed. Quarto may leave an untracked `vignettes/.gitignore`; delete it rather than commit it.

- [ ] **Step 2: Edit the vignette.** Apply to `vignettes/sas-procedures.qmd`:

  Replace 1 in `vignettes/sas-procedures.qmd`:

````markdown
title: "PROC CONTENTS, PROC MEANS and PROC FREQ in R"
````

  with:

````markdown
title: "PROC CONTENTS, MEANS, FREQ and UNIVARIATE in R"
````

  Replace 2 in `vignettes/sas-procedures.qmd`:

````markdown
  %\VignetteIndexEntry{PROC CONTENTS, PROC MEANS and PROC FREQ in R}
````

  with:

````markdown
  %\VignetteIndexEntry{PROC CONTENTS, MEANS, FREQ and UNIVARIATE in R}
````

  Replace 3 in `vignettes/sas-procedures.qmd`:

````markdown
## Three Procedures You Already Run
````

  with:

````markdown
## Four Procedures You Already Run
````

  Replace 4 in `vignettes/sas-procedures.qmd`:

````markdown
trust the file enough to analyse it. `proc_contents()`, `proc_means()` and
`proc_freq()` are those three habits, kept intact in R.
````

  with:

````markdown
trust the file enough to analyse it. `proc_contents()`, `proc_means()` and
`proc_freq()` are those three habits, kept intact in R.

The fourth comes a little later. When a summary needs weights, a percentile
such as the 2.5th, or a test against a null value, you reach for
`PROC UNIVARIATE`, and `proc_univariate()` gives you its output data set.
````

  Replace 5 in `vignettes/sas-procedures.qmd`:

````markdown
## Did the Extract Change? `compare_datasets()`
````

  with:

````markdown
## Weighted Percentiles and Tests: `proc_univariate()`

Most `PROC UNIVARIATE` steps in our SAS programs are not after the printed
report. They write an `OUTPUT` data set with percentiles that `PROC MEANS`
cannot give: weighted ones, and decimal points such as the 2.5th and 97.5th
for a bootstrap interval.

```sas
proc univariate data=cohort noprint;
  var age;
  weight wt;
  output out=pct pctlpts=2.5 16 50 84 97.5 pctlpre=p_;
run;
```

In R, `pctlpts` and `pctlpre` are arguments, and each point becomes a column
named the way SAS names it, with the decimal point turned into an underscore:

```{r univ-pctl}
wdta <- dta
wdta$wt <- ifelse(wdta$sex == "Female", 2, 1)

proc_univariate(wdta, vars = "age", stats = c("n", "sumwgt"),
                weights = "wt", pctlpts = c(2.5, 16, 50, 84, 97.5),
                pctlpre = "p_")
```

### Weighted Quantiles Follow a Different Rule

With `weights`, `proc_univariate()` weights `median`, `q1`, `q3`, `qrange`,
`pNN` and every `pctlpts` column. `proc_means()` does not, because
`PROC MEANS` does not. The same call can therefore give two medians:

```{r univ-weighted}
w4 <- data.frame(x = c(1, 2, 3, 4), wt = c(1, 3, 1, 1))

proc_means(w4, vars = "x", stats = "median", weights = "wt")

proc_univariate(w4, vars = "x", stats = "median", weights = "wt")
```

The weighted rule is not `QNTLDEF=5` with weights added. SAS sorts the values,
accumulates the weights, and takes the first value whose running weight passes
the target, here half of the total weight of 6. The running weights are 1, 4,
5 and 6, so the median is 2. When a running weight lands exactly on the target,
SAS averages that value and the next one. `PCTLDEF=` has no effect under
`WEIGHT`, and `proc_univariate()` has no argument for it.

### `VARDEF` Changes More Than the Variance

`vardef` is SAS `VARDEF=`, the divisor of the variance: `"df"` for the
number of observations minus one, the default; `"n"` for the number of
observations; `"wdf"` for the sum of the weights minus one; and `"weight"` for
the sum of the weights. Several of our weighted steps use `VARDEF=WDF`. It
changes `var`, `std` and `cv`, and it also changes what SAS is willing to
compute. `t`, `probt` and `stdmean` are missing unless the divisor
is `DF`, and `skewness` and `kurtosis` are missing under `WDF` and `WEIGHT`.
`proc_univariate()` returns `NA` in the same places:

```{r univ-vardef}
proc_univariate(wdta, vars = "age", weights = "wt",
                stats = c("std", "stdmean", "skewness"), vardef = "wdf")

proc_univariate(wdta, vars = "age", weights = "wt",
                stats = c("std", "stdmean", "skewness"))
```

Under weights, `stdmean` divides the standard deviation by the square root of
the sum of the weights, not of the number of observations.

### Tests for Location and Normality

`mu0` is SAS `MU0=`, the null value for the three location tests:

```{r univ-tests}
proc_univariate(dta, vars = "bmi", mu0 = 25,
                stats = c("mean", "t", "probt", "msign", "probm",
                          "signrank", "probs", "normal", "probn"))
```

`t` is Student's t, `msign` the sign test and `signrank` the Wilcoxon signed
rank test, with an exact p-value when 20 or fewer values differ from `mu0`.
`normal` is the Shapiro-Wilk statistic.

Three limits come from SAS. Under `weights`, SAS computes only the t test, so
the sign, signed rank and normality columns are `NA`. Above 2000 observations
SAS replaces Shapiro-Wilk with a Kolmogorov D test, which is not ported, so
`normal` and `probn` are `NA` there and the call warns once. And R's
`shapiro.test()` implements a later revision of the algorithm than SAS does:
`normal` agrees with SAS to about eight decimal places, and `probn` slightly
less closely.

## Did the Extract Change? `compare_datasets()`
````

  Replace 6 in `vignettes/sas-procedures.qmd`:

````markdown
| `PROC FREQ` tests (`CHISQ`, `FISHER`, ...) | Available | Not ported |
````

  with:

````markdown
| `PROC FREQ` tests (`CHISQ`, `FISHER`, ...) | Available | Not ported |
| `PROC UNIVARIATE` quantiles under `WEIGHT` | Weighted, `PCTLDEF=` ignored | Weighted, same rule |
| `PROC UNIVARIATE` `PCTLDEF=` | 1 to 5 | 5 only |
| `PROC UNIVARIATE` non-positive weights | Negative treated as zero, observation still counted | Error |
| `PROC UNIVARIATE` normality above 2000 observations | Kolmogorov D | `NA`, with a warning |
| `PROC UNIVARIATE` Shapiro-Wilk | Royston (1992) | Royston (1995), through `shapiro.test()` |
| `PROC UNIVARIATE` plots, printed tables, confidence limits, robust estimators | Available | Not ported |
````

  Replace 7 in `vignettes/sas-procedures.qmd`:

````markdown
- [ ] Read `attr(, "frequency_missing")` when you leave `missing = FALSE`.
````

  with:

````markdown
- [ ] Read `attr(, "frequency_missing")` when you leave `missing = FALSE`.
- [ ] Use `proc_univariate()`, not `proc_means()`, for percentiles from a
      weighted step; `proc_means()` quantiles ignore the weights.
- [ ] Carry `VARDEF=` across as `vardef`, and expect `NA` where SAS leaves a
      statistic missing under it.
- [ ] Read an `NA` in `normal` above 2000 observations as "not computed", not
      as a test result.
````

  Replace 8 in `vignettes/sas-procedures.qmd`:

````markdown
- `?proc_contents`, `?proc_means`, `?proc_freq`, `?compare_datasets`
````

  with:

````markdown
- `?proc_contents`, `?proc_means`, `?proc_freq`, `?proc_univariate`,
  `?compare_datasets`
````

- [ ] **Step 3: Add the NEWS entry.** Apply to `NEWS.md` (the heading already exists after #119; the entry goes first under `## New features`):

  Replace 1 in `NEWS.md`:

```markdown
# hvtiRutilities (unreleased)

## New features
```

  with:

```markdown
# hvtiRutilities (unreleased)

## New features

* **`proc_univariate()` ports the SAS `PROC UNIVARIATE` output statistics.**
  Weighted and decimal percentiles (`pctlpts`, `pctlpre`), `vardef`, `mu0`,
  `stdmean`, and the tests for location (`t`, `msign`, `signrank`) and
  normality (Shapiro-Wilk), checked against SAS 9.4 output. With `weights`
  the quantiles are weighted, unlike `proc_means()`. Statistics SAS leaves
  missing are `NA`. Normality above 2000 observations is `NA` with a warning,
  because SAS switches to a Kolmogorov D test there, which is not ported.
  Non-positive weights are an error. `proc_means()` now shares its statistic
  engine with `proc_univariate()`; its results are unchanged.
```

- [ ] **Step 4: Render and check.**

```bash
out=$(mktemp -d); lib=$(mktemp -d)
R CMD INSTALL --no-docs --library="$lib" . > /dev/null 2>&1
R_LIBS="$lib" quarto render vignettes/sas-procedures.qmd \
  --output-dir "$out" > /dev/null 2>&1 && ls "$out"
grep -c "p_97_5" "$out"/sas-procedures.html
git diff -U0 main -- vignettes/sas-procedures.qmd NEWS.md \
  | grep "^+" | LC_ALL=C grep -c $'\xe2\x80\x94'
rm -rf "$out" "$lib" vignettes/.gitignore
```

  Expected: the directory listing, then `1` (the `p_97_5` column appears in the rendered page), then `0` (no em-dash among the added lines). In the page, the `univ-weighted` chunk prints a median of `2.5` from `proc_means()` and `2` from `proc_univariate()`, and the `univ-vardef` chunk prints `NA` for `stdmean` and `skewness` under `vardef = "wdf"`.

- [ ] **Commit.**

```bash
git add vignettes/sas-procedures.qmd \
  NEWS.md
git commit -F - <<'EOF'
docs: document proc_univariate() in the SAS procedures vignette

A section on weighted and decimal percentiles, VARDEF= and the tests, the
differences from SAS, checklist items, and a NEWS entry.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

## Task 7: Full verification and the pull request

**Files:** none changed, unless a check below fails (fix, then re-run the whole task).

**Interfaces:** consumes the branch as a whole.

- [ ] **Step 1: Full test suite.**

```bash
Rscript -e 'devtools::test()'
```

  Expected: `[ FAIL 0 | WARN 7 | SKIP 0 | PASS 4437 ]` (4444 expectations; the 7 warnings are pre-existing). If `main` had a different baseline in Task 1, expect that baseline plus 2321.

- [ ] **Step 2: Docs are current** (the `docs-current` CI job).

```bash
Rscript -e 'roxygen2::roxygenise()'
git diff --exit-code man/ NAMESPACE DESCRIPTION && echo docs-current
```

  Expected: `docs-current`, exit status 0.

- [ ] **Step 3: No new lints.** Install the branch into a scratch library so `object_usage_linter` sees the new functions, then compare with `main`.

```bash
lib=$(mktemp -d)
R CMD INSTALL --no-docs --library="$lib" . > /dev/null
R_LIBS="$lib" Rscript -e '
fs <- c("R/proc_means.R", "R/stat_engine.R", "R/proc_univariate.R",
        "tests/testthat/test-stat_engine.R",
        list.files("tests/testthat", "^test-proc_univariate",
                   full.names = TRUE))
for (f in fs) cat(f, length(lintr::lint(f)), "\n")'
git show main:R/proc_means.R > "$lib/main_proc_means.R"
R_LIBS="$lib" Rscript -e \
  "cat('main', length(lintr::lint('$lib/main_proc_means.R')), '\n')"
rm -rf "$lib"
```

  Expected: `R/proc_means.R 2`, `R/stat_engine.R 1`, every other file `0`, and `main 4`. The remaining lints pre-date this PR: two long lines in `proc_means.R` and the `object_name_linter` hit on `.STATS`, which moved.

- [ ] **Step 4: `R CMD check --as-cran` with the manual, from a clean export.**

```bash
chk=$(mktemp -d)
git archive --format=tar HEAD | tar -x -C "$chk"
(cd "$chk" && R CMD build . && R CMD check --as-cran hvtiRutilities_*.tar.gz)
grep -E "^Status|NOTE|WARNING|ERROR" "$chk"/hvtiRutilities.Rcheck/00check.log
```

  Expected: `Status: 1 NOTE`, the environmental `New submission` NOTE only (measured `Status: OK` with `_R_CHECK_CRAN_INCOMING_REMOTE_=false`, which suppresses that NOTE). `checking PDF version of manual ... OK` and `checking re-building of vignette outputs ... OK` must both appear. Read the per-step `[Ns]` timings: the whole check stays well under 10 minutes.

- [ ] **Step 5: pkgdown index.**

```bash
Rscript -e 'pkgdown::check_pkgdown()'
```

  Expected: `No problems found.`

- [ ] **Step 6: Push and open the pull request.**

```bash
git push -u origin feat/proc-univariate
gh pr create --base main --head feat/proc-univariate \
  --title "feat: add proc_univariate(), a port of SAS PROC UNIVARIATE statistics" \
  --body-file - <<'EOF'
## Summary

Adds `proc_univariate()`, a port of the SAS `PROC UNIVARIATE` `OUTPUT OUT=`
statistics, per `dev/specs/2026-09-17-proc-univariate-design.md`.

- Weighted and decimal percentiles (`pctlpts`, `pctlpre`), `vardef`, `mu0`,
  `stdmean`, the location tests (`t`, `msign`, `signrank`) and Shapiro-Wilk.
- Statistics SAS leaves missing are `NA`; normality above 2000 observations is
  `NA` with one warning (SAS's Kolmogorov D test is not ported).
- The statistic registry moved to `R/stat_engine.R` (its own commit, a pure
  move) and gained a per-procedure context. `proc_means()` is a wrapper over
  the shared driver; its tests pass unchanged.
- A class level whose every weight is missing keeps its row in `proc_means()`
  (#119) and has none in `proc_univariate()`, as in SAS.

## Verification

- Parity with SAS 9.4 M8: 25/25 oracle scenarios, every column, at 1e-10
  relative (`normal` 1e-7, `probn` 1e-6: R and SAS implement different
  revisions of Royston's Shapiro-Wilk algorithm).
- `devtools::test()`: FAIL 0, WARN 7 (pre-existing).
- `roxygenise()` leaves `man/`, `NAMESPACE`, `DESCRIPTION` unchanged.
- No new lints on touched files.
- `R CMD check --as-cran` with the manual: only the New submission NOTE.
- `pkgdown::check_pkgdown()`: no problems.

Test fixtures are in `tests/testthat/fixtures-proc_univariate/` rather than
`fixtures/`, which is the `sas_triage()` corpus.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
```

  Expected: the PR URL. The `protect main` ruleset needs one approving review from someone other than the author, and Copilot reviews once on open without re-reviewing pushes; say in the PR what changed after its review instead of waiting for a second pass. Do not merge.

