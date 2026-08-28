# Job-Type Inventory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `hvtiRutilities` a filename-only corpus sweep — `job_files()` and `job_census()` — that answers "which studies have run which job types, and how many" across `/studies`, replacing a hand-count.

**Architecture:** Two packages, two PRs, in order. PR 1 moves `hvti_taxonomy()`/`hvti_non_prefixes()` down from `hvtiRtemplates` into `hvtiRutilities` and builds the sweep on top of them. PR 2 deletes the originals and re-exports them from the new home, so `hvtiRtemplates`' public surface is unchanged. The sweep is built from three small internal helpers — a name parser, a placement resolver, a row assembler — each independently tested, then a roll-up and a print method.

**Tech Stack:** R (≥ 4.1.0), roxygen2 8.1.0, testthat edition 3, `withr` for temp dirs in tests, base R for the sweep (no dplyr — the sweep is vectorised base and adding NSE here buys nothing).

**Spec:** `dev/specs/2026-08-26-job-type-inventory-design.md`. Read it before Task 1.

## Global Constraints

- **Versions are patch bumps only.** `hvtiRutilities` 1.1.0 → **1.1.1**; `hvtiRtemplates` 1.0.3 → **1.0.4**. Never roll the minor or major digit. Always a straight three-digit version — no `.9000`, no fourth digit.
- **`DESCRIPTION` and `NEWS.md` are updated in the same commit.** A test greps `NEWS.md` for the exact `DESCRIPTION` version. `DESCRIPTION` line 4 is `Version:`; `NEWS.md` line 1 is `# <package> <version>`.
- **Never commit to `main`.** PR 1 is on branch `feat/job-type-inventory` in `hvtiRutilities`; PR 2 is on `refactor/taxonomy-from-utilities` in `hvtiRtemplates`. Open PRs with `gh pr create` and let the user merge.
- **Do not touch the study tree.** `/Volumes/qhsstudies/...` and `/studies` are read-only for this work. `preserve_root` carries a stray 2023 `.git` with no remote — never branch or commit there.
- **No file contents are read.** The sweep is filename-only: no `.lst` parsing, no `TemporalHazard` dependency, no `readLines()` on corpus files.
- **`prefix` is not "split on the first dot".** Parsers run in the fixed order `set`, `template`, `r_transitional`, `legacy`, first match wins. `legacy` must be last — it is permissive enough to match `03.01-ac.qmd` as prefix `03`.
- **No extension allowlist**, ever. See spec §4.4.
- **Nothing is dropped.** Every candidate file is a row; placement and classification are columns.
- Tests use `withr::local_tempdir()` and build their own fixtures. No test may touch `/studies` or require a network mount.
- Style: match the surrounding code. Comments explain *why*, not *what*. Roxygen `@return` on every exported object.

---

## File Structure

**PR 1 — `hvtiRutilities`**

| file | responsibility |
|---|---|
| `R/taxonomy.R` (create) | `hvti_taxonomy()`, `hvti_non_prefixes()` — moved verbatim from `hvtiRtemplates` |
| `R/job_names.R` (create) | `.job_name_fields()` — one basename → `naming`, `prefix`, `is_template` |
| `R/job_census.R` (create) | `.job_placement()`, `job_files()`, `job_census()`, `print.hvti_job_census()` |
| `tests/testthat/test-taxonomy.R` (create) | the three table-only blocks moved from `hvtiRtemplates` |
| `tests/testthat/helper-corpus.R` (create) | `make_corpus_fixture()` — the synthetic tree every sweep test uses |
| `tests/testthat/test-job-names.R` (create) | parser behaviour and parser ORDER |
| `tests/testthat/test-job-files.R` (create) | placement, status, depth, classification, the full row |
| `tests/testthat/test-job-census.R` (create) | roll-up counts and print output |
| `DESCRIPTION`, `NEWS.md`, `_pkgdown.yml` (modify) | version, entry, reference index |

**PR 2 — `hvtiRtemplates`**

| file | responsibility |
|---|---|
| `R/taxonomy.R` (delete) | contents now live in `hvtiRutilities` |
| `R/reexports.R` (create) | `@importFrom` + `@export` for both functions |
| `tests/testthat/test-taxonomy.R` (modify) | drop the three moved blocks, keep six |
| `DESCRIPTION`, `NEWS.md` (modify) | `Imports: hvtiRutilities`, version, entry |

---

# PR 1 — `hvtiRutilities`

### Task 1: Move the taxonomy down

**Files:**
- Create: `/Users/ehrlinj/Documents/GitHub/hvtiRutilities/R/taxonomy.R`
- Create: `/Users/ehrlinj/Documents/GitHub/hvtiRutilities/tests/testthat/test-taxonomy.R`
- Modify: `/Users/ehrlinj/Documents/GitHub/hvtiRutilities/_pkgdown.yml`

**Interfaces:**
- Consumes: nothing.
- Produces: `hvti_taxonomy()` → `data.frame` with columns `prefix`, `name`, `folder`, `description`; `prefix` is `NA_character_` for exactly the `estimates` row. `hvti_non_prefixes()` → `character` vector.

- [ ] **Step 1: Create the branch**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRutilities
git checkout main && git pull
git checkout -b feat/job-type-inventory
```

- [ ] **Step 2: Copy the taxonomy source verbatim**

Copy the file unchanged — do not retype it, do not reformat it, do not "improve" the table.

```bash
cp /Users/ehrlinj/Documents/GitHub/hvtiRtemplates/R/taxonomy.R \
   /Users/ehrlinj/Documents/GitHub/hvtiRutilities/R/taxonomy.R
```

- [ ] **Step 3: Write the moved tests**

Create `tests/testthat/test-taxonomy.R` with exactly the three table-only blocks. The other six blocks in the source file call `template_list()` and stay in `hvtiRtemplates` — do not copy them.

```r
library(testthat)
library(hvtiRutilities)

test_that("hvti_taxonomy() has the expected shape", {
  tx <- hvti_taxonomy()
  expect_s3_class(tx, "data.frame")
  expect_named(tx, c("prefix", "name", "folder", "description"))
  expect_gt(nrow(tx), 25)
  expect_false(any(duplicated(tx$prefix)))
  expect_true(all(nzchar(tx$description)))
})

test_that("the taxonomy and the non-prefix list are disjoint", {
  expect_equal(intersect(hvti_taxonomy()$prefix, hvti_non_prefixes()),
               character(0))
})

test_that("exactly the artifact-kind rows have an NA prefix", {
  # `folder` names two things: for most rows it is an analysis type's home
  # folder, matched to a real prefix; `estimates` is an artifact kind with no
  # analysis that produces it, so its prefix is NA. This pins that mapping
  # down explicitly -- without it, a future row could pick up an NA prefix by
  # typo, or a real prefix could silently go missing, and nothing here would
  # notice.
  tx <- hvti_taxonomy()
  artifact_kind_folders <- c("estimates")
  expect_equal(is.na(tx$prefix), tx$folder %in% artifact_kind_folders)
})
```

- [ ] **Step 4: Regenerate docs and run the tests**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRutilities
Rscript -e 'devtools::document()'
Rscript -e 'devtools::test(filter = "taxonomy")'
```

Expected: 3 tests, all PASS. `NAMESPACE` gains `export(hvti_non_prefixes)` and `export(hvti_taxonomy)`.

- [ ] **Step 5: Index both functions in `_pkgdown.yml`**

An exported function absent from `_pkgdown.yml` makes `pkgdown::build_site()` warn. Insert this block immediately **before** the existing `- title: Package Utilities` block (around line 146):

```yaml
- title: Analysis Taxonomy
  desc: The two-letter prefix system inherited from the CORR analysis binder
  contents:
  - hvti_taxonomy
  - hvti_non_prefixes

```

- [ ] **Step 6: Commit**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRutilities
git add R/taxonomy.R tests/testthat/test-taxonomy.R man/ NAMESPACE _pkgdown.yml
git commit -m "feat: move hvti_taxonomy() and hvti_non_prefixes() in from hvtiRtemplates

The prefix table is shared vocabulary, not template machinery, and
hvtiRutilities is the lower layer. The alternative -- hvtiRutilities
importing hvtiRtemplates -- inverts the layering and sets up a cycle.

Only the three table-only tests move. The six that call template_list()
assert the installed templates agree with the taxonomy, which is a claim
hvtiRtemplates makes about its own inst/ and does not travel.

hvtiRtemplates still defines these; its copy is deleted in its own PR, so
there is no window where the table exists twice."
```

---

### Task 2: The filename parsers

**Files:**
- Create: `/Users/ehrlinj/Documents/GitHub/hvtiRutilities/R/job_names.R`
- Test: `/Users/ehrlinj/Documents/GitHub/hvtiRutilities/tests/testthat/test-job-names.R`

**Interfaces:**
- Consumes: nothing.
- Produces: `.job_name_fields(basenames)` — internal, **vectorised**. Takes a character vector of basenames, returns a `data.frame` with `nrow() == length(basenames)` and columns `naming` (chr), `prefix` (chr), `is_template` (lgl). All three are `NA` / `FALSE` for a name no parser claims.

Four conventions are live in the corpus. See spec §4.2 for why each exists and why the order is fixed.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-job-names.R`:

```r
library(testthat)
library(hvtiRutilities)

test_that("the legacy SAS convention yields the leading dot-field", {
  out <- hvtiRutilities:::.job_name_fields("hz.dead.lst")
  expect_equal(out$naming, "legacy")
  expect_equal(out$prefix, "hz")
  expect_false(out$is_template)
})

test_that("a tp. marker is stripped first and recorded", {
  # Without stripping first, tp.hz.dead.lst classifies as prefix "tp", which
  # both loses that it is an hz template and collides with the exclusion rule.
  out <- hvtiRutilities:::.job_name_fields("tp.hz.dead.lst")
  expect_equal(out$prefix, "hz")
  expect_true(out$is_template)
})

test_that("prefixes are not assumed two characters wide", {
  # vars, rfsrc, rfc and rfs are all in hvti_taxonomy().
  out <- hvtiRutilities:::.job_name_fields(c("vars.temp.sas", "rfsrc.surv.R"))
  expect_equal(out$prefix, c("vars", "rfsrc"))
})

test_that("the set convention is parsed, parity variant included", {
  out <- hvtiRutilities:::.job_name_fields(
    c("dead_pa-hz-03.01-ac.qmd", "dead_pa-hz-03.01-ac-parity.qmd")
  )
  expect_equal(out$naming, c("set", "set"))
  expect_equal(out$prefix, c("ac", "ac"))
})

test_that("the template convention is parsed", {
  out <- hvtiRutilities:::.job_name_fields("03.01-ac.qmd")
  expect_equal(out$naming, "template")
  expect_equal(out$prefix, "ac")
})

test_that("preserve_root's transitional R jobs are parsed, parity included", {
  out <- hvtiRutilities:::.job_name_fields(
    c("02-hz-dead_pa.qmd", "01-ac-dead_pa-parity.qmd")
  )
  expect_equal(out$naming, c("r_transitional", "r_transitional"))
  expect_equal(out$prefix, c("hz", "ac"))
})

test_that("legacy runs LAST -- it would otherwise shadow the template form", {
  # This is the whole reason the order is fixed. The legacy pattern happily
  # reads 03.01-ac.qmd as prefix "03". If this test fails, the parser order
  # has been rearranged and every R job in the corpus is misclassified.
  out <- hvtiRutilities:::.job_name_fields("03.01-ac.qmd")
  expect_equal(out$prefix, "ac")
  expect_false(identical(out$prefix, "03"))
})

test_that("a name no parser claims survives as NA rather than erroring", {
  out <- hvtiRutilities:::.job_name_fields(c("shape-census.R", "Makefile"))
  expect_true(all(is.na(out$naming)))
  expect_true(all(is.na(out$prefix)))
  expect_false(any(out$is_template))
})

test_that("the parser is vectorised and order-preserving", {
  out <- hvtiRutilities:::.job_name_fields(
    c("hz.dead.lst", "Makefile", "03.01-ac.qmd")
  )
  expect_equal(nrow(out), 3L)
  expect_equal(out$naming, c("legacy", NA, "template"))
})
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRutilities
Rscript -e 'devtools::test(filter = "job-names")'
```

Expected: every test ERRORs with `object '.job_name_fields' not found`.

- [ ] **Step 3: Write the implementation**

Create `R/job_names.R`:

```r
# Parsing a job filename into its prefix.
#
# Four naming conventions are live in the corpus at once, and they are not
# variations on one pattern -- see
# specs/2026-08-26-job-type-inventory-design.md section 4.2. Each gets its own
# anchored regex, and the parsers run most-specific-first.
#
# The order is load-bearing, not stylistic. `legacy` is permissive enough to
# match almost any dotted name -- it reads "03.01-ac.qmd" as prefix "03" --
# so it must run last or it shadows the three R-side patterns and every R job
# in the corpus is misclassified. test-job-names.R pins this.

# One row per input basename, in input order. `naming` and `prefix` are NA for
# a name no parser claims; the row still exists, because a file this sweep
# cannot classify must remain findable rather than vanish.
.job_name_fields <- function(basenames) {
  n <- length(basenames)
  naming <- rep(NA_character_, n)
  prefix <- rep(NA_character_, n)
  is_template <- rep(FALSE, n)

  # A leading `tp.` marks a template that is not meant to be run. Strip it
  # before any parser sees the name, so the real prefix is what gets matched.
  marked <- grepl("^tp[.]", basenames)
  stripped <- sub("^tp[.]", "", basenames)
  is_template <- marked

  patterns <- list(
    # <endpoint>-<type>-<NN>.<MM>-<prefix>[-parity].qmd
    set            = "^[A-Za-z0-9_]+-[A-Za-z0-9_]+-\\d{2}[.]\\d{2}-([A-Za-z0-9]+)(?:-parity)?[.]qmd$",
    # <NN>.<MM>-<prefix>.qmd
    template       = "^\\d{2}[.]\\d{2}-([A-Za-z0-9]+)[.]qmd$",
    # <NN>-<prefix>-<endpoint>[-parity].qmd
    r_transitional = "^\\d{2}-([A-Za-z0-9]+)-[A-Za-z0-9_]+(?:-parity)?[.]qmd$",
    # <prefix>.<anything>.<ext>
    legacy         = "^([A-Za-z0-9_]+)[.].+$"
  )

  for (nm in names(patterns)) {
    todo <- is.na(naming)
    if (!any(todo)) break
    hit <- todo & grepl(patterns[[nm]], stripped)
    if (!any(hit)) next
    naming[hit] <- nm
    prefix[hit] <- sub(patterns[[nm]], "\\1", stripped[hit])
  }

  data.frame(
    naming = naming,
    prefix = prefix,
    is_template = is_template,
    stringsAsFactors = FALSE
  )
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRutilities
Rscript -e 'devtools::test(filter = "job-names")'
```

Expected: 9 tests, all PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRutilities
git add R/job_names.R tests/testthat/test-job-names.R
git commit -m "feat: parse job filenames across the four live conventions

legacy, template, set and r_transitional. The parsers run most-specific
first and legacy runs last -- it reads 03.01-ac.qmd as prefix 03 and would
shadow every R-side name if tried earlier. A test pins the order."
```

---

### Task 3: The corpus fixture and placement resolver

**Files:**
- Create: `/Users/ehrlinj/Documents/GitHub/hvtiRutilities/tests/testthat/helper-corpus.R`
- Create: `/Users/ehrlinj/Documents/GitHub/hvtiRutilities/R/job_census.R`
- Test: `/Users/ehrlinj/Documents/GitHub/hvtiRutilities/tests/testthat/test-job-files.R`

**Interfaces:**
- Consumes: `hvti_taxonomy()` from Task 1.
- Produces: `make_corpus_fixture(dir)` — test helper, returns `dir`. `.job_placement(paths, root)` — internal, vectorised; returns a `data.frame` with `nrow() == length(paths)` and columns `study` (chr, relative to `root`, `NA` when unplaced), `folder` (chr, `NA` when unplaced), `status` (chr: `"placed"` / `"nested"` / `"unplaced"`), `depth` (int, `NA` when unplaced).

- [ ] **Step 1: Write the fixture helper**

Create `tests/testthat/helper-corpus.R`. Every hazard the spec names gets exactly one instance, so a regression names itself.

```r
# A disposable corpus for the sweep tests. Every file here exists to pin one
# behaviour the spec calls out; if you add a file, say which.
#
#   alpha/distributions/hz.dead.lst        canonical placed legacy job
#   alpha/distributions/hz.dead.sas        same stem, second artifact
#   alpha/distributions/hz.dead.log        same stem, third artifact
#   alpha/distributions/hz.dead.sas~       editor backup: inflates n_files,
#                                          NOT n_jobs -- it shares the stem
#   alpha/distributions/tp.hz.dead.lst     template, counted separately
#   alpha/graphs/Training/hp.curve.pdf     nested one level below the folder
#   alpha/analyses/hz.misfiled.sas         hz outside its taxonomy folder
#   alpha/distributions/pp.notes.pdf       documented non-prefix
#   alpha/distributions/zz.mystery.sas     genuinely unknown prefix
#   alpha/README.md                        unplaced, and prefix "README"
#   beta/distributions/ac.dead.lst         a SECOND study -- the template gate
#                                          counts distinct studies, so one
#                                          study cannot exercise it
#   gamma/sub/distributions/ac.dead.lst    a MULTI-LEVEL study path. Real
#                                          studies are cardiac/rhythm/maze/
#                                          atricure/gender, not one component;
#                                          without this the path join is only
#                                          ever exercised in its degenerate
#                                          single-element case
make_corpus_fixture <- function(dir) {
  files <- c(
    "alpha/distributions/hz.dead.lst",
    "alpha/distributions/hz.dead.sas",
    "alpha/distributions/hz.dead.log",
    "alpha/distributions/hz.dead.sas~",
    "alpha/distributions/tp.hz.dead.lst",
    "alpha/graphs/Training/hp.curve.pdf",
    "alpha/analyses/hz.misfiled.sas",
    "alpha/distributions/pp.notes.pdf",
    "alpha/distributions/zz.mystery.sas",
    "alpha/README.md",
    "beta/distributions/ac.dead.lst",
    "gamma/sub/distributions/ac.dead.lst"
  )
  for (f in files) {
    p <- file.path(dir, f)
    dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
    file.create(p)
  }
  dir
}
```

- [ ] **Step 2: Write the failing placement test**

Create `tests/testthat/test-job-files.R`:

```r
library(testthat)
library(hvtiRutilities)

test_that("a file directly in a taxonomy folder is placed at depth 0", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  out <- hvtiRutilities:::.job_placement(
    file.path(d, "alpha/distributions/hz.dead.lst"), d
  )
  expect_equal(out$status, "placed")
  expect_equal(out$study, "alpha")
  expect_equal(out$folder, "distributions")
  expect_equal(out$depth, 0L)
})

test_that("a file nested below the folder keeps its study and records depth", {
  # graphs/Training/ is real in preserve_root. A naive "study is the file's
  # grandparent" rule credits these to a study named "graphs".
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  out <- hvtiRutilities:::.job_placement(
    file.path(d, "alpha/graphs/Training/hp.curve.pdf"), d
  )
  expect_equal(out$status, "nested")
  expect_equal(out$study, "alpha")
  expect_equal(out$folder, "graphs")
  expect_equal(out$depth, 1L)
})

test_that("a file with no taxonomy ancestor is unplaced, not dropped", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  out <- hvtiRutilities:::.job_placement(file.path(d, "alpha/README.md"), d)
  expect_equal(out$status, "unplaced")
  expect_true(is.na(out$study))
  expect_true(is.na(out$folder))
  expect_true(is.na(out$depth))
})

test_that("study is relative to the root, never absolute", {
  # The same study resolves to different absolute paths on the server and on
  # a Mac mount; an absolute study makes two runs incomparable.
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  out <- hvtiRutilities:::.job_placement(
    file.path(d, "beta/distributions/ac.dead.lst"), d
  )
  expect_equal(out$study, "beta")
  expect_false(grepl(d, out$study, fixed = TRUE))
})

test_that("a root holding regex metacharacters still strips correctly", {
  # The root is arbitrary input. An earlier draft anchored a regex on the
  # unescaped root, which passed every other test in this file because `.`
  # and `-` match themselves -- and produced a wrong study the moment a
  # directory name carried a metacharacter. Strip by position instead.
  d <- withr::local_tempdir()
  odd <- file.path(d, "study (copy) v1.2+")
  dir.create(file.path(odd, "epsilon", "distributions"), recursive = TRUE)
  file.create(file.path(odd, "epsilon", "distributions", "ac.dead.lst"))

  out <- hvtiRutilities:::.job_placement(
    file.path(odd, "epsilon/distributions/ac.dead.lst"), odd
  )
  expect_equal(out$study, "epsilon")
  expect_equal(out$status, "placed")
})

test_that("a multi-level study path is joined, not truncated", {
  # Real studies are cardiac/rhythm/maze/atricure/gender. Taking only the
  # taxonomy folder's immediate parent would collapse every study under maze
  # into one row named "gender".
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  out <- hvtiRutilities:::.job_placement(
    file.path(d, "gamma/sub/distributions/ac.dead.lst"), d
  )
  expect_equal(out$study, "gamma/sub")
  expect_equal(out$folder, "distributions")
  expect_equal(out$depth, 0L)
})
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRutilities
Rscript -e 'devtools::test(filter = "job-files")'
```

Expected: every test ERRORs with `object '.job_placement' not found`.

- [ ] **Step 4: Write the implementation**

Create `R/job_census.R` with the placement resolver. Later tasks append to this file.

```r
# Attributing a file to a study, and saying how confidently.
#
# The study is the directory holding the taxonomy folder -- `distributions`,
# `analyses`, `graphs` and the rest. Files nest below those folders in the
# real corpus (preserve_root has ten hp.* files in graphs/Training/ and its R
# jobs two levels down in analyses/R_hazard/qmd/), so the walk finds the
# NEAREST taxonomy ancestor rather than assuming the file's own parent.
#
# Nothing is discarded. A file with no taxonomy folder anywhere above it gets
# status "unplaced" and keeps its row: a sweep that reports only what it kept
# makes a missing job indistinguishable from a job that does not exist, and
# that is exactly how shape-census.R under-reported twice.

.job_placement <- function(paths, root) {
  folders <- unique(hvti_taxonomy()$folder)

  # Strip the root prefix BY POSITION, not with a regex anchor. A root path is
  # arbitrary input -- a directory named "study (copy)" or "v1.2+" carries
  # regex metacharacters -- and an unescaped anchor matches the wrong thing
  # while still looking like it worked, because `.` and `-` match themselves.
  # normalizePath() on both sides so a symlinked root (/var -> /private/var on
  # macOS) does not make the prefix fail to line up.
  nroot <- normalizePath(root, mustWork = FALSE)
  npaths <- normalizePath(paths, mustWork = FALSE)
  rel <- substring(npaths, nchar(nroot) + 2L)

  parts <- strsplit(rel, "/", fixed = TRUE)

  out <- lapply(parts, function(p) {
    # Drop the basename: only directory components can be a taxonomy folder.
    dirs <- utils::head(p, -1L)
    hits <- which(dirs %in% folders)
    if (!length(hits)) {
      return(list(study = NA_character_, folder = NA_character_,
                  status = "unplaced", depth = NA_integer_))
    }
    i <- max(hits)                       # nearest to the file
    depth <- length(dirs) - i
    list(
      study  = if (i == 1L) "." else paste(dirs[seq_len(i - 1L)], collapse = "/"),
      folder = dirs[[i]],
      status = if (depth == 0L) "placed" else "nested",
      depth  = as.integer(depth)
    )
  })

  data.frame(
    study  = vapply(out, `[[`, character(1), "study"),
    folder = vapply(out, `[[`, character(1), "folder"),
    status = vapply(out, `[[`, character(1), "status"),
    depth  = vapply(out, `[[`, integer(1), "depth"),
    stringsAsFactors = FALSE
  )
}
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRutilities
Rscript -e 'devtools::test(filter = "job-files")'
```

Expected: 4 tests, all PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRutilities
git add R/job_census.R tests/testthat/helper-corpus.R tests/testthat/test-job-files.R
git commit -m "feat: resolve a file's study by its nearest taxonomy ancestor

Files nest below the taxonomy folder in the real corpus -- preserve_root
has hp.* files in graphs/Training/ and R jobs in analyses/R_hazard/qmd/ --
so a 'study is the file's grandparent' rule credits those to a study named
graphs. depth keeps nested files countable but separable.

A file with no taxonomy ancestor gets status unplaced and keeps its row."
```

---

### Task 4: `job_files()` — the row assembler

**Files:**
- Modify: `/Users/ehrlinj/Documents/GitHub/hvtiRutilities/R/job_census.R` (append)
- Test: `/Users/ehrlinj/Documents/GitHub/hvtiRutilities/tests/testthat/test-job-files.R` (append)

**Interfaces:**
- Consumes: `.job_name_fields()` (Task 2), `.job_placement()` (Task 3), `hvti_taxonomy()` and `hvti_non_prefixes()` (Task 1).
- Produces: `job_files(roots)` — **exported**. Returns a `data.frame` with one row per file found, columns in this exact order: `path`, `study`, `folder`, `status`, `depth`, `naming`, `prefix`, `is_template`, `stem`, `ext`, `prefix_class`, `folder_expected`, `folder_ok`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-job-files.R`:

```r
test_that("job_files() returns one row per file and drops nothing", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  out <- job_files(d)
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 12L)   # every file in the fixture
  expect_equal(
    names(out),
    c("path", "study", "folder", "status", "depth", "naming", "prefix",
      "is_template", "stem", "ext", "prefix_class", "folder_expected",
      "folder_ok")
  )
})

test_that("the stem drops only the final extension", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)
  out <- job_files(d)

  hz <- out[out$prefix %in% "hz" & !out$is_template, ]
  expect_true(all(hz$stem %in% c("hz.dead", "hz.misfiled")))
})

test_that("an editor backup shares its stem, so it inflates files not jobs", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)
  out <- job_files(d)

  dead <- out[out$stem %in% "hz.dead" & !out$is_template, ]
  expect_equal(nrow(dead), 4L)                      # lst sas log sas~
  expect_equal(length(unique(dead$stem)), 1L)
  expect_true("sas~" %in% dead$ext)
})

test_that("prefix_class is three-way, not two", {
  # hvti_non_prefixes() already distinguishes 'not a prefix' from 'a prefix
  # nobody documented'. Collapsing them reports pp -- 20 files in
  # preserve_root -- as a discovery.
  d <- withr::local_tempdir()
  make_corpus_fixture(d)
  out <- job_files(d)

  expect_equal(out$prefix_class[out$prefix %in% "hz"][1], "known")
  expect_equal(out$prefix_class[out$prefix %in% "pp"], "non_prefix")
  expect_equal(out$prefix_class[out$prefix %in% "zz"], "unknown")
})

test_that("folder_ok flags a prefix sitting outside its taxonomy folder", {
  # hz belongs in distributions. The corpus answer for hz was 'zero misfiled'
  # -- but that was verified, not assumed, and every prefix gets the check.
  d <- withr::local_tempdir()
  make_corpus_fixture(d)
  out <- job_files(d)

  mis <- out[out$stem %in% "hz.misfiled", ]
  expect_equal(mis$folder, "analyses")
  expect_equal(mis$folder_expected, "distributions")
  expect_false(mis$folder_ok)

  ok <- out[out$stem %in% "hz.dead" & out$ext %in% "lst" & !out$is_template, ]
  expect_true(ok$folder_ok)
})

test_that("a tp. file is a template and keeps its real prefix", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)
  out <- job_files(d)

  tpl <- out[out$is_template, ]
  expect_equal(nrow(tpl), 1L)
  expect_equal(tpl$prefix, "hz")
  expect_equal(tpl$stem, "tp.hz.dead")
})

test_that("there is no extension allowlist", {
  # A draft default of sas/lst/log/pdf/rtf, tuned on hz/ac/hp/bh, would have
  # dropped every R-side job in the corpus. .md is not a job extension and is
  # still present, because the filter does not exist.
  d <- withr::local_tempdir()
  make_corpus_fixture(d)
  out <- job_files(d)

  expect_true("md" %in% out$ext)
})

test_that("multiple roots are swept and the rows concatenate", {
  d1 <- withr::local_tempdir()
  d2 <- withr::local_tempdir()
  make_corpus_fixture(d1)
  make_corpus_fixture(d2)

  expect_equal(nrow(job_files(c(d1, d2))), 24L)
})
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRutilities
Rscript -e 'devtools::test(filter = "job-files")'
```

Expected: the eight new tests ERROR with `could not find function "job_files"`. The four placement tests still PASS.

- [ ] **Step 3: Write the implementation**

Append to `R/job_census.R`:

```r
#' Inventory the job files under one or more corpus roots
#'
#' @description
#' Walks each root and returns one row per file. This is a filename-only
#' sweep: no file is opened, nothing is parsed, and there is no
#' \code{TemporalHazard} dependency.
#'
#' @details
#' \strong{Nothing is filtered out.} Placement and classification are columns,
#' not reasons to drop a row, so a file this sweep cannot classify stays
#' findable. A sweep that reports only what it kept makes a missing job
#' indistinguishable from a job that does not exist.
#'
#' There is deliberately no extension allowlist. See
#' \code{vignette}-adjacent design note
#' \code{specs/2026-08-26-job-type-inventory-design.md}, section 4.4: a
#' plausible default tuned on the hazard prefixes would have dropped every
#' R-side job in the corpus.
#'
#' \strong{Run this server-side.} It stats every file beneath \code{roots},
#' which is metadata-latency-bound over an SMB mount -- a 40-file scan has
#' timed out at two minutes over the share.
#'
#' @param roots Character. One or more directories to sweep.
#'
#' @return A data frame with one row per file and the columns \code{path},
#'   \code{study}, \code{folder}, \code{status}, \code{depth}, \code{naming},
#'   \code{prefix}, \code{is_template}, \code{stem}, \code{ext},
#'   \code{prefix_class}, \code{folder_expected} and \code{folder_ok}.
#'   Zero rows if the roots hold no files.
#'
#' @seealso \code{\link{job_census}}, \code{\link{hvti_taxonomy}}
#'
#' @export
#'
#' @examples
#' d <- file.path(tempdir(), "job-files-example")
#' dir.create(file.path(d, "alpha", "distributions"), recursive = TRUE)
#' file.create(file.path(d, "alpha", "distributions", "hz.dead.lst"))
#' job_files(d)[, c("study", "folder", "prefix", "status")]
#' unlink(d, recursive = TRUE)
job_files <- function(roots) {
  stopifnot(is.character(roots), length(roots) >= 1L)

  per_root <- lapply(roots, function(r) {
    paths <- list.files(r, recursive = TRUE, full.names = TRUE,
                        all.files = TRUE, no.. = TRUE)
    paths <- paths[!dir.exists(paths)]
    if (!length(paths)) return(NULL)

    base <- basename(paths)
    fields <- .job_name_fields(base)
    place <- .job_placement(paths, r)

    # The stem drops the FINAL extension only: hz.dead.lst -> hz.dead, so the
    # .lst, .sas, .log and .sas~ of one job share a stem and count as one job.
    has_ext <- grepl("[.]", base)
    stem <- ifelse(has_ext, sub("[.][^.]*$", "", base), base)
    ext <- ifelse(has_ext, sub("^.*[.]", "", base), NA_character_)

    tx <- hvti_taxonomy()
    i <- match(fields$prefix, tx$prefix)
    folder_expected <- tx$folder[i]

    prefix_class <- ifelse(
      is.na(fields$prefix), NA_character_,
      ifelse(!is.na(i), "known",
             ifelse(fields$prefix %in% hvti_non_prefixes(),
                    "non_prefix", "unknown"))
    )

    data.frame(
      path = paths,
      study = place$study,
      folder = place$folder,
      status = place$status,
      depth = place$depth,
      naming = fields$naming,
      prefix = fields$prefix,
      is_template = fields$is_template,
      stem = stem,
      ext = ext,
      prefix_class = prefix_class,
      folder_expected = folder_expected,
      folder_ok = !is.na(folder_expected) & !is.na(place$folder) &
        folder_expected == place$folder,
      stringsAsFactors = FALSE
    )
  })

  out <- do.call(rbind, per_root)
  if (is.null(out)) {
    out <- data.frame(
      path = character(0), study = character(0), folder = character(0),
      status = character(0), depth = integer(0), naming = character(0),
      prefix = character(0), is_template = logical(0), stem = character(0),
      ext = character(0), prefix_class = character(0),
      folder_expected = character(0), folder_ok = logical(0),
      stringsAsFactors = FALSE
    )
  }
  rownames(out) <- NULL
  out
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRutilities
Rscript -e 'devtools::document()'
Rscript -e 'devtools::test(filter = "job-files")'
```

Expected: 12 tests, all PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRutilities
git add R/job_census.R tests/testthat/test-job-files.R man/ NAMESPACE
git commit -m "feat: job_files() -- one row per corpus file, nothing dropped

Placement and classification are columns rather than reasons to drop a
row. prefix_class is three-way: hvti_non_prefixes() already separates
'not a prefix' from 'a prefix nobody documented'.

No extension allowlist: a plausible default tuned on hz/ac/hp/bh would
have silently removed every R-side job in the corpus."
```

---

### Task 5: `job_census()` — the roll-up

**Files:**
- Modify: `/Users/ehrlinj/Documents/GitHub/hvtiRutilities/R/job_census.R` (append)
- Test: `/Users/ehrlinj/Documents/GitHub/hvtiRutilities/tests/testthat/test-job-census.R`

**Interfaces:**
- Consumes: `job_files()` (Task 4).
- Produces: `job_census(x)` — **exported**. `x` is a character vector of roots or a `job_files()` data frame. Returns an object of class `c("hvti_job_census", "data.frame")` with columns `study`, `prefix`, `folder`, `is_template`, `n_jobs`, `n_files`, and an attribute `"files"` holding the `job_files()` frame it was built from.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-job-census.R`:

```r
library(testthat)
library(hvtiRutilities)

test_that("job_census() counts jobs by distinct stem and files by row", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  out <- job_census(d)
  expect_s3_class(out, "hvti_job_census")
  expect_true(all(c("study", "prefix", "folder", "is_template",
                    "n_jobs", "n_files") %in% names(out)))

  hz <- out[out$study %in% "alpha" & out$prefix %in% "hz" &
              out$folder %in% "distributions" & !out$is_template, ]
  expect_equal(hz$n_jobs, 1L)    # hz.dead
  expect_equal(hz$n_files, 4L)   # lst sas log sas~
})

test_that("templates are counted separately from jobs, never dropped", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)
  out <- job_census(d)

  tpl <- out[out$is_template, ]
  expect_equal(nrow(tpl), 1L)
  expect_equal(tpl$prefix, "hz")
  expect_equal(tpl$n_jobs, 1L)
})

test_that("job_census() accepts a job_files() frame without re-walking", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  expect_equal(job_census(job_files(d)), job_census(d))
})

test_that("the source rows are retained so accounting stays reachable", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  out <- job_census(d)
  expect_equal(nrow(attr(out, "files")), 12L)
})

test_that("unplaced files do not silently vanish from the roll-up", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  out <- job_census(d)
  files <- attr(out, "files")
  expect_true("unplaced" %in% files$status)
})

test_that("a second study is what makes a prefix templatable", {
  # The gate the roadmap needs: distinct studies per prefix, jobs only. This
  # is the shape of the 2026-08-26 hand-count -- hm/hs/bh sat at one study
  # each and therefore could not be templated.
  d <- withr::local_tempdir()
  make_corpus_fixture(d)
  out <- job_census(d)

  distinct_studies <- function(p) {
    length(unique(out$study[!out$is_template & out$prefix %in% p]))
  }

  expect_equal(distinct_studies("hz"), 1L)   # alpha only -- blocked
  expect_equal(distinct_studies("ac"), 2L)   # beta and gamma/sub -- unblocked
})
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRutilities
Rscript -e 'devtools::test(filter = "job-census")'
```

Expected: every test ERRORs with `could not find function "job_census"`.

- [ ] **Step 3: Write the implementation**

Append to `R/job_census.R`:

```r
#' Roll a job-file inventory up to studies and prefixes
#'
#' @description
#' Answers the question the template roadmap keeps needing: for each job
#' prefix, which studies have run it and how many jobs each.
#'
#' @details
#' Two count columns, deliberately. \code{n_jobs} counts distinct stems and is
#' the honest unit -- the \code{.lst}, \code{.sas} and \code{.log} of one job
#' are one job, and an editor backup does not create a second. \code{n_files}
#' counts rows, and exists because the hand-count this replaces counted files;
#' keeping both means the new output can be reconciled against the table that
#' already drove a decision.
#'
#' The \code{job_files()} rows are kept on the result as the \code{"files"}
#' attribute, so the accounting -- unplaced files, unknown prefixes, misfiled
#' jobs -- stays reachable from the summary rather than being computed and
#' thrown away.
#'
#' @param x Character roots to sweep, or a data frame returned by
#'   \code{\link{job_files}}.
#'
#' @return A data frame of class \code{hvti_job_census} with one row per
#'   \code{(study, prefix, folder, is_template)} and columns \code{n_jobs} and
#'   \code{n_files}. The originating \code{job_files()} rows are attached as
#'   the \code{"files"} attribute.
#'
#' @seealso \code{\link{job_files}}
#'
#' @export
#'
#' @examples
#' d <- file.path(tempdir(), "job-census-example")
#' dir.create(file.path(d, "alpha", "distributions"), recursive = TRUE)
#' file.create(file.path(d, "alpha", "distributions", "hz.dead.lst"))
#' file.create(file.path(d, "alpha", "distributions", "hz.dead.sas"))
#' job_census(d)
#' unlink(d, recursive = TRUE)
job_census <- function(x) {
  files <- if (is.data.frame(x)) x else job_files(x)

  keep <- !is.na(files$prefix) & !is.na(files$study)
  src <- files[keep, , drop = FALSE]

  if (!nrow(src)) {
    out <- data.frame(
      study = character(0), prefix = character(0), folder = character(0),
      is_template = logical(0), n_jobs = integer(0), n_files = integer(0),
      stringsAsFactors = FALSE
    )
  } else {
    key <- paste(src$study, src$prefix, src$folder, src$is_template,
                 sep = "\r")
    split_src <- split(src, key)
    out <- do.call(rbind, lapply(split_src, function(g) {
      data.frame(
        study = g$study[[1]],
        prefix = g$prefix[[1]],
        folder = g$folder[[1]],
        is_template = g$is_template[[1]],
        n_jobs = length(unique(g$stem)),
        n_files = nrow(g),
        stringsAsFactors = FALSE
      )
    }))
    out <- out[order(out$prefix, out$study, out$is_template), , drop = FALSE]
  }

  rownames(out) <- NULL
  attr(out, "files") <- files
  class(out) <- c("hvti_job_census", "data.frame")
  out
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRutilities
Rscript -e 'devtools::document()'
Rscript -e 'devtools::test(filter = "job-census")'
```

Expected: 6 tests, all PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRutilities
git add R/job_census.R tests/testthat/test-job-census.R man/ NAMESPACE
git commit -m "feat: job_census() rolls the inventory up to study and prefix

n_jobs counts distinct stems; n_files counts rows. Both, because the
hand-count this replaces counted files -- keeping the second column is
what lets the new output be reconciled against it.

The job_files() rows ride along as the 'files' attribute so the
accounting stays reachable from the summary."
```

---

### Task 6: The print method — where the accounting surfaces

**Files:**
- Modify: `/Users/ehrlinj/Documents/GitHub/hvtiRutilities/R/job_census.R` (append)
- Test: `/Users/ehrlinj/Documents/GitHub/hvtiRutilities/tests/testthat/test-job-census.R` (append)

**Interfaces:**
- Consumes: `job_census()` (Task 5).
- Produces: `print.hvti_job_census(x, ...)` — S3 method, returns `x` invisibly.

The summary is what gets read. Both times `shape-census.R` under-reported, the CSV was complete and only the printed summary narrowed — so every accounting bucket prints unconditionally, including the empty ones.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-job-census.R`:

```r
test_that("print leads with prefixes ranked by distinct studies", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  out <- capture.output(print(job_census(d)))
  expect_true(any(grepl("distinct studies", out, ignore.case = TRUE)))
})

test_that("print reports every accounting bucket, including empty ones", {
  # An empty bucket that prints "0" is a claim. A bucket that prints nothing
  # is indistinguishable from a bucket nobody computed -- which is how the
  # hazard census under-reported twice.
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  out <- paste(capture.output(print(job_census(d))), collapse = "\n")
  expect_match(out, "unplaced")
  expect_match(out, "nested")
  expect_match(out, "[Uu]nknown prefix")
  expect_match(out, "[Mm]isfiled")
})

test_that("print names the unknown prefix and the misfiled job", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)

  out <- paste(capture.output(print(job_census(d))), collapse = "\n")
  expect_match(out, "zz")            # the unknown prefix
  expect_match(out, "hz.misfiled")   # the prefix outside its folder
})

test_that("print returns its argument invisibly", {
  d <- withr::local_tempdir()
  make_corpus_fixture(d)
  x <- job_census(d)

  expect_invisible(print(x))
})
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRutilities
Rscript -e 'devtools::test(filter = "job-census")'
```

Expected: the four new tests FAIL — the default data-frame print emits none of these strings.

- [ ] **Step 3: Write the implementation**

Append to `R/job_census.R`:

```r
#' @param ... Ignored; present for S3 consistency with \code{print}.
#' @rdname job_census
#' @export
print.hvti_job_census <- function(x, ...) {
  files <- attr(x, "files")
  jobs <- x[!x$is_template, , drop = FALSE]

  # The lookup that replaces the hand-count. A prefix present in one study
  # cannot be templated: a template extracted from a single example encodes
  # that study's choices as though they were general.
  cat("Jobs by prefix -- distinct studies is the column that says whether a\n")
  cat("template is unblocked (a prefix at 1 study is blocked).\n\n")
  if (nrow(jobs)) {
    by_prefix <- do.call(rbind, lapply(split(jobs, jobs$prefix), function(g) {
      data.frame(prefix = g$prefix[[1]],
                 distinct_studies = length(unique(g$study)),
                 n_jobs = sum(g$n_jobs),
                 n_files = sum(g$n_files),
                 stringsAsFactors = FALSE)
    }))
    by_prefix <- by_prefix[order(-by_prefix$distinct_studies,
                                 by_prefix$prefix), , drop = FALSE]
    rownames(by_prefix) <- NULL
    print.data.frame(by_prefix)
  } else {
    cat("  (none)\n")
  }

  cat("\nTemplates (tp.), counted separately from jobs: ",
      sum(x$n_files[x$is_template]), " files\n", sep = "")

  # Every bucket below prints whether or not it has contents. A bucket that
  # prints nothing cannot be told apart from one nobody computed.
  cat("\nPlacement:\n")
  for (s in c("placed", "nested", "unplaced")) {
    n <- sum(files$status == s)
    cat("  ", s, ": ", n, "\n", sep = "")
    if (s != "placed" && n) {
      cat("    e.g. ", utils::head(files$path[files$status == s], 3L),
          sep = "\n    ")
      cat("\n")
    }
  }

  unknown <- files[files$prefix_class %in% "unknown", , drop = FALSE]
  cat("\nUnknown prefixes (not in hvti_taxonomy(), not in",
      "hvti_non_prefixes()): ", nrow(unknown), "\n", sep = " ")
  if (nrow(unknown)) {
    tab <- sort(table(unknown$prefix), decreasing = TRUE)
    for (p in names(tab)) {
      cat("  ", p, ": ", tab[[p]], "  e.g. ",
          unknown$path[unknown$prefix == p][1], "\n", sep = "")
    }
  }

  mis <- files[!is.na(files$folder_expected) & !files$folder_ok &
                 files$status != "unplaced", , drop = FALSE]
  cat("\nMisfiled (prefix outside its taxonomy folder): ", nrow(mis), "\n",
      sep = "")
  if (nrow(mis)) {
    for (i in seq_len(min(nrow(mis), 5L))) {
      cat("  ", basename(mis$path[i]), " in ", mis$folder[i],
          ", expected ", mis$folder_expected[i], "\n", sep = "")
    }
  }

  unparsed <- sum(is.na(files$naming))
  cat("\nUnparsed names (no convention matched): ", unparsed, "\n", sep = "")

  cat("\nExtensions:\n")
  print(sort(table(files$ext, useNA = "ifany"), decreasing = TRUE))

  invisible(x)
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRutilities
Rscript -e 'devtools::document()'
Rscript -e 'devtools::test(filter = "job-census")'
```

Expected: 10 tests, all PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRutilities
git add R/job_census.R tests/testthat/test-job-census.R man/ NAMESPACE
git commit -m "feat: print method leads with the template gate, then the accounting

Distinct-studies-per-prefix first, because that is the lookup this
replaces. Then placement, unknown prefixes, misfiled jobs, unparsed
names and extensions -- each printed whether or not it has contents.

Both times shape-census.R under-reported, the CSV was complete and only
the printed summary narrowed. An empty bucket that prints 0 is a claim;
one that prints nothing is indistinguishable from one nobody computed."
```

---

### Task 7: Ship PR 1 — docs, version, full check

**Files:**
- Modify: `/Users/ehrlinj/Documents/GitHub/hvtiRutilities/DESCRIPTION`
- Modify: `/Users/ehrlinj/Documents/GitHub/hvtiRutilities/NEWS.md`
- Modify: `/Users/ehrlinj/Documents/GitHub/hvtiRutilities/_pkgdown.yml`

**Interfaces:**
- Consumes: everything from Tasks 1–6.
- Produces: an open PR.

- [ ] **Step 1: Bump the version**

`DESCRIPTION` line 4: `Version: 1.1.0` → `Version: 1.1.1`. Also set `Date:` on line 5 to `2026-08-26`. Patch digit only — never roll the minor.

- [ ] **Step 2: Add the NEWS entry**

`NEWS.md` line 1 is `# hvtiRutilities 1.1.0` → `# hvtiRutilities 1.1.1`. A test greps NEWS for the exact DESCRIPTION version, so these must match.

Add under the existing `## New features` heading:

```markdown
- `job_files()` and `job_census()` — a filename-only inventory of the job
  corpus. `job_files()` returns one row per file with its study, taxonomy
  folder, prefix and naming convention; `job_census()` rolls that up to
  `(study, prefix, folder)` with `n_jobs` (distinct stems) and `n_files`.
  The print method leads with distinct-studies-per-prefix, which is the
  lookup that says whether a job type can be templated yet.

  Nothing is filtered: placement and classification are columns, so a file
  the sweep cannot classify stays in the output rather than vanishing. There
  is no extension allowlist, deliberately — see
  `dev/specs/2026-08-26-job-type-inventory-design.md` §4.4.
- `hvti_taxonomy()` and `hvti_non_prefixes()` — the analysis-prefix table,
  moved here from `hvtiRtemplates`, which now imports them back. The table is
  shared vocabulary rather than template machinery, and this package is the
  lower layer.
```

- [ ] **Step 3: Index the new functions in `_pkgdown.yml`**

Add immediately after the `- title: Analysis Taxonomy` block from Task 1:

```yaml
- title: Corpus Inventory
  desc: Sweep the job corpus by filename -- which studies ran which job types
  contents:
  - job_files
  - job_census

```

- [ ] **Step 4: Run the full check**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRutilities
Rscript -e 'devtools::document()'
Rscript -e 'devtools::check()'
```

Expected: **0 errors, 0 warnings, 0 notes.** If `check()` reports an undocumented argument or a missing `\value`, fix it before continuing — do not open the PR on a dirty check.

- [ ] **Step 5: Verify against the real corpus, read-only**

This is the acceptance test the synthetic fixture cannot give you. Run it **on the server**, never over the SMB mount.

```bash
env -u R_HOME /opt/R/4.6.0/bin/Rscript -e 'devtools::load_all("~/hvtiRutilities"); print(job_census("/studies"))'
```

Expected: `hm`, `hs` and `bh` each show `distinct_studies = 1`, reproducing by lookup the table that was built by hand on 2026-08-26. If any of the three shows more than 1, **stop** — either the sweep is over-counting or the hand-count was wrong, and which one it is must be settled before this ships.

- [ ] **Step 6: Commit and open the PR**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRutilities
git add DESCRIPTION NEWS.md _pkgdown.yml man/ NAMESPACE
git commit -m "chore: bump to 1.1.1 for the job-type inventory"
git push -u origin feat/job-type-inventory
gh pr create --title "Job-type inventory sweep, and the taxonomy moves down" --body "$(cat <<'EOF'
Implements §2 of `hvtiRtemplates/specs/2026-08-26-job-type-census-sweep.md`,
per the design in `dev/specs/2026-08-26-job-type-inventory-design.md`.

`job_files()` returns one row per corpus file; `job_census()` rolls it up to
`(study, prefix, folder)` with `n_jobs` and `n_files`. The print method leads
with distinct-studies-per-prefix — the lookup that replaces a hand-count and
says whether a job type can be templated yet.

`hvti_taxonomy()` and `hvti_non_prefixes()` move here from `hvtiRtemplates`.
The prefix table is shared vocabulary, not template machinery, and this is the
lower layer; the alternative direction sets up a cycle. **`hvtiRtemplates`
still defines its own copy until its companion PR merges** — merge that one
next so the table never lives in two places for long.

Three design points worth a reviewer's attention:

- **No extension allowlist.** A plausible default (`sas`/`lst`/`log`/`pdf`/
  `rtf`), tuned on the hazard prefixes, would have silently dropped every
  R-side job in the corpus. §4.4.
- **Nothing is discarded.** Placement is a `status` column. Both times
  `shape-census.R` under-reported, the CSV was complete and only the summary
  narrowed — so every accounting bucket prints even when empty.
- **Four naming conventions are live** and the parser order is load-bearing:
  `legacy` reads `03.01-ac.qmd` as prefix `03`, so it must run last. A test
  pins the order.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

# PR 2 — `hvtiRtemplates`

**Do not start until PR 1 is merged and installed.** PR 2's tests fail without it.

### Task 8: Delete the taxonomy, import it back

**Files:**
- Delete: `/Users/ehrlinj/Documents/GitHub/hvtiRtemplates/R/taxonomy.R`
- Create: `/Users/ehrlinj/Documents/GitHub/hvtiRtemplates/R/reexports.R`
- Modify: `/Users/ehrlinj/Documents/GitHub/hvtiRtemplates/tests/testthat/test-taxonomy.R`
- Modify: `/Users/ehrlinj/Documents/GitHub/hvtiRtemplates/DESCRIPTION`
- Modify: `/Users/ehrlinj/Documents/GitHub/hvtiRtemplates/NEWS.md`

**Interfaces:**
- Consumes: `hvti_taxonomy()`, `hvti_non_prefixes()` from `hvtiRutilities` ≥ 1.1.1.
- Produces: the same two functions, re-exported. `hvtiRtemplates`' public surface is unchanged.

- [ ] **Step 1: Install PR 1 and branch**

```bash
Rscript -e 'devtools::install("~/Documents/GitHub/hvtiRutilities")'
cd /Users/ehrlinj/Documents/GitHub/hvtiRtemplates
git checkout main && git pull
git checkout -b refactor/taxonomy-from-utilities
```

- [ ] **Step 2: Delete the original and write the re-export**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRtemplates
git rm R/taxonomy.R
```

Create `R/reexports.R`:

```r
# The analysis-prefix taxonomy lives in hvtiRutilities.
#
# It moved there because it is shared vocabulary -- which prefix means what,
# which folder it belongs in -- rather than template machinery, and
# hvtiRutilities is the lower layer. Re-exported here so this package's
# public surface is unchanged: R/templates.R, the test suite and
# inst/templates/README.md all still call hvti_taxonomy() unqualified.

#' @importFrom hvtiRutilities hvti_taxonomy
#' @export
hvtiRutilities::hvti_taxonomy

#' @importFrom hvtiRutilities hvti_non_prefixes
#' @export
hvtiRutilities::hvti_non_prefixes
```

- [ ] **Step 3: Remove the three moved test blocks**

In `tests/testthat/test-taxonomy.R`, delete exactly these three `test_that` blocks — they now live in `hvtiRutilities`:

- `"hvti_taxonomy() has the expected shape"` (was line 1)
- `"the taxonomy and the non-prefix list are disjoint"` (was line 50)
- `"exactly the artifact-kind rows have an NA prefix"` (was line 55)

Keep all six that call `template_list()`. They assert the installed templates agree with the taxonomy, which is this package's claim about its own `inst/` and does not travel.

- [ ] **Step 4: Declare the dependency**

In `DESCRIPTION`, change:

```
Imports:
    stats
```

to:

```
Imports:
    hvtiRutilities (>= 1.1.1),
    stats
```

The version floor is not decoration: on 1.1.0 the functions do not exist and the failure would be `object 'hvti_taxonomy' not found` at load, which does not name its own cause.

- [ ] **Step 5: Bump the version and add the NEWS entry**

`DESCRIPTION` line 4: `Version: 1.0.3` → `Version: 1.0.4`.
`NEWS.md` line 1: `# hvtiRtemplates 1.0.3` → `# hvtiRtemplates 1.0.4`.

Add under `## New features` (or a new `## Internal` heading if none fits):

```markdown
- `hvti_taxonomy()` and `hvti_non_prefixes()` now live in `hvtiRutilities`
  and are re-exported from here. Callers are unaffected — both are still
  available unqualified from `hvtiRtemplates`. The table is shared
  vocabulary rather than template machinery, and `hvtiRutilities` is the
  lower layer, so the dependency now points that way.
```

- [ ] **Step 6: Document, test, check**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRtemplates
Rscript -e 'devtools::document()'
Rscript -e 'devtools::test()'
Rscript -e 'devtools::check()'
```

Expected: all tests PASS — in particular the six retained taxonomy tests, which prove the re-export works, since they call `hvti_taxonomy()` unqualified. `check()` must be 0/0/0.

- [ ] **Step 7: Confirm the public surface is unchanged**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRtemplates
git diff main -- NAMESPACE
```

Expected: `export(hvti_non_prefixes)` and `export(hvti_taxonomy)` are still present, now accompanied by `importFrom(hvtiRutilities,...)` lines. If either export disappeared, the roxygen re-export idiom was written wrongly and every existing caller breaks.

- [ ] **Step 8: Commit and open the PR**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRtemplates
git add -A
git commit -m "refactor: take the taxonomy from hvtiRutilities

The prefix table is shared vocabulary, not template machinery, so it now
lives in the lower package and is re-exported from here. This package's
public surface is unchanged -- R/templates.R, the tests and
inst/templates/README.md all still call hvti_taxonomy() unqualified.

The three table-only tests moved with the table. The six that call
template_list() stay: they assert the installed templates agree with the
taxonomy, which is this package's claim about its own inst/."
git push -u origin refactor/taxonomy-from-utilities
gh pr create --title "Take hvti_taxonomy() from hvtiRutilities" --body "$(cat <<'EOF'
Companion to `ehrlinger/hvtiRutilities` PR 1 — **merge this after that one**,
and install it first or the tests here fail with `object 'hvti_taxonomy' not
found`.

Deletes `R/taxonomy.R` and re-exports both functions from `hvtiRutilities`
(>= 1.1.1). The public surface is unchanged; `git diff main -- NAMESPACE`
shows both exports still present.

Three of the nine `test-taxonomy.R` blocks moved with the table — the ones
testing the table alone. The six that call `template_list()` stay, since they
assert the installed templates agree with the taxonomy, which is a claim this
package makes about its own `inst/`.

This closes the window where the prefix table existed in two packages.
`taxonomy.R`'s own docstring is the reason that window was kept short: *"The
same table lived in a README and drifted from the files it described."*

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-Review

**Spec coverage.** Every section maps to a task: §3.1 taxonomy move → Task 1; §4.2 naming conventions and parser order → Task 2; §4.1 placement/status/depth → Task 3; §4 the full row, §4.3 three-way `prefix_class`, §4.4 no extension filter → Task 4; §5 roll-up and both count columns → Task 5; §5 print accounting → Task 6; §7 versions, tests, runtime note → Task 7; §7 PR 2 → Task 8. §6 (`new_job()` not renamed) and §8 (README declarations) are explicitly out of scope and correctly have no task.

**Fixed during review.**

1. **A multi-level study path was untested.** The fixture's studies were single-component (`alpha`, `beta`), so the `paste(dirs[seq_len(i - 1L)], collapse = "/")` join was only ever exercised in its degenerate one-element case — and real studies are `cardiac/rhythm/maze/atricure/gender`. A truncating implementation would have passed every test while collapsing every study under `maze` into one row named `gender`. Fixture gained `gamma/sub/distributions/ac.dead.lst`; Task 3 gained an assertion on it; the file counts in Tasks 4 and 5 moved from 11/22 to 12/24 to match.
2. **A dead line in Task 5's test** referenced a `prefix_class_known` column that does not exist. Rewritten as a `distinct_studies()` helper, which also makes the test say what it is for: `ac` now sits in two studies and `hz` in one, so the assertion demonstrates both sides of the template gate rather than just the blocked side.
3. **`.escape_regex()` escaped nothing, and is now deleted.** Verified in R: `a.b(c)` came back as `a.b(c)` — the bracket expression was malformed, so `.job_placement()` anchored a regex on an *unescaped* root path. Every test in this plan still passed, because `.` and `-` match themselves; it broke only on a root carrying a regex metacharacter, and then produced a wrong `study` rather than an error. Replaced with positional stripping (`substring(npaths, nchar(nroot) + 2L)`), which needs no escaping at all, and pinned with a new test using a root named `study (copy) v1.2+`.

**Known gap, stated rather than hidden.**

**Step 5 of Task 7 requires server access.** The synthetic fixture cannot prove the sweep agrees with the real corpus; only the `/studies` run reproducing `hm`/`hs`/`bh` at one study each can. If the analysis host is unavailable, the PR may still open — but say so explicitly in the PR body rather than letting a green test suite imply the corpus check passed.

**Type consistency.** `.job_name_fields()` returns `naming`/`prefix`/`is_template`; `job_files()` consumes exactly those. `.job_placement()` returns `study`/`folder`/`status`/`depth`; `job_files()` consumes exactly those. `job_census()` consumes `study`, `prefix`, `folder`, `is_template`, `stem` from `job_files()` — all present in Task 4's column list. `print.hvti_job_census()` consumes `status`, `prefix_class`, `folder_expected`, `folder_ok`, `naming`, `ext`, `path` from the `"files"` attribute — all present.
