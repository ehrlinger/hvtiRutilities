# SAS Macro Canonicalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce the legacy SAS macro library to a signed-off canonical set of macro definitions, with a signature database and a name-collision hazard report, so that Phase 1 can build a trustworthy SAS oracle.

**Architecture:** Four exported R functions in `hvtiRutilities`, plus internal helpers. `sas_macro_defs()` extracts every `%macro`…`%mend` definition from a file. `sas_macro_signature()` parses the structured header comment block. `sas_triage()` applies an ordered rule ladder across a directory and returns one row per macro definition, marking divergent redefinitions `ambiguous` rather than guessing. `write_macro_manifest()` serialises the result to YAML. Human decisions live in a committed `macro_overrides.yaml` and are re-applied on every run, making the manifest reproducible byte-for-byte.

**Tech Stack:** R (>= 4.1.0), `digest` (SHA-256 body hashing), `yaml` (manifest I/O), `testthat` edition 3. No SAS dependency — SAS runs on a separate system and Phase 0 must not require it.

---

## Spec

`specs/2026-07-10-sas-macro-canonicalization-design.md`

## File Structure

| File | Responsibility |
|---|---|
| `R/sas_macro_defs.R` | Extract every macro definition from one `.sas` file. Case-insensitive. Errors on unmatched `%macro`. |
| `R/sas_lint.R` | Internal `.sas_lint()`. Pure-R heuristic validity check. No SAS. |
| `R/sas_macro_signature.R` | Parse the `MACRO NAME:` / `MACRO CALL` / `MODIFIED BY` header block. |
| `R/sas_triage.R` | The rule ladder. Exported `sas_triage()`; internal `.classify_visibility()`, `.strip_variant_suffix()`. |
| `R/write_macro_manifest.R` | YAML serialisation of the decision table + `collision_report.md`. |
| `tests/testthat/fixtures/` | Nine synthetic `.sas` fixtures. No PHI. |
| `tests/testthat/test-sas_macro_defs.R` | Extraction, case folding, multi-definition, unmatched `%mend`. |
| `tests/testthat/test-sas_lint.R` | Each lint check. |
| `tests/testthat/test-sas_macro_signature.R` | Header parsing, missing header. |
| `tests/testthat/test-sas_triage.R` | Rules 1–6, visibility, overrides, idempotence. |
| `tests/testthat/test-write_macro_manifest.R` | Round-trip, byte-for-byte stability. |

### Key design decision: no timestamp in the manifest

The spec requires `macro_manifest.yaml` to reproduce byte-for-byte across runs.
A generated-on timestamp would make that impossible. Run metadata (date, R
version, corpus counts) therefore lives in the **report**, not the manifest.
This deliberately diverges from `R/manifest.R`, which stores `extract_date`
inside the manifest — that manifest tracks datasets that genuinely change over
time, whereas this one describes a frozen 2019 corpus.

### Decision table schema

`sas_triage()` returns a `data.frame` with one row per macro definition:

| Column | Type | Meaning |
|---|---|---|
| `file` | character | Basename of the defining file |
| `macro` | character | Macro name, lowercased |
| `params` | character | Comma-joined parameter names, `""` if none |
| `body_hash` | character | SHA-256 of the normalized body |
| `line_start` | integer | Line of the `%macro` statement |
| `line_end` | integer | Line of the matching `%mend` |
| `visibility` | character | `"public"`, `"public?"`, or `"private"` |
| `decision` | character | `"canonical"`, `"drop"`, `"ambiguous"`, `"unclassified"` |
| `rule` | integer | Which rule fired (1–6), `NA` for `unclassified` |
| `evidence` | character | Human-readable justification |

---

## Task 1: Fixtures

**Files:**
- Create: `tests/testthat/fixtures/alpha.sas`
- Create: `tests/testthat/fixtures/Copy of alpha.sas`
- Create: `tests/testthat/fixtures/beta.sas`
- Create: `tests/testthat/fixtures/beta.sas~`
- Create: `tests/testthat/fixtures/gamma_broken.sas`
- Create: `tests/testthat/fixtures/delta.sas`
- Create: `tests/testthat/fixtures/delta_dup.sas`
- Create: `tests/testthat/fixtures/epsilon.sas`
- Create: `tests/testthat/fixtures/zeta.sas`
- Create: `tests/testthat/fixtures/zeta_old.sas`
- Create: `tests/testthat/fixtures/multi.sas`
- Create: `tests/testthat/fixtures/upper.sas`
- Create: `tests/testthat/fixtures/nomend.sas`

These fixtures are the substrate for every later task. They contain no PHI and
no real macro logic.

- [ ] **Step 1: Create the fixture directory and files**

```bash
mkdir -p tests/testthat/fixtures
```

`tests/testthat/fixtures/alpha.sas`:
```sas
%macro alpha(dsn);
  data &dsn._out; set &dsn.; run;
%mend alpha;
```

`tests/testthat/fixtures/Copy of alpha.sas` — byte-identical to `alpha.sas`:
```sas
%macro alpha(dsn);
  data &dsn._out; set &dsn.; run;
%mend alpha;
```

`tests/testthat/fixtures/beta.sas`:
```sas
%macro beta;
  proc print data=work.x; run;
%mend beta;
```

`tests/testthat/fixtures/beta.sas~` — the Emacs backup, deliberately different:
```sas
%macro beta;
  proc print data=work.old; run;
%mend beta;
```

`tests/testthat/fixtures/gamma_broken.sas` — unbalanced single quote, mirroring
the real `CR_compare_CP_test_AT.sas` defect:
```sas
%macro gamma;
  define dev1/display Number*events of*interest' format=9.;
%mend gamma;
```

`tests/testthat/fixtures/delta.sas`:
```sas
%macro delta(n);
  %let half = %sysevalf(&n. / 2);
%mend delta;
```

`tests/testthat/fixtures/delta_dup.sas` — byte-identical body, different file.
This is the benign vendored-helper case (rule 5):
```sas
%macro delta(n);
  %let half = %sysevalf(&n. / 2);
%mend delta;
```

`tests/testthat/fixtures/epsilon.sas` — unique, defined once (rule 4):
```sas
%macro epsilon;
  %put NOTE: epsilon;
%mend epsilon;
```

`tests/testthat/fixtures/zeta.sas` — the divergent pair, mirroring the real
`_freq_` vs `freq` defect:
```sas
%macro zeta;
  tau=tau1; keep _freq_ tau;
%mend zeta;
```

`tests/testthat/fixtures/zeta_old.sas`:
```sas
%macro zeta;
  tau=tau1; keep freq tau;
%mend zeta;
```

`tests/testthat/fixtures/multi.sas` — three definitions in one file, the common
real-world shape (451 definitions across 179 files):
```sas
%macro helper_one;
  %put one;
%mend helper_one;

%macro helper_two;
  %put two;
%mend helper_two;

%macro multi;
  %helper_one;
  %helper_two;
%mend multi;
```

`tests/testthat/fixtures/upper.sas` — uppercase declaration, the regression test
for the `awk`/`IGNORECASE` defect found during design:
```sas
%MACRO UPPER(IN);
  PROC MEANS DATA=&IN.; RUN;
%MEND UPPER;
```

`tests/testthat/fixtures/nomend.sas` — `%macro` with no `%mend`:
```sas
%macro nomend;
  data x; set y; run;
```

- [ ] **Step 2: Verify the backup fixture survives git**

`.gitignore` does not currently ignore `*~`, so `beta.sas~` will be tracked.
Confirm:

```bash
git check-ignore -v "tests/testthat/fixtures/beta.sas~" ; echo "exit=$?"
```

Expected: no output, `exit=1` (not ignored).

- [ ] **Step 3: Commit**

```bash
git add tests/testthat/fixtures
git commit -m "test: add synthetic SAS fixtures for macro canonicalization"
```

---

## Task 2: `sas_macro_defs()` — extract every definition

**Files:**
- Create: `R/sas_macro_defs.R`
- Test: `tests/testthat/test-sas_macro_defs.R`

- [ ] **Step 1: Write the failing tests**

`tests/testthat/test-sas_macro_defs.R`:
```r
library(testthat)
library(hvtiRutilities)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

fx <- function(name) testthat::test_path("fixtures", name)

# ---------------------------------------------------------------------------
# sas_macro_defs — extraction
# ---------------------------------------------------------------------------

test_that("sas_macro_defs extracts a single definition", {
  res <- sas_macro_defs(fx("alpha.sas"))

  expect_s3_class(res, "data.frame")
  expect_equal(nrow(res), 1L)
  expect_equal(res$macro, "alpha")
  expect_equal(res$params, "dsn")
  expect_equal(res$line_start, 1L)
  expect_equal(res$line_end, 3L)
  expect_true(nzchar(res$body_hash))
})

test_that("sas_macro_defs extracts every definition in a multi-macro file", {
  res <- sas_macro_defs(fx("multi.sas"))

  expect_equal(nrow(res), 3L)
  expect_setequal(res$macro, c("helper_one", "helper_two", "multi"))
})

test_that("sas_macro_defs folds case: %MACRO UPPER is found", {
  res <- sas_macro_defs(fx("upper.sas"))

  expect_equal(nrow(res), 1L)
  expect_equal(res$macro, "upper")
  expect_equal(res$params, "in")
  expect_true(nzchar(res$body_hash))
})

test_that("sas_macro_defs errors on an unmatched %macro", {
  expect_error(
    sas_macro_defs(fx("nomend.sas")),
    "unmatched '%macro nomend'.*line 1",
    fixed = FALSE
  )
})

test_that("sas_macro_defs errors on a file with no macro definition", {
  tmp <- withr::local_tempfile(fileext = ".sas")
  writeLines("proc print data=x; run;", tmp)

  expect_error(sas_macro_defs(tmp), "no %macro definition")
})

# ---------------------------------------------------------------------------
# sas_macro_defs — body hashing
# ---------------------------------------------------------------------------

test_that("identical bodies hash identically across files", {
  a <- sas_macro_defs(fx("delta.sas"))
  b <- sas_macro_defs(fx("delta_dup.sas"))

  expect_equal(a$body_hash, b$body_hash)
})

test_that("divergent bodies hash differently (_freq_ vs freq)", {
  a <- sas_macro_defs(fx("zeta.sas"))
  b <- sas_macro_defs(fx("zeta_old.sas"))

  expect_equal(a$macro, b$macro)
  expect_false(identical(a$body_hash, b$body_hash))
})

test_that("body hash ignores case and whitespace, not content", {
  t1 <- withr::local_tempfile(fileext = ".sas")
  t2 <- withr::local_tempfile(fileext = ".sas")
  writeLines(c("%macro q;", "  proc print; run;", "%mend q;"), t1)
  writeLines(c("%MACRO Q;", "PROC PRINT;    RUN;", "%MEND Q;"), t2)

  expect_equal(sas_macro_defs(t1)$body_hash, sas_macro_defs(t2)$body_hash)
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "sas_macro_defs")'`
Expected: FAIL — `could not find function "sas_macro_defs"`

- [ ] **Step 3: Write the implementation**

`R/sas_macro_defs.R`:
```r
## =============================================================================
## Internal: normalize a macro body prior to hashing.
## Case-folds and collapses all whitespace runs to a single space, so that
## cosmetic reformatting does not register as a semantic difference.
.normalize_body <- function(lines) {
  txt <- paste(lines, collapse = " ")
  txt <- tolower(txt)
  txt <- gsub("[[:space:]]+", " ", txt)
  trimws(txt)
}

## =============================================================================
## Internal: parse the parameter list from a %macro statement.
## "%macro foo(a, b=1, c);" -> "a,b,c"   |   "%macro foo;" -> ""
.parse_params <- function(stmt) {
  m <- regmatches(stmt, regexpr("\\(([^)]*)\\)", stmt))
  if (length(m) == 0L) {
    return("")
  }
  inner <- gsub("^\\(|\\)$", "", m)
  if (!nzchar(trimws(inner))) {
    return("")
  }
  parts <- strsplit(inner, ",", fixed = TRUE)[[1]]
  parts <- sub("=.*$", "", parts)
  paste(trimws(tolower(parts)), collapse = ",")
}

## =============================================================================
#' Extract every macro definition from a SAS file
#'
#' @description
#' Scans a `.sas` file and returns one row for each `%macro`...`%mend` pair it
#' contains. SAS files in the legacy CORR library are macro *collections*, not
#' single macros, so a file routinely defines several.
#'
#' @details
#' Matching is case-insensitive: SAS macro names are case-insensitive and the
#' legacy corpus mixes `%macro skip;` with `%MACRO MRG;` freely. Nested
#' definitions are handled by depth counting, so an inner `%mend` does not
#' terminate an outer macro.
#'
#' The body hash is a SHA-256 digest of the definition with case folded and
#' whitespace runs collapsed. Two definitions with the same hash are
#' semantically identical up to formatting.
#'
#' An unmatched `%macro` is an error, never a silently truncated body. A file
#' containing no `%macro` at all is likewise an error.
#'
#' @param file Character. Path to a `.sas` file.
#'
#' @return A \code{data.frame} with one row per macro definition and columns
#'   \code{file}, \code{macro}, \code{params}, \code{body_hash},
#'   \code{line_start}, and \code{line_end}. Macro and parameter names are
#'   lowercased.
#'
#' @export sas_macro_defs
#'
#' @examples
#' f <- system.file("extdata", "example_macro.sas", package = "hvtiRutilities")
#' if (nzchar(f)) sas_macro_defs(f)
#'
#' @importFrom digest digest
sas_macro_defs <- function(file) {
  if (!file.exists(file)) {
    stop("File does not exist: ", file, call. = FALSE)
  }

  lines <- readLines(file, warn = FALSE)

  start_re <- "^[[:space:]]*%macro[[:space:]]+([a-z_][a-z0-9_]*)"
  mend_re <- "^[[:space:]]*%mend"

  lower <- tolower(lines)
  is_start <- grepl(start_re, lower)
  is_mend <- grepl(mend_re, lower)

  if (!any(is_start)) {
    stop("no %macro definition found in: ", basename(file), call. = FALSE)
  }

  open <- integer(0) # stack of open %macro line numbers
  defs <- list()

  for (i in seq_along(lines)) {
    if (is_start[i]) {
      open <- c(open, i)
    } else if (is_mend[i] && length(open) > 0L) {
      s <- open[length(open)]
      open <- open[-length(open)]

      stmt <- lower[s]
      name <- sub(paste0(start_re, ".*$"), "\\1", stmt)

      defs[[length(defs) + 1L]] <- data.frame(
        file       = basename(file),
        macro      = name,
        params     = .parse_params(stmt),
        body_hash  = digest::digest(
          .normalize_body(lines[s:i]),
          algo = "sha256", serialize = FALSE
        ),
        line_start = s,
        line_end   = i,
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(open) > 0L) {
    s <- open[1L]
    name <- sub(paste0(start_re, ".*$"), "\\1", lower[s])
    stop(
      "unmatched '%macro ", name, "' at line ", s, " in ", basename(file),
      ". Refusing to hash a truncated body.",
      call. = FALSE
    )
  }

  out <- do.call(rbind, defs)
  out[order(out$line_start), , drop = FALSE]
}
```

- [ ] **Step 4: Add `withr` to Suggests and roxygenise**

`withr` is already in `Suggests` in `DESCRIPTION`. Confirm, then regenerate docs:

```bash
grep -n 'withr' DESCRIPTION
Rscript -e 'roxygen2::roxygenise()'
```

Expected: `withr` present; `NAMESPACE` gains `export(sas_macro_defs)` and
`importFrom(digest,digest)`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "sas_macro_defs")'`
Expected: PASS, 8 tests.

- [ ] **Step 6: Commit**

```bash
git add R/sas_macro_defs.R tests/testthat/test-sas_macro_defs.R NAMESPACE man/
git commit -m "feat: sas_macro_defs() extracts all macro definitions, case-insensitively"
```

---

## Task 3: `.sas_lint()` — pure-R heuristic validity check

**Files:**
- Create: `R/sas_lint.R`
- Test: `tests/testthat/test-sas_lint.R`

Rule 3 of the ladder drops files that fail this check. It must be pure R: SAS
runs on a separate system and Phase 0 must remain reproducible without it.

- [ ] **Step 1: Write the failing tests**

`tests/testthat/test-sas_lint.R`:
```r
library(testthat)
library(hvtiRutilities)

fx <- function(name) testthat::test_path("fixtures", name)

test_that(".sas_lint passes a well-formed file", {
  res <- hvtiRutilities:::.sas_lint(fx("alpha.sas"))

  expect_true(res$valid)
  expect_length(res$failures, 0L)
})

test_that(".sas_lint catches an unbalanced single quote", {
  res <- hvtiRutilities:::.sas_lint(fx("gamma_broken.sas"))

  expect_false(res$valid)
  expect_match(paste(res$failures, collapse = " "), "unbalanced quote")
})

test_that(".sas_lint catches an unmatched %macro", {
  res <- hvtiRutilities:::.sas_lint(fx("nomend.sas"))

  expect_false(res$valid)
  expect_match(paste(res$failures, collapse = " "), "%macro/%mend")
})

test_that(".sas_lint catches a file with no macro definition", {
  tmp <- withr::local_tempfile(fileext = ".sas")
  writeLines("proc print data=x; run;", tmp)

  res <- hvtiRutilities:::.sas_lint(tmp)
  expect_false(res$valid)
  expect_match(paste(res$failures, collapse = " "), "no %macro definition")
})

test_that(".sas_lint folds case for %MACRO/%MEND", {
  res <- hvtiRutilities:::.sas_lint(fx("upper.sas"))

  expect_true(res$valid)
})

test_that(".sas_lint ignores quotes inside comment lines", {
  tmp <- withr::local_tempfile(fileext = ".sas")
  writeLines(
    c("* it's a comment with an apostrophe;",
      "%macro ok;",
      "  proc print; run;",
      "%mend ok;"),
    tmp
  )

  expect_true(hvtiRutilities:::.sas_lint(tmp)$valid)
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "sas_lint")'`
Expected: FAIL — `'.sas_lint' is not an exported object`

- [ ] **Step 3: Write the implementation**

`R/sas_lint.R`:
```r
## =============================================================================
## Internal: strip SAS line comments before quote balancing.
## SAS comments take two forms: a statement starting with `*` and ending `;`,
## and /* ... */ blocks. Apostrophes inside comments are prose, not syntax.
.strip_comments <- function(lines) {
  lines <- gsub("/\\*.*?\\*/", "", lines)
  lines[grepl("^[[:space:]]*\\*", lines)] <- ""
  lines
}

## =============================================================================
## Internal: heuristic SAS validity check. Pure R, no SAS dependency.
##
## Returns list(valid = logical(1), failures = character()).
## Never throws: a broken file is data, and the caller records it as evidence.
.sas_lint <- function(file) {
  lines <- readLines(file, warn = FALSE)
  lower <- tolower(lines)
  failures <- character(0)

  ## 1. At least one macro definition.
  n_macro <- sum(grepl("^[[:space:]]*%macro[[:space:]]+[a-z_]", lower))
  if (n_macro == 0L) {
    failures <- c(failures, "no %macro definition")
  }

  ## 2. %macro / %mend balance.
  n_mend <- sum(grepl("^[[:space:]]*%mend", lower))
  if (n_macro != n_mend) {
    failures <- c(
      failures,
      sprintf("%%macro/%%mend imbalance: %d open, %d close", n_macro, n_mend)
    )
  }

  ## 3. Single-quote balance, per line, comments removed.
  code <- .strip_comments(lines)
  odd <- which(vapply(
    gregexpr("'", code, fixed = TRUE),
    function(m) if (m[1L] == -1L) FALSE else (length(m) %% 2L == 1L),
    logical(1)
  ))
  if (length(odd) > 0L) {
    failures <- c(
      failures,
      sprintf("unbalanced quote at line(s): %s",
              paste(odd, collapse = ", "))
    )
  }

  ## 4. do / end balance across the file.
  n_do <- sum(vapply(
    gregexpr("\\bdo\\b", tolower(code)),
    function(m) if (m[1L] == -1L) 0L else length(m), integer(1)
  ))
  n_end <- sum(vapply(
    gregexpr("\\bend\\b", tolower(code)),
    function(m) if (m[1L] == -1L) 0L else length(m), integer(1)
  ))
  if (n_do != n_end) {
    failures <- c(
      failures,
      sprintf("do/end imbalance: %d do, %d end", n_do, n_end)
    )
  }

  list(valid = length(failures) == 0L, failures = failures)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "sas_lint")'`
Expected: PASS, 6 tests.

Note: `alpha.sas` and `upper.sas` contain no `do`/`end`, so check 4 passes
trivially (`0 == 0`). `gamma_broken.sas` has `%macro`/`%mend` balanced and
trips only the quote check, which is the intended discrimination.

- [ ] **Step 5: Commit**

```bash
git add R/sas_lint.R tests/testthat/test-sas_lint.R
git commit -m "feat: .sas_lint() heuristic SAS validity check, no SAS dependency"
```

---

## Task 4: `sas_macro_signature()` — parse the header block

**Files:**
- Create: `R/sas_macro_signature.R`
- Create: `tests/testthat/fixtures/documented.sas`
- Test: `tests/testthat/test-sas_macro_signature.R`

The real corpus documents macros in a structured comment block (see
`ExpdObsdPlot.sas`). Those fields are evidence for human review in rule 6, and
the documented call signature is a direct Phase 1 input.

- [ ] **Step 1: Create the fixture**

`tests/testthat/fixtures/documented.sas`, modelled on the real
`ExpdObsdPlot.sas` header:
```sas
*_______________________________________________________________________;
* MACRO NAME:  DocMacro
* SHORT DESC:  Does a documented thing
*-----------------------------------------------------------------------;
* CREATED BY:  Artis, Amanda                                  2019/04/05
*-----------------------------------------------------------------------;
* MODIFIED BY:  Artis, Amanda                                 2019/04/09
*
* Added binned summary estimates to the output.
*_______________________________________________________________________;
* MACRO CALL
*
* %DocMacro(DSN, NBINS)
*_______________________________________________________________________;
%macro DocMacro(dsn, nbins);
  %put &dsn. &nbins.;
%mend DocMacro;
```

- [ ] **Step 2: Write the failing tests**

`tests/testthat/test-sas_macro_signature.R`:
```r
library(testthat)
library(hvtiRutilities)

fx <- function(name) testthat::test_path("fixtures", name)

test_that("sas_macro_signature parses the header block", {
  res <- sas_macro_signature(fx("documented.sas"))

  expect_equal(res$macro_name, "docmacro")
  expect_equal(res$short_desc, "Does a documented thing")
  expect_equal(res$created_on, "2019/04/05")
  expect_equal(res$modified_on, "2019/04/09")
  expect_equal(res$documented_call, "%DocMacro(DSN, NBINS)")
})

test_that("sas_macro_signature returns NA fields for an undocumented file", {
  res <- sas_macro_signature(fx("alpha.sas"))

  expect_equal(res$file, "alpha.sas")
  expect_true(is.na(res$macro_name))
  expect_true(is.na(res$modified_on))
})

test_that("sas_macro_signature takes the LAST MODIFIED BY date", {
  tmp <- withr::local_tempfile(fileext = ".sas")
  writeLines(
    c("* MODIFIED BY:  A                         2015/01/01",
      "* MODIFIED BY:  B                         2018/06/30",
      "%macro m; %put x; %mend m;"),
    tmp
  )

  expect_equal(sas_macro_signature(tmp)$modified_on, "2018/06/30")
})
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "sas_macro_signature")'`
Expected: FAIL — `could not find function "sas_macro_signature"`

- [ ] **Step 4: Write the implementation**

`R/sas_macro_signature.R`:
```r
## =============================================================================
## Internal: pull the first capture group of `re` from `lines`, or NA.
.header_field <- function(lines, re, which = c("first", "last")) {
  which <- match.arg(which)
  hits <- grep(re, lines, ignore.case = TRUE, value = TRUE)
  if (length(hits) == 0L) {
    return(NA_character_)
  }
  hit <- if (which == "first") hits[1L] else hits[length(hits)]
  trimws(sub(paste0(".*", re, ".*$"), "\\1", hit, ignore.case = TRUE))
}

## =============================================================================
#' Parse the documentation header of a legacy SAS macro file
#'
#' @description
#' Legacy CORR macros carry a structured comment block naming the macro, its
#' purpose, its documented call signature, and a modification log. This function
#' extracts those fields. They are used as evidence during human review of
#' divergent macro redefinitions, and the documented call is a direct input to
#' the Phase 1 SAS harness.
#'
#' @details
#' All fields are optional. A file with no header block yields a row of
#' \code{NA}s rather than an error, because an undocumented macro is a normal
#' occurrence in this corpus and not a defect.
#'
#' When several \code{MODIFIED BY} lines are present, the \strong{last} date is
#' returned. Note that this date is advisory evidence only; \code{sas_triage()}
#' never uses it to choose between competing macro definitions.
#'
#' @param file Character. Path to a `.sas` file.
#'
#' @return A one-row \code{data.frame} with columns \code{file},
#'   \code{macro_name}, \code{short_desc}, \code{created_on},
#'   \code{modified_on}, and \code{documented_call}. Absent fields are
#'   \code{NA_character_}. \code{macro_name} is lowercased.
#'
#' @export sas_macro_signature
#'
#' @examples
#' f <- system.file("extdata", "example_macro.sas", package = "hvtiRutilities")
#' if (nzchar(f)) sas_macro_signature(f)
sas_macro_signature <- function(file) {
  if (!file.exists(file)) {
    stop("File does not exist: ", file, call. = FALSE)
  }

  lines <- readLines(file, warn = FALSE)

  macro_name <- .header_field(lines, "MACRO NAME:[[:space:]]*([A-Za-z0-9_]+)")
  short_desc <- .header_field(lines, "SHORT DESC:[[:space:]]*(.*?)[[:space:]]*$")
  created_on <- .header_field(lines, "CREATED BY:.*?([0-9]{4}/[0-9]{2}/[0-9]{2})")
  modified_on <- .header_field(
    lines, "MODIFIED BY:.*?([0-9]{4}/[0-9]{2}/[0-9]{2})",
    which = "last"
  )

  call_hits <- grep("^\\*[[:space:]]*(%[A-Za-z0-9_]+\\(.*\\))", lines, value = TRUE)
  documented_call <- if (length(call_hits) == 0L) {
    NA_character_
  } else {
    trimws(sub("^\\*[[:space:]]*", "", call_hits[1L]))
  }

  data.frame(
    file            = basename(file),
    macro_name      = if (is.na(macro_name)) NA_character_ else tolower(macro_name),
    short_desc      = short_desc,
    created_on      = created_on,
    modified_on     = modified_on,
    documented_call = documented_call,
    stringsAsFactors = FALSE
  )
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `Rscript -e 'roxygen2::roxygenise(); devtools::test(filter = "sas_macro_signature")'`
Expected: PASS, 3 tests.

- [ ] **Step 6: Commit**

```bash
git add R/sas_macro_signature.R tests/testthat/test-sas_macro_signature.R \
        tests/testthat/fixtures/documented.sas NAMESPACE man/
git commit -m "feat: sas_macro_signature() parses legacy macro header blocks"
```

---

## Task 5: Visibility classification

**Files:**
- Create: `R/sas_triage.R` (internal helpers only, this task)
- Test: `tests/testthat/test-sas_triage.R` (visibility section)

A macro whose name matches its file basename is the public entry point; the
rest are private inline helpers vendored by copy-paste. Only public entry points
need R implementations in Phase 2. This annotation is **advisory** and never
drives a `drop`.

- [ ] **Step 1: Write the failing tests**

`tests/testthat/test-sas_triage.R` (first section; later tasks append):
```r
library(testthat)
library(hvtiRutilities)

fx_dir <- function() testthat::test_path("fixtures")

# ---------------------------------------------------------------------------
# Visibility classification
# ---------------------------------------------------------------------------

test_that(".classify_visibility marks an exact basename match public", {
  expect_equal(
    hvtiRutilities:::.classify_visibility("std_dif", "std_dif.sas"),
    "public"
  )
})

test_that(".classify_visibility marks a variant-suffixed file public?", {
  expect_equal(
    hvtiRutilities:::.classify_visibility("std_dif", "std_dif_wt.sas"),
    "public?"
  )
  expect_equal(
    hvtiRutilities:::.classify_visibility("std_dif", "std_difma.sas"),
    "public?"
  )
})

test_that(".classify_visibility marks an inline helper private", {
  expect_equal(
    hvtiRutilities:::.classify_visibility("skip", "readin.sas"),
    "private"
  )
  expect_equal(
    hvtiRutilities:::.classify_visibility("numobs", "lgtphcurv9.sas"),
    "private"
  )
})

test_that(".strip_variant_suffix removes known variant markers", {
  expect_equal(hvtiRutilities:::.strip_variant_suffix("std_dif_wt"), "std_dif")
  expect_equal(hvtiRutilities:::.strip_variant_suffix("std_difma"), "std_dif")
  expect_equal(hvtiRutilities:::.strip_variant_suffix("cr_compare_cp_old"), "cr_compare_cp")
  expect_equal(hvtiRutilities:::.strip_variant_suffix("epsilon"), "epsilon")
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "sas_triage")'`
Expected: FAIL — `'.classify_visibility' is not an exported object`

- [ ] **Step 3: Write the implementation**

`R/sas_triage.R` (helpers; `sas_triage()` itself lands in Task 6):
```r
## =============================================================================
## Internal: known variant markers observed in the legacy corpus.
## Ordered longest-first so that `_test_at` strips before `_test`.
.VARIANT_SUFFIXES <- c(
  "_test_at", "_testma", "_test", "_old", "_new", "_orig",
  "_wt", "_at", "_b", "ma"
)

## =============================================================================
## Internal: strip one trailing variant marker from a lowercased stem.
.strip_variant_suffix <- function(stem) {
  for (sfx in .VARIANT_SUFFIXES) {
    if (grepl(paste0(sfx, "$"), stem) && nchar(stem) > nchar(sfx)) {
      return(sub(paste0(sfx, "$"), "", stem))
    }
  }
  stem
}

## =============================================================================
## Internal: classify a macro definition as a public entry point or a private
## inline helper. Advisory only -- never used to drop a definition.
.classify_visibility <- function(macro, file) {
  stem <- tolower(sub("\\.sas~?$", "", basename(file), ignore.case = TRUE))
  macro <- tolower(macro)

  if (identical(stem, macro)) {
    return("public")
  }
  if (identical(.strip_variant_suffix(stem), macro)) {
    return("public?")
  }
  "private"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "sas_triage")'`
Expected: PASS, 4 tests.

Note `.strip_variant_suffix("std_difma")` → `"std_dif"` because `ma` is the
last-listed suffix and `std_difma` ends in it. `"epsilon"` is unchanged: it
ends in no listed marker.

- [ ] **Step 5: Commit**

```bash
git add R/sas_triage.R tests/testthat/test-sas_triage.R
git commit -m "feat: public/private visibility classification for macro definitions"
```

---

## Task 6: `sas_triage()` — the rule ladder

**Files:**
- Modify: `R/sas_triage.R` (append the exported function)
- Test: `tests/testthat/test-sas_triage.R` (append)

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-sas_triage.R`:
```r
# ---------------------------------------------------------------------------
# sas_triage — file-level rules 1-3
# ---------------------------------------------------------------------------

test_that("rule 1 drops 'Copy of' files", {
  res <- sas_triage(fx_dir())
  row <- res[res$file == "Copy of alpha.sas", ]

  expect_equal(nrow(row), 1L)
  expect_equal(row$decision, "drop")
  expect_equal(row$rule, 1L)
  expect_match(row$evidence, "filename-prefix duplicate")
})

test_that("rule 2 drops editor backups", {
  res <- sas_triage(fx_dir())
  row <- res[res$file == "beta.sas~", ]

  expect_equal(row$decision, "drop")
  expect_equal(row$rule, 2L)
  expect_match(row$evidence, "editor backup")
})

test_that("rule 3 drops files failing lint, citing the failure", {
  res <- sas_triage(fx_dir())
  row <- res[res$file == "gamma_broken.sas", ]

  expect_equal(row$decision, "drop")
  expect_equal(row$rule, 3L)
  expect_match(row$evidence, "unbalanced quote")
})

test_that("rule 3 drops nomend.sas without erroring the whole run", {
  res <- sas_triage(fx_dir())
  row <- res[res$file == "nomend.sas", ]

  expect_equal(row$decision, "drop")
  expect_equal(row$rule, 3L)
  expect_match(row$evidence, "%macro/%mend")
})

# ---------------------------------------------------------------------------
# sas_triage — definition-level rules 4-6
# ---------------------------------------------------------------------------

test_that("rule 4 marks a singly-defined macro canonical", {
  res <- sas_triage(fx_dir())
  row <- res[res$macro == "epsilon", ]

  expect_equal(nrow(row), 1L)
  expect_equal(row$decision, "canonical")
  expect_equal(row$rule, 4L)
})

test_that("rule 5 marks identical redefinitions canonical", {
  res <- sas_triage(fx_dir())
  rows <- res[res$macro == "delta", ]

  expect_equal(nrow(rows), 2L)
  expect_true(all(rows$decision == "canonical"))
  expect_true(all(rows$rule == 5L))
  expect_match(rows$evidence[1], "2 identical copies")
})

test_that("rule 6 REFUSES to decide on divergent redefinitions", {
  res <- sas_triage(fx_dir())
  rows <- res[res$macro == "zeta", ]

  expect_equal(nrow(rows), 2L)
  expect_true(all(rows$decision == "ambiguous"))
  expect_true(all(rows$rule == 6L))
  expect_false(any(rows$decision == "canonical"))
  expect_match(rows$evidence[1], "2 distinct bodies")
})

test_that("multi-macro files contribute one row per definition", {
  res <- sas_triage(fx_dir())
  rows <- res[res$file == "multi.sas", ]

  expect_equal(nrow(rows), 3L)
  expect_setequal(rows$macro, c("helper_one", "helper_two", "multi"))
})

test_that("uppercase %MACRO is triaged, not skipped", {
  res <- sas_triage(fx_dir())
  expect_true("upper" %in% res$macro)
})

test_that("sas_triage errors on a directory with no .sas files", {
  d <- withr::local_tempdir()
  expect_error(sas_triage(d), "no \\.sas files")
})

test_that("sas_triage errors if any definition is unclassified", {
  # Force the failure path: a decision table with a hole must not pass silently.
  expect_error(
    hvtiRutilities:::.assert_no_unclassified(
      data.frame(macro = "x", decision = "unclassified",
                 stringsAsFactors = FALSE)
    ),
    "1 definition\\(s\\) unclassified"
  )
})

# ---------------------------------------------------------------------------
# sas_triage — overrides and idempotence
# ---------------------------------------------------------------------------

test_that("an override resolves an ambiguous macro", {
  ov <- withr::local_tempfile(fileext = ".yaml")
  yaml::write_yaml(list(list(
    macro          = "zeta",
    canonical_file = "zeta.sas",
    rationale      = "zeta.sas uses the _FREQ_ automatic variable.",
    decided_by     = "JE",
    decided_on     = "2026-07-10"
  )), ov)

  res <- sas_triage(fx_dir(), overrides = ov)
  rows <- res[res$macro == "zeta", ]

  expect_equal(rows$decision[rows$file == "zeta.sas"], "canonical")
  expect_equal(rows$decision[rows$file == "zeta_old.sas"], "drop")
  expect_match(rows$evidence[rows$file == "zeta.sas"], "override")
})

test_that("sas_triage is idempotent", {
  a <- sas_triage(fx_dir())
  b <- sas_triage(fx_dir())

  expect_identical(a, b)
})

test_that("an override naming an unknown macro errors", {
  ov <- withr::local_tempfile(fileext = ".yaml")
  yaml::write_yaml(list(list(
    macro = "does_not_exist", canonical_file = "nope.sas",
    rationale = "x", decided_by = "JE", decided_on = "2026-07-10"
  )), ov)

  expect_error(sas_triage(fx_dir(), overrides = ov), "does_not_exist")
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "sas_triage")'`
Expected: FAIL — `could not find function "sas_triage"`

- [ ] **Step 3: Write the implementation**

Append to `R/sas_triage.R`:
```r
## =============================================================================
## Internal: NULL-coalescing operator. Base R gained `%||%` in 4.4.0; this
## package declares R (>= 4.1.0), so define it here rather than raise the floor.
`%||%` <- function(x, y) if (is.null(x)) y else x

## =============================================================================
## Internal: refuse to return a decision table with holes in it.
.assert_no_unclassified <- function(tbl) {
  n <- sum(tbl$decision == "unclassified")
  if (n > 0L) {
    stop(
      n, " definition(s) unclassified: ",
      paste(unique(tbl$macro[tbl$decision == "unclassified"]), collapse = ", "),
      ". Every definition must carry a decision.",
      call. = FALSE
    )
  }
  invisible(tbl)
}

## =============================================================================
## Internal: read and validate the overrides file.
.read_overrides <- function(path) {
  if (is.null(path)) {
    return(list())
  }
  if (!file.exists(path)) {
    stop("Overrides file does not exist: ", path, call. = FALSE)
  }
  ov <- yaml::read_yaml(path)
  required <- c("macro", "canonical_file", "rationale", "decided_by", "decided_on")
  for (entry in ov) {
    missing <- setdiff(required, names(entry))
    if (length(missing) > 0L) {
      stop(
        "Override for '", entry$macro %||% "<unnamed>",
        "' is missing field(s): ", paste(missing, collapse = ", "),
        call. = FALSE
      )
    }
  }
  stats::setNames(ov, vapply(ov, function(e) tolower(e$macro), character(1)))
}

## =============================================================================
#' Triage a directory of legacy SAS macro files
#'
#' @description
#' Applies an ordered rule ladder to every `.sas` file in \code{dir} and returns
#' one row per macro definition, each carrying a \code{decision} and the
#' \code{evidence} that justifies it.
#'
#' @details
#' Only the top level of \code{dir} is scanned; subdirectories are ignored.
#'
#' File-level rules, applied first, in order:
#' \enumerate{
#'   \item \code{Copy of *} -- drop, as a filename-prefix duplicate.
#'   \item \code{*.sas~} -- drop, as an editor backup superseded by construction.
#'   \item Fails \code{.sas_lint()} -- drop, citing the specific lint failure.
#' }
#'
#' Definition-level rules, applied per macro name across surviving files:
#' \enumerate{
#'   \item[4.] Defined in exactly one file -- canonical.
#'   \item[5.] Defined in several files, all bodies hashing identically --
#'     canonical, recording every defining file.
#'   \item[6.] Defined in several files with two or more distinct bodies --
#'     \strong{ambiguous}. No canonical file is chosen.
#' }
#'
#' Rule 6 never auto-resolves. Modification dates and visibility are attached as
#' evidence for a human, never consumed as a tiebreaker, because a tool that
#' silently picks a winner launders a coin-flip into a committed artifact.
#' Filesystem mtime is deliberately never consulted: the corpus froze in 2019
#' and lives on a network volume where timestamps do not survive copies.
#'
#' Ambiguity is resolved by a human writing an entry into \code{overrides} and
#' re-running. This makes the result reproducible and auditable.
#'
#' @param dir Character. Path to a directory of `.sas` files. Use a local clone;
#'   the canonical library lives on a network volume where file operations are
#'   slow.
#' @param overrides Character or \code{NULL}. Path to a `macro_overrides.yaml`
#'   recording human decisions. Each entry requires \code{macro},
#'   \code{canonical_file}, \code{rationale}, \code{decided_by}, and
#'   \code{decided_on}.
#'
#' @return A \code{data.frame} with one row per macro definition and columns
#'   \code{file}, \code{macro}, \code{params}, \code{body_hash},
#'   \code{line_start}, \code{line_end}, \code{visibility}, \code{decision},
#'   \code{rule}, and \code{evidence}. Rows are sorted by \code{macro} then
#'   \code{file}, so the result is deterministic.
#'
#' @export sas_triage
#'
#' @examples
#' \donttest{
#' d <- system.file("extdata", "macros", package = "hvtiRutilities")
#' if (nzchar(d)) sas_triage(d)
#' }
#'
#' @importFrom stats setNames
sas_triage <- function(dir, overrides = NULL) {
  files <- list.files(dir, pattern = "\\.sas~?$", ignore.case = TRUE,
                      full.names = TRUE)
  if (length(files) == 0L) {
    stop("no .sas files found in: ", dir, call. = FALSE)
  }
  ov <- .read_overrides(overrides)

  dropped <- list()
  kept <- character(0)

  ## --- file-level rules 1-3 -------------------------------------------------
  for (f in files) {
    b <- basename(f)

    if (grepl("^Copy of ", b)) {
      dropped[[b]] <- list(rule = 1L, evidence = "filename-prefix duplicate")
    } else if (grepl("~$", b)) {
      dropped[[b]] <- list(
        rule = 2L,
        evidence = "editor backup, superseded by construction"
      )
    } else {
      lint <- .sas_lint(f)
      if (!lint$valid) {
        dropped[[b]] <- list(
          rule = 3L,
          evidence = paste("lint:", paste(lint$failures, collapse = "; "))
        )
      } else {
        kept <- c(kept, f)
      }
    }
  }

  drop_rows <- if (length(dropped) == 0L) {
    NULL
  } else {
    do.call(rbind, lapply(names(dropped), function(b) {
      data.frame(
        file = b, macro = NA_character_, params = NA_character_,
        body_hash = NA_character_, line_start = NA_integer_,
        line_end = NA_integer_, visibility = NA_character_,
        decision = "drop", rule = dropped[[b]]$rule,
        evidence = dropped[[b]]$evidence, stringsAsFactors = FALSE
      )
    }))
  }

  ## --- extract definitions from surviving files -----------------------------
  defs <- do.call(rbind, lapply(kept, sas_macro_defs))
  defs$visibility <- mapply(.classify_visibility, defs$macro, defs$file,
                            USE.NAMES = FALSE)
  defs$decision <- "unclassified"
  defs$rule <- NA_integer_
  defs$evidence <- NA_character_

  ## --- definition-level rules 4-6 -------------------------------------------
  for (m in unique(defs$macro)) {
    idx <- which(defs$macro == m)
    n_files <- length(unique(defs$file[idx]))
    n_bodies <- length(unique(defs$body_hash[idx]))

    if (n_files == 1L) {
      defs$decision[idx] <- "canonical"
      defs$rule[idx] <- 4L
      defs$evidence[idx] <- "defined once"
    } else if (n_bodies == 1L) {
      defs$decision[idx] <- "canonical"
      defs$rule[idx] <- 5L
      defs$evidence[idx] <- sprintf("%d identical copies", n_files)
    } else {
      defs$decision[idx] <- "ambiguous"
      defs$rule[idx] <- 6L
      defs$evidence[idx] <- sprintf(
        "%d distinct bodies across %d files; human decision required",
        n_bodies, n_files
      )
    }
  }

  ## --- apply human overrides ------------------------------------------------
  for (m in names(ov)) {
    idx <- which(defs$macro == m)
    if (length(idx) == 0L) {
      stop("Override names unknown macro: ", m, call. = FALSE)
    }
    canon <- ov[[m]]$canonical_file
    if (!canon %in% defs$file[idx]) {
      stop(
        "Override for '", m, "' names canonical_file '", canon,
        "', which does not define it.", call. = FALSE
      )
    }
    win <- idx[defs$file[idx] == canon]
    lose <- setdiff(idx, win)

    defs$decision[win] <- "canonical"
    defs$evidence[win] <- paste0("override: ", ov[[m]]$rationale)
    defs$decision[lose] <- "drop"
    defs$evidence[lose] <- paste0("override: superseded by ", canon)
  }

  out <- rbind(defs, drop_rows)
  .assert_no_unclassified(out)

  out <- out[order(out$macro, out$file, na.last = TRUE), , drop = FALSE]
  rownames(out) <- NULL
  out
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Rscript -e 'roxygen2::roxygenise(); devtools::test(filter = "sas_triage")'`
Expected: PASS, 18 tests — the 4 visibility tests from Task 5 live in the same
file and run under the same filter.

- [ ] **Step 5: Commit**

```bash
git add R/sas_triage.R tests/testthat/test-sas_triage.R NAMESPACE man/
git commit -m "feat: sas_triage() rule ladder; rule 6 refuses to auto-resolve"
```

---

## Task 7: `write_macro_manifest()` and the collision report

**Files:**
- Create: `R/write_macro_manifest.R`
- Test: `tests/testthat/test-write_macro_manifest.R`

- [ ] **Step 1: Write the failing tests**

`tests/testthat/test-write_macro_manifest.R`:
```r
library(testthat)
library(hvtiRutilities)

fx_dir <- function() testthat::test_path("fixtures")

test_that("write_macro_manifest round-trips the canonical set", {
  tbl <- sas_triage(fx_dir())
  p <- withr::local_tempfile(fileext = ".yaml")

  write_macro_manifest(tbl, p)
  back <- yaml::read_yaml(p)

  macros <- vapply(back$macros, function(e) e$macro, character(1))
  expect_true("epsilon" %in% macros)
  expect_true("zeta" %in% macros)
})

test_that("manifest is byte-for-byte stable across runs", {
  tbl <- sas_triage(fx_dir())
  p1 <- withr::local_tempfile(fileext = ".yaml")
  p2 <- withr::local_tempfile(fileext = ".yaml")

  write_macro_manifest(tbl, p1)
  write_macro_manifest(tbl, p2)

  expect_identical(
    digest::digest(p1, algo = "sha256", file = TRUE),
    digest::digest(p2, algo = "sha256", file = TRUE)
  )
})

test_that("manifest contains no timestamp", {
  tbl <- sas_triage(fx_dir())
  p <- withr::local_tempfile(fileext = ".yaml")
  write_macro_manifest(tbl, p)

  txt <- paste(readLines(p), collapse = "\n")
  expect_false(grepl(format(Sys.Date(), "%Y-%m-%d"), txt))
})

test_that("ambiguous macros are recorded with their distinct bodies", {
  tbl <- sas_triage(fx_dir())
  p <- withr::local_tempfile(fileext = ".yaml")
  write_macro_manifest(tbl, p)
  back <- yaml::read_yaml(p)

  zeta <- Filter(function(e) e$macro == "zeta", back$macros)[[1]]
  expect_equal(zeta$status, "ambiguous")
  expect_equal(length(zeta$candidates), 2L)
})

test_that("write_collision_report lists every multiply-defined macro", {
  tbl <- sas_triage(fx_dir())
  p <- withr::local_tempfile(fileext = ".md")

  write_collision_report(tbl, p)
  txt <- paste(readLines(p), collapse = "\n")

  expect_match(txt, "zeta")
  expect_match(txt, "delta")
  expect_false(grepl("\\bepsilon\\b", txt))
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "write_macro_manifest")'`
Expected: FAIL — `could not find function "write_macro_manifest"`

- [ ] **Step 3: Write the implementation**

`R/write_macro_manifest.R`:
```r
## =============================================================================
#' Write the canonical macro manifest
#'
#' @description
#' Serialises a \code{sas_triage()} decision table to YAML, one entry per macro
#' name, recording its status and every file that defines it.
#'
#' @details
#' The manifest deliberately contains \strong{no timestamp}. It describes a
#' frozen 2019 corpus, and a generated-on field would defeat the byte-for-byte
#' reproducibility that makes the manifest trustworthy as a reviewed artifact.
#' Run metadata belongs in the report, not here. This diverges from
#' \code{\link{update_manifest}}, whose \code{extract_date} is meaningful
#' because the datasets it tracks genuinely change over time.
#'
#' @param x A \code{data.frame} returned by \code{\link{sas_triage}}.
#' @param path Character. Destination `.yaml` path.
#'
#' @return Invisibly, \code{path}.
#'
#' @export write_macro_manifest
#'
#' @examples
#' \donttest{
#' d <- system.file("extdata", "macros", package = "hvtiRutilities")
#' if (nzchar(d)) {
#'   write_macro_manifest(sas_triage(d), tempfile(fileext = ".yaml"))
#' }
#' }
write_macro_manifest <- function(x, path) {
  # File-level drop rows (rules 1-3) carry macro = "" so that base-R
  # `df[df$macro == name, ]` subsetting in the tests does not inject phantom
  # NA rows. Real macro definitions always have a non-empty name, so nzchar()
  # cleanly separates definitions from whole-file drops.
  defs <- x[!is.na(x$macro) & nzchar(x$macro), , drop = FALSE]
  macros <- sort(unique(defs$macro))

  entries <- lapply(macros, function(m) {
    rows <- defs[defs$macro == m, , drop = FALSE]
    rows <- rows[order(rows$file), , drop = FALSE]

    status <- if (any(rows$decision == "ambiguous")) {
      "ambiguous"
    } else {
      "canonical"
    }

    list(
      macro      = m,
      status     = status,
      rule       = as.integer(rows$rule[1L]),
      visibility = rows$visibility[1L],
      params     = rows$params[1L],
      candidates = lapply(seq_len(nrow(rows)), function(i) {
        list(
          file      = rows$file[i],
          body_hash = substr(rows$body_hash[i], 1L, 16L),
          decision  = rows$decision[i],
          evidence  = rows$evidence[i]
        )
      })
    )
  })

  yaml::write_yaml(list(macros = entries), path)
  invisible(path)
}

## =============================================================================
#' Write the macro name-collision report
#'
#' @description
#' Reports every macro name defined in more than one file, with its distinct
#' body count and defining files. In SAS, `%include`-ing two files that define
#' the same macro means the second silently shadows the first, so this report
#' is a prerequisite for building a trustworthy SAS harness.
#'
#' @param x A \code{data.frame} returned by \code{\link{sas_triage}}.
#' @param path Character. Destination `.md` path.
#'
#' @return Invisibly, \code{path}.
#'
#' @export write_collision_report
#'
#' @examples
#' \donttest{
#' d <- system.file("extdata", "macros", package = "hvtiRutilities")
#' if (nzchar(d)) {
#'   write_collision_report(sas_triage(d), tempfile(fileext = ".md"))
#' }
#' }
write_collision_report <- function(x, path) {
  # nzchar() excludes file-level drop rows (macro = ""); see write_macro_manifest.
  defs <- x[!is.na(x$macro) & nzchar(x$macro), , drop = FALSE]

  counts <- table(defs$macro)
  multi <- sort(names(counts[counts > 1L]))

  lines <- c(
    "# SAS macro name-collision report",
    "",
    "Macro names defined in more than one file. In SAS, `%include`-ing two",
    "such files means the second definition silently shadows the first.",
    "",
    "| Macro | Files | Distinct bodies | Visibility | Status |",
    "|---|---|---|---|---|"
  )

  for (m in multi) {
    rows <- defs[defs$macro == m, , drop = FALSE]
    status <- if (any(rows$decision == "ambiguous")) "**ambiguous**" else "canonical"
    lines <- c(lines, sprintf(
      "| `%s` | %d | %d | %s | %s |",
      m, length(unique(rows$file)), length(unique(rows$body_hash)),
      rows$visibility[1L], status
    ))
  }

  lines <- c(lines, "", sprintf("Total colliding names: %d", length(multi)))
  writeLines(lines, path)
  invisible(path)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Rscript -e 'roxygen2::roxygenise(); devtools::test(filter = "write_macro_manifest")'`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add R/write_macro_manifest.R tests/testthat/test-write_macro_manifest.R NAMESPACE man/
git commit -m "feat: write_macro_manifest() and write_collision_report()"
```

---

## Task 8: Record subdirectory exclusions

**Files:**
- Modify: `R/sas_triage.R` (add `.scan_excluded_dirs()`, call it from `sas_triage()`)
- Modify: `R/write_macro_manifest.R` (emit exclusions into the report)
- Test: `tests/testthat/test-sas_triage.R` (append)

The spec requires that excluded subdirectories be "recorded in the manifest, not
silently dropped." `sas_triage()` uses non-recursive `list.files()`, so it never
sees them. A directory of 79 `.sas` files that no artifact mentions is exactly
the silent omission the spec forbids.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-sas_triage.R`:
```r
# ---------------------------------------------------------------------------
# Subdirectory exclusions are recorded, not silently dropped
# ---------------------------------------------------------------------------

test_that(".scan_excluded_dirs counts .sas files in each subdirectory", {
  d <- withr::local_tempdir()
  writeLines("%macro top; %mend top;", file.path(d, "top.sas"))
  dir.create(file.path(d, "archive"))
  writeLines("%macro a; %mend a;", file.path(d, "archive", "a.sas"))
  writeLines("%macro b; %mend b;", file.path(d, "archive", "b.sas"))

  res <- hvtiRutilities:::.scan_excluded_dirs(d)

  expect_equal(nrow(res), 1L)
  expect_equal(res$directory, "archive")
  expect_equal(res$n_sas, 2L)
})

test_that("sas_triage attaches excluded directories as an attribute", {
  res <- sas_triage(fx_dir())
  ex <- attr(res, "excluded_dirs")

  expect_s3_class(ex, "data.frame")
  expect_true(all(c("directory", "n_sas") %in% names(ex)))
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "sas_triage")'`
Expected: FAIL — `'.scan_excluded_dirs' is not an exported object`

- [ ] **Step 3: Write the implementation**

Append to `R/sas_triage.R`:
```r
## =============================================================================
## Internal: enumerate immediate subdirectories and count the .sas files they
## hold. sas_triage() scans only the top level; these counts are recorded so
## that excluded files are visible in the artifacts rather than silently absent.
.scan_excluded_dirs <- function(dir) {
  subs <- list.dirs(dir, recursive = FALSE, full.names = TRUE)
  if (length(subs) == 0L) {
    return(data.frame(
      directory = character(0), n_sas = integer(0),
      stringsAsFactors = FALSE
    ))
  }

  counts <- vapply(subs, function(s) {
    length(list.files(s, pattern = "\\.sas$", ignore.case = TRUE,
                      recursive = TRUE))
  }, integer(1))

  out <- data.frame(
    directory = basename(subs),
    n_sas     = as.integer(counts),
    stringsAsFactors = FALSE
  )
  out <- out[order(out$directory), , drop = FALSE]
  rownames(out) <- NULL
  out
}
```

In `sas_triage()`, immediately before the final `out` is returned, replace:

```r
  out <- out[order(out$macro, out$file, na.last = TRUE), , drop = FALSE]
  rownames(out) <- NULL
  out
}
```

with:

```r
  out <- out[order(out$macro, out$file, na.last = TRUE), , drop = FALSE]
  rownames(out) <- NULL
  attr(out, "excluded_dirs") <- .scan_excluded_dirs(dir)
  out
}
```

- [ ] **Step 4: Surface exclusions in the collision report**

In `R/write_macro_manifest.R`, inside `write_collision_report()`, replace:

```r
  lines <- c(lines, "", sprintf("Total colliding names: %d", length(multi)))
  writeLines(lines, path)
  invisible(path)
```

with:

```r
  lines <- c(lines, "", sprintf("Total colliding names: %d", length(multi)))

  ex <- attr(x, "excluded_dirs")
  if (!is.null(ex) && nrow(ex) > 0L) {
    lines <- c(
      lines, "", "## Excluded subdirectories", "",
      "Not triaged. Counts recorded so the omission is visible.", "",
      "| Directory | `.sas` files |", "|---|---|",
      sprintf("| `%s` | %d |", ex$directory, ex$n_sas)
    )
  }

  writeLines(lines, path)
  invisible(path)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "sas_triage")'`
Expected: PASS, 20 tests.

Note: `tests/testthat/fixtures/` has no subdirectories, so
`attr(res, "excluded_dirs")` is a zero-row data frame there. The first test
builds its own temp directory to exercise the counting path.

- [ ] **Step 6: Commit**

```bash
git add R/sas_triage.R R/write_macro_manifest.R tests/testthat/test-sas_triage.R
git commit -m "feat: record excluded subdirectories rather than silently skipping them"
```

---

## Task 9: Full test suite and R CMD check

**Files:**
- Modify: `DESCRIPTION` (add `digest` if absent from Imports — verify)

- [ ] **Step 1: Confirm `digest` and `yaml` are in Imports**

```bash
sed -n '/^Imports:/,/^Suggests:/p' DESCRIPTION
```

Expected: both `digest` and `yaml` listed. They are, per the current
`DESCRIPTION`. No change needed.

- [ ] **Step 2: Run the whole suite**

Run: `Rscript -e 'devtools::test()'`
Expected: PASS. No regressions in the 15 pre-existing test files.

- [ ] **Step 3: Run R CMD check**

Run: `Rscript -e 'devtools::check(document = TRUE)'`
Expected: 0 errors, 0 warnings, 0 notes.

If a note appears for undocumented `\value` on the new exports, fix it — every
exported object needs `@return`, per the CRAN Cookbook. All five exports above
declare one.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: full check clean for macro canonicalization functions"
```

---

## Task 10: Run against the real corpus

**Files:**
- Create: `specs/artifacts/macro_manifest.yaml`
- Create: `specs/artifacts/macro_signatures.yaml`
- Create: `specs/artifacts/collision_report.md`
- Create: `specs/artifacts/macro_overrides.yaml`

This is where the tool meets the 179 files. It will produce ambiguities — that
is the correct outcome, not a failure. Expect rule 6 to fire for `skip` (11
distinct bodies), `std_dif` (5), `mrg` (2), `numobs` (2), `dist` (2), and much
of the remaining 85 multiply-defined names.

- [ ] **Step 1: Clone the macro library locally**

The canonical copy is on a network volume where `git log --follow` timed out at
120 seconds. Work on a local clone.

```bash
git clone /Volumes/qhsprograms/apps/sas/macro.library /tmp/macro.library
ls /tmp/macro.library/*.sas | wc -l
```

Expected: `179`.

Note: the clone will contain only *tracked* files. 24 `.sas` files are
untracked in the source repo and will be absent. Copy them across explicitly:

```bash
rsync -a --include='*.sas' --include='*.sas~' --include='*.SAS~' \
      --exclude='*' /Volumes/qhsprograms/apps/sas/macro.library/ /tmp/macro.library/
ls /tmp/macro.library/*.sas | wc -l
```

Expected: `179` (tracked + untracked, top level only).

- [ ] **Step 2: Run triage with no overrides and inspect**

```bash
Rscript -e '
  devtools::load_all(".")
  tbl <- try(sas_triage("/tmp/macro.library"), silent = TRUE)
  if (inherits(tbl, "try-error")) { cat(conditionMessage(attr(tbl, "condition")), "\n"); quit(status = 1) }
  cat("definitions:", nrow(tbl), "\n")
  print(table(tbl$decision, useNA = "ifany"))
  print(table(tbl$rule, useNA = "ifany"))
'
```

Expected: roughly 451 definition rows plus ~29 file-level `drop` rows.
`decision` shows a non-zero `ambiguous` count. Zero `unclassified` — if any
appear, `sas_triage()` will have errored, which is the designed behaviour.

- [ ] **Step 3: Emit the collision report for human review**

```bash
Rscript -e '
  devtools::load_all(".")
  tbl <- sas_triage("/tmp/macro.library")
  dir.create("specs/artifacts", showWarnings = FALSE, recursive = TRUE)
  write_collision_report(tbl, "specs/artifacts/collision_report.md")
'
head -20 specs/artifacts/collision_report.md
```

Expected: a table whose rows include `skip` with 14 files / 11 distinct bodies,
and `std_dif` with 5 / 5. Below it, an "Excluded subdirectories" table listing
`archive` (20), `tests` (17), `table_mac` (17), `readin_samples` (17),
`logis_reclassi` (4), `repeat_test` (2), `macros_to_test` (2) — 79 `.sas` files
accounted for rather than silently absent.

- [ ] **Step 4: Emit the signature database**

```bash
Rscript -e '
  devtools::load_all(".")
  files <- list.files("/tmp/macro.library", pattern = "\\.sas$", full.names = TRUE)
  sigs <- do.call(rbind, lapply(files, sas_macro_signature))
  yaml::write_yaml(
    lapply(seq_len(nrow(sigs)), function(i) as.list(sigs[i, ])),
    "specs/artifacts/macro_signatures.yaml"
  )
'
```

- [ ] **Step 5: STOP. Human review gate.**

Rule 6 fired. Every `ambiguous` macro now needs a human decision written into
`specs/artifacts/macro_overrides.yaml`. This is not automatable and must not be
automated — that is the entire point of the design.

Seed the file with the one decision already established during design:

`specs/artifacts/macro_overrides.yaml`:
```yaml
- macro: cr_compare_cp
  canonical_file: CR_compare_CP.sas
  rationale: >
    CR_compare_CP_old.sas uses `keep freq tau`; the SAS automatic variable is
    `_FREQ_`, so the _old variant silently produces wrong counts.
    CR_compare_CP_test_AT.sas has unbalanced quotes and cannot compile.
  decided_by: JE
  decided_on: 2026-07-10
```

Present the collision report to the maintainer. Do not proceed until every
`ambiguous` macro has an entry.

- [ ] **Step 6: Re-run with overrides and confirm zero ambiguity**

```bash
Rscript -e '
  devtools::load_all(".")
  tbl <- sas_triage("/tmp/macro.library",
                    overrides = "specs/artifacts/macro_overrides.yaml")
  stopifnot(!any(tbl$decision == "ambiguous"))
  write_macro_manifest(tbl, "specs/artifacts/macro_manifest.yaml")
  write_collision_report(tbl, "specs/artifacts/collision_report.md")
  cat("canonical definitions:", sum(tbl$decision == "canonical"), "\n")
'
```

Expected: no error; `macro_manifest.yaml` written.

- [ ] **Step 7: Verify byte-for-byte reproducibility**

```bash
Rscript -e '
  devtools::load_all(".")
  tbl <- sas_triage("/tmp/macro.library", overrides = "specs/artifacts/macro_overrides.yaml")
  write_macro_manifest(tbl, "/tmp/m2.yaml")
' 
cmp specs/artifacts/macro_manifest.yaml /tmp/m2.yaml && echo "IDENTICAL"
```

Expected: `IDENTICAL`.

- [ ] **Step 8: Commit the artifacts**

```bash
git add specs/artifacts
git commit -m "chore: canonical macro manifest, signatures, and collision report"
```

---

## Success criteria

Verify each before declaring Phase 0 done:

- [ ] Every macro definition carries a `decision` and `evidence`.
- [ ] Zero definitions are `unclassified` (enforced by `.assert_no_unclassified()`).
- [ ] Every `ambiguous` macro has an entry in `macro_overrides.yaml`.
- [ ] `sas_triage()` reproduces `macro_manifest.yaml` byte-for-byte (Task 10 Step 7).
- [ ] All 79 `.sas` files in excluded subdirectories are counted in the report.
- [ ] No macro is declared canonical by a heuristic tiebreaker — grep the source
      for any use of `file.mtime`, `modified_on`, or `created_on` in
      `R/sas_triage.R` and confirm none influence `decision`.
- [ ] `collision_report.md` accounts for all 85 multiply-defined names.
- [ ] `devtools::check()` is 0/0/0.
