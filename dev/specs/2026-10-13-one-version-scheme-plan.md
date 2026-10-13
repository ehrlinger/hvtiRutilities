# One version scheme for study datasets: implementation plan (deprecation release)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the deprecation release of `2026-10-13-one-version-scheme-design.md`: provenance on
dated versions, a stage-gated working read, `review_built()`, and deprecation warnings on the
release path.

**Architecture:** Provenance is a top-level `provenance:` map in `manifest.yaml`, keyed by parquet
name, filled from a `<stem>.build.yml` sidecar that registration claims only when its hash matches
the bytes converted. `read_built()` treats every read that is not of a dated version as a working
read, which passes a stage gate (datasets/descriptive jobs, or the interactive console) and
signals `hvtiRutilities_working_read`. The release path keeps working and warns.

**Tech Stack:** R, testthat edition 3, yaml, digest, arrow (Suggests), knitr (Suggests), withr.

**Scope:** the deprecation release only (spec section 7, first bullet list). The removal release
is a separate plan, written once hvtiRtemplates and hvtiRdatabuild no longer call the release
functions; its number is John Ehrlinger's decision.

## Global Constraints

- Roxygen is **Rd markup, not markdown**: `\code{}`, `\strong{}`, `\emph{}`, `\itemize{}`,
  `\link{}`. Backticks and `**` land literally in the `.Rd`.
- Lines at most **135** characters (`.lintr`); `lint_package()` must be clean under
  `LINTR_ERROR_ON_LINT`. Install first (`R CMD INSTALL --no-docs .`) before trusting a lint count.
- Every new export goes in `_pkgdown.yml`'s explicit `reference:` index, or the site build errors.
- `devtools::document()` output (`man/`, `NAMESPACE`) is committed with the source change.
- No `news/` edits to `NEWS.md` and no `Version:` bump in this PR: one fragment,
  `news/feat-one-version-scheme.md`, bullets only, no heading.
- Never record a key value or a data value in a manifest, a build record, a message or a test
  fixture name.
- Base `.Deprecated()` / `warning()`, no lifecycle dependency. `.Deprecated()` signals class
  `deprecatedWarning` (measured), and `.deprecated_arg()` uses the same class so one
  `expect_warning(class = "deprecatedWarning")` covers both.
- Definition of done: `devtools::test()` passes, `devtools::check()` 0/0/0.

## File structure

| file | responsibility | change |
|---|---|---|
| `R/version_provenance.R` | the `provenance:` map, the build sidecar, record validation and claiming | create |
| `R/working_read.R` | `HVTI_DATA` default, job-file and stage detection, the working-read condition | create |
| `R/review_built.R` | `review_built()` and `print.built_review` | create |
| `R/registered_versions.R` | reserve record names; write provenance rows from `.next_version()`, `.migrate_entry()`, `.update_study_manifest()`; condition text | modify |
| `R/register_data.R` | claim the sidecar, write the row, roll back; warn on release arguments | modify |
| `R/manifest.R` | `verify_manifest()` checks build records | modify |
| `R/study_data.R` | `read_built(working =)`, the gate on non-dated reads, the example | modify |
| `R/provenance.R` | `provenance_data(working =)` | modify |
| `R/data_updates.R`, `R/study_config.R` | deprecation warnings | modify |
| `vignettes/dataset-versioning.qmd` | replace the release sections with dated versions, `review_built()` and working reads | modify |
| `tests/testthat/setup-working-context.R` | run the suite as an interactive console so the gate does not refuse ordinary reads | create |
| `tests/testthat/test-version_provenance.R`, `test-working_read.R`, `test-review_built.R` | new tests | create |

---

### Task 1: The `provenance:` map

**Files:**
- Create: `R/version_provenance.R`
- Modify: `R/registered_versions.R` (`.recover_cached_version()`, `.migrate_entry()`,
  `.update_study_manifest()`)
- Test: `tests/testthat/test-version_provenance.R`

**Interfaces:**
- Produces: `.version_provenance(manifest, parquet)` → list with at least `origin`;
  `.set_version_provenance(manifest, parquet, row)` → manifest;
  `.legacy_row()` → `list(origin = "legacy")`.
- Produces: each step list from `.next_version()` / `.migrate_entry()` carries
  `provenance`, a named list `parquet -> row` (empty list when none).

- [ ] **Step 1: Write the failing tests**

```r
# tests/testthat/test-version_provenance.R
test_that("a version with no provenance row reads as legacy", {
  m <- list(datasets = list())
  expect_identical(.version_provenance(m, "built_20260915.parquet"), list(origin = "legacy"))
  m$provenance <- list(built_20260915.parquet = list(origin = "bd", build = list(job = "00_datasets/bd.qmd")))
  expect_identical(.version_provenance(m, "built_20260915.parquet")$origin, "bd")
})

test_that("setting a row keeps the others", {
  m <- .set_version_provenance(list(), "a_20260101.parquet", .legacy_row())
  m <- .set_version_provenance(m, "a_20260102.parquet", list(origin = "bd"))
  expect_identical(names(m$provenance), c("a_20260101.parquet", "a_20260102.parquet"))
})

test_that("registration and update write a legacy row for every new version", {
  root <- versioned_study()
  m <- .read_manifest(file.path(root, "manifest.yaml"))
  expect_identical(m$provenance$built_20260915.parquet, list(origin = "legacy"))

  path <- file.path(study_dir("datasets", root), "built.csv")
  utils::write.csv(data.frame(id = 1:4, DEAD = c(1L, 0L, 0L, 1L)), path, row.names = FALSE)
  withr::with_dir(root, suppressMessages(update_manifest(extract_date = "2026-10-01")))
  m <- .read_manifest(file.path(root, "manifest.yaml"))
  expect_identical(m$provenance$built_20261001.parquet, list(origin = "legacy"))
  expect_identical(m$provenance$built_20260915.parquet, list(origin = "legacy"))
})

test_that("an older reader's rewrite keeps the map and adds no row", {
  # 1.5.2 reads the whole manifest, replaces $datasets and writes it back.
  root <- versioned_study()
  mp <- file.path(root, "manifest.yaml")
  m <- .read_manifest(mp)
  m$provenance$built_20260915.parquet <- list(origin = "bd", build = list(job = "00_datasets/bd.qmd"))
  .write_manifest(m, mp)
  old_style <- yaml::read_yaml(mp)
  old_style$datasets <- Filter(Negate(is.character), old_style$datasets)
  old_style$datasets[[1]]$parquet <- "built_20261001.parquet"
  yaml::write_yaml(old_style, mp)
  m <- .read_manifest(mp)
  expect_identical(.version_provenance(m, "built_20260915.parquet")$origin, "bd")
  expect_identical(.version_provenance(m, "built_20261001.parquet")$origin, "legacy")
})
```

Also add, beside the existing `.migrate_entry()` recovery test in
`tests/testthat/test-registered_versions.R` (the one asserting `recovered_from = "cache"`), this
expectation after its `update_manifest()` call:

```r
  m <- .read_manifest(file.path(root, "manifest.yaml"))
  expect_identical(m$provenance[[e$history[[1]]$parquet]], list(origin = "legacy"))
```

- [ ] **Step 2: Run to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "version_provenance")'`
Expected: FAIL, `could not find function ".version_provenance"`.

- [ ] **Step 3: Implement the map**

```r
# R/version_provenance.R
# Provenance of a registered version: how its data were produced. Design:
# dev/specs/2026-10-13-one-version-scheme-design.md, section 4.
#
# Kept in a top-level `provenance:` map keyed by parquet name, never on the
# version record. hvtiRutilities 1.5.1 and 1.5.2 copy every field they do not
# know onto the next version they write, so an origin on the entry would be
# inherited by a later rebuild; they rewrite only `datasets:` and keep other
# top-level keys, so a version they register has no row and reads as legacy.

.legacy_row <- function() list(origin = "legacy")

.version_provenance <- function(manifest, parquet) {
  rows <- if (is.list(manifest$provenance)) manifest$provenance else list()
  row <- rows[[parquet]]
  if (is.list(row) && is.character(row$origin) && length(row$origin) == 1L) row else .legacy_row()
}

.set_version_provenance <- function(manifest, parquet, row) {
  rows <- if (is.list(manifest$provenance)) manifest$provenance else list()
  rows[[parquet]] <- row
  manifest$provenance <- rows
  manifest
}
```

In `R/registered_versions.R`:

1. `.next_version()`: in the `registered` return list add
   `provenance = stats::setNames(list(.legacy_row()), version$parquet)`; in the `unchanged`
   return list add `provenance = list()`. (Task 2 replaces the legacy row with the claimed one.)
2. `.migrate_entry()`: in its return list add

```r
    provenance = c(
      stats::setNames(list(.legacy_row()), version$parquet),
      if (length(history)) stats::setNames(list(.legacy_row()), history[[1L]]$parquet)
    ),
```

3. `.update_study_manifest()`: before the `for (name in targets)` loop add
   `provenance <- list()`; inside, after `manifest$datasets[[hit]] <- step$entry`, add
   `provenance <- c(provenance, step$provenance)`; after the loop, before `behind <- character()`:

```r
  for (nm in names(provenance)) manifest <- .set_version_provenance(manifest, nm, provenance[[nm]])
```

4. `register_data()` (`R/register_data.R`): after `if (is.null(manifest$datasets)) manifest$datasets <- list()`,
   add

```r
  if (is.null(release)) manifest <- .set_version_provenance(manifest, version$parquet, .legacy_row())
```

`stats` is base-priority and already used unqualified elsewhere; qualify it here as written.

- [ ] **Step 4: Run to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "version_provenance|registered_versions")'`
Expected: PASS, no regressions in `registered_versions`.

- [ ] **Step 5: Commit**

```bash
git add R/version_provenance.R R/registered_versions.R R/register_data.R tests/testthat/test-version_provenance.R tests/testthat/test-registered_versions.R
git commit -m "Record each registered version's origin in a provenance map"
```

---

### Task 2: Claim the build sidecar

**Files:**
- Modify: `R/version_provenance.R`, `R/registered_versions.R` (`.version_filename()`,
  `.recorded_version_names()`, `.next_version()`, `.migrate_entry()`), `R/register_data.R`
- Test: `tests/testthat/test-version_provenance.R`

**Interfaces:**
- Consumes: `.legacy_row()`, `.set_version_provenance()` (Task 1).
- Produces: `.build_sidecar_path(source_path)` → `<dir>/<stem>.build.yml`;
  `.version_record_name(parquet)` → `<stem>_YYYYMMDD[_rN].build.yml`;
  `.claim_build_record(source_path, source_sha256, parquet, caller)` →
  `list(row, from, to, note)`, where `from`/`to` are the renamed record and its sidecar path
  (`character()` when nothing was moved) and `note` is `NULL` or one sentence.

- [ ] **Step 1: Write the failing tests**

```r
# appended to tests/testthat/test-version_provenance.R

# A build record for the bytes at `source`, as bd will write it.
write_build_sidecar <- function(source, ..., built_sha256 = digest::digest(source, algo = "sha256", file = TRUE)) {
  rec <- utils::modifyList(list(
    schema = 1L, built_sha256 = built_sha256, job = "00_datasets/bd.qmd", view = "cardiac_master_v",
    as_of = "2026-10-01T00:00:00Z", cohort_sha256 = strrep("a", 64), overlay_sha256 = NULL,
    derived_after_overlay = TRUE, attrition = list(n_start = 10L, n_end = 4L)
  ), list(...))
  path <- .build_sidecar_path(source)
  yaml::write_yaml(rec, path)
  path
}

unregistered_study <- function(env = parent.frame()) {
  testthat::skip_if_not_installed("arrow")
  root <- file.path(withr::local_tempdir(.local_envir = env), "study")
  suppressMessages(study_setup(root, "Sidecar fixture", 42L))
  src <- file.path(study_dir("datasets", root), "built.csv")
  utils::write.csv(data.frame(id = 1:3, DEAD = c(1L, 0L, 0L)), src, row.names = FALSE)
  Sys.setFileTime(src, as.POSIXct("2026-09-15 12:00:00", tz = "UTC"))
  list(root = root, src = src)
}

test_that("a matching sidecar makes a bd version and moves beside its parquet", {
  s <- unregistered_study()
  write_build_sidecar(s$src)
  suppressMessages(register_data(s$root, "built.csv"))
  dir <- dirname(s$src)
  expect_false(file.exists(.build_sidecar_path(s$src)))
  expect_true(file.exists(file.path(dir, "built_20260915.build.yml")))
  row <- .version_provenance(.read_manifest(file.path(s$root, "manifest.yaml")), "built_20260915.parquet")
  expect_identical(row$origin, "bd")
  expect_identical(row$build$record, "built_20260915.build.yml")
  expect_identical(row$build$record_sha256,
                   digest::digest(file.path(dir, "built_20260915.build.yml"), algo = "sha256", file = TRUE))
  expect_identical(row$build$view, "cardiac_master_v")
  expect_null(row$build$attrition)
})

test_that("no sidecar gives legacy", {
  s <- unregistered_study()
  suppressMessages(register_data(s$root, "built.csv"))
  row <- .version_provenance(.read_manifest(file.path(s$root, "manifest.yaml")), "built_20260915.parquet")
  expect_identical(row, list(origin = "legacy"))
})

test_that("a sidecar for other bytes gives legacy, says so, and stays put", {
  s <- unregistered_study()
  side <- write_build_sidecar(s$src, built_sha256 = strrep("0", 64))
  expect_message(register_data(s$root, "built.csv"), "describes a different built.csv")
  expect_true(file.exists(side))
  row <- .version_provenance(.read_manifest(file.path(s$root, "manifest.yaml")), "built_20260915.parquet")
  expect_identical(row$origin, "legacy")
})

test_that("an invalid or underived matching record stops and writes nothing", {
  s <- unregistered_study()
  dir <- dirname(s$src)
  before <- sort(list.files(dir))
  side <- write_build_sidecar(s$src, view = NULL)
  expect_error(register_data(s$root, "built.csv"), "missing view")
  expect_identical(sort(list.files(dir)), before |> c(basename(side)) |> sort())
  expect_false(file.exists(file.path(s$root, "manifest.yaml")))

  write_build_sidecar(s$src, derived_after_overlay = FALSE)
  expect_error(register_data(s$root, "built.csv"), "derivations were not recomputed")
  expect_identical(sort(list.files(dir)), before |> c(basename(side)) |> sort())
})

test_that("update_manifest claims a sidecar for a rebuild and keeps it on failure", {
  root <- versioned_study()
  src <- file.path(study_dir("datasets", root), "built.csv")
  utils::write.csv(data.frame(id = 1:4, DEAD = c(1L, 0L, 0L, 1L)), src, row.names = FALSE)
  write_build_sidecar(src)
  withr::with_dir(root, suppressMessages(update_manifest(extract_date = "2026-10-01")))
  m <- .read_manifest(file.path(root, "manifest.yaml"))
  expect_identical(.version_provenance(m, "built_20261001.parquet")$origin, "bd")
  expect_identical(.version_provenance(m, "built_20260915.parquet")$origin, "legacy")
})

test_that("a failed manifest write renames the record back to its sidecar", {
  root <- versioned_study()
  src <- file.path(study_dir("datasets", root), "built.csv")
  utils::write.csv(data.frame(id = 1:4, DEAD = c(1L, 0L, 0L, 1L)), src, row.names = FALSE)
  side <- write_build_sidecar(src)
  local_mocked_bindings(.write_manifest = function(manifest, path) stop("disk full"))
  expect_error(withr::with_dir(root, update_manifest(extract_date = "2026-10-01")), "disk full")
  expect_true(file.exists(side))
  expect_false(file.exists(file.path(dirname(src), "built_20261001.build.yml")))
  expect_false(file.exists(file.path(dirname(src), "built_20261001.parquet")))
})

test_that("a record with no built_sha256 is malformed, not stale", {
  s <- unregistered_study()
  write_build_sidecar(s$src, built_sha256 = NULL)
  expect_error(register_data(s$root, "built.csv"), "built_sha256 must be a SHA-256")
  expect_false(file.exists(file.path(s$root, "manifest.yaml")))
})

test_that("as_of must be a whole, real timestamp", {
  expect_true(.is_iso_timestamp("2026-10-01T00:00:00Z"))
  expect_true(.is_iso_timestamp("2026-10-01T08:30:00.5-04:00"))
  for (bad in c("2026-99-99Tgarbage", "2026-02-30T00:00:00Z", "2026-10-01T25:00:00Z", "2026-10-01", NA)) {
    expect_false(.is_iso_timestamp(bad), info = bad)
  }
})

test_that("a sidecar rewritten during registration is put back and nothing is registered", {
  s <- unregistered_study()
  side <- write_build_sidecar(s$src)
  local_mocked_bindings(.registration_rename = function(from, to) {
    ok <- file.rename(from, to)
    if (identical(basename(from), "built.build.yml")) cat("view: other\n", file = to, append = TRUE)
    ok
  })
  expect_error(register_data(s$root, "built.csv"), "changed while it was being registered")
  expect_true(file.exists(side))
  expect_false(file.exists(file.path(s$root, "manifest.yaml")))
})

test_that("a new version never takes a recorded record's name", {
  expect_true("x_20260915.build.yml" %in% .recorded_version_names(list(list(file = "x.csv", parquet = "x_20260915.parquet"))))
})
```

- [ ] **Step 2: Run to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "version_provenance")'`
Expected: FAIL, `could not find function ".build_sidecar_path"`.

- [ ] **Step 3: Implement the sidecar**

Append to `R/version_provenance.R`:

```r
# bd writes <stem>.build.yml beside the working file; a registered version's
# record shares the version's name.
.build_sidecar_path <- function(source_path) {
  file.path(dirname(source_path), paste0(tools::file_path_sans_ext(basename(source_path)), ".build.yml"))
}

.version_record_name <- function(parquet) sub("[.]parquet$", ".build.yml", parquet)

.build_required <- c("schema", "built_sha256", "job", "view", "as_of", "cohort_sha256",
                     "overlay_sha256", "derived_after_overlay")

.is_sha256 <- function(x) is.character(x) && length(x) == 1L && !is.na(x) && grepl("^[0-9a-f]{64}$", x)

# The whole timestamp, not its prefix: the shape, then the calendar and clock
# (strptime() returns NA for 2026-02-30 and for hour 25; measured 2026-10-13).
.is_iso_timestamp <- function(x) {
  shape <- "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})$"
  is.character(x) && length(x) == 1L && !is.na(x) && grepl(shape, x) &&
    !is.na(as.POSIXct(substr(x, 1L, 19L), format = "%Y-%m-%dT%H:%M:%S", tz = "UTC"))
}

.validate_build_record <- function(rec, file, caller) {
  bad <- function(why) {
    stop(caller, "(): ", file, " is not a valid build record: ", why, ". Nothing was written.", call. = FALSE)
  }
  text <- function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
  missing <- setdiff(.build_required, names(rec))
  if (length(missing)) bad(paste0("missing ", paste(missing, collapse = ", ")))
  if (!identical(rec$schema, 1L)) bad("schema must be 1")
  if (!text(rec$job)) bad("job must be the job file's study-relative path")
  if (!text(rec$view)) bad("missing view")
  if (!.is_iso_timestamp(rec$as_of)) bad("as_of must be an ISO 8601 timestamp, such as 2026-10-01T00:00:00Z")
  if (!.is_sha256(rec$cohort_sha256)) bad("cohort_sha256 must be a SHA-256")
  if (!is.null(rec$overlay_sha256) && !.is_sha256(rec$overlay_sha256)) bad("overlay_sha256 must be a SHA-256 or null")
  if (!is.logical(rec$derived_after_overlay) || length(rec$derived_after_overlay) != 1L ||
        is.na(rec$derived_after_overlay)) {
    bad("derived_after_overlay must be true or false")
  }
  invisible(rec)
}

# Claim the sidecar for the version just written from `source_path`. Only a
# record whose built_sha256 is the hash of the bytes converted is claimed; a
# record for other bytes is left where it is and the version is legacy. The
# caller renames `from` back to `to` if its manifest write fails.
.claim_build_record <- function(source_path, source_sha256, parquet, caller) {
  none <- list(row = .legacy_row(), from = character(), to = character(), note = NULL)
  sidecar <- .build_sidecar_path(source_path)
  if (!file.exists(sidecar)) return(none)
  fail <- function(why) {
    stop(caller, "(): ", basename(sidecar), " ", why, ". Nothing was written.", call. = FALSE)
  }
  # Read the bytes once and parse those bytes, so the record validated is the
  # record whose hash is checked after the move: bd rewriting the sidecar
  # between the read and the rename cannot pair one record's fields with
  # another's checksum.
  bytes <- readBin(sidecar, "raw", file.size(sidecar))
  claimed_sha256 <- digest::digest(bytes, algo = "sha256", serialize = FALSE)
  rec <- tryCatch(yaml::yaml.load(rawToChar(bytes)), error = function(e) {
    fail(paste0("is not valid YAML (", conditionMessage(e), ")"))
  })
  if (!is.list(rec)) fail("is not a valid build record: it is not a mapping")
  # A record without a valid built_sha256 is malformed, not stale: it must
  # not fall through to the legacy branch below.
  if (!.is_sha256(rec$built_sha256)) fail("is not a valid build record: built_sha256 must be a SHA-256")
  if (!identical(rec$built_sha256, source_sha256)) {
    none$note <- paste0(basename(sidecar), " describes a different ", basename(source_path),
                        ", so this version is recorded as legacy")
    return(none)
  }
  .validate_build_record(rec, basename(sidecar), caller)
  if (!isTRUE(rec$derived_after_overlay)) {
    fail(paste0("says its derivations were not recomputed after the corrections overlay was applied, so ",
                basename(source_path), " cannot be registered. Re-run the build"))
  }
  dest <- file.path(dirname(source_path), .version_record_name(parquet))
  # .registration_rename() (R/register_data.R) is file.rename() behind a binding tests can mock.
  if (file.exists(dest) || !.registration_rename(sidecar, dest)) fail(paste0("could not be moved to ", basename(dest)))
  if (!identical(digest::digest(dest, algo = "sha256", file = TRUE), claimed_sha256)) {
    file.rename(dest, sidecar)
    fail("changed while it was being registered. Wait for the build that writes it to finish, then run this again")
  }
  list(
    row = list(origin = "bd", build = list(
      record = basename(dest), record_sha256 = claimed_sha256,
      job = rec$job, view = rec$view, as_of = rec$as_of,
      cohort_sha256 = rec$cohort_sha256, overlay_sha256 = rec$overlay_sha256
    )),
    from = dest, to = sidecar, note = NULL
  )
}
```

In `R/registered_versions.R`:

1. `.recorded_version_names()`: change `c(p, .version_schema_name(p))` to
   `c(p, .version_schema_name(p), .version_record_name(p))`.
2. `.version_filename()`: replace the `free <-` expression with

```r
    side <- c(name, .version_schema_name(name), .version_record_name(name))
    free <- !any(side %in% taken) && !any(file.exists(file.path(dir, side)))
```

3. `.next_version()`: replace everything from `version <- .write_version(...)` to the end of the
   function with

```r
  version <- .write_version(source_path, dir, date, taken, caller = "update_manifest", key = key)
  files <- file.path(dir, c(version$parquet, .version_schema_name(version$parquet)))
  claimed <- FALSE
  on.exit(if (!claimed) unlink(files), add = TRUE)
  claim <- .claim_build_record(source_path, version$source_sha256, version$parquet, "update_manifest")
  claimed <- TRUE
  list(
    entry = .versioned_entry(entry$file, version, extra = .entry_extra(entry),
                             history = c(list(.history_record(entry)), history)),
    written = files,
    restore = list(from = claim$from, to = claim$to),
    provenance = stats::setNames(list(claim$row), version$parquet),
    action = "registered",
    detail = paste0("registered ", version$parquet, " (", version$n_rows, " rows, ", version$n_cols,
                    " columns); previous version kept as ", entry$parquet,
                    if (!is.null(claim$note)) paste0("; ", claim$note) else "")
  )
```

4. `.migrate_entry()`: after `version <- .write_version(...)` insert

```r
  new_files <- file.path(dirname(source_path), c(version$parquet, .version_schema_name(version$parquet)))
  on.exit(if (!returned) unlink(new_files), add = TRUE)
  claim <- .claim_build_record(source_path, version$source_sha256, version$parquet, "update_manifest")
```

   then in its return list: `restore = list(from = c(restore$from, claim$from), to = c(restore$to, claim$to))`,
   `written = new_files`, the `provenance` element from Task 1 with `.legacy_row()` for the new
   version replaced by `claim$row`, and `detail` gains `if (!is.null(claim$note)) paste0("; ", claim$note)`.

5. `register_data()` (`R/register_data.R`), directly after
   `on.exit(if (!registered) unlink(version_files), add = TRUE)`:

```r
  claim <- NULL
  if (is.null(release)) {
    claim <- .claim_build_record(path, version$source_sha256, version$parquet, "register_data")
    on.exit(if (!registered) file.rename(claim$from, claim$to), add = TRUE)
  }
```

   replace Task 1's `.legacy_row()` line with
   `if (is.null(release)) manifest <- .set_version_provenance(manifest, version$parquet, claim$row)`,
   and before the final `study_status(cfg$root)` add `if (!is.null(claim$note)) message(claim$note)`.

`file.rename(character(), character())` returns `logical(0)` and is safe in both rollbacks.

- [ ] **Step 4: Run to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "version_provenance|registered_versions|register_data")'`
Expected: PASS. Measured while planning (yaml as installed, testthat 3.3.2): a `NULL` element
writes as `overlay_sha256: ~` and reads back as a named `NULL`, so `"overlay_sha256" %in% names(rec)`
holds for the default fixture; `utils::modifyList(base, list(view = NULL))` removes `view`, which is
how the "missing view" fixture is made.

- [ ] **Step 5: Commit**

```bash
git add R/version_provenance.R R/registered_versions.R R/register_data.R tests/testthat/test-version_provenance.R
git commit -m "Claim a bd build record as a version's provenance"
```

---

### Task 3: `verify_manifest()` checks build records

**Files:**
- Modify: `R/manifest.R` (new helper beside `.verify_versioned_entry()`; one line in
  `verify_manifest()` before `report <- do.call(rbind, results)`)
- Test: `tests/testthat/test-version_provenance.R`

**Interfaces:**
- Consumes: `.version_provenance()`, the `build$record` / `build$record_sha256` fields (Task 2),
  `.verify_row(file, status, message)` (existing).
- Produces: `.verify_build_records(manifest, resolve)` → data frame of verify rows or `NULL`.

- [ ] **Step 1: Write the failing tests**

```r
test_that("verify_manifest checks build records and stops on a changed or missing one", {
  s <- unregistered_study()
  write_build_sidecar(s$src)
  suppressMessages(register_data(s$root, "built.csv"))
  mp <- file.path(s$root, "manifest.yaml")
  rec <- file.path(dirname(s$src), "built_20260915.build.yml")

  rep <- verify_manifest(mp, stop_on_error = FALSE)
  expect_true(any(rep$file == "built_20260915.parquet (build record)" & rep$status == "OK"))

  cat("# edited\n", file = rec, append = TRUE)
  expect_error(verify_manifest(mp), "provenance of a registered version")
  unlink(rec)
  rep <- verify_manifest(mp, stop_on_error = FALSE)
  expect_identical(rep$status[rep$file == "built_20260915.parquet (build record)"], "FAIL")
})

test_that("a provenance row for no recorded version fails", {
  root <- versioned_study()
  mp <- file.path(root, "manifest.yaml")
  m <- .set_version_provenance(.read_manifest(mp), "ghost_20200101.parquet", list(origin = "legacy"))
  .write_manifest(m, mp)
  rep <- verify_manifest(mp, stop_on_error = FALSE)
  expect_identical(rep$status[rep$file == "ghost_20200101.parquet (provenance)"], "FAIL")
})
```

- [ ] **Step 2: Run to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "version_provenance")'`
Expected: FAIL, no `(build record)` row.

- [ ] **Step 3: Implement**

In `R/manifest.R`, after `.verify_versioned_entry()`:

```r
# Each version's build record (section 4.5 of the one-version-scheme design):
# a missing or edited record FAILs like a missing parquet, and a row naming no
# recorded version means manifest.yaml was edited by hand.
.verify_build_records <- function(manifest, resolve) {
  rows <- if (is.list(manifest$provenance)) manifest$provenance else list()
  if (!length(rows)) return(NULL)
  recorded <- .recorded_version_names(manifest$datasets)
  restore <- " It is the provenance of a registered version: restore it from backup, do not edit it."
  out <- lapply(names(rows), function(parquet) {
    if (!parquet %in% recorded) {
      return(.verify_row(paste0(parquet, " (provenance)"), "FAIL",
                         paste0("manifest.yaml has provenance for ", parquet, ", which no dataset records. ",
                                "Restore manifest.yaml from version control.")))
    }
    build <- rows[[parquet]]$build
    if (!is.list(build)) return(NULL)
    label <- paste0(parquet, " (build record)")
    target <- resolve(build$record)
    if (!file.exists(target)) return(.verify_row(label, "FAIL", paste0(build$record, " is missing.", restore)))
    if (!identical(digest::digest(target, algo = "sha256", file = TRUE), build$record_sha256)) {
      return(.verify_row(label, "FAIL", paste0(build$record, " does not match its recorded checksum.", restore)))
    }
    .verify_row(label, "OK", paste0("SHA-256 match (", build$record, ")"))
  })
  do.call(rbind, out)
}
```

In `verify_manifest()`, directly before `report <- do.call(rbind, results)`:

```r
  results <- c(results, list(.verify_build_records(manifest, resolve_entry)))
```

Read the lines after `report <-` to confirm the stop message is built from each FAIL row's
`message`, so "provenance of a registered version" reaches the error; if it is built from `file`
only, assert on `"built_20260915.parquet (build record)"` instead.

- [ ] **Step 4: Run to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "version_provenance|manifest")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/manifest.R tests/testthat/test-version_provenance.R
git commit -m "verify_manifest() checks each version's build record"
```

---

### Task 4: The working-read context

**Files:**
- Create: `R/working_read.R`, `tests/testthat/setup-working-context.R`,
  `tests/testthat/test-working_read.R`

**Interfaces:**
- Produces: `.hvti_working_default()` → logical(1) or error;
  `.is_interactive()` → `interactive()` (a binding tests can mock);
  `.job_file()` → absolute path or `NULL`;
  `.assert_working_stage(cfg, built, caller = "read_built")` → invisible `TRUE` or error;
  `.working_read_condition(file)` → condition of class
  `c("hvtiRutilities_working_read", "message", "condition")`.

- [ ] **Step 1: Write the failing tests**

```r
# tests/testthat/test-working_read.R
test_that("HVTI_DATA accepts only 'working'", {
  withr::local_envvar(HVTI_DATA = NA)
  expect_false(.hvti_working_default())
  withr::local_envvar(HVTI_DATA = "")
  expect_false(.hvti_working_default())
  withr::local_envvar(HVTI_DATA = "working")
  expect_true(.hvti_working_default())
  withr::local_envvar(HVTI_DATA = "wroking")
  expect_error(.hvti_working_default(), "only accepted value is \"working\"")
})

stage_study <- function(env = parent.frame()) {
  root <- file.path(withr::local_tempdir(.local_envir = env), "study")
  suppressMessages(study_setup(root, "Stage fixture", 42L))
  study_config(root, require_data = FALSE)
}

test_that("the gate allows datasets and descriptive jobs and refuses the rest", {
  cfg <- stage_study()
  local_mocked_bindings(.is_interactive = function() FALSE)
  for (stage in c("datasets", "descriptive")) {
    job <- file.path(study_dir(stage, cfg$root), "job.qmd")
    local_mocked_bindings(.job_file = function() job)
    expect_true(.assert_working_stage(cfg, "built.csv"))
  }
  for (stage in c("distributions", "analyses", "graphs")) {
    job <- file.path(study_dir(stage, cfg$root), "fit", "fit.qmd")
    local_mocked_bindings(.job_file = function() job)
    expect_error(.assert_working_stage(cfg, "built.csv"),
                 paste0(basename(study_dir(stage, cfg$root)), " jobs read registered data only"))
  }
  local_mocked_bindings(.job_file = function() file.path(tempdir(), "elsewhere.qmd"))
  expect_error(.assert_working_stage(cfg, "built.csv"), "outside the study")
  local_mocked_bindings(.job_file = function() NULL)
  expect_error(.assert_working_stage(cfg, "built.csv"), "non-interactive session with no job file")
})

test_that("the interactive console is allowed", {
  cfg <- stage_study()
  local_mocked_bindings(.is_interactive = function() TRUE, .job_file = function() NULL)
  expect_true(.assert_working_stage(cfg, "built.csv"))
})

test_that("a legacy (bare-name) layout is gated by the same stages", {
  root <- file.path(withr::local_tempdir(), "study")
  dir.create(file.path(root, "descriptive"), recursive = TRUE)
  dir.create(file.path(root, "analyses"))
  cfg <- list(root = root)
  local_mocked_bindings(.is_interactive = function() FALSE,
                        .job_file = function() file.path(root, "descriptive", "dc.qmd"))
  expect_true(.assert_working_stage(cfg, "built.csv"))
  local_mocked_bindings(.job_file = function() file.path(root, "analyses", "km.qmd"))
  expect_error(.assert_working_stage(cfg, "built.csv"), "analyses jobs read registered data only")
})

test_that("Rscript's --file names the job", {
  local_mocked_bindings(.knitr_input = function() NULL,
                        .command_args = function() c("/usr/lib/R/bin/exec/R", "--file=30_analyses/fit.R"))
  expect_identical(basename(.job_file()), "fit.R")
})

test_that("Rscript's encoding of spaces in --file is decoded", {
  local_mocked_bindings(.knitr_input = function() NULL,
                        .command_args = function() c("R", "--file=/studies/a~+~b/10_descriptive/dc.R"))
  expect_identical(.job_file(), "/studies/a b/10_descriptive/dc.R")
})

test_that("paths resolve the same whether or not they exist", {
  root <- withr::local_tempdir()
  expect_identical(.real_path(file.path(root, "no", "such.qmd")),
                   file.path(normalizePath(root), "no", "such.qmd"))
})

test_that("the working-read condition carries its class", {
  cnd <- .working_read_condition("built.csv")
  expect_s3_class(cnd, "hvtiRutilities_working_read")
  expect_match(conditionMessage(cnd), "Results from it are a draft")
})
```

- [ ] **Step 2: Run to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "working_read")'`
Expected: FAIL, `could not find function ".hvti_working_default"`.

- [ ] **Step 3: Implement**

```r
# R/working_read.R
# Reading the working dataset before it is registered. Design:
# dev/specs/2026-10-13-one-version-scheme-design.md, section 5.1.
#
# Any read that is not of a dated version serves the working file, so the
# gate applies to the data read, not to the `working` argument. It is honoured
# in the interactive console and in jobs in the study's datasets or descriptive
# folder; everywhere else the job must read registered data.

.hvti_working_default <- function() {
  value <- Sys.getenv("HVTI_DATA", "")
  if (!nzchar(value)) return(FALSE)
  if (identical(value, "working")) return(TRUE)
  stop("HVTI_DATA is \"", value, "\". The only accepted value is \"working\", which reads the working ",
       "dataset; unset HVTI_DATA to read registered data.", call. = FALSE)
}

# Bindings over base and knitr so tests can stand in for a render or Rscript.
.is_interactive <- function() interactive()
.command_args <- function() commandArgs(trailingOnly = FALSE)
.knitr_input <- function() {
  if (!requireNamespace("knitr", quietly = TRUE)) return(NULL)
  knitr::current_input(dir = TRUE)
}

# The job being run: the document knitr is rendering, else the script Rscript was given.
.job_file <- function() {
  input <- .knitr_input()
  if (!is.null(input)) return(input)
  arg <- grep("^--file=", .command_args(), value = TRUE)
  # R writes a space in the script's path as "~+~" (measured 2026-10-13).
  if (length(arg)) return(gsub("~+~", " ", sub("^--file=", "", arg[[1L]]), fixed = TRUE))
  NULL
}

# Resolve symlinks (macOS /var -> /private/var, a symlinked mount) the same way
# for a path whether or not it exists: normalise its deepest existing ancestor
# and re-append the rest. normalizePath() alone leaves a missing path as given.
.real_path <- function(path) {
  path <- path.expand(path)
  rest <- character()
  while (!file.exists(path) && !identical(dirname(path), path)) {
    rest <- c(basename(path), rest)
    path <- dirname(path)
  }
  do.call(file.path, as.list(c(normalizePath(path, mustWork = FALSE), rest)))
}

.assert_working_stage <- function(cfg, built, caller = "read_built") {
  job <- .job_file()
  if (is.null(job) && .is_interactive()) return(invisible(TRUE))
  allowed <- vapply(c("datasets", "descriptive"), function(k) basename(study_dir(k, cfg$root)), character(1))
  stage <- NULL
  if (!is.null(job)) {
    job <- .real_path(job)
    root <- .real_path(cfg$root)
    if (startsWith(job, paste0(root, "/")) || startsWith(job, paste0(root, "\\"))) {
      stage <- strsplit(substring(job, nchar(root) + 2L), "[/\\\\]")[[1L]][[1L]]
    }
  }
  if (!is.null(stage) && stage %in% allowed) return(invisible(TRUE))
  who <- if (is.null(job)) {
    "A non-interactive session with no job file can"
  } else if (is.null(stage)) {
    paste0(basename(job), " is outside the study, so it can")
  } else {
    paste0(stage, " jobs")
  }
  stop(caller, "(): ", who, " read registered data only. ", built,
       " has no dated version, or HVTI_DATA asks for the working file. Register it with register_data() ",
       "or update_manifest(), or unset HVTI_DATA.", call. = FALSE)
}

.working_read_condition <- function(file) {
  structure(
    class = c("hvtiRutilities_working_read", "message", "condition"),
    list(message = paste0("Read the working ", file, ", not a registered version. Results from it are a draft.\n"),
         call = NULL)
  )
}
```

`tests/testthat/setup-working-context.R`, so the rest of the suite reads as the console would:

```r
# The gate in read_built() refuses a non-interactive session with no job file,
# which is what testthat is. Tests that are not about the gate read as the
# interactive console would; test-working_read.R mocks these bindings itself.
testthat::local_mocked_bindings(.is_interactive = function() TRUE, .knitr_input = function() NULL,
                                .command_args = function() character(),
                                .package = "hvtiRutilities", .env = testthat::teardown_env())
```

It mocks the inputs `.job_file()` reads, not `.job_file()` itself, so the `--file=` test can still
call the real `.job_file()`. Mocking `.command_args` also matters under `R CMD check`, whose test
run passes `--file=testthat.R`, a job file outside any study.

A test's own `local_mocked_bindings()` call overrides these for that test only.

- [ ] **Step 4: Run to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "working_read")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/working_read.R tests/testthat/setup-working-context.R tests/testthat/test-working_read.R
git commit -m "Add the HVTI_DATA default and the stage gate for working reads"
```

---

### Task 5: `read_built()` and `provenance_data()` read the working file

**Files:**
- Modify: `R/study_data.R` (`read_built()` signature, body, roxygen, example), `R/provenance.R`
  (`provenance_data()`)
- Test: `tests/testthat/test-working_read.R`

**Interfaces:**
- Consumes: everything Task 4 produces; `.is_versioned()`, `.read_registered_version()`,
  `.cache_read()`, `.normalise_built()` (existing).
- Produces: `read_built(cfg, refresh = FALSE, dataset = "study", allow_withdrawn = FALSE,
  working = .hvti_working_default())`;
  `provenance_data(dataset = "study", cfg = study_config(), role = "analysis",
  working = .hvti_working_default())`.

- [ ] **Step 1: Write the failing tests**

```r
test_that("a working read of a registered study reads the source and writes nothing", {
  root <- versioned_study()
  cfg <- study_config(root)
  src <- built_path(cfg)
  utils::write.csv(data.frame(id = 1:4, DEAD = c(1L, 0L, 0L, 1L)), src, row.names = FALSE)
  before <- list(files = sort(list.files(dirname(src))),
                 manifest = digest::digest(file.path(root, "manifest.yaml"), algo = "sha256", file = TRUE))
  expect_message(d <- read_built(cfg, working = TRUE), class = "hvtiRutilities_working_read")
  expect_identical(nrow(d), 4L)
  expect_identical(names(d), c("id", "dead"))
  expect_identical(sort(list.files(dirname(src))), before$files)
  expect_identical(digest::digest(file.path(root, "manifest.yaml"), algo = "sha256", file = TRUE), before$manifest)
  expect_identical(nrow(suppressMessages(read_built(cfg))), 3L)
})

test_that("HVTI_DATA=working switches the default and refresh is refused", {
  root <- versioned_study()
  cfg <- study_config(root)
  withr::local_envvar(HVTI_DATA = "working")
  expect_message(read_built(cfg), class = "hvtiRutilities_working_read")
  expect_error(read_built(cfg, refresh = TRUE), "nothing is cached")
  expect_no_message(read_built(cfg, working = FALSE), class = "hvtiRutilities_working_read")
})

test_that("an analysis job cannot read a study with no dated version, whatever HVTI_DATA says", {
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Unregistered", 42L))
  utils::write.csv(data.frame(id = 1:3, DEAD = c(1L, 0L, 0L)),
                   file.path(study_dir("datasets", root), "built.csv"), row.names = FALSE)
  raw <- yaml::read_yaml(file.path(root, "_study.yml"))
  raw$built <- "built.csv"
  yaml::write_yaml(raw, file.path(root, "_study.yml"))
  cfg <- study_config(root)
  withr::local_envvar(HVTI_DATA = NA)
  local_mocked_bindings(.is_interactive = function() FALSE,
                        .job_file = function() file.path(study_dir("analyses", root), "km", "km.qmd"))
  expect_error(read_built(cfg), "jobs read registered data only")

  local_mocked_bindings(.job_file = function() file.path(study_dir("descriptive", root), "dc", "dc.qmd"))
  expect_message(read_built(cfg), class = "hvtiRutilities_working_read")
  # The cache wrote a role: source entry on that read; the dataset is still not registered.
  local_mocked_bindings(.job_file = function() file.path(study_dir("analyses", root), "km", "km.qmd"))
  expect_error(read_built(cfg), "jobs read registered data only")
})

test_that("a legacy role: source entry is gated until update_manifest() converts it", {
  root <- versioned_study()
  mp <- file.path(root, "manifest.yaml")
  m <- .read_manifest(mp)
  e <- m$datasets[[1]]
  m$datasets[[1]] <- list(file = e$file, extract_date = e$extract_date, n_rows = e$n_rows,
                          sha256 = e$source_sha256, role = "source", n_cols = e$n_cols)
  m$provenance <- NULL
  yaml::write_yaml(m, mp)
  local_mocked_bindings(.is_interactive = function() FALSE,
                        .job_file = function() file.path(study_dir("graphs", root), "g", "g.qmd"))
  expect_error(read_built(study_config(root)), "update_manifest")
})

test_that("a release-pinned dataset keeps reading ungated while the release path is deprecated", {
  fx <- suppressMessages(suppressWarnings(make_release_aware_study(withr::local_tempdir())))
  local_mocked_bindings(.is_interactive = function() FALSE,
                        .job_file = function() file.path(study_dir("analyses", fx$root), "km", "km.qmd"))
  cfg <- suppressWarnings(study_config(fx$root), classes = "deprecatedWarning")
  expect_no_message(read_built(cfg), class = "hvtiRutilities_working_read")
})

test_that("provenance_data records the source for a working read", {
  root <- versioned_study()
  cfg <- study_config(root)
  expect_match(provenance_data(cfg = cfg)$path, "built_20260915[.]parquet$")
  expect_match(provenance_data(cfg = cfg, working = TRUE)$path, "built[.]csv$")
})
```

- [ ] **Step 2: Run to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "working_read")'`
Expected: FAIL, `unused argument (working = TRUE)`.

- [ ] **Step 3: Implement `read_built()`**

Signature (new argument last, so positional callers are unaffected):

```r
read_built <- function(cfg = study_config(), refresh = FALSE,
                       dataset = "study", allow_withdrawn = FALSE,
                       working = .hvti_working_default()) {
```

At the top, after the `allow_withdrawn` check:

```r
  if (!is.logical(working) || length(working) != 1L || is.na(working)) {
    stop("working must be TRUE or FALSE", call. = FALSE)
  }
```

After `entry <- .manifest_entry(manifest_path, p)` and before the combined-parents check:

```r
  # Only a dated version is registered data. Any other read serves the working
  # file, so it passes the stage gate and is reported as a draft. A release-
  # pinned contract is exempt while the release path is deprecated: it was
  # verified against its catalog above, and that path keeps working until the
  # removal release, which drops this exemption with it.
  unregistered <- !.is_versioned(entry) && is.null(contract$release)
  if (working || unregistered) {
    .assert_working_stage(cfg, basename(p))
    if (working) {
      if (isTRUE(refresh)) {
        stop("read_built(): refresh = TRUE does not apply to a working read: nothing is cached.", call. = FALSE)
      }
      if (!file.exists(p)) stop("read_built(): missing ", p, call. = FALSE)
      raw <- read_clinical_data(p, convert_types = FALSE)
      .assert_no_lowercase_collision(raw, p)
      message(.working_read_condition(basename(p)))
      return(.normalise_built(as.data.frame(raw)))
    }
  }
```

At the very end, replace `.normalise_built(d)` with

```r
  if (unregistered) message(.working_read_condition(basename(p)))
  .normalise_built(d)
```

(the versioned branch returns earlier, and a release-pinned read reaches this line without the
message).

Roxygen: add, in Rd markup,

```r
#' @param working Logical. If \code{TRUE}, read the working dataset as it stands
#'   rather than its registered version, writing nothing. Defaults to
#'   \code{TRUE} when the environment variable \code{HVTI_DATA} is
#'   \code{"working"}. Any read that is not of a dated version is a working read:
#'   it is allowed only in the interactive console and in jobs in the study's
#'   datasets or descriptive folder, and signals a message of class
#'   \code{hvtiRutilities_working_read}.
```

Example: the current example reads an unregistered CSV, which the gate refuses under
`R CMD check`. Replace its body with a registered study:

```r
#' @examples
#' if (requireNamespace("arrow", quietly = TRUE)) {
#'   root <- file.path(tempdir(), "read-built-example")
#'   suppressMessages(study_setup(root, "Example", 1L))
#'   write.csv(data.frame(DEAD = c(1, 0, 0), IV_DEAD = 1:3),
#'             file.path(study_dir("datasets", root), "example.csv"), row.names = FALSE)
#'   suppressMessages(register_data(root, "example.csv"))
#'   names(read_built(study_config(root)))
#'   unlink(root, recursive = TRUE)
#' }
```

`study_setup(root, study, study_tracker_id)` with its defaults (`renv = FALSE`, `cleanup = FALSE`,
`adopt = FALSE`) writes only under `root` and starts no git or renv process (read while planning,
2026-10-13); every test fixture already relies on that. The example therefore writes only to
`tempdir()`, as the Cookbook requires.

- [ ] **Step 4: Implement `provenance_data()`**

```r
provenance_data <- function(dataset = "study", cfg = study_config(),
                            role = "analysis", working = .hvti_working_default()) {
  dataset <- .canonical_dataset(dataset)
  .provenance_role(role, "provenance_data")
  .study_dataset(cfg, dataset)
  source <- built_path(cfg, dataset)
  entry <- .manifest_entry(file.path(cfg$root, "manifest.yaml"), source)
  authoritative <- if (isTRUE(working)) source else .authoritative_path(entry, source)
```

(the rest unchanged), and document `working` with one Rd sentence: "If \code{TRUE}, record the
working source file, as \code{\link{read_built}(working = TRUE)} reads it."

- [ ] **Step 5: Run the whole suite**

Run: `Rscript -e 'devtools::test()'`
Expected: PASS. The setup file makes every other test the interactive console, so existing
unregistered reads keep passing; any test that asserts `expect_no_message(read_built(...))` on
a non-dated dataset now sees the working-read message. Change those to
`expect_no_message(..., class = "hvtiRutilities_source_changed")` or wrap the read in
`suppressMessages(..., classes = "hvtiRutilities_working_read")`, one by one, and say in the
commit message how many were changed.

- [ ] **Step 6: Commit**

```bash
git add R/study_data.R R/provenance.R tests/testthat/
git commit -m "read_built() serves the working file only where the stage gate allows"
```

---

### Task 5b: Migrate a promoted entry from its parquet

The gate stops every non-dated read, and `update_manifest()` is the way out. But a legacy
**promoted** entry (`role: primary`, no `parquet:`) whose source was retired takes the
"not on disk; jobs keep reading built.parquet" branch of `.update_study_manifest()` and gets no
dated version, so its analysis jobs would stay blocked. Measured 2026-10-13: no study on the share
is in this state (the one `primary` entry is already dated), but the path must exist.

**Files:**
- Modify: `R/registered_versions.R` (new `.migrate_promoted_entry()`; the missing-source branch
  of `.update_study_manifest()`)
- Test: `tests/testthat/test-version_provenance.R`

**Interfaces:**
- Consumes: `.version_filename()`, `.reserved_names()`, `.versioned_entry()`, `.entry_extra()`,
  `.legacy_row()`, `.derived_paths()` (existing and Task 1).
- Produces: `.migrate_promoted_entry(entry, source_path, datasets)` → a step list
  (`entry`, `restore`, `provenance`, `action = "migrated"`, `detail`) or `NULL` when the legacy
  parquet is missing or does not match the entry's `sha256`.

- [ ] **Step 1: Write the failing test**

```r
# A legacy promoted entry: the data is <stem>.parquet and the source is retired.
promoted_study <- function(env = parent.frame()) {
  root <- versioned_study(env)
  dir <- study_dir("datasets", root)
  file.rename(file.path(dir, "built_20260915.parquet"), file.path(dir, "built.parquet"))
  file.rename(file.path(dir, "built_20260915.schema.csv"), file.path(dir, "built.schema.csv"))
  mp <- file.path(root, "manifest.yaml")
  e <- .read_manifest(mp)$datasets[[1]]
  yaml::write_yaml(list(datasets = list(list(
    file = "built.csv", role = "primary", sha256 = e$sha256, source_sha256 = e$source_sha256,
    extract_date = e$extract_date, n_rows = e$n_rows, n_cols = e$n_cols, promoted_date = "2026-09-20"
  ))), mp)
  unlink(file.path(dir, "built.csv"))
  root
}

test_that("a promoted entry with a retired source migrates from its parquet and lifts the gate", {
  root <- promoted_study()
  dir <- study_dir("datasets", root)
  before <- digest::digest(file.path(dir, "built.parquet"), algo = "sha256", file = TRUE)
  local_mocked_bindings(.is_interactive = function() FALSE,
                        .job_file = function() file.path(study_dir("analyses", root), "km", "km.qmd"))
  expect_error(read_built(study_config(root)), "jobs read registered data only")

  out <- withr::with_dir(root, suppressMessages(update_manifest()))
  expect_identical(out$action, "migrated")
  e <- .read_manifest(file.path(root, "manifest.yaml"))$datasets[[1]]
  expect_identical(e$parquet, "built_20260915.parquet")
  expect_identical(e$recovered_from, "promoted")
  expect_identical(e$sha256, before)
  expect_identical(e$promoted_date, "2026-09-20")
  expect_false(file.exists(file.path(dir, "built.parquet")))
  expect_identical(nrow(read_built(study_config(root))), 3L)
})

test_that("a promoted parquet that does not match its hash is not migrated", {
  root <- promoted_study()
  cat("x", file = file.path(study_dir("datasets", root), "built.parquet"), append = TRUE)
  out <- withr::with_dir(root, suppressMessages(update_manifest()))
  expect_false(identical(out$action, "migrated"))
  expect_false(file.exists(file.path(study_dir("datasets", root), "built_20260915.parquet")))
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `Rscript -e 'devtools::test(filter = "version_provenance")'`
Expected: FAIL, `out$action` is `"unchanged"`.

- [ ] **Step 3: Implement**

In `R/registered_versions.R`, after `.migrate_entry()`:

```r
# A legacy promoted entry (role: primary, no parquet:) whose source was retired
# holds its data only in <stem>.parquet. Rename that file to a dated version:
# it is the only copy, so it is moved, never rewritten, and only once its hash
# matches the entry. The caller renames it back if the manifest write fails.
.migrate_promoted_entry <- function(entry, source_path, datasets = list()) {
  legacy <- .derived_paths(source_path)
  if (!file.exists(legacy$parquet) ||
        !identical(digest::digest(legacy$parquet, algo = "sha256", file = TRUE), entry$sha256)) {
    return(NULL)
  }
  dir <- dirname(source_path)
  date <- if (is.null(entry$extract_date)) .mtime_date(legacy$parquet) else entry$extract_date
  name <- .version_filename(tools::file_path_sans_ext(entry$file), date, dir, .reserved_names(datasets))
  parquet <- file.path(dir, name)
  schema <- file.path(dir, .version_schema_name(name))
  if (!file.rename(legacy$parquet, parquet)) return(NULL)
  from <- parquet
  to <- legacy$parquet
  if (file.exists(legacy$schema)) {
    if (!file.rename(legacy$schema, schema)) {
      file.rename(parquet, legacy$parquet)
      return(NULL)
    }
    from <- c(from, schema)
    to <- c(to, legacy$schema)
  }
  version <- list(
    parquet = name, sha256 = entry$sha256, source_sha256 = entry$source_sha256,
    extract_date = format(as.Date(date), "%Y-%m-%d"),
    n_rows = as.integer(entry$n_rows), n_cols = as.integer(entry$n_cols),
    schema_sha256 = if (file.exists(schema)) digest::digest(schema, algo = "sha256", file = TRUE) else entry$schema_sha256,
    reader = entry$reader, recovered_from = "promoted"
  )
  version <- Filter(Negate(is.null), version)
  list(
    entry = .versioned_entry(entry$file, version, extra = .entry_extra(entry)),
    restore = list(from = from, to = to),
    provenance = stats::setNames(list(.legacy_row()), name),
    action = "migrated",
    detail = paste0("registered ", name, " from the promoted ", basename(legacy$parquet),
                    "; its source ", entry$file, " was retired")
  )
}
```

In `.update_study_manifest()`, at the top of the `if (!file.exists(source_path)) {` block:

```r
      promoted <- if (!.is_versioned(entry) && identical(entry$role, "primary")) {
        .migrate_promoted_entry(entry, source_path, manifest$datasets)
      }
      if (!is.null(promoted)) {
        restore$from <- c(restore$from, promoted$restore$from)
        restore$to <- c(restore$to, promoted$restore$to)
        provenance <- c(provenance, promoted$provenance)
        manifest$datasets[[hit]] <- promoted$entry
        rows[[name]] <- .manifest_update_row(name, promoted$action, promoted$detail)
        next
      }
```

`changed` already counts `"migrated"`, so the manifest is written; a failed write renames both
files back through `restore`.

- [ ] **Step 4: Run to verify it passes**

Run: `Rscript -e 'devtools::test(filter = "version_provenance|registered_versions")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/registered_versions.R tests/testthat/test-version_provenance.R
git commit -m "update_manifest() migrates a promoted entry whose source was retired"
```

---

### Task 6: `review_built()`

**Files:**
- Create: `R/review_built.R`, `tests/testthat/test-review_built.R`
- Modify: `R/registered_versions.R` (`.source_changed_condition()` text and the `registered`
  detail in `.next_version()`), `_pkgdown.yml`

**Interfaces:**
- Consumes: `.read_registered_version()`, `.source_changed()`, `compare_datasets()`,
  `.normalise_built()`, `.manifest_entry()` (existing).
- Produces: exported `review_built(cfg = study_config(), dataset = "study")` → object of class
  `built_review` with elements `dataset`, `registered`, `working`, `changed`, `comparison`;
  exported S3 method `print.built_review`.

- [ ] **Step 1: Write the failing tests**

```r
# tests/testthat/test-review_built.R
test_that("an unchanged source is reviewed without a comparison", {
  root <- versioned_study()
  r <- review_built(study_config(root))
  expect_s3_class(r, "built_review")
  expect_false(r$changed)
  expect_null(r$comparison)
  expect_identical(r$registered$parquet, "built_20260915.parquet")
  expect_output(print(r), "unchanged since 2026-09-15")
})

test_that("a rebuilt source is compared with the registered version", {
  root <- versioned_study()
  cfg <- study_config(root)
  utils::write.csv(data.frame(id = 1:4, DEAD = c(1L, 0L, 0L, 1L), AGE = 60:63), built_path(cfg), row.names = FALSE)
  r <- review_built(cfg)
  expect_true(r$changed)
  expect_identical(r$working$n_rows, 4L)
  expect_identical(r$comparison$rows_old, 3L)
  expect_identical(r$comparison$rows_new, 4L)
  expect_identical(r$comparison$cols_added, "age")
  expect_output(print(r), "update_manifest")
})

test_that("a missing source stops rather than reading as unchanged", {
  root <- versioned_study()
  cfg <- study_config(root)
  unlink(built_path(cfg))
  expect_error(review_built(cfg), "is not on disk")
})

test_that("a dataset with no dated version stops", {
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(study_setup(root, "Nothing registered", 42L))
  raw <- yaml::read_yaml(file.path(root, "_study.yml"))
  raw$built <- "built.csv"
  yaml::write_yaml(raw, file.path(root, "_study.yml"))
  utils::write.csv(data.frame(id = 1:3), file.path(study_dir("datasets", root), "built.csv"), row.names = FALSE)
  expect_error(review_built(study_config(root)), "nothing is registered to compare against")
})
```

Check `compare_datasets()`'s returned element types (`rows_old` may be an integer or a double)
by running it once on two small frames before fixing `expect_identical` vs `expect_equal`.

- [ ] **Step 2: Run to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "review_built")'`
Expected: FAIL, `could not find function "review_built"`.

- [ ] **Step 3: Implement**

```r
# R/review_built.R

#' Review a rebuilt study dataset before registering it
#'
#' @description
#' Compares the working dataset, as it stands in the study's datasets folder,
#' with its registered version, the dated parquet jobs read. It reads both and
#' writes nothing. Run it after a rebuild and before
#' \code{\link{update_manifest}()}, which registers the rebuilt file as the next
#' version. It describes how the data changed; it does not certify that the
#' new file is analytically or clinically correct.
#'
#' @param cfg List. A study manifest from \code{\link{study_config}}.
#' @param dataset Character(1). Logical dataset name. Defaults to
#'   \code{"study"}. \code{"built"} is a second name for \code{"study"}.
#'
#' @return An object of class \code{"built_review"} with
#'   \describe{
#'     \item{dataset}{The logical dataset name.}
#'     \item{registered}{The current version record from \code{manifest.yaml}.}
#'     \item{working}{A list with the source file's \code{sha256}, \code{n_rows} and \code{n_cols}.}
#'     \item{changed}{\code{TRUE} when the source differs from the registered version.}
#'     \item{comparison}{A \code{\link{compare_datasets}} result, or \code{NULL} when unchanged.}
#'   }
#'
#' @seealso \code{\link{update_manifest}}, \code{\link{read_built}}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' review_built(study_config())
#' }
review_built <- function(cfg = study_config(), dataset = "study") {
  dataset <- .canonical_dataset(dataset)
  .study_dataset(cfg, dataset)
  p <- built_path(cfg, dataset)
  entry <- .manifest_entry(file.path(cfg$root, "manifest.yaml"), p)
  if (!.is_versioned(entry)) {
    stop("review_built(): nothing is registered to compare against for ", basename(p),
         ". Register it with register_data(), or run update_manifest() to convert a legacy entry.", call. = FALSE)
  }
  # .source_changed() reads a missing source as unchanged; a review must not.
  if (!file.exists(p)) {
    stop("review_built(): ", basename(p), " is not on disk, so there is nothing to review. Jobs keep reading ",
         entry$parquet, ".", call. = FALSE)
  }
  changed <- .source_changed(p, entry)
  raw <- read_clinical_data(p, convert_types = FALSE)
  .assert_no_lowercase_collision(raw, p, "review_built")
  working <- .normalise_built(as.data.frame(raw))
  comparison <- if (changed) {
    registered <- suppressMessages(.read_registered_version(p, entry),
                                   classes = "hvtiRutilities_source_changed")
    compare_datasets(.normalise_built(registered), working)
  }
  structure(
    list(dataset = dataset, registered = .history_record(entry),
         working = list(sha256 = digest::digest(p, algo = "sha256", file = TRUE),
                        n_rows = nrow(working), n_cols = ncol(working)),
         changed = changed, comparison = comparison),
    class = "built_review"
  )
}

#' @export
print.built_review <- function(x, ...) {
  r <- x$registered
  if (!x$changed) {
    cat(x$dataset, ": the working file is unchanged since ", r$extract_date, " (", r$parquet, ").\n", sep = "")
    return(invisible(x))
  }
  cat(x$dataset, ": the working file differs from ", r$parquet, " (registered ", r$extract_date, ").\n", sep = "")
  print(x$comparison)
  cat("Register it as the next version with hvtiRutilities::update_manifest().\n")
  invisible(x)
}
```

Check that `compare_datasets()` results have a print method (`methods(class = class(x$comparison))`);
if not, print `rows_old`, `rows_new`, `cols_added` and `cols_dropped` explicitly instead of
`print(x$comparison)`.

In `R/registered_versions.R`, `.source_changed_condition()`: change the last sentence to
`". Review it with hvtiRutilities::review_built(), then run hvtiRutilities::update_manifest() to register it.\n"`.
Check the existing test "the source-changed condition names the fix" still matches, and update its
pattern if it pins the old sentence.

`_pkgdown.yml`: in the section listing `read_built`, add `  - review_built` after
`  - read_built`.

- [ ] **Step 4: Run, document, and confirm the site index**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "review_built|registered_versions")'`
Expected: PASS; `NAMESPACE` gains `export(review_built)` and `S3method(print,built_review)`.
Run: `Rscript -e 'pkgdown::check_pkgdown()'`
Expected: no missing topics.

- [ ] **Step 5: Commit**

```bash
git add R/review_built.R R/registered_versions.R _pkgdown.yml NAMESPACE man/ tests/testthat/test-review_built.R
git commit -m "Add review_built() to compare a rebuilt dataset with its registered version"
```

---

### Task 7: Deprecate the release path

**Files:**
- Modify: `R/data_updates.R` (`check_data_updates()`, `review_data_update()`,
  `adopt_data_update()`), `R/register_data.R`, `R/study_data.R`, `R/study_config.R`
- Test: `tests/testthat/test-data_updates.R`, `tests/testthat/test-version_provenance.R`

**Interfaces:**
- Consumes: `.hvti_deprecated` (existing environment of once-per-session flags).
- Produces: `.deprecated_arg(fn, arg, instead)` (internal warning helper).

- [ ] **Step 1: Write the failing tests**

```r
# appended to tests/testthat/test-version_provenance.R
test_that("each retired function and argument warns, naming its replacement", {
  expect_warning(.deprecated_arg("register_data", "release_id", "a build record sidecar"),
                 class = "deprecatedWarning")
  expect_warning(.deprecated_arg("register_data", "release_id", "a build record sidecar"),
                 "release_id.*a build record sidecar")
})
```

In `tests/testthat/test-data_updates.R`, at the first call of each of `check_data_updates()`,
`review_data_update()` and `adopt_data_update()`, wrap it as
`expect_warning(<call>, class = "deprecatedWarning")`; elsewhere in that file wrap calls in
`suppressWarnings(<call>, classes = "deprecatedWarning")` so existing assertions keep their
meaning. Add one test that `study_config()` warns once per session on a `release:` contract:

```r
test_that("study_config warns once on a release contract", {
  root <- suppressMessages(make_release_aware_study(withr::local_tempdir()))$root   # helper-release.R
  spent <- .hvti_deprecated$release_contract
  assign("release_contract", FALSE, envir = .hvti_deprecated)
  withr::defer(assign("release_contract", spent, envir = .hvti_deprecated))
  expect_warning(study_config(root), class = "deprecatedWarning")
  expect_no_warning(study_config(root))
})
```

In `tests/testthat/setup-deprecation-notices.R`, add `"release_contract"` to the `for (flag in ...)`
vector and to the `rm(list = ...)` in its `withr::defer()`, so the notice is spent before any
test runs, exactly as the two existing notices are. Every release fixture is a new temporary
study, so a per-study flag would fire in nearly every release test.
```

- [ ] **Step 2: Run to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "data_updates|version_provenance")'`
Expected: FAIL.

- [ ] **Step 3: Implement**

In `R/version_provenance.R`:

```r
.deprecated_arg <- function(fn, arg, instead) {
  warning(structure(
    class = c("deprecatedWarning", "warning", "condition"),
    list(message = paste0(fn, "(", arg, " =) is deprecated: catalog releases are retired. Use ", instead,
                          " instead. It will be removed in a later release."),
         call = NULL)
  ))
}
```

- `check_data_updates()`: first line `.Deprecated("study_status", package = "hvtiRutilities",
  msg = "check_data_updates() is deprecated: catalog releases are retired. Use study_status() or verify_manifest(), whose PENDING rows report a rebuilt dataset.")`.
- `review_data_update()`: same with `"review_built"` and its sentence.
- `adopt_data_update()`: same with `"update_manifest"` and its sentence.
- `register_data()`: after the `xor()` check, `if (!is.null(release_id)) .deprecated_arg("register_data", "catalog_dataset, release_id", "a build record sidecar and plain register_data()")`.
- `read_built()`: after the `allow_withdrawn` check, `if (!missing(allow_withdrawn)) .deprecated_arg("read_built", "allow_withdrawn", "a dated version, which is never withdrawn,")`.
- `study_config()` (`R/study_config.R`), after `raw$release <- .study_validate_release(...)`:

```r
  if (!is.null(raw$release) || any(vapply(raw$additional_datasets, function(a) !is.null(a$release), logical(1)))) {
    if (!isTRUE(.hvti_deprecated$release_contract)) {
      assign("release_contract", TRUE, envir = .hvti_deprecated)
      warning(structure(class = c("deprecatedWarning", "warning", "condition"), list(
        message = paste0(found, " pins a dataset to a catalog release. Catalog releases are retired and will ",
                         "stop being read in a later release; remove the release: block and run update_manifest()."),
        call = NULL)))
    }
  }
```

Move this block to after `raw$additional_datasets <- .study_validate_additional(...)` if that is
where `additional_datasets` is validated, so `vapply` sees a list.

Update the roxygen `@description` of the three functions and the `@param` of the two arguments
with one Rd sentence each: "\strong{Deprecated.} Catalog releases are retired; use
\code{\link{<replacement>}}."

- [ ] **Step 4: Run the whole suite**

Run: `Rscript -e 'devtools::document(); devtools::test()'`
Expected: PASS with no stray `deprecatedWarning` reported by testthat. A stray one names a test
that calls the release path without wrapping; wrap it as in Step 1.

- [ ] **Step 5: Commit**

```bash
git add R/ man/ tests/testthat/
git commit -m "Deprecate the catalog release path"
```

---

### Task 8: Vignette and news

**Files:**
- Modify: `vignettes/dataset-versioning.qmd`
- Create: `news/feat-one-version-scheme.md`

- [ ] **Step 1: Rewrite the vignette's release sections**

Read `vignettes/dataset-versioning.qmd` lines 280-340 (the `UPDATE AVAILABLE`, review/adopt and
`allow_withdrawn` sections). Replace them with three short sections, in house voice (apply the
`ehrlinger-writing` skill), all chunks `eval=FALSE`:

1. "Looking at a rebuild before registering it": `review_built()`, then `update_manifest()`.
2. "Running a job on the working file": `HVTI_DATA=working quarto render 10_descriptive/...`,
   which stages allow it, that the report is a draft, and that analysis jobs stop until the
   dataset has a dated version.
3. "How a version was produced": `origin`, the build record beside the parquet, and that the
   record stays on the share.

Delete the release prose rather than marking it deprecated; the functions' help pages carry the
deprecation.

- [ ] **Step 2: Write the news fragment**

```markdown
* Registered versions record how their data were produced. `manifest.yaml` gains a
  `provenance:` map, keyed by parquet name: `origin: bd` with a pointer to the build record
  when a build left a `<stem>.build.yml` describing exactly the file registered, and
  `origin: legacy` otherwise. `verify_manifest()` checks each build record.
* `read_built(working = TRUE)`, or `HVTI_DATA=working`, reads the working dataset before it is
  registered. Any read that is not of a dated version is a working read: it is allowed in the
  console and in datasets and descriptive jobs, stops in distribution, analysis and graph jobs,
  and signals `hvtiRutilities_working_read`. **A study still on a legacy registration stops in
  those jobs until `update_manifest()` converts it.**
* New `review_built()` compares a rebuilt dataset with its registered version before
  `update_manifest()` registers it.
* The catalog release path is deprecated: `check_data_updates()`, `review_data_update()`,
  `adopt_data_update()`, `register_data(catalog_dataset =, release_id =)` and
  `read_built(allow_withdrawn =)` warn, and `study_config()` warns once on a `release:`
  contract. They will be removed in a later release.
```

- [ ] **Step 3: Commit**

```bash
git add vignettes/dataset-versioning.qmd news/feat-one-version-scheme.md
git commit -m "Document dated-version review, working reads and provenance"
```

---

### Task 9: Gates

- [ ] **Step 1:** `R CMD INSTALL --no-docs .` then
  `Rscript -e 'Sys.setenv(LINTR_ERROR_ON_LINT = "true"); lintr::lint_package()'`. Expected: no lints.
- [ ] **Step 2:** `Rscript -e 'devtools::document()'`, then `git status --short man/ NAMESPACE`.
  Expected: clean (docs-current would otherwise fail).
- [ ] **Step 3:** `Rscript -e 'devtools::check()'`. Expected: 0 errors, 0 warnings, 0 notes.
  Read the examples section: the new `read_built()` example must have run, not been skipped.
- [ ] **Step 4: Quarto gate test.** Add to `tests/testthat/test-working_read.R`:

```r
test_that("the stage gate sees a real Quarto render's job file", {
  skip_if_not_installed("quarto")
  skip_if(is.null(quarto::quarto_path()), "Quarto is not installed")
  root <- versioned_study()
  for (stage in c("descriptive", "analyses")) {
    dir <- file.path(study_dir(stage, root), "probe")
    dir.create(dir, recursive = TRUE)
    writeLines(c("---", "title: probe", "---", "```{r}",
                 sprintf("cfg <- hvtiRutilities::study_config(%s)", deparse(root)),
                 "ok <- tryCatch({suppressMessages(hvtiRutilities::read_built(cfg, working = TRUE)); 'allowed'},",
                 "  error = function(e) 'refused')",
                 "writeLines(ok, 'result.txt')", "```"), file.path(dir, "probe.qmd"))
    quarto::quarto_render(file.path(dir, "probe.qmd"), quiet = TRUE)
    expect_identical(readLines(file.path(dir, "result.txt")),
                     if (stage == "descriptive") "allowed" else "refused")
  }
})
```

  It runs against the **installed** package, so install first (Step 1). If it fails because
  `knitr::current_input(dir = TRUE)` names an intermediate outside the job directory under Quarto,
  stop and report: the gate's job-file detection needs a design change, not a test change.
- [ ] **Step 5: Reverse dependencies.** Install this branch, then run hvtiRtemplates' and
  hvtiRdatabuild's test suites against it. Expected failures to **report, not fix here**: any
  hvtiRtemplates test that renders a distribution, analysis or graph template against a fixture
  study without a dated version now stops at the gate. Count them by file and list them in the
  PR; they are the hvtiRtemplates work this release creates (fixtures move to dated versions),
  and the patch release must not be tagged until that work lands.
- [ ] **Step 6:** Commit the Quarto test, open the PR from `feat/one-version-scheme`, run a
  local `/code-review` first and say in the PR body that it stood in for the Copilot bot.

## Spec coverage

| spec section | task |
|---|---|
| 4.1 origin, 4.4 provenance map | 1 |
| 4.2 sidecar, 4.3 record | 2 |
| 4.5 verification | 3 |
| 5.1 default, gate, read, signal | 4, 5 |
| 5.1 every non-dated read gated; provenance | 5 |
| 5.1 the way out of the gate for a promoted legacy entry | 5b |
| 5.2 `review_built()` | 6 |
| 5.3 replacements; 7 deprecation release | 6, 7, 8 |
| 9 tests | 1 to 7, 9 |
| 6 refusal, 7 removal release | not here: the removal plan |
| 8 hand-offs | 9, step 5 (reported in the PR) |
