# `use_value_labels` Implementation Plan (design note §7, option B)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Date:** 2026-09-02
**Package:** `hvtiRutilities`
**Spec:** `dev/specs/2026-09-02-label-length-and-fallback-design.md`, §7.3 option **B**,
decided by John Ehrlinger on 2026-09-02. **Read §2.2, §7.1, §7.2 and §7.3 before Task 1.**
**Reads with:** `dev/specs/2026-09-02-ordinal-representation-design.md` §7.1 — the two notes
share the rule this plan implements.

**Goal:** Give `r_data_types()` a `use_value_labels` argument, default `FALSE` with a
one-time warning, that converts a `haven_labelled` column through its own value labels
instead of through its numeric codes — and make every column's conversion rule readable
afterwards from a per-column report.

**Architecture:** The four sequential `dplyr::across()` passes in `r_data_types()` become
one per-column dispatcher, `.convert_column()`, that returns both the converted column
**and** the rule that produced it. That is what makes the report structurally unable to
disagree with the data: there is one decision site, not a conversion chain plus a
predicate function that describes it. `use_value_labels` then becomes one branch at the
top of that dispatcher. Four tasks: refactor (no behaviour change bar one crash fix),
report, argument, then documentation and the PR.

**Tech Stack:** R (>= 4.1.0), `labelled` (already in `Imports`), `haven` (already in
`Imports`), `dplyr`, roxygen2, testthat edition 3, `withr` for test-local state.

---

## Global Constraints

- **Roxygen here is Rd markup, not markdown.** `DESCRIPTION` has no
  `Roxygen: list(markdown = TRUE)`. Use `\code{}`, `\strong{}`, `\emph{}`, `\itemize{}`,
  `\link{}`. Backticks and `*` bullets land literally in the `.Rd` and render as garbage.
- **Every new export goes in `_pkgdown.yml`.** The `reference:` index is explicit and
  pkgdown **errors** — not warns — on a topic missing from it. This plan adds exactly one
  export, `type_conversion_report()`.
- **Lines are 80 characters.** `lintr` enforces it. The package is not lint-clean overall,
  so green lint is not the bar — do not *add* lints.
- **Do not bump `Version:` in this PR.** A pull request lands without touching
  `DESCRIPTION`. Its entry goes under the `# hvtiRutilities (unreleased)` heading in
  `NEWS.md`, which is **already present** at line 1 — add to it, do not create a second one
  and do not rename it. A separate commit, at most once a day, renames the heading and
  updates `DESCRIPTION`. See `.claude/house-style.md`.
- **Never push to `main`.** Branch is `feat/use-value-labels`. `main` is protected by the
  `protect main` ruleset: PR-only, and **one approving review the author cannot supply**.
  Plan for the wait; do not force-push around a rejection.
- **`r_data_types()` is exported, re-exported, used in three vignettes and by
  `read_clinical_data()`.** `AGENTS.md`: *"a breaking change here is a breaking change
  everywhere."* Every task below is additive or behaviour-preserving, with exactly one
  stated exception (Task 1, the crash).
- **`devtools::document()` must be run and `man/`, `NAMESPACE`, `DESCRIPTION` committed
  with the source change.** The `lint.yaml` **docs-current** job regenerates and runs
  `git diff --exit-code`; a forgotten `document()` fails the PR.
- **Definition of done is `devtools::test()` green and `devtools::check()` 0/0/0.** It
  reached 0/0/0 on 2026-08-20. Do not let a NOTE creep back.
- The existing 575 lines across `tests/testthat/test-r_data_types.R` and
  `test-r_data_types-extended.R` are the equivalence harness for Task 1. They must pass
  **unmodified** except for the two assertions Task 1 names explicitly.

---

## Scope

**In:** everything §7.3 lists under *"What B commits to"*, plus the reporting requirement
that §7.3 attaches to it (*"B is not a licence to skip the report"*).

**Out, and deliberately so:**

| item | where it belongs |
|---|---|
| `catalog_file` on `read_clinical_data()` (§5) | its own PR. Additive, independent, and does not gate this one — B is testable from a `haven::labelled()` vector constructed in a test, with no `.sas7bcat` anywhere. |
| Option **C**, the declaration-first converter | a later plan. This one leaves the `level_source` vocabulary open for C's `"declaration"` value but does not add it. |
| `label_max`, the fallback test, the prefix stripper (§4, §2.1, §6) | separate plans against the same design note. |
| The enumerated-levels declaration (§8) | undecided; blocks C, not B. |
| Flipping the default to `TRUE` | a later release, by the maintainer's decision. This PR ships `FALSE`. |

---

## What the code does today, verified by running it on 2026-09-02

Two facts. The first is the one §2.2 records. The second is not in the design note, was
found while writing this plan, and changes what Task 1 has to do.

**1. A multi-level labelled column silently loses its level text.**

```r
x <- haven::labelled(c(1, 2, 1, 3),
                     labels = c(Home = 1, Rehab = 2, SNF = 3),
                     label  = "Discharge disposition")
str(r_data_types(data.frame(disp = x)))
#> $ disp: Factor w/ 3 levels "1","2","3": 1 2 1 3
#>   ..- attr(*, "label")= chr "Discharge disposition"
```

`Home`, `Rehab`, `SNF` are gone. `R/r_data_types.R:109` tests
`n_distinct(x) < factor_size & !is.factor(x) & is.numeric(x)`; a `haven_labelled` vector
is `is.numeric()` and is not a factor, so `factor()` sees only the codes.

**2. 🔴 A two-valued labelled column does not lose anything — it errors.**

```r
b <- haven::labelled(c(0, 1, 1, 0), labels = c(No = 0, Yes = 1),
                     label = "Prior stroke")
r_data_types(data.frame(flag = b))
#> Error in `as.logical()`:
#> ! Can't convert `x` <labelled<double>> to <logical>.
```

The binary branch at `R/r_data_types.R:101` calls `as.logical()`, and `vctrs` has no cast
from `haven_labelled` to logical. This branch runs **before** the factor branch, so it is
reached first for any two-valued column.

The reach is not hypothetical. `read_clinical_data()` does
`as.data.frame(haven::read_sas(file))`, which preserves `haven_labelled` columns, then
`r_data_types(data, ...)` when `convert_types = TRUE`. **A SAS file with one formatted
yes/no variable crashes `read_clinical_data(convert_types = TRUE)` today.** Only
`convert_types` defaulting to `FALSE` since 1.0.x keeps this from being a daily failure.

**Consequence for the design.** `use_value_labels = FALSE` cannot mean "leave the code
path alone", because the code path is a crash. Task 1 defines it: drop the value labels
explicitly, then convert the plain vector — which is what the multi-level branch already
does by accident, made deliberate and made total.

**Adjacent, observed, and NOT fixed here.** `r_data_types()` reads labels with
`null_action = "fill"` (line 83) and writes them back at line 130, so an unlabelled column
comes out with its **own name stamped into its `label` attribute**:

```r
attr(r_data_types(data.frame(hgb_bs = c(9.1, 10.2, 11.3, 12.4, 13.5)))$hgb_bs, "label")
#> [1] "hgb_bs"
```

That is the display-seam fill of §2.1 leaking into storage, and it is the same shape of
defect as §4.1. It is out of scope: fixing it changes what every existing caller gets back
and it needs its own decision. Raise it separately; do not fold it in.

---

## File Structure

| file | responsibility |
|---|---|
| `R/r_data_types.R` (modify) | `r_data_types()`: validation, `skip_vars`, the `use_value_labels` argument and its one-time warning, label restore. Gains the internal `.convert_column()` — the single decision site for every column. |
| `R/type_report.R` (create) | `.type_report()`, the row builder, and the exported accessor `type_conversion_report()`. Separate file: the report is a different concern from the conversion and has its own tests. |
| `tests/testthat/test-r_data_types-value-labels.R` (create) | everything `haven_labelled`: the crash, the discard, `to_factor()`, branch precedence, the warning. |
| `tests/testthat/test-type-report.R` (create) | the report's columns, its rule vocabulary, `skip_vars`, the accessor's error. |
| `tests/testthat/test-r_data_types.R` (untouched) | the equivalence harness. |
| `tests/testthat/test-r_data_types-extended.R` (untouched) | the equivalence harness. |
| `tests/testthat/test-read_clinical_data.R` (modify, Task 3) | two `expect_silent()` assertions that a new warning would make order-dependent. |
| `_pkgdown.yml` (modify) | `type_conversion_report` under **Data Type Conversion**. |
| `NEWS.md` (modify) | entries under the existing `# hvtiRutilities (unreleased)`. |
| `man/`, `NAMESPACE` (regenerate) | `devtools::document()` output. Never hand-edited. |

---

# Task 1: One decision site per column

Replace the four `dplyr::across()` passes with a per-column dispatcher. **No behaviour
change except the crash**, which becomes a defined conversion. The existing 575 lines of
tests are the gate.

**Files:**
- Modify: `R/r_data_types.R:95-119`
- Create: `tests/testthat/test-r_data_types-value-labels.R`

**Interfaces:**
- Consumes: nothing.
- Produces: internal `.convert_column(x, factor_size, binary_factor, use_value_labels)`
  → a `list` with four elements, always all four:
  `value` (the converted vector), `rule` (a single string from the vocabulary below),
  `level_source` (`"value labels"`, `"inference"`, or `NA_character_`),
  `storage_in` (`class(x)[1]` **as received**, before any conversion).
  Task 2 consumes exactly these names.
- Rule vocabulary, fixed here and used unchanged by Tasks 2 and 3:
  `"value_labels"`, `"binary_logical"`, `"binary_factor"`, `"character_factor"`,
  `"n_distinct_factor"`, `"unchanged"`. Task 2 adds one more, `"skipped"`, which
  `.convert_column()` never returns because skipped columns never reach it.

- [ ] **Step 1: Create the branch**

```bash
cd /path/to/hvtiRutilities   # this plan's commands are relative to the repo root
git checkout main && git pull
git checkout -b feat/use-value-labels
```

- [ ] **Step 2: Write the failing test for the crash**

Create `tests/testthat/test-r_data_types-value-labels.R` with exactly this content:

```r
# Value-label handling in r_data_types(). See
# dev/specs/2026-09-02-label-length-and-fallback-design.md sections 2.2 and 7.3.

test_that("a two-valued haven_labelled column converts instead of erroring", {
  # as.logical() has no vctrs cast from haven_labelled, so the binary branch
  # used to abort. Dropping the value labels first makes the default path a
  # conversion rather than a crash.
  b <- haven::labelled(c(0, 1, 1, 0), labels = c(No = 0, Yes = 1),
                       label = "Prior stroke")

  out <- r_data_types(data.frame(flag = b), use_value_labels = FALSE)

  expect_type(out$flag, "logical")
  expect_equal(out$flag, c(FALSE, TRUE, TRUE, FALSE))
  expect_equal(attr(out$flag, "label"), "Prior stroke")
})

test_that("a multi-level haven_labelled column keeps the codes as levels", {
  # The status quo of section 2.2, pinned deliberately: with use_value_labels
  # off, the level text is discarded and the numeric codes become the levels.
  x <- haven::labelled(c(1, 2, 1, 3), labels = c(Home = 1, Rehab = 2, SNF = 3),
                       label = "Discharge disposition")

  out <- r_data_types(data.frame(disp = x), use_value_labels = FALSE)

  expect_s3_class(out$disp, "factor")
  expect_equal(levels(out$disp), c("1", "2", "3"))
  expect_equal(attr(out$disp, "label"), "Discharge disposition")
})
```

Note both tests already pass `use_value_labels = FALSE`, an argument Task 3 adds. That is
deliberate: Task 1 adds the parameter to the **internal** dispatcher and to
`r_data_types()`'s formals with no warning attached, so these tests run now; Task 3 adds
the warning and the `TRUE` branch. Splitting it this way keeps Task 1 a refactor a
reviewer can approve on the existing suite alone.

- [ ] **Step 3: Run it and confirm both fail**

```bash
Rscript -e 'devtools::test(filter = "r_data_types-value-labels")'
```

Expected: two failures. The first with
`Can't convert 'x' <labelled<double>> to <logical>`; the second with
`unused argument (use_value_labels = FALSE)`.

- [ ] **Step 4: Replace the conversion chain**

In `R/r_data_types.R`, add above `r_data_types()`:

```r
# The character values that stand in for a missing observation in exported
# clinical data. Held here so the dispatcher and its tests agree on the list.
.na_strings <- c("NA", "na", "Na", "nA")

# Convert one column and say why.
#
# This is the only place a conversion decision is made. Returning the rule
# alongside the value is what keeps type_conversion_report() from being a
# second, drifting description of what the conversion does -- a report derived
# from a separate predicate can disagree with the data it claims to describe,
# and the disagreement is invisible.
#
# Branch order reproduces the four dplyr::across() passes this replaced:
# NA strings, binary-to-logical, character-to-factor, n_distinct-to-factor,
# then the optional logical-to-factor. The value-label branch is new and runs
# ahead of all of them, because a declared type beats an inferred one.
.convert_column <- function(x, factor_size, binary_factor, use_value_labels) {
  storage_in <- class(x)[1]
  out <- function(value, rule, level_source = NA_character_) {
    list(value = value, rule = rule, level_source = level_source,
         storage_in = storage_in)
  }

  # Dates and times are never altered by type conversion.
  if (inherits(x, c("Date", "POSIXct", "POSIXlt"))) {
    return(out(x, "unchanged"))
  }

  has_val_labels <- inherits(x, "haven_labelled") &&
    length(labelled::val_labels(x)) > 0L

  if (has_val_labels && use_value_labels) {
    return(out(labelled::to_factor(x), "value_labels", "value labels"))
  }

  # Value labels are not being used. Drop them rather than carrying them into
  # the numeric branches: as.logical() has no vctrs cast from haven_labelled
  # and aborts, which made a two-valued formatted SAS variable an error.
  if (inherits(x, "haven_labelled")) {
    x <- haven::zap_labels(x)
  }

  if (is.character(x)) {
    for (s in .na_strings) {
      x <- dplyr::na_if(x, s)
    }
  }

  n <- dplyr::n_distinct(x, na.rm = TRUE)

  if (!is.factor(x) && !is.character(x) && n == 2L) {
    was_logical <- is.logical(x)
    x <- as.logical(x)
    if (binary_factor) {
      return(out(factor(x, exclude = NA), "binary_factor", "inference"))
    }
    return(out(x, if (was_logical) "unchanged" else "binary_logical"))
  }

  if (is.character(x)) {
    return(out(factor(x, exclude = NA), "character_factor", "inference"))
  }

  if (n < factor_size && n > 2L && !is.factor(x) && is.numeric(x)) {
    return(out(factor(x, exclude = NA), "n_distinct_factor", "inference"))
  }

  # A column that was already logical and did not take the binary branch --
  # all-NA, or a single distinct value.
  if (binary_factor && is.logical(x)) {
    return(out(factor(x, exclude = NA), "binary_factor", "inference"))
  }

  out(x, "unchanged")
}
```

Add `use_value_labels = FALSE` to the signature (no warning yet — Task 3):

```r
r_data_types <- function(dataset,
                         factor_size = 10,
                         skip_vars = NULL,
                         binary_factor = FALSE,
                         use_value_labels = FALSE) {
```

Then replace the whole conversion block — the four `dplyr::mutate(dplyr::across(...))`
calls and the `if (binary_factor)` block, `R/r_data_types.R:95-119` — with:

```r
  # Convert Variables to new types
  converted <- lapply(new_data, .convert_column,
                      factor_size      = factor_size,
                      binary_factor    = binary_factor,
                      use_value_labels = use_value_labels)
  # `[]<-` rather than a rebuild: it preserves the tibble/data.table class of
  # the input, which the contract promises and the extended tests assert.
  new_data[] <- lapply(converted, `[[`, "value")
```

Leave everything else in the function untouched: the validation block, the `skip_vars`
split and restore, `keep_label`, and the `labelled::var_label(new_data) <- keep_label`
line at the end.

- [ ] **Step 5: Run the new tests**

```bash
Rscript -e 'devtools::test(filter = "r_data_types-value-labels")'
```

Expected: PASS, 6 assertions.

- [ ] **Step 6: Run the equivalence harness — this is the real gate**

```bash
Rscript -e 'devtools::test(filter = "r_data_types")'
```

Expected: PASS. Every assertion in `test-r_data_types.R` and
`test-r_data_types-extended.R` passes **unmodified**. If any fails, the refactor is not
equivalent — fix `.convert_column()`, do not edit the test. The ones most likely to catch
a mistake, and what they are protecting:

| test file:line | protects |
|---|---|
| `-extended.R:85` | an **ordered** factor input stays ordered — `.convert_column()` must fall through to `"unchanged"` for any factor |
| `-extended.R:55,65,75` | `Date` and `POSIXct` untouched — the early return |
| `-extended.R:223` | `binary_factor = TRUE` reaches columns that were already logical |
| `-extended.R:303` | a tibble comes back a tibble — the `[]<-` line |
| `-extended.R:10-12,172` | a zero-column and a zero-row frame survive `lapply()` |
| `-extended.R:147` | `skip_vars` restores original column order |
| `-extended.R:199` | `"NA"`/`"na"`/`"Na"`/`"nA"` all become `NA` before the factor branch |

- [ ] **Step 7: Run the full suite and lint the changed file**

```bash
Rscript -e 'devtools::test()'
Rscript -e 'print(lintr::lint("R/r_data_types.R"))'
```

Expected: tests PASS. Lint may report pre-existing findings in the file — compare against
`git stash`ed output if unsure, and add none.

- [ ] **Step 8: Commit**

```bash
git add R/r_data_types.R tests/testthat/test-r_data_types-value-labels.R
git commit -m "$(cat <<'EOF'
refactor: one decision site per column in r_data_types()

The four sequential dplyr::across() passes become a per-column dispatcher,
.convert_column(), which returns the converted column and the rule that
produced it. The rule is what the per-column report will be built from; a
report derived from a separate predicate can drift from the conversion it
describes, and the drift is invisible.

Behaviour is unchanged except for one crash. as.logical() has no vctrs cast
from haven_labelled, so the binary branch aborted on any two-valued formatted
SAS variable -- which is to say on read_clinical_data(convert_types = TRUE)
against most SAS exports. The labels are now dropped explicitly before the
numeric branches, making that path a conversion rather than an error.

The existing 575 lines of r_data_types tests pass unmodified and are the
equivalence gate for the refactor.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

# Task 2: The per-column report

§7.3: *"the converter must report. One row per column: the rule that fired, the source of
the levels, and what it produced. Without that, §7.1's second clause is unimplemented and
this note has fixed the symptom again."*

**Files:**
- Create: `R/type_report.R`
- Modify: `R/r_data_types.R`
- Create: `tests/testthat/test-type-report.R`
- Modify: `_pkgdown.yml`

**Interfaces:**
- Consumes: `.convert_column()`'s `list(value, rule, level_source, storage_in)` from Task 1.
- Produces:
  - internal `.type_report(converted, dataset, skip_vars)` → `data.frame`, one row per
    column of `dataset`, in `names(dataset)` order, columns
    `variable` (chr), `storage_in` (chr), `rule` (chr), `level_source` (chr),
    `n_levels` (int), `storage_out` (chr).
  - exported `type_conversion_report(x)` → that data frame, read from the
    `"hvti_type_conversion"` attribute of an `r_data_types()` result.
  - `r_data_types()` attaches that attribute to everything it returns, on both settings of
    `use_value_labels`. §7.3: *"an argument that silently changes which rule fires is the
    same defect in a new place"* — so the report is unconditional, not opt-in.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-type-report.R`:

```r
# The per-column conversion report. See
# dev/specs/2026-09-02-label-length-and-fallback-design.md section 7.3.

test_that("the report has one row per column, in column order", {
  dta <- data.frame(
    num  = c(1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5, 8.5, 9.5, 10.5, 11.5, 12.5),
    flag = c(0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1),
    chr  = letters[1:12],
    few  = c(1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3),
    stringsAsFactors = FALSE
  )

  rep <- type_conversion_report(r_data_types(dta, use_value_labels = FALSE))

  expect_s3_class(rep, "data.frame")
  expect_equal(rep$variable, c("num", "flag", "chr", "few"))
  expect_equal(names(rep), c("variable", "storage_in", "rule", "level_source",
                             "n_levels", "storage_out"))
})

test_that("each inference rule is named, and named as inference", {
  dta <- data.frame(
    num  = c(1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5, 8.5, 9.5, 10.5, 11.5, 12.5),
    flag = c(0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1),
    chr  = letters[1:12],
    few  = c(1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3),
    stringsAsFactors = FALSE
  )

  rep <- type_conversion_report(r_data_types(dta, use_value_labels = FALSE))

  expect_equal(rep$rule, c("unchanged", "binary_logical", "character_factor",
                           "n_distinct_factor"))
  expect_equal(rep$level_source,
               c(NA, NA, "inference", "inference"))
  expect_equal(rep$n_levels, c(NA_integer_, NA_integer_, 12L, 3L))
  expect_equal(rep$storage_out,
               c("numeric", "logical", "factor", "factor"))
  expect_equal(rep$storage_in,
               c("numeric", "numeric", "character", "numeric"))
})

test_that("a skipped column is reported as skipped, not as unchanged", {
  # The two are different claims. "unchanged" means every rule was tested and
  # none fired; "skipped" means no rule was tested. Collapsing them would make
  # skip_vars invisible in the record of what happened.
  dta <- data.frame(a = c(1, 2, 3, 1), b = c(0, 1, 0, 1))

  rep <- type_conversion_report(
    r_data_types(dta, skip_vars = "b", use_value_labels = FALSE)
  )

  expect_equal(rep$rule, c("n_distinct_factor", "skipped"))
  expect_equal(rep$storage_in, c("numeric", "numeric"))
  expect_equal(rep$storage_out, c("factor", "numeric"))
  expect_true(is.na(rep$level_source[2]))
})

test_that("the report is attached whether or not value labels are used", {
  dta <- data.frame(a = c(1, 2, 3, 1))

  expect_s3_class(type_conversion_report(
    r_data_types(dta, use_value_labels = FALSE)), "data.frame")
  expect_s3_class(type_conversion_report(
    r_data_types(dta, use_value_labels = TRUE)), "data.frame")
})

test_that("a zero-column frame yields a zero-row report with the same columns", {
  rep <- type_conversion_report(
    r_data_types(data.frame(), use_value_labels = FALSE)
  )

  expect_equal(nrow(rep), 0)
  expect_equal(names(rep), c("variable", "storage_in", "rule", "level_source",
                             "n_levels", "storage_out"))
})

test_that("the accessor says what went wrong rather than returning NULL", {
  expect_error(type_conversion_report(mtcars),
               "did not come from r_data_types")
})
```

- [ ] **Step 2: Run and confirm they fail**

```bash
Rscript -e 'devtools::test(filter = "type-report")'
```

Expected: all six fail with `could not find function "type_conversion_report"`.

- [ ] **Step 3: Create `R/type_report.R`**

```r
# Assemble the per-column record of what r_data_types() did.
#
# Built from the dispatcher's own return value, not from a second reading of
# the data, so a row cannot describe a rule other than the one that ran.
# Skipped columns never reach the dispatcher and are filled in here.
.type_report <- function(converted, dataset, skip_vars) {
  row <- function(variable, storage_in, rule, level_source, value) {
    data.frame(
      variable     = variable,
      storage_in   = storage_in,
      rule         = rule,
      level_source = level_source,
      n_levels     = if (is.factor(value)) {
        length(levels(value))
      } else {
        NA_integer_
      },
      storage_out  = class(value)[1],
      stringsAsFactors = FALSE
    )
  }

  rows <- lapply(names(dataset), function(v) {
    if (v %in% skip_vars) {
      col <- dataset[[v]]
      return(row(v, class(col)[1], "skipped", NA_character_, col))
    }
    r <- converted[[v]]
    row(v, r$storage_in, r$rule, r$level_source, r$value)
  })

  if (!length(rows)) {
    return(data.frame(variable = character(0), storage_in = character(0),
                      rule = character(0), level_source = character(0),
                      n_levels = integer(0), storage_out = character(0),
                      stringsAsFactors = FALSE))
  }

  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

#' Read the per-column type-conversion report
#'
#' @description
#' Returns the record \code{\link{r_data_types}} attaches to its result: one
#' row per column, naming the rule that fired and where the levels came from.
#'
#' @details
#' A column that became a factor because it was \emph{declared} one, and a
#' column that became a factor because it happened to have seven distinct
#' values, are otherwise the same object. This is how a caller tells them
#' apart.
#'
#' The columns are:
#' \itemize{
#'   \item \code{variable} -- the column name.
#'   \item \code{storage_in} -- its class as received, before conversion.
#'   \item \code{rule} -- one of \code{"value_labels"}, \code{"binary_logical"},
#'     \code{"binary_factor"}, \code{"character_factor"},
#'     \code{"n_distinct_factor"}, \code{"unchanged"} or \code{"skipped"}.
#'     \code{"unchanged"} means every rule was tested and none fired;
#'     \code{"skipped"} means the column was named in \code{skip_vars} and no
#'     rule was tested.
#'   \item \code{level_source} -- \code{"value labels"} where the levels came
#'     from the column's own value labels, \code{"inference"} where they came
#'     from counting distinct values, and \code{NA} where no levels were made.
#'   \item \code{n_levels} -- levels produced, or \code{NA} for a non-factor.
#'   \item \code{storage_out} -- the class of the returned column.
#' }
#'
#' The report is an attribute of the returned object. Operations that rebuild
#' a data frame -- most \pkg{dplyr} verbs among them -- drop it. Read it
#' directly from the \code{r_data_types()} result.
#'
#' @param x An object returned by \code{\link{r_data_types}}.
#'
#' @return A data frame with columns \code{variable}, \code{storage_in},
#'   \code{rule}, \code{level_source}, \code{n_levels} and \code{storage_out},
#'   one row per column of the converted dataset, in column order.
#'
#' @seealso \code{\link{r_data_types}}
#'
#' @export type_conversion_report
#'
#' @examples
#' converted <- r_data_types(datasets::mtcars, use_value_labels = FALSE)
#' type_conversion_report(converted)
type_conversion_report <- function(x) {
  report <- attr(x, "hvti_type_conversion", exact = TRUE)
  if (is.null(report)) {
    stop("No type-conversion report on this object: it did not come from ",
         "r_data_types(), or an intervening operation dropped its ",
         "attributes.", call. = FALSE)
  }
  report
}
```

- [ ] **Step 4: Attach the report in `r_data_types()`**

In `R/r_data_types.R`, immediately after the
`labelled::var_label(new_data) <- keep_label` line, replace the bare `new_data` return
with:

```r
  labelled::var_label(new_data) <- keep_label
  attr(new_data, "hvti_type_conversion") <-
    .type_report(converted, dataset, skip_vars)
  new_data
```

`skip_vars` is `NULL` when not supplied, and `v %in% NULL` is `FALSE` for every `v`, so
no guard is needed.

- [ ] **Step 5: Run the tests**

```bash
Rscript -e 'devtools::test(filter = "type-report")'
Rscript -e 'devtools::test(filter = "r_data_types")'
```

Expected: both PASS. The second confirms the attribute broke nothing — no existing test
compares a whole returned frame with `identical()`, and every `digest::digest()` call in
the package hashes a **file**, not an object, so no checksum shifts.

- [ ] **Step 6: Add the export to `_pkgdown.yml`**

The **Data Type Conversion** section at `_pkgdown.yml:68` becomes:

```yaml
- title: Data Type Conversion
  desc: >
    Automatically infer and convert column types, and read back which rule
    fired on which column.
  contents:
  - r_data_types
  - type_conversion_report
```

pkgdown **errors** on a missing topic and the site build is a required check.

- [ ] **Step 7: Document and build the site**

```bash
Rscript -e 'devtools::document()'
Rscript -e 'pkgdown::build_reference_index()'
```

Expected: `man/type_conversion_report.Rd` created, `NAMESPACE` gains
`export(type_conversion_report)`, index builds without error.

- [ ] **Step 8: Commit**

```bash
git add R/type_report.R R/r_data_types.R tests/testthat/test-type-report.R \
        _pkgdown.yml man/ NAMESPACE
git commit -m "$(cat <<'EOF'
feat: report which type-conversion rule fired on which column

r_data_types() now attaches a per-column record to its result, read back with
type_conversion_report(): the rule that fired, where the levels came from,
and what it produced. A column that became a factor because it was declared
one and a column that became a factor because it happened to have seven
distinct values were previously the same object.

Attached on both settings of use_value_labels. An argument that silently
changes which rule fires is the same defect in a new place.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

# Task 3: `use_value_labels`

The argument itself: the `TRUE` branch, and the one-time warning on the `FALSE` default.

**Files:**
- Modify: `R/r_data_types.R`
- Modify: `tests/testthat/test-r_data_types-value-labels.R`
- Modify: `tests/testthat/test-read_clinical_data.R:149-169`

**Interfaces:**
- Consumes: `.convert_column()`'s `use_value_labels` branch from Task 1 (already written,
  not yet reachable through a documented argument); `.hvti_deprecated`, the one-shot
  warning environment defined at `R/read_clinical_data.R:4`.
- Produces: `r_data_types(dataset, factor_size, skip_vars, binary_factor,
  use_value_labels)`, warning once per session when `use_value_labels` is not supplied.

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-r_data_types-value-labels.R`:

```r
test_that("use_value_labels = TRUE keeps the level text", {
  x <- haven::labelled(c(1, 2, 1, 3), labels = c(Home = 1, Rehab = 2, SNF = 3),
                       label = "Discharge disposition")

  out <- r_data_types(data.frame(disp = x), use_value_labels = TRUE)

  expect_s3_class(out$disp, "factor")
  expect_equal(levels(out$disp), c("Home", "Rehab", "SNF"))
  expect_equal(as.character(out$disp), c("Home", "Rehab", "Home", "SNF"))
  expect_equal(attr(out$disp, "label"), "Discharge disposition")
})

test_that("value labels beat the binary-to-logical branch", {
  # The binary branch runs first in the inference chain, so without this
  # precedence a labelled yes/no variable would come back logical with its
  # level text gone -- exactly the case the whole change is for.
  b <- haven::labelled(c(0, 1, 1, 0), labels = c(No = 0, Yes = 1),
                       label = "Prior stroke")

  out <- r_data_types(data.frame(flag = b), use_value_labels = TRUE)

  expect_s3_class(out$flag, "factor")
  expect_equal(levels(out$flag), c("No", "Yes"))
})

test_that("value labels beat factor_size", {
  # A declared type is not subject to a threshold on distinct values.
  codes <- c(1, 2, 3, 4, 5, 6)
  x <- haven::labelled(codes,
                       labels = c(a = 1, b = 2, c = 3, d = 4, e = 5, f = 6))

  out <- r_data_types(data.frame(v = x), factor_size = 3,
                      use_value_labels = TRUE)

  expect_s3_class(out$v, "factor")
  expect_equal(levels(out$v), c("a", "b", "c", "d", "e", "f"))
})

test_that("an unlabelled code keeps its code as the level text", {
  # labelled::to_factor(levels = "default") uses the label where there is one
  # and the value where there is not, so a code missing from the catalogue is
  # visible in the output rather than silently dropped to NA.
  p <- haven::labelled(c(1, 2, 9, 1), labels = c(Home = 1, Rehab = 2))

  out <- r_data_types(data.frame(v = p), use_value_labels = TRUE)

  expect_equal(levels(out$v), c("Home", "Rehab", "9"))
})

test_that("a haven_labelled column with no value labels falls through", {
  x <- haven::labelled(c(1, 2, 3, 1), label = "Just a label")

  out <- r_data_types(data.frame(v = x), use_value_labels = TRUE)
  rep <- type_conversion_report(out)

  expect_equal(rep$rule, "n_distinct_factor")
  expect_equal(rep$level_source, "inference")
})

test_that("the report names value labels as the level source", {
  x <- haven::labelled(c(1, 2, 1, 3), labels = c(Home = 1, Rehab = 2, SNF = 3))

  rep <- type_conversion_report(
    r_data_types(data.frame(disp = x), use_value_labels = TRUE)
  )

  expect_equal(rep$rule, "value_labels")
  expect_equal(rep$level_source, "value labels")
  expect_equal(rep$n_levels, 3L)
  expect_equal(rep$storage_in, "haven_labelled")
  expect_equal(rep$storage_out, "factor")
})

test_that("omitting use_value_labels warns once per session", {
  # The one-shot flag is session state; reset it so this test is
  # order-independent. `pkg:::name$field <- value` is not valid R -- the
  # replacement-function desugaring tries to reassign the bare symbol `pkg`,
  # which is never a bound variable. Use assign() against the
  # (reference-semantics) environment instead, and restore the prior value so
  # the reset doesn't leak into tests in other files.
  env <- hvtiRutilities:::.hvti_deprecated
  prior <- if (exists("use_value_labels", envir = env, inherits = FALSE)) {
    get("use_value_labels", envir = env, inherits = FALSE)
  } else {
    NULL
  }
  withr::defer(assign("use_value_labels", prior, envir = env))
  assign("use_value_labels", NULL, envir = env)

  dta <- data.frame(a = c(1, 2, 3, 1))

  expect_warning(r_data_types(dta), "use_value_labels")
  expect_silent(r_data_types(dta))
})

test_that("passing use_value_labels explicitly never warns", {
  env <- hvtiRutilities:::.hvti_deprecated
  prior <- if (exists("use_value_labels", envir = env, inherits = FALSE)) {
    get("use_value_labels", envir = env, inherits = FALSE)
  } else {
    NULL
  }
  withr::defer(assign("use_value_labels", prior, envir = env))
  assign("use_value_labels", NULL, envir = env)

  dta <- data.frame(a = c(1, 2, 3, 1))

  expect_silent(r_data_types(dta, use_value_labels = FALSE))
  expect_silent(r_data_types(dta, use_value_labels = TRUE))
})
```

- [ ] **Step 2: Run and confirm the warning tests fail**

```bash
Rscript -e 'devtools::test(filter = "r_data_types-value-labels")'
```

Expected: the six behaviour tests **pass already** — Task 1 wired the branch. The two
warning tests fail: `expect_warning()` finds no warning.

- [ ] **Step 3: Add the one-time warning**

At the top of `r_data_types()`'s body, **before** the `is.data.frame(dataset)` check:

```r
  if (missing(use_value_labels) &&
        is.null(.hvti_deprecated$use_value_labels)) {
    .hvti_deprecated$use_value_labels <- TRUE
    warning(
      "r_data_types(): 'use_value_labels' defaults to FALSE, so a column ",
      "carrying SAS value labels is converted from its numeric codes and ",
      "the level text -- Home, Rehab, SNF -- is discarded. Pass ",
      "use_value_labels = TRUE to convert through the labels instead, or ",
      "FALSE to silence this warning. The default will become TRUE in a ",
      "later release.",
      call. = FALSE
    )
  }
```

This is the shape of the `convert_types` warning at `R/read_clinical_data.R:66`: it names
the harm in plain terms rather than saying "deprecated", and it says what to pass to
silence it. `.hvti_deprecated` is defined at `R/read_clinical_data.R:4` and is package
namespace state — no import needed.

- [ ] **Step 4: Run the tests**

```bash
Rscript -e 'devtools::test(filter = "r_data_types-value-labels")'
```

Expected: PASS.

- [ ] **Step 5: Run the full suite and expect two failures in `read_clinical_data`**

```bash
Rscript -e 'devtools::test()'
```

Expected: **failures** in `test-read_clinical_data.R`. `read_clinical_data()` calls
`r_data_types(data, ...)` with `use_value_labels` missing, so the new warning fires
through it and the two `expect_silent(read_clinical_data(tmp, convert_types = TRUE))`
assertions at lines 167 and 168 break — or worse, pass or fail depending on which test
file ran first and consumed the one-shot flag. Order-dependent is the real defect here;
fix it rather than waiting to be bitten.

- [ ] **Step 6: Pin those two assertions**

In `tests/testthat/test-read_clinical_data.R`, in the test
`"passing convert_types explicitly never warns"`, change the two final assertions to name
both arguments:

```r
  expect_silent(read_clinical_data(tmp, convert_types = FALSE))
  expect_silent(read_clinical_data(tmp, convert_types = TRUE,
                                   use_value_labels = FALSE))
```

`convert_types = FALSE` never reaches `r_data_types()`, so the first line needs nothing.

Then in the test `"convert_types = TRUE still converts"` and in **every other test in that
file that passes `convert_types = TRUE`**, add `use_value_labels = FALSE`. Find them:

```bash
grep -n "convert_types = TRUE" tests/testthat/test-read_clinical_data.R
```

Leaving `read_clinical_data()` to forward the argument through `...` — rather than giving
it a `use_value_labels` parameter of its own — is deliberate: the warning is aimed at
whoever asked for type conversion, and that is the caller who passed
`convert_types = TRUE`.

- [ ] **Step 7: Run the full suite**

```bash
Rscript -e 'devtools::test()'
```

Expected: PASS, no warnings.

- [ ] **Step 8: Commit**

```bash
git add R/r_data_types.R tests/testthat/test-r_data_types-value-labels.R \
        tests/testthat/test-read_clinical_data.R
git commit -m "$(cat <<'EOF'
feat: use_value_labels on r_data_types(), default FALSE

haven represents a SAS numeric-plus-format variable as a haven_labelled
vector carrying the code-to-text mapping. r_data_types() destroyed it: the
column is is.numeric() and is not a factor, so factor() saw only the codes
and Home/Rehab/SNF were dropped on the floor.

use_value_labels = TRUE converts through labelled::to_factor() instead, ahead
of every inference branch -- so a declared type beats both the
binary-to-logical rule and the factor_size threshold. The report names "value
labels" as the level source when it fires.

The default is FALSE for now and warns once when it is not supplied, the
shape of the convert_types warning. It becomes TRUE in a later release. Until
then no existing caller changes behaviour.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

# Task 4: Documentation, NEWS, and the PR

**Files:**
- Modify: `R/r_data_types.R` (roxygen block)
- Modify: `NEWS.md`
- Regenerate: `man/`, `NAMESPACE`

**Interfaces:**
- Consumes: everything from Tasks 1–3.
- Produces: a PR against `main`.

- [ ] **Step 1: Update the roxygen block**

In `R/r_data_types.R`, the `@details` `\enumerate{}` list currently describes the old
chain. Replace it with the branch order the dispatcher actually runs, and add the new
`@param` and `@seealso`. **Rd markup, not markdown** — no backticks, no `*` bullets.

```r
#' @details
#' Each column is converted by the first rule that matches, in this order:
#' \enumerate{
#'   \item When \code{use_value_labels = TRUE} and the column carries value
#'     labels, they become the factor levels. This runs ahead of every rule
#'     below: a declared type is not subject to a threshold on distinct
#'     values.
#'   \item Character strings "NA", "na", "Na" and "nA" become \code{NA}.
#'   \item Numeric or integer columns with exactly 2 distinct values become
#'     logical, or factors when \code{binary_factor = TRUE}.
#'   \item Remaining character columns become factors.
#'   \item Numeric columns with 3 to \code{factor_size} distinct values
#'     become factors.
#'   \item Logical columns become factors when \code{binary_factor = TRUE}.
#' }
#'
#' Date, POSIXct and POSIXlt columns are never altered by type conversion.
#'
#' Which rule fired on which column is recorded on the result and read back
#' with \code{\link{type_conversion_report}}.
#'
#' @param use_value_labels Logical. If TRUE, a column carrying value labels --
#'   what \pkg{haven} reads from a SAS numeric-plus-format variable -- is
#'   converted through \code{\link[labelled]{to_factor}}, so the level text is
#'   kept. If FALSE the value labels are dropped and the numeric codes are
#'   converted instead. Default is FALSE, which warns once per session; the
#'   default becomes TRUE in a later release.
#'
#' @seealso \code{\link{type_conversion_report}} for the record of which rule
#'   fired on which column.
```

Add to `@examples`, after the existing `binary_factor` example:

```r
#' # Keep the level text of a SAS formatted variable
#' disp <- haven::labelled(c(1, 2, 1, 3),
#'                         labels = c(Home = 1, Rehab = 2, SNF = 3),
#'                         label  = "Discharge disposition")
#' converted <- r_data_types(data.frame(disp = disp), use_value_labels = TRUE)
#' levels(converted$disp)
#' type_conversion_report(converted)
```

Also update the `@return` line to name the attribute:

```r
#' @return An object of the same class as \code{dataset} with columns
#'   converted according to the function's rules. Variable labels are
#'   preserved. The result carries a per-column conversion report, read with
#'   \code{\link{type_conversion_report}}.
```

- [ ] **Step 2: Add the NEWS entries**

`NEWS.md` line 1 already reads `# hvtiRutilities (unreleased)` and line 3 already reads
`## Bug fixes`. **Do not add a second unreleased heading and do not rename the existing
one** — a renamed top heading silently merges two versions and no CI gate can see it.

Insert a new `## New features` section immediately **after** line 1 and before the
existing `## Bug fixes`:

```markdown
## New features

- **`r_data_types()` can keep the level text of a SAS formatted variable.**
  `haven` reads a numeric-plus-format variable as a `haven_labelled` vector
  carrying its own code-to-text mapping. `r_data_types()` threw it away: the
  column is `is.numeric()` and is not a factor, so the factor branch saw only
  the codes and `Home`, `Rehab`, `SNF` were lost. Downstream, every table
  reconstructed them by hand from the variable label — which is why REDCap
  labels ended up enumerating eight options.

  The new `use_value_labels` argument converts through
  `labelled::to_factor()` instead. It runs ahead of every inference rule, so
  a declared type beats both the binary-to-logical branch and the
  `factor_size` threshold.

  It defaults to `FALSE` and warns once per session when it is not supplied,
  the same shape as the `convert_types` warning. The default becomes `TRUE`
  in a later release; until then no existing caller changes behaviour.

- **`type_conversion_report()` says which rule fired on which column.** One
  row per column: the rule, whether the levels came from value labels or from
  counting distinct values, how many there were, and the class in and out. A
  column that became a factor because it was declared one and a column that
  became a factor because it happened to have seven distinct values were
  previously the same object.
```

Then add to the **existing** `## Bug fixes` section, as its first entry:

```markdown
- **`r_data_types()` no longer errors on a two-valued SAS formatted
  variable.** `as.logical()` has no `vctrs` cast from `haven_labelled`, and
  the binary branch called it before anything had dropped the labels — so
  `read_clinical_data(convert_types = TRUE)` aborted on any SAS export
  carrying a formatted yes/no variable. The labels are now dropped explicitly
  before the numeric branches when `use_value_labels = FALSE`, making that
  path a conversion rather than a crash.
```

**Do not touch `DESCRIPTION`.** Version stays `1.1.8`. The bump is a separate commit the
maintainer makes when naming a version.

- [ ] **Step 3: Document, and check the docs job will pass**

```bash
Rscript -e 'devtools::document()'
git diff --exit-code man/ NAMESPACE DESCRIPTION
```

Expected: `document()` writes; then `git diff --exit-code` **fails** on unstaged `man/`
changes, which is correct at this point. Stage them, then re-run it — it must exit 0 with
everything staged. That is exactly what the **docs-current** job runs.

- [ ] **Step 4: Lint the changed files**

```bash
Rscript -e 'print(lintr::lint("R/r_data_types.R"))'
Rscript -e 'print(lintr::lint("R/type_report.R"))'
```

Expected: no line over 80 characters, no new findings. ⚠️ `object_usage_linter` resolves
cross-file references against the **installed** package, so `.type_report()` called from
`R/r_data_types.R` may lint as *"no visible global function definition"* until the package
is installed. That warning is an artifact, not a defect — `R CMD check` runs its own
codetools pass and is the real test.

- [ ] **Step 5: Full check**

```bash
Rscript -e 'devtools::check()'
```

Expected: **0 errors, 0 warnings, 0 notes.** Two things to look at if a note appears:
the new `@examples` block calls `haven::labelled()`, and `haven` is in `Imports`, so it is
available — but the example must run in under the check's example budget and must not
depend on a file. The `type_conversion_report()` example uses `datasets::mtcars`, which is
base. `\value` is present on both exported objects, which is the CRAN Cookbook item this
package has tripped on before.

- [ ] **Step 6: Push and open the PR**

```bash
git add R/r_data_types.R NEWS.md man/ NAMESPACE
git commit -m "$(cat <<'EOF'
docs: document use_value_labels and the conversion report

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
git push -u origin feat/use-value-labels
gh pr create --title "feat: convert SAS value labels instead of discarding them" --body "$(cat <<'EOF'
Implements option **B** of `dev/specs/2026-09-02-label-length-and-fallback-design.md` §7.3,
decided 2026-09-02. Plan: `dev/specs/2026-09-02-r-data-types-value-labels-plan.md`.

## What was wrong

`haven` reads a SAS numeric-plus-format variable as a `haven_labelled` vector carrying its
own code-to-text mapping. `r_data_types()` destroyed it — the column is `is.numeric()` and
is not a factor, so the factor branch saw only the codes and `Home`, `Rehab`, `SNF` went on
the floor. Every table downstream reconstructed them by hand from the variable label, which
is why REDCap labels ended up enumerating eight options in a field meant for one.

Found while implementing, and not in the design note: **a two-valued formatted variable did
not lose its labels, it errored.** `as.logical()` has no `vctrs` cast from `haven_labelled`
and the binary branch runs first, so `read_clinical_data(convert_types = TRUE)` aborted on
any SAS export with a formatted yes/no variable. Only `convert_types` defaulting to `FALSE`
kept that from being a daily failure.

## What this does

- `use_value_labels` on `r_data_types()`, default `FALSE`, warning once per session — the
  shape of the `convert_types` warning at `R/read_clinical_data.R:66`. The default becomes
  `TRUE` in a later release. **No existing caller changes behaviour.**
- `TRUE` converts through `labelled::to_factor()`, ahead of every inference rule, so a
  declared type beats both the binary branch and the `factor_size` threshold.
- `FALSE` drops the labels explicitly before the numeric branches, which is what turns the
  crash into a conversion.
- `type_conversion_report()` — one row per column, naming the rule that fired and whether
  the levels came from value labels or from counting distinct values. §7.3 is explicit that
  B is not a licence to skip this: an argument that silently changes which rule fires is the
  same defect in a new place.
- The four `dplyr::across()` passes became one per-column dispatcher, so the report is built
  from the conversion's own return value rather than from a second description of it.

## Not in this PR

`catalog_file` on `read_clinical_data()` (§5), option C's declaration-first converter,
`label_max` (§4), the prefix stripper (§6). Each is separable and each has its own entry in
the design note's definition of done.

## Verification

- `devtools::test()` — green. The existing 575 lines of `r_data_types` tests pass
  **unmodified** and were the equivalence gate for the refactor.
- `devtools::check()` — 0 errors, 0 warnings, 0 notes.
- `DESCRIPTION` untouched; the entry is under `# hvtiRutilities (unreleased)`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

⚠️ The PR will sit at `REVIEW_REQUIRED` until somebody other than the author approves it —
`required_approving_review_count` is 1 and GitHub refuses self-approval. Copilot reviews on
open and **does not re-review on push**, so if it finds something, say in a PR comment what
you changed and why rather than waiting for a second pass.

---

## Self-Review

**Spec coverage.** Every clause of §7.3's *"What B commits to"* maps to a task:

| spec clause | task |
|---|---|
| *"A `use_value_labels` argument on `r_data_types()`"* | Task 3 |
| *"default `FALSE` in the release that introduces it"* | Task 3, Step 3 |
| *"warning once when it is not supplied — the shape of the `convert_types` warning"* | Task 3, Step 3 |
| *"The default flips to `TRUE` in a later release"* | stated in the roxygen and NEWS, **not implemented** — correct, it is a later release |
| *"Until it flips, no existing caller changes behaviour"* | Task 1, Step 6 — the 575-line harness passes unmodified |
| *"B is not a licence to skip the report"* | Task 2, attached unconditionally |
| *"the rule that fired, the source of the levels, and what it produced"* | Task 2, `rule` / `level_source` / `n_levels` + `storage_out` |
| §7.1 *"say which happened"* | Task 2, `level_source` distinguishes `"value labels"` from `"inference"` |
| §2.2 the discard | Task 3, the `to_factor()` branch |

§4 (`label_max`), §2.1 (the fallback test), §5 (`catalog_file`), §6 (prefixes) and §8 are
explicitly out of scope above and correctly have no task. §7.3's option C is named as a
later plan; `level_source`'s vocabulary is left open for its `"declaration"` value but the
value is not added.

**Fixed during review.**

1. **The report was originally specified as a predicate function run beside the conversion
   chain.** That is the drift the design note warns about in a different guise: two
   descriptions of one behaviour, with no gate on their agreement. Replaced with the
   per-column dispatcher, which is why Task 1 exists at all — the refactor is not
   incidental tidying, it is what makes the report trustworthy.
2. **`use_value_labels` was originally added in Task 3 only.** But Task 1's crash fix has
   to decide what the `FALSE` path does with a `haven_labelled` column, and that decision
   *is* the argument. Moved the parameter into Task 1 without its warning, so Task 1's own
   tests can run and Task 1 stays reviewable on the existing suite.
3. **`read_clinical_data()`'s `expect_silent()` tests would have become order-dependent.**
   The one-shot warning flag is session state; whichever test file consumed it first would
   decide whether `expect_silent(read_clinical_data(tmp, convert_types = TRUE))` passed.
   That is worse than a clean failure, because it would go green on CI and red locally.
   Task 3 Step 6 pins the argument explicitly.
4. **`"unchanged"` and `"skipped"` were one value.** They are different claims — every rule
   tested and none fired, versus no rule tested — and collapsing them would make
   `skip_vars` invisible in the record of what happened. Split, with a test.
5. **A column that was already `logical` reported `"binary_logical"`.** The binary branch
   calls `as.logical()` on it, which is a no-op, so the report claimed a conversion that
   did not happen. `.convert_column()` checks `was_logical` and reports `"unchanged"`.

**Verified rather than assumed.** Every claim in *"What the code does today"* was produced
by running the code on 2026-09-02, not read off the source: the discard, the crash, the
name-into-label stamping. So was `labelled::to_factor()` on a partially-labelled vector
(`Home Rehab 9` — the unlabelled code survives as its own level, which is the fourth test
in Task 3), and `new_data[] <- lapply(...)` preserving `tbl_df` class and surviving a
zero-column frame.

**Type consistency.** `.convert_column()` returns `list(value, rule, level_source,
storage_in)` in Task 1; `.type_report()` consumes exactly those four names in Task 2. The
rule vocabulary is fixed once in Task 1's Interfaces block and used unchanged in Task 2's
roxygen, Task 2's tests and Task 3's tests. The attribute is `"hvti_type_conversion"` in
all three places it appears. The report's six column names are identical in
`.type_report()`, in the `@return`, and in both test files.

**Known gap, stated rather than hidden.** No test in this plan reads a real `.sas7bdat`.
Every `haven_labelled` fixture is constructed in-process with `haven::labelled()`. That is
deliberate — B must not wait on the open question of whether `.sas7bcat` catalogues exist
in the corpus (§5.1) — but it does mean this PR proves the conversion, not the read. The
end-to-end claim needs `catalog_file` (§5) and a real file, and belongs to that PR.
