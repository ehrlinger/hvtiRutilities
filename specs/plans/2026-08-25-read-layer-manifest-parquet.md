# Read layer, manifest, and lazy parquet cache — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the read layer coercing event variables, record a durable
column-level schema for every dataset read, and cache large `.sas7bdat` reads
as parquet on first use.

**Architecture:** Three changes in one path. `dataset_schema()` captures a
sidecar from the haven read. `update_manifest()`/`verify_manifest()` gain the
fields that make a format migration checkable. `read_built()` gains a lazy,
manifest-keyed parquet cache that is invisible to callers and degrades to a
plain haven read when `arrow` is absent.

**Tech Stack:** R (>= 4.1), haven, yaml, digest, labelled, testthat edition 3,
arrow (Suggests, optional at runtime).

**Spec:** `specs/2026-08-25-read-layer-manifest-parquet-design.md`

## Global Constraints

- Branch: `feat/read-layer-manifest-parquet`. Never commit to `main`.
- Version is already `1.1.0` in `DESCRIPTION` and `NEWS.md`. Do **not** bump
  it again. Append bullets to the existing `# hvtiRutilities 1.1.0` section.
- `arrow` goes in **Suggests**, never Imports. Every use is guarded by
  `requireNamespace("arrow", quietly = TRUE)`. No caching without it; reads
  still work.
- Never read a `.sas7bdat` merely to count rows or columns. `.auto_count_rows()`
  refuses this unless `options(manifest.allow_heavy_rowcount = TRUE)`. Pass
  `n_rows`/`n_cols` from a frame already in hand.
- The sidecar's `label` comes from `attr(x, "label")`. Never from
  `proc_contents()$variables$label`, which fills absent labels with the
  variable name.
- Run `Rscript -e 'roxygen2::roxygenise(".")'` after any roxygen change and
  commit the regenerated `man/*.Rd` alongside.
- Baseline before you start: 1126 tests pass, 0 fail, 0 error, 0 skip.

## File Structure

**Create**
- `R/dataset_schema.R` — `dataset_schema()`. One responsibility: turn a frame
  into a schema table. No I/O.
- `R/parquet_cache.R` — cache internals. Path derivation, validity, atomic
  write, sidecar durability. All internal except where noted.
- `tests/testthat/test-dataset_schema.R`
- `tests/testthat/test-parquet_cache.R`

**Modify**
- `R/read_clinical_data.R` — `convert_types` default.
- `R/study_data.R` — `read_built()`: collision guard, then cache.
- `R/manifest.R` — `update_manifest()` fields; `verify_manifest()` checks.
- `DESCRIPTION`, `NEWS.md`, `NAMESPACE` (via roxygen).
- `tests/testthat/test-read_clinical_data.R`, `test-study_data.R`,
  `test-manifest.R`.

**Note on `role`.** `verify_manifest()` hashes `entry$file`, and a promoted
entry's `file` is already the parquet. Role-switching on the hash target
therefore needs no code. `role` earns its place through sidecar durability
(Task 5) and cache validity (Task 5), plus provenance in the file.

---

### Task 1: `dataset_schema()`

**Files:**
- Create: `R/dataset_schema.R`
- Create: `tests/testthat/test-dataset_schema.R`
- Modify: `NEWS.md`

**Interfaces:**
- Consumes: nothing.
- Produces: `dataset_schema(data)` → `data.frame` with columns `num`
  (integer), `variable`, `class`, `type`, `format`, `label` (all character
  except `num`), one row per column of `data`, in creation order. `format` and
  `label` are `NA_character_` when the source attribute is absent.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-dataset_schema.R`:

```r
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e 'devtools::test(filter = "dataset_schema")'`
Expected: FAIL — `could not find function "dataset_schema"`.

- [ ] **Step 3: Write the implementation**

Create `R/dataset_schema.R`:

```r
#' Column-level schema of a dataset
#'
#' @description
#' One row per column: creation position, name, R class, SAS two-valued type,
#' \code{format.sas} and label. This is the durable description of a source
#' dataset — what a schema sidecar records, and what a later read is compared
#' against.
#'
#' @details
#' \code{label} and \code{format} are read from the column attributes directly
#' and are \code{NA} when the source carries none. This is the difference from
#' \code{\link{proc_contents}}, which fills an absent label with the variable's
#' own name: right for a printed listing, wrong for a record that outlives the
#' source dataset.
#'
#' Nothing here describes the data, only its shape. Two reads of an unchanged
#' file produce an identical schema, which is what makes the sidecar's hash
#' meaningful.
#'
#' @param data A data frame, tibble, or similar tabular object.
#'
#' @return A data frame with columns \code{num} (creation position, integer),
#'   \code{variable}, \code{class} (first R class), \code{type}
#'   (\code{"Num"}/\code{"Char"}), \code{format} (SAS format or \code{NA}) and
#'   \code{label} (or \code{NA}).
#'
#' @seealso \code{\link{proc_contents}} for a printable listing that also
#'   summarises completeness.
#'
#' @export
#'
#' @examples
#' d <- data.frame(x = 1:3, y = letters[1:3])
#' attr(d$x, "label") <- "An identifier"
#' dataset_schema(d)
dataset_schema <- function(data) {
  if (!is.data.frame(data)) {
    stop("'data' must be a data frame.", call. = FALSE)
  }

  cols <- c("num", "variable", "class", "type", "format", "label")

  if (ncol(data) == 0L) {
    empty <- data.frame(num = integer(0), variable = character(0),
                        class = character(0), type = character(0),
                        format = character(0), label = character(0),
                        stringsAsFactors = FALSE)
    return(empty[, cols, drop = FALSE])
  }

  # Attributes are read directly rather than through labelled::var_label(),
  # whose null_action = "fill" would substitute the variable name.
  attr_chr <- function(x, which) {
    v <- attr(x, which, exact = TRUE)
    if (is.null(v) || length(v) == 0L) NA_character_ else as.character(v)[1L]
  }

  data.frame(
    num      = seq_len(ncol(data)),
    variable = names(data),
    class    = vapply(data, function(x) class(x)[1L], character(1)),
    type     = vapply(data,
                      function(x) if (is.character(x) || is.factor(x)) "Char" else "Num",
                      character(1)),
    format   = vapply(data, attr_chr, character(1), which = "format.sas"),
    label    = vapply(data, attr_chr, character(1), which = "label"),
    row.names = NULL,
    stringsAsFactors = FALSE
  )
}
```

- [ ] **Step 4: Regenerate docs and run the test**

Run: `Rscript -e 'roxygen2::roxygenise(".")' && Rscript -e 'devtools::test(filter = "dataset_schema")'`
Expected: PASS, 4 tests. `NAMESPACE` gains `export(dataset_schema)` and
`man/dataset_schema.Rd` is created.

- [ ] **Step 5: Add the NEWS bullet**

Under the existing `# hvtiRutilities 1.1.0` heading, add a `## New features`
section above `## Documentation`:

```markdown
## New features

- `dataset_schema()` — one row per column giving creation position, name, R
  class, SAS type, `format.sas` and label. Labels and formats are read from
  the column attributes directly, so an absent label is `NA` rather than the
  variable's own name. This is the durable description of a source dataset:
  it describes shape only, so two reads of an unchanged file produce an
  identical schema.
```

- [ ] **Step 6: Commit**

```bash
git add R/dataset_schema.R tests/testthat/test-dataset_schema.R man/dataset_schema.Rd NAMESPACE NEWS.md
git commit -m "feat: add dataset_schema() for durable column-level schemas"
```

---

### Task 2: `convert_types` default

**Files:**
- Modify: `R/read_clinical_data.R:57` (signature) and the roxygen above it
- Modify: `tests/testthat/test-read_clinical_data.R`
- Modify: `NEWS.md`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `read_clinical_data(file, convert_types = FALSE, ...)`. Callers
  omitting `convert_types` get `FALSE` and a once-per-session warning.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-read_clinical_data.R`:

```r
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
  hvtiRutilities:::.hvti_deprecated$convert_types <- NULL

  expect_warning(read_clinical_data(tmp), "convert_types")
  expect_silent(read_clinical_data(tmp))
})

test_that("passing convert_types explicitly never warns", {
  tmp <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(dead = c(1, 0)), tmp, row.names = FALSE)

  hvtiRutilities:::.hvti_deprecated$convert_types <- NULL

  expect_silent(read_clinical_data(tmp, convert_types = FALSE))
  expect_silent(read_clinical_data(tmp, convert_types = TRUE))
})

test_that("convert_types = TRUE still converts", {
  tmp <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(dead = c(1, 0, 1, 0)), tmp, row.names = FALSE)

  d <- read_clinical_data(tmp, convert_types = TRUE)

  expect_true(is.logical(d$dead))
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e 'devtools::test(filter = "read_clinical_data")'`
Expected: FAIL — the first test finds `d$dead` logical, and
`.hvti_deprecated` does not exist.

- [ ] **Step 3: Write the implementation**

In `R/read_clinical_data.R`, add above the function:

```r
# One-shot deprecation flags, keyed by name. An environment rather than a
# package variable so a warning fires once per session rather than once per
# call: a study reading forty datasets should be told once.
.hvti_deprecated <- new.env(parent = emptyenv())
```

Change the signature and add the warning as the first statement of the body:

```r
read_clinical_data <- function(file, convert_types = FALSE, ...) {
  if (missing(convert_types) && is.null(.hvti_deprecated$convert_types)) {
    .hvti_deprecated$convert_types <- TRUE
    warning(
      "read_clinical_data(): 'convert_types' now defaults to FALSE, so ",
      "columns are returned as read. It previously defaulted to TRUE, which ",
      "converted any two-valued numeric column to logical -- including 0/1 ",
      "event and censoring flags. Pass convert_types = TRUE to restore the ",
      "old behaviour, or FALSE to silence this warning.",
      call. = FALSE
    )
  }

  if (!is.character(file) || length(file) != 1L) {
```

The rest of the body is unchanged.

Update the `@param convert_types` roxygen line to:

```r
#' @param convert_types Logical. Apply \code{\link{r_data_types}} to the data
#'   after reading. Defaults to \code{FALSE}: the file is returned as read.
#'   \code{TRUE} converts any two-valued numeric column to logical, which is
#'   wrong for 0/1 event and censoring flags, so type conversion belongs to a
#'   declared variable-derivation step rather than to reading.
```

- [ ] **Step 4: Regenerate docs and run the test**

Run: `Rscript -e 'roxygen2::roxygenise(".")' && Rscript -e 'devtools::test(filter = "read_clinical_data")'`
Expected: PASS.

- [ ] **Step 5: Run the full suite — this default change reaches other tests**

Run: `Rscript -e 'r <- devtools::test(reporter = "silent"); df <- as.data.frame(r); cat("PASS:", sum(df$passed), "FAIL:", sum(df$failed), "ERR:", sum(df$error), "SKIP:", sum(df$skipped), "\n")'`
Expected: `FAIL: 0 ERR: 0`. Any test that broke was relying on the old
default; fix it by passing `convert_types = TRUE` explicitly, which is the
behaviour it was asserting. Do not weaken the assertion.

- [ ] **Step 6: Add the NEWS bullet and commit**

Add under `# hvtiRutilities 1.1.0`, in a `## Breaking changes` section placed
first:

```markdown
## Breaking changes

- `read_clinical_data()`'s `convert_types` argument now defaults to `FALSE`.
  It defaulted to `TRUE`, applying `r_data_types()` to every column, which
  converts any two-valued numeric column to logical — including 0/1 event and
  censoring flags, which `hzr_kaplan()` and similar then reject. Reading and
  type derivation are now separate steps. Callers who omit the argument get a
  once-per-session warning; pass `convert_types = TRUE` to restore the old
  behaviour.
```

```bash
git add R/read_clinical_data.R tests/testthat/test-read_clinical_data.R man/read_clinical_data.Rd NEWS.md
git commit -m "fix!: convert_types defaults to FALSE so reading no longer coerces events"
```

---

### Task 3: `read_built()` lowercase collision guard

**Files:**
- Modify: `R/study_data.R:130-134` (inside `read_built()`)
- Modify: `tests/testthat/test-study_data.R`
- Modify: `NEWS.md`

**Interfaces:**
- Consumes: nothing from Tasks 1-2.
- Produces: `read_built()` errors instead of returning duplicate column names.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-study_data.R`:

```r
test_that("read_built errors when lowercasing collides rather than duplicating a column", {
  # SAS variable names are case-insensitive, so this collision cannot be built
  # with haven::write_sas(). A .csv source reaches the same code path.
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "datasets"), recursive = TRUE)

  yaml::write_yaml(
    list(study = "Collision fixture", population = "n=2",
         built = "built_test.csv", citation = "Fixture.",
         cohort = list(n = 2L, n_events = 1L, n_censored = 1L,
                       event = "dead", time = "iv_dead")),
    file.path(dir, "_study.yml")
  )

  d <- data.frame(FOO = 1:2, foo = 3:4, dead = c(1L, 0L),
                  iv_dead = c(1, 2), check.names = FALSE)
  write.csv(d, file.path(dir, "datasets", "built_test.csv"), row.names = FALSE)

  expect_error(read_built(study_config(dir)), "FOO")
  expect_error(read_built(study_config(dir)), "foo")
})

test_that("read_built still lowercases names when there is no collision", {
  dir <- withr::local_tempdir()
  make_study_fixture(dir)

  d <- read_built(study_config(dir))

  expect_true(all(names(d) == tolower(names(d))))
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e 'devtools::test(filter = "study_data")'`
Expected: FAIL — no error is raised; `read_built()` returns a frame with two
columns named `foo`.

- [ ] **Step 3: Write the implementation**

In `R/study_data.R`, replace the single line `names(d) <- tolower(names(d))`
inside `read_built()` with:

```r
  # Lowercasing is unconditional, so a source carrying both FOO and foo would
  # yield two columns named foo and every downstream d$foo would silently take
  # the first. SAS names are case-insensitive and cannot collide; .csv, .xlsx
  # and .rds sources can.
  lower <- tolower(names(d))
  if (anyDuplicated(lower)) {
    clashes <- unique(lower[duplicated(lower)])
    detail <- vapply(clashes, function(x) {
      paste0(x, " <- ", paste(names(d)[lower == x], collapse = ", "))
    }, character(1))
    stop("read_built(): lowercasing column names produces duplicates in ",
         basename(p), ": ", paste(detail, collapse = "; "),
         ". Rename the colliding columns at the source.", call. = FALSE)
  }
  names(d) <- lower
```

`p` is already bound to the dataset path earlier in the function.

- [ ] **Step 4: Run the test**

Run: `Rscript -e 'devtools::test(filter = "study_data")'`
Expected: PASS.

- [ ] **Step 5: Add the NEWS bullet and commit**

Add to the `## Bug fixes` section under `# hvtiRutilities 1.1.0`, creating it
after `## New features` if it does not exist:

```markdown
- `read_built()` now errors when lowercasing column names produces duplicates,
  naming the colliding pair, instead of returning two identically named
  columns where every downstream selection silently takes the first. SAS names
  cannot collide this way; `.csv`, `.xlsx` and `.rds` sources can.
```

```bash
git add R/study_data.R tests/testthat/test-study_data.R NEWS.md
git commit -m "fix: read_built() errors on lowercase column-name collisions"
```

---

### Task 4: Manifest fields

**Files:**
- Modify: `R/manifest.R:127-155` (`update_manifest()` signature and entry)
- Modify: `R/manifest.R:278+` (`verify_manifest()` per-entry checks)
- Modify: `tests/testthat/test-manifest.R`
- Modify: `NEWS.md`

**Interfaces:**
- Consumes: nothing from Tasks 1-3.
- Produces: `update_manifest(file, manifest_path, extract_date, n_rows = NULL,
  n_cols = NULL, source = NULL, sort_key = NULL, schema_sha256 = NULL,
  role = c("source", "primary"), verbose = FALSE)`. Entries gain `n_cols`,
  `schema_sha256` and `role`. `verify_manifest()` reports `FAIL` on a
  `schema_sha256` mismatch and on two entries claiming the same derived paths.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-manifest.R`:

```r
test_that("update_manifest records n_cols, schema_sha256 and role", {
  dir <- withr::local_tempdir()
  f <- file.path(dir, "d.csv")
  write.csv(data.frame(a = 1:3, b = 4:6), f, row.names = FALSE)
  side <- file.path(dir, "d.schema.csv")
  write.csv(dataset_schema(data.frame(a = 1:3, b = 4:6)), side, row.names = FALSE)
  mp <- file.path(dir, "manifest.yaml")

  update_manifest(f, manifest_path = mp, n_cols = 2L,
                  schema_sha256 = digest::digest(side, algo = "sha256", file = TRUE))

  m <- yaml::read_yaml(mp)
  expect_equal(m$datasets[[1]]$n_cols, 2L)
  expect_equal(m$datasets[[1]]$role, "source")
  expect_type(m$datasets[[1]]$schema_sha256, "character")
})

test_that("update_manifest rejects an unknown role", {
  dir <- withr::local_tempdir()
  f <- file.path(dir, "d.csv")
  write.csv(data.frame(a = 1), f, row.names = FALSE)

  expect_error(
    update_manifest(f, manifest_path = file.path(dir, "manifest.yaml"),
                    role = "authoritative"),
    "should be one of"
  )
})

test_that("verify_manifest fails when the sidecar has been edited", {
  dir <- withr::local_tempdir()
  f <- file.path(dir, "d.csv")
  write.csv(data.frame(a = 1:3), f, row.names = FALSE)
  side <- file.path(dir, "d.schema.csv")
  write.csv(dataset_schema(data.frame(a = 1:3)), side, row.names = FALSE)
  mp <- file.path(dir, "manifest.yaml")
  update_manifest(f, manifest_path = mp, n_cols = 1L,
                  schema_sha256 = digest::digest(side, algo = "sha256", file = TRUE))

  cat("tampered\n", file = side, append = TRUE)

  res <- verify_manifest(mp, stop_on_error = FALSE)
  expect_true(any(res$status == "FAIL"))
  expect_match(paste(res$message, collapse = " "), "schema")
})

test_that("verify_manifest reports two entries claiming the same derived paths", {
  dir <- withr::local_tempdir()
  write.csv(data.frame(a = 1), file.path(dir, "built.csv"), row.names = FALSE)
  saveRDS(data.frame(a = 1), file.path(dir, "built.rds"))
  mp <- file.path(dir, "manifest.yaml")
  update_manifest(file.path(dir, "built.csv"), manifest_path = mp, n_cols = 1L)
  update_manifest(file.path(dir, "built.rds"), manifest_path = mp, n_cols = 1L)

  res <- verify_manifest(mp, stop_on_error = FALSE)
  expect_match(paste(res$message, collapse = " "), "derived path")
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e 'devtools::test(filter = "manifest")'`
Expected: FAIL — `unused arguments (n_cols, schema_sha256, role)`.

- [ ] **Step 3: Extend `update_manifest()`**

Change the signature to:

```r
update_manifest <- function(file,
                            manifest_path = "manifest.yaml",
                            extract_date  = Sys.Date(),
                            n_rows        = NULL,
                            n_cols        = NULL,
                            source        = NULL,
                            sort_key      = NULL,
                            schema_sha256 = NULL,
                            role          = c("source", "primary"),
                            verbose       = FALSE) {
  role <- match.arg(role)
```

and extend the entry, immediately after the existing `entry <- list(...)`:

```r
  # role is written even though every entry starts as "source". Adding the
  # field once manifests exist across many studies would mean migrating them,
  # which is the schema-drift problem this file exists to prevent.
  entry$role <- role
  if (!is.null(n_cols))        entry$n_cols        <- as.integer(n_cols)
  if (!is.null(schema_sha256)) entry$schema_sha256 <- schema_sha256
```

Add the roxygen params:

```r
#' @param n_cols Integer. Column count. Pass it from a frame already read; a
#'   row count alone cannot detect a dropped column.
#' @param schema_sha256 Character. SHA-256 of this dataset's schema sidecar,
#'   making the manifest-to-sidecar link tamper-evident.
#' @param role Either \code{"source"} (the file is authoritative and any
#'   parquet beside it is a disposable cache) or \code{"primary"} (the parquet
#'   is authoritative because the source has been retired). See the
#'   \emph{Promotion} section of the read-layer design spec.
```

- [ ] **Step 3b: Fix `verify_manifest()`'s `data_dir` default**

Pre-existing defect, fixed here because the sidecar check added in Step 4
resolves paths against `data_dir` and would inherit it.

`study_init()` writes `manifest.yaml` at the study root while datasets live in
`<root>/datasets/`, so defaulting `data_dir` to the manifest's own directory
is wrong for the layout this package itself creates. `verify_manifest()`'s
`@examples` fail on preserve_root today with
`File not found: …/preserve_root/built.sas7bdat`. Only `study_status()` works,
because it passes `data_dir = file.path(root, "datasets")` explicitly.

First, the test — append to `tests/testthat/test-manifest.R`:

```r
test_that("verify_manifest finds datasets in datasets/ without an explicit data_dir", {
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "datasets"))
  f <- file.path(dir, "datasets", "d.csv")
  write.csv(data.frame(a = 1:3), f, row.names = FALSE)
  mp <- file.path(dir, "manifest.yaml")
  update_manifest(f, manifest_path = mp, n_cols = 1L)

  res <- verify_manifest(mp, stop_on_error = FALSE)

  expect_equal(res$status, "PASS")
})

test_that("verify_manifest still resolves alongside the manifest when there is no datasets/", {
  dir <- withr::local_tempdir()
  f <- file.path(dir, "d.csv")
  write.csv(data.frame(a = 1:3), f, row.names = FALSE)
  mp <- file.path(dir, "manifest.yaml")
  update_manifest(f, manifest_path = mp, n_cols = 1L)

  res <- verify_manifest(mp, stop_on_error = FALSE)

  expect_equal(res$status, "PASS")
})
```

Then replace the `data_dir` default block in `verify_manifest()`:

```r
  if (is.null(data_dir)) {
    # study_init() writes manifest.yaml at the study root and the datasets one
    # level down, so the manifest's own directory is the wrong place to look.
    # Prefer <manifest dir>/datasets when it exists; fall back to the manifest's
    # directory for a flat layout.
    base <- dirname(normalizePath(manifest_path))
    nested <- file.path(base, "datasets")
    data_dir <- if (dir.exists(nested)) nested else base
  }
```

Update the `@param data_dir` roxygen to say so:

```r
#' @param data_dir Directory holding the dataset files. Defaults to
#'   \code{datasets/} beneath the manifest's own directory when that exists,
#'   and to the manifest's directory otherwise — matching the layout
#'   \code{\link{study_init}} creates, where \code{manifest.yaml} sits at the
#'   study root and datasets one level down.
```

- [ ] **Step 4: Extend `verify_manifest()`**

Inside the `lapply` over `manifest$datasets`, after the existing SHA-256
comparison succeeds and before the function returns its PASS row, add:

```r
    if (!is.null(entry$schema_sha256)) {
      side <- file.path(data_dir,
                        paste0(tools::file_path_sans_ext(entry$file),
                               ".schema.csv"))
      if (!file.exists(side)) {
        return(data.frame(
          file = entry$file, status = "FAIL",
          message = paste0("Schema sidecar not found: ", side),
          row_count_checked = FALSE, stringsAsFactors = FALSE))
      }
      side_sha <- digest::digest(side, algo = "sha256", file = TRUE)
      if (!identical(side_sha, entry$schema_sha256)) {
        return(data.frame(
          file = entry$file, status = "FAIL",
          message = paste0("Schema sidecar SHA-256 mismatch\n  expected: ",
                           entry$schema_sha256, "\n  actual:   ", side_sha),
          row_count_checked = FALSE, stringsAsFactors = FALSE))
      }
    }
```

After the `results <- lapply(...)` call and before results are combined, add
the cross-entry check:

```r
  # Derived paths are stem-based, so two sources differing only by extension
  # would claim the same .parquet and .schema.csv. Nothing overwrites silently
  # today because the writer is keyed on the source, but the collision is
  # reachable and produces a sidecar describing the wrong dataset.
  stems <- vapply(manifest$datasets,
                  function(e) tools::file_path_sans_ext(e$file), character(1))
  clash <- unique(stems[duplicated(stems)])
  if (length(clash)) {
    files <- vapply(manifest$datasets, function(e) e$file, character(1))
    collisions <- lapply(clash, function(s) data.frame(
      file    = paste(files[stems == s], collapse = ", "),
      status  = "FAIL",
      message = paste0("Entries share the derived path stem '", s,
                       "' and would claim the same .parquet and .schema.csv."),
      row_count_checked = FALSE, stringsAsFactors = FALSE))
    results <- c(results, collisions)
  }
```

- [ ] **Step 5: Run the tests**

Run: `Rscript -e 'roxygen2::roxygenise(".")' && Rscript -e 'devtools::test(filter = "manifest")'`
Expected: PASS.

- [ ] **Step 6: Add the NEWS bullets and commit**

Add to `## New features`:

```markdown
- `update_manifest()` gains `n_cols`, `schema_sha256` and `role`. A row count
  alone cannot detect a dropped column, and a hash of the schema sidecar makes
  the manifest-to-sidecar link tamper-evident. `role` is `"source"` or
  `"primary"` and distinguishes a dataset SAS still builds from one whose
  parquet has become authoritative.
- `verify_manifest()` checks `schema_sha256` against the sidecar on disk, and
  reports two entries whose file stems collide and would therefore claim the
  same derived `.parquet` and `.schema.csv` paths.
```

```bash
git add R/manifest.R tests/testthat/test-manifest.R man/update_manifest.Rd man/verify_manifest.Rd NEWS.md
git commit -m "feat: manifest records n_cols, schema hash and role; verify checks both"
```

---

### Task 5: Lazy parquet cache

**Files:**
- Create: `R/parquet_cache.R`
- Create: `tests/testthat/test-parquet_cache.R`
- Modify: `DESCRIPTION` (Suggests)
- Modify: `R/study_data.R` (`read_built()`)
- Modify: `NEWS.md`

**Interfaces:**
- Consumes: `dataset_schema()` (Task 1); `update_manifest(..., n_cols =,
  schema_sha256 =, role =)` (Task 4); `read_built()`'s collision guard
  (Task 3).
- Produces: internal `.cache_read(path, cfg)` returning a `data.frame`, used
  by `read_built()`. Not exported.

- [ ] **Step 1: Add arrow to Suggests**

In `DESCRIPTION`, add `arrow` to the `Suggests:` list in alphabetical position
(before `e1071`):

```
Suggests:
    arrow,
    e1071,
```

- [ ] **Step 2: Write the failing test**

Create `tests/testthat/test-parquet_cache.R`:

```r
skip_if_no_arrow <- function() skip_if_not_installed("arrow")

test_that("first read writes a parquet and a sidecar; second read uses them", {
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir)
  cfg <- study_config(dir)

  d1 <- read_built(cfg)
  expect_true(file.exists(file.path(dir, "datasets", "built_test.parquet")))
  expect_true(file.exists(file.path(dir, "datasets", "built_test.schema.csv")))

  d2 <- read_built(cfg)
  expect_equal(d1, d2)
})

test_that("changing the source invalidates the cache", {
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir, n = 20L)
  cfg <- study_config(dir)

  expect_equal(nrow(read_built(cfg)), 20L)

  # Rewrite the source with a different row count. Asserting on the returned
  # data rather than on the parquet's mtime is deliberate: an mtime comparison
  # passes whether or not the cache was rebuilt, so it tests nothing. A stale
  # cache returns 20 rows here.
  replacement <- data.frame(
    id      = 1:5,
    x       = as.numeric(1:5),
    dead    = c(1L, 1L, 0L, 0L, 0L),
    iv_dead = as.numeric(1:5)
  )
  suppressWarnings(haven::write_sas(
    replacement, file.path(dir, "datasets", "built_test.sas7bdat")))

  expect_equal(nrow(read_built(cfg)), 5L)
})

test_that("a parquet round trip preserves haven metadata", {
  skip_if_no_arrow()
  tmp <- withr::local_tempfile(fileext = ".parquet")
  d <- data.frame(x = 1:3)
  d$grp <- haven::labelled(c(1, 2, 1), labels = c(No = 1, Yes = 2), label = "Group")
  d$when <- as.POSIXct("2020-01-01", tz = "UTC")
  attr(d$x, "format.sas") <- "BEST12"

  arrow::write_parquet(d, tmp)
  b <- as.data.frame(arrow::read_parquet(tmp))

  expect_s3_class(b$grp, "haven_labelled")
  expect_equal(attr(b$grp, "labels"), c(No = 1, Yes = 2))
  expect_equal(attr(b$grp, "label"), "Group")
  expect_equal(attr(b$x, "format.sas"), "BEST12")
  expect_equal(format(b$when[1], tz = "UTC", usetz = TRUE),
               "2020-01-01 UTC")
})

test_that("the sidecar of a promoted entry is never regenerated", {
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  make_study_fixture(dir)
  cfg <- study_config(dir)
  read_built(cfg)

  side <- file.path(dir, "datasets", "built_test.schema.csv")
  writeLines("do not overwrite", side)

  mp <- file.path(dir, "datasets", "manifest.yaml")
  m <- yaml::read_yaml(mp)
  m$datasets[[1]]$role <- "primary"
  yaml::write_yaml(m, mp)

  src <- file.path(dir, "datasets", "built_test.sas7bdat")
  Sys.setFileTime(src, Sys.time() + 5)
  suppressWarnings(try(read_built(cfg), silent = TRUE))

  expect_equal(readLines(side), "do not overwrite")
})

test_that("a failed conversion leaves no partial parquet", {
  skip_if_no_arrow()
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "datasets"))
  target <- file.path(dir, "datasets", "x.parquet")

  expect_error(
    hvtiRutilities:::.write_parquet_atomic(
      data.frame(a = I(list(1, 2))), target),
    NULL
  )
  expect_false(file.exists(target))
})

test_that("reads still work when arrow is unavailable", {
  dir <- withr::local_tempdir()
  make_study_fixture(dir)
  withr::local_options(hvtiRutilities.disable_parquet_cache = TRUE)

  d <- read_built(study_config(dir))

  expect_s3_class(d, "data.frame")
  expect_false(file.exists(file.path(dir, "datasets", "built_test.parquet")))
})
```

- [ ] **Step 3: Run test to verify it fails**

Run: `Rscript -e 'devtools::test(filter = "parquet_cache")'`
Expected: FAIL — no parquet is written and
`.write_parquet_atomic` does not exist.

- [ ] **Step 4: Write the implementation**

Create `R/parquet_cache.R`:

```r
# Lazy parquet cache for the read layer.
#
# Conversion happens on first read, never in a bulk sweep, so a dataset nobody
# reads is never converted and superseded copies cost nothing.
#
# Validity is decided by the source's size and mtime -- a stat, not a read.
# Re-hashing the source on every call would read the whole file and defeat the
# cache entirely; the sha256 is computed once at conversion, recorded in the
# manifest, and verified on demand by verify_manifest().

.cache_enabled <- function() {
  !isTRUE(getOption("hvtiRutilities.disable_parquet_cache", FALSE)) &&
    requireNamespace("arrow", quietly = TRUE)
}

.derived_paths <- function(path) {
  stem <- tools::file_path_sans_ext(path)
  list(parquet = paste0(stem, ".parquet"),
       schema  = paste0(stem, ".schema.csv"))
}

# Write to a temporary name in the destination directory and rename into
# place. Two jobs can race on the first read of a shared dataset, and rename
# within a filesystem is atomic where a half-written .parquet is not.
.write_parquet_atomic <- function(data, target) {
  tmp <- tempfile(pattern = basename(target), tmpdir = dirname(target),
                  fileext = ".tmp")
  ok <- FALSE
  on.exit(if (!ok && file.exists(tmp)) unlink(tmp), add = TRUE)
  arrow::write_parquet(data, tmp)
  if (!file.rename(tmp, target)) {
    stop("Could not move the converted parquet into place: ", target,
         call. = FALSE)
  }
  ok <- TRUE
  invisible(target)
}

# The manifest entry for one source file, or NULL.
.manifest_entry <- function(manifest_path, file) {
  if (!file.exists(manifest_path)) return(NULL)
  m <- yaml::read_yaml(manifest_path)
  if (is.null(m$datasets)) return(NULL)
  for (e in m$datasets) if (identical(e$file, basename(file))) return(e)
  NULL
}

.cache_valid <- function(path, derived, entry) {
  if (is.null(entry) || !file.exists(derived$parquet)) return(FALSE)
  info <- file.info(path)
  identical(as.numeric(entry$source_size), as.numeric(info$size)) &&
    isTRUE(abs(as.numeric(as.POSIXct(entry$source_mtime, tz = "UTC")) -
                 as.numeric(info$mtime)) < 1)
}

# Read `path`, using or populating the parquet cache beside it.
#
# manifest_path is passed in rather than derived from `path`: study_init()
# writes manifest.yaml at the STUDY ROOT while datasets live in
# <root>/datasets/, so dirname(path) is the wrong directory. Derived files
# (.parquet, .schema.csv) do sit beside the source.
.cache_read <- function(path, reader, manifest_path) {
  if (!.cache_enabled()) return(reader(path))

  derived  <- .derived_paths(path)
  manifest <- manifest_path
  entry    <- .manifest_entry(manifest, path)

  if (.cache_valid(path, derived, entry)) {
    return(as.data.frame(arrow::read_parquet(derived$parquet)))
  }

  d <- reader(path)

  # Order matters: the sidecar comes off this read, never off the parquet, so
  # the baseline is independent of the conversion it exists to check.
  #
  # A promoted entry's sidecar is the only surviving record of the SAS
  # dataset. Rewriting it from a later read would launder that away, so it is
  # written once and never again.
  promoted <- identical(entry$role, "primary")
  if (!promoted) {
    utils::write.csv(dataset_schema(d), derived$schema, row.names = FALSE)
  }

  info <- file.info(path)
  update_manifest(
    file          = path,
    manifest_path = manifest,
    n_rows        = nrow(d),
    n_cols        = ncol(d),
    schema_sha256 = if (file.exists(derived$schema)) {
      digest::digest(derived$schema, algo = "sha256", file = TRUE)
    } else {
      NULL
    },
    role          = if (promoted) "primary" else "source"
  )
  .stamp_source_state(manifest, basename(path), info)

  .write_parquet_atomic(d, derived$parquet)
  d
}

# The fast key lives beside the entry rather than inside update_manifest(),
# whose contract is about identifying a dataset rather than about caching.
.stamp_source_state <- function(manifest_path, file, info) {
  m <- yaml::read_yaml(manifest_path)
  m$datasets <- lapply(m$datasets, function(e) {
    if (identical(e$file, file)) {
      e$source_size  <- as.numeric(info$size)
      e$source_mtime <- format(info$mtime, "%Y-%m-%d %H:%M:%S", tz = "UTC")
    }
    e
  })
  yaml::write_yaml(m, manifest_path)
  invisible(TRUE)
}
```

- [ ] **Step 5: Wire it into `read_built()`**

In `R/study_data.R`, replace

```r
  d <- as.data.frame(read_clinical_data(p, convert_types = FALSE))
```

with

```r
  d <- as.data.frame(
    .cache_read(p,
                function(f) read_clinical_data(f, convert_types = FALSE),
                manifest_path = file.path(cfg$root, "manifest.yaml"))
  )
```

`cfg$root` is the study root, which is where `study_init()` writes
`manifest.yaml`. Do not derive the manifest path from `dirname(p)` — that is
`<root>/datasets/`, and no manifest lives there.

- [ ] **Step 6: Run the tests**

Run: `Rscript -e 'devtools::test(filter = "parquet_cache")'`
Expected: PASS, with no skips on a machine where arrow is installed.

- [ ] **Step 7: Run the full suite**

Run: `Rscript -e 'r <- devtools::test(reporter = "silent"); df <- as.data.frame(r); cat("PASS:", sum(df$passed), "FAIL:", sum(df$failed), "ERR:", sum(df$error), "SKIP:", sum(df$skipped), "\n")'`
Expected: `FAIL: 0 ERR: 0`, total passes above the 1126 baseline.

- [ ] **Step 8: Add the NEWS bullets and commit**

Add to `## New features`:

```markdown
- `read_built()` now caches its source as parquet on first read and uses that
  cache while the source's size and modification time are unchanged. The
  schema sidecar and manifest entry are written from the haven read, before
  the parquet exists, so the recorded baseline is independent of the
  conversion. Conversion is lazy: a dataset nobody reads is never converted.
  `arrow` is a suggested package — without it, or with
  `options(hvtiRutilities.disable_parquet_cache = TRUE)`, reads behave exactly
  as before.
```

```bash
git add DESCRIPTION R/parquet_cache.R R/study_data.R tests/testthat/test-parquet_cache.R NEWS.md
git commit -m "feat: lazy parquet cache in the read layer, keyed on the manifest"
```

---

### Task 6: Study-side follow-up (no commit in this repo)

**Files:**
- Modify: `/Volumes/qhsstudies/vascular/thoracic-aorta/dissection/ascending/acute/preserve_root/analyses/R_hazard/R/study.R`

**Interfaces:**
- Consumes: the new `read_clinical_data()` default (Task 2) and `read_built()`
  (Tasks 3, 5).
- Produces: nothing this repo depends on.

The preserve_root study tree is not a git workspace for this work. Edit the
file; do not commit there.

- [ ] **Step 1: Confirm the study's built filename matches `_study.yml`**

Run:

```bash
grep -n 'built:' "/Volumes/qhsstudies/vascular/thoracic-aorta/dissection/ascending/acute/preserve_root/_study.yml"
```

Expected: `built: built.sas7bdat`.

- [ ] **Step 2: Replace the reader**

In `analyses/R_hazard/R/study.R`, replace the body of `read_preserve_root()`:

```r
read_preserve_root <- function() {
  d <- hvtiRutilities::read_built()
  d[!is.na(d$pr_avail) & d$pr_avail == 1, , drop = FALSE]
}
```

`read_built()` resolves the path through `study_config()`, so `sas_path()` is
no longer needed here. Keep the existing comment about `%vars` above the
function: it still explains why no variable derivation happens on read.

- [ ] **Step 3: Verify the cohort gate still passes**

Run:

```bash
cd "/Volumes/qhsstudies/vascular/thoracic-aorta/dissection/ascending/acute/preserve_root/analyses/R_hazard" && Rscript -e 'source("R/study.R"); d <- add_g_root3(read_preserve_root()); assert_cohort_gate(d); cat("gate passed, n =", nrow(d), "\n")'
```

Expected: `gate passed, n = 291`.

This is the real check on Task 2. The gate expects `total=291, events=77,
uncensored=72, interval=5, right=214`. It was written to survive logical
columns, so it passes either way — but `class(d$idead)` should now be numeric
rather than logical. Confirm:

```bash
cd "/Volumes/qhsstudies/vascular/thoracic-aorta/dissection/ascending/acute/preserve_root/analyses/R_hazard" && Rscript -e 'source("R/study.R"); d <- read_preserve_root(); cat("idead:", class(d$idead), " ic_dead:", class(d$ic_dead), "\n")'
```

Expected: `idead: numeric  ic_dead: numeric`.

- [ ] **Step 4: Confirm the cache populated**

Run:

```bash
ls -l "/Volumes/qhsstudies/vascular/thoracic-aorta/dissection/ascending/acute/preserve_root/datasets/built.parquet" "/Volumes/qhsstudies/vascular/thoracic-aorta/dissection/ascending/acute/preserve_root/datasets/built.schema.csv"
```

Expected: both exist. The sidecar should have 880 lines — 879 variables plus a
header.

---

## Self-Review

**Spec coverage.** Schema sidecar → Task 1. Manifest extension → Task 4. Lazy
cache → Task 5. `convert_types` default → Task 2. Study-side follow-up →
Task 6. Collision guards → Task 3 (lowercase) and Task 4 (derived paths).
Promotion → Task 4 writes `role`; Task 5 honours it for sidecar durability.
Metadata fidelity → Task 5 Step 2, test three. Every spec testing bullet maps
to a test above except *atomic write*, covered in Task 5 Step 2, test five.

**Deviation from the spec, recorded deliberately.** The spec's Promotion table
says `verify_manifest()` hashes the source for a `source` entry and the
parquet for a `primary` one. No code implements this: `verify_manifest()`
already hashes `entry$file`, and a promoted entry's `file` *is* the parquet.
The behaviour is correct without a role switch, so none was added. The `role`
field still earns its place through sidecar durability and cache validity.

**Not built, and why.** No `promote_dataset()` helper. The spec describes
promotion as a per-entry field change and nothing yet performs one; adding a
function for a transition that has not happened would be speculative. Revisit
when the first SAS job actually retires.

**Types.** `dataset_schema()` returns `num/variable/class/type/format/label`
throughout. `.cache_read(path, reader)`, `.write_parquet_atomic(data, target)`
and `.derived_paths(path)$parquet|$schema` are used consistently in Tasks 5
and 6.
