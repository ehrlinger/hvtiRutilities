# Changelog

## hvtiRutilities 1.1.5

### Documentation

- **Development records moved to `dev/specs/`,** adopting the portfolio
  convention settled in `ehrlinger/house-style`. Designs and their plans
  now share a directory and a slug, with `-design` / `-plan` carrying
  the distinction `specs/` and `specs/plans/` used to encode a second
  time. The six paths quoted in `NEWS.md`, `R/`, `man/` and the tests
  were repointed, so nothing here links at a file that no longer exists.
- **`ROADMAP.md` moved to the repository root.** It says where the
  package is going rather than what was decided on a date, so it is not
  a development record. `.Rbuildignore` gained a matching line to keep
  the tarball clean.

## hvtiRutilities 1.1.4

### New features

Candidate-pool preparation helpers, ported from a study’s local `R/`
([\#47](https://github.com/ehrlinger/hvtiRutilities/issues/47)). They
were written for one study and are needed by the `hm` and `bh` job
templates in `hvtiRtemplates`, which cannot depend on one study’s
private helpers.

- **[`sas_variable_block()`](https://ehrlinger.github.io/hvtiRutilities/reference/sas_variable_block.md)**
  reads a variable list out of a `.sas` job rather than transcribing it
  — a transcribed list drifts from the job it claims to reproduce and
  nothing catches it. Comment handling is the whole difficulty, and it
  is silent in **both** directions: a banner comment
  (`/***** Patient Variables *****/`) contains `*`, so line-by-line
  stripping leaves it intact and it swallows the **first** name on the
  next line (`female`, `afib_pr`, `plvidd` and `size` were lost this
  way), while a `/* ... */` spanning two lines is never stripped and a
  commented-**out** variable is read as live (`avet_con` entered a
  screen that way). Both are regression-tested.

- **[`covariate_audit()`](https://ehrlinger.github.io/hvtiRutilities/reference/covariate_audit.md)**,
  **[`imputed_levels()`](https://ehrlinger.github.io/hvtiRutilities/reference/imputed_levels.md)**
  and
  **[`covariates_to_numeric()`](https://ehrlinger.github.io/hvtiRutilities/reference/covariates_to_numeric.md)**
  report and apply what happens to a covariate on its way into a model.
  `%vars(missing=1, impute=1)` mean-imputes and adds a paired `ms_*`
  indicator, so a 0/1 clinical variable arrives with **three** values —
  0, 1, and the cohort mean (one real column’s third value is 0.714, the
  prevalence of hypertension, not any patient’s status). In SAS those
  enter linearly; read into R they arrive as **factors** and get
  dummy-coded, which is a different model with a different parameter
  count and nothing in the output says so.

  `NA` in `noninteger_levels` means **“not knowable here”**, not “none”:
  mean imputation is detectable in a discrete column but invisible by
  construction in a continuous one.

- **[`concept_of()`](https://ehrlinger.github.io/hvtiRutilities/reference/concept_of.md)**,
  **[`concept_map()`](https://ehrlinger.github.io/hvtiRutilities/reference/concept_map.md)**,
  **[`prune_to_one_form()`](https://ehrlinger.github.io/hvtiRutilities/reference/prune_to_one_form.md)**
  and
  **[`selection_crowding()`](https://ehrlinger.github.io/hvtiRutilities/reference/selection_crowding.md)**
  group a candidate pool into clinical concepts. A SAS pool offers every
  transformation as a separate candidate, so a stepwise screen spends
  its steps on them and a per-variable frequency reports each separately
  — five forms of age each cleared 80% on one screen while the retained
  set collapsed to four concepts, and the paper reports concepts.

  The rule is deliberately conservative, because grouping too little
  only costs some pruning while grouping too much silently merges two
  clinical concepts. Stem truncation is handled automatically but only
  when unambiguous; contractions need an explicit alias.

- **[`pool_collinear_pairs()`](https://ehrlinger.github.io/hvtiRutilities/reference/pool_collinear_pairs.md)**
  catches what concept grouping cannot: candidates that are the same
  information under unrelated names. `male` and `female` are exact
  complements, both were offered to a screen, and 101 of 500 replicates
  selected **both** — fitting a rank-deficient design with nothing in
  the output saying so.

- **`POOL_AFFIXES`**, **`POOL_PLAIN_SUFFIX`** and **`POOL_MIN_STEM`**
  carry the legacy naming conventions as documented **defaults**,
  overridable per study rather than edited in place.

The affix and alias machinery is a **permanent compatibility layer, not
a temporary shim**: stem truncation exists because SAS capped names at 8
characters, and reproducing a legacy SAS job in R is routine work rather
than a migration with an end date.

`concept_frequencies()` is deliberately **not** ported yet — it takes a
bagging object whose structure does not exist in this package. It
belongs with the `bh` work.

## hvtiRutilities 1.1.3

### Bug fixes

- [`job_files()`](https://ehrlinger.github.io/hvtiRutilities/reference/job_files.md)
  no longer aborts a sweep when a filename is invalid in the session’s
  encoding. A shared corpus does not guarantee valid names – one Latin-1
  byte in a name created on Windows was enough to kill the sweep of a
  841,042-file directory with `input string 841042 is invalid`. Invalid
  bytes are now replaced with their `<xx>` escape, so the file appears
  in the output with a legible, greppable name instead of taking the
  directory down with it.

  Two of the three string operations involved failed *silently* rather
  than loudly, which is the worse half of this bug:
  [`grepl()`](https://rdrr.io/r/base/grep.html) warns and returns
  `FALSE`, leaving the prefix unclassified, and
  [`strsplit()`](https://rdrr.io/r/base/strsplit.html) warns and returns
  `NA`, marking the file unplaced. Only
  [`substring()`](https://rdrr.io/r/base/substr.html) raised an error.
  Had the error not fired first, the file would have been miscounted
  rather than reported.

## hvtiRutilities 1.1.2

### Bug fixes

- [`job_files()`](https://ehrlinger.github.io/hvtiRutilities/reference/job_files.md)
  now credits a file under a symlinked subdirectory to the study it was
  walked into. It normalised every path before stripping the root
  prefix, and
  [`normalizePath()`](https://rdrr.io/r/base/normalizePath.html)
  resolves symlinks – so when a subdirectory inside the corpus pointed
  somewhere outside the root, the resolved path no longer carried that
  prefix, the strip sliced at the wrong offset, and `study` came back
  mangled with no error raised.

### Performance

- [`job_files()`](https://ehrlinger.github.io/hvtiRutilities/reference/job_files.md)
  makes one filesystem pass per file instead of three. The per-file
  [`normalizePath()`](https://rdrr.io/r/base/normalizePath.html) is
  unnecessary – [`list.files()`](https://rdrr.io/r/base/list.files.html)
  prefixes its results with the root exactly as given, and the root is
  already normalised – and the per-file
  [`dir.exists()`](https://rdrr.io/r/base/files2.html) was redundant,
  since `list.files(recursive = TRUE)` never returns directories. Each
  removed pass was a stat syscall; on a local disk that is invisible,
  but the corpus is read over an SMB mount where every stat is a network
  round-trip and the two passes dominated the walk. A partial corpus
  sweep over the share reached one top-level directory in an hour before
  this change.

### Breaking changes

- [`read_clinical_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/read_clinical_data.md)’s
  `convert_types` argument now defaults to `FALSE`. It defaulted to
  `TRUE`, applying
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  to every column, which converts any two-valued numeric column to
  logical — including 0/1 event and censoring flags, which
  `hzr_kaplan()` and similar then reject. Reading and type derivation
  are now separate steps. Callers who omit the argument get a
  once-per-session warning; pass `convert_types = TRUE` to restore the
  old behaviour.

### New features

- [`job_files()`](https://ehrlinger.github.io/hvtiRutilities/reference/job_files.md)
  and
  [`job_census()`](https://ehrlinger.github.io/hvtiRutilities/reference/job_census.md)
  — a filename-only inventory of the job corpus.
  [`job_files()`](https://ehrlinger.github.io/hvtiRutilities/reference/job_files.md)
  returns one row per file with its study, taxonomy folder, prefix and
  naming convention;
  [`job_census()`](https://ehrlinger.github.io/hvtiRutilities/reference/job_census.md)
  rolls that up to `(study, prefix, folder, is_template)` with `n_jobs`
  (distinct stems) and `n_files`. The print method leads with
  distinct-studies-per-prefix, which is the lookup that says whether a
  job type can be templated yet.

  Nothing is filtered: placement and classification are columns, so a
  file the sweep cannot classify stays in the output rather than
  vanishing. There is no extension allowlist, deliberately — see
  `dev/specs/2026-08-26-job-type-inventory-design.md` §4.4.

- [`hvti_taxonomy()`](https://ehrlinger.github.io/hvtiRutilities/reference/hvti_taxonomy.md)
  and
  [`hvti_non_prefixes()`](https://ehrlinger.github.io/hvtiRutilities/reference/hvti_non_prefixes.md)
  — the analysis-prefix table, moved here from `hvtiRtemplates`, which
  now imports them back. The table is shared vocabulary rather than
  template machinery, and this package is the lower layer.

- [`dataset_schema()`](https://ehrlinger.github.io/hvtiRutilities/reference/dataset_schema.md)
  — one row per column giving creation position, name, R class, SAS
  type, `format.sas` and label. Labels and formats are read from the
  column attributes directly, so an absent label is `NA` rather than the
  variable’s own name. This is the durable description of a source
  dataset: it describes shape only, so two reads of an unchanged file
  produce an identical schema.

- [`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)
  gains `n_cols`, `schema_sha256` and `role`. `n_cols` is recorded as
  part of the schema baseline, since a row count alone cannot detect a
  dropped column; it is
  [`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)’s
  comparison of `schema_sha256` against the sidecar on disk – a hash of
  the schema sidecar, making the manifest-to-sidecar link tamper-evident
  – that actually detects one. `role` is `"source"` or `"primary"` and
  distinguishes a dataset SAS still builds from one whose parquet has
  become authoritative.

- [`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)
  checks `schema_sha256` against the sidecar on disk, and reports two
  entries whose file stems collide and would therefore claim the same
  derived `.parquet` and `.schema.csv` paths.

- [`read_built()`](https://ehrlinger.github.io/hvtiRutilities/reference/read_built.md)
  now caches its source as parquet on first read and uses that cache
  while the source’s size and modification time are unchanged. The
  schema sidecar and manifest entry are written from the haven read,
  before the parquet exists, so the recorded baseline is independent of
  the conversion. Conversion is lazy: a dataset nobody reads is never
  converted. `arrow` is a suggested package — without it, or with
  `options(hvtiRutilities.disable_parquet_cache = TRUE)`, reads behave
  exactly as before.

- The parquet cache’s validity check now follows the manifest entry’s
  `role` rather than a single size/mtime heuristic. A `role: "primary"`
  entry is served from its parquet unconditionally — the source may have
  been retired and need not exist. A `role: "source"` entry is valid
  when the source’s `size` and `mtime` both match the recorded stamp;
  size alone cannot be trusted, since a `.sas7bdat` is page-aligned and
  a changed row count can leave its size identical. Whether a matching
  `mtime` alone proves the source is unchanged is a property of the
  filesystem, and it is measured from the `stat` rather than assumed: a
  fractional `mtime` means sub-second resolution and is trusted
  directly; a whole-second `mtime` means the filesystem cannot see
  inside that second, and the recorded `sha256` is verified instead.
  Production runs on a local filesystem with nanosecond `mtime`, so the
  fast path applies there; development over SMB may see whole-second
  stamps and pay for a hash — neither is a special case in the code. The
  source is stat’d before the read rather than after, so a source
  rewritten mid-read is stamped conservatively stale instead of
  validating forever, and if the source’s `size` or `mtime` changes
  again between that `stat` and the end of the read, the frame is
  discarded and the read errors rather than caching a possibly torn
  result. (An earlier draft of this validity check compared the source’s
  `mtime` against a client-side
  [`Sys.time()`](https://rdrr.io/r/base/Sys.time.html) recorded at
  conversion; that compared two different clocks whenever the files live
  on another host, so a client running even one second fast made every
  entry look unambiguous forever. It never shipped in a release.)

- [`read_built()`](https://ehrlinger.github.io/hvtiRutilities/reference/read_built.md)
  gains `refresh = TRUE`, which forces a re-read from the source and a
  reconversion regardless of role or the cached `size`/`mtime` stamp —
  for changes a timestamp can’t express, such as a rebuild that
  preserves `mtime` or a correction applied out of band.
  `refresh = TRUE` against a `role: "primary"` entry errors clearly,
  naming the role, rather than failing inside haven, even with `arrow`
  absent or the cache disabled.
  [`read_built()`](https://ehrlinger.github.io/hvtiRutilities/reference/read_built.md)
  also now serves a `role: "primary"` entry whose source file is
  missing, instead of erroring before the manifest is even consulted —
  without this, promotion (retiring the source once its parquet is
  authoritative) was unreachable. If a promoted entry’s parquet is also
  missing, the error now names the parquet as the missing copy rather
  than the source, which was retired on purpose.

- [`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)
  now hashes whichever file a manifest entry’s `role` makes
  authoritative — the source for `role: "source"`, the parquet (resolved
  the same way the cache names it) for `role: "primary"` — rather than
  always hashing the entry’s own file. `file` never changes on
  promotion, so this cannot be inferred from the name. A missing source
  is therefore no longer reported as a failure once an entry is
  promoted; it is expected, since promotion means the source was
  retired.

- A cache miss on a promoted (`role: "primary"`) entry — its parquet
  lost while the retired source happens to still be present — now
  reconverts the parquet without rewriting the entry as an ordinary miss
  would: `sha256` is updated to describe the new parquet, and
  `promoted_date` and `source_sha256` are left untouched, rather than
  being silently dropped and replaced with the source’s own hash.

- The parquet cache now verifies each conversion round-trips before
  returning: the freshly written parquet is read back and compared
  against the frame haven returned — column names, order, classes and
  values — and a mismatch removes the parquet and errors naming the
  first column that differs, rather than leaving mismatched data behind
  a “successful” write. This matters most for a `role: "primary"` entry,
  which has no second chance to self-heal once the source is retired.

- [`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)
  gains `reader`, recording the package and version that produced a
  derived file (e.g. `"haven 2.5.5"`). The parquet cache supplies it
  automatically. Under `role: "primary"` this is part of the parquet’s
  provenance: a reader defect found later is otherwise unfindable once
  the source is gone.

### Bug fixes

- [`read_built()`](https://ehrlinger.github.io/hvtiRutilities/reference/read_built.md)
  now errors when lowercasing column names produces duplicates, naming
  the colliding pair, instead of returning two identically named columns
  where every downstream selection silently takes the first. SAS names
  cannot collide this way; `.csv`, `.xlsx` and `.rds` sources can.
- [`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)’s
  default `data_dir` now resolves each entry individually instead of
  choosing `datasets/` vs. the manifest’s own directory once for the
  whole manifest based on whether `datasets/` exists. Previously, a
  flat-layout study whose manifest referenced files beside
  `manifest.yaml` would have every entry misdirected into `datasets/`
  (and fail with “File not found”) merely because that directory
  happened to also exist, empty or not. Each entry now prefers
  `datasets/<file>` only when that file is actually there, and otherwise
  resolves beside the manifest. Callers who pass `data_dir` explicitly
  are unaffected — an explicit `data_dir` is still used exactly as
  given, with no nested search.
- An unreadable cached parquet (truncated, corrupted, an interrupted
  write from outside this package) no longer permanently breaks
  [`read_built()`](https://ehrlinger.github.io/hvtiRutilities/reference/read_built.md)
  for that dataset. A `role: "source"` entry warns, naming the file, and
  falls back to regenerating it from the source; a `role: "primary"`
  entry still errors, naming it the only copy, since there is no source
  to regenerate from.
- The parquet cache’s validity check no longer errors on a half-written
  stamp — `source_size` recorded without `source_mtime`, from a hand
  edit or an interrupted write. Any missing stamp field now reads as
  “not valid” rather than reaching `as.POSIXct(NULL)` and throwing.
- The parquet cache’s schema sidecar write, and both of the manifest
  writes it triggers
  ([`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)
  and the internal stamp update), are now atomic — a temporary file,
  then a rename — matching `.write_parquet_atomic()`’s existing
  discipline, which is now shared by all three through one helper. Two
  first reads racing on the same dataset could previously leave one
  process hashing a sidecar the other was midway through truncating,
  recording a `schema_sha256` that matched nothing on disk and putting
  the entry into permanent verification failure.

### Notes

- `utils` is added to `DESCRIPTION`’s `Imports:`. `R/parquet_cache.R`
  calls [`utils::write.csv()`](https://rdrr.io/r/utils/write.table.html)
  and
  [`utils::packageVersion()`](https://rdrr.io/r/utils/packageDescription.html),
  and `utils` was already imported in `NAMESPACE`, but it was missing
  from `DESCRIPTION` — which `R CMD check` flags.
- [`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)
  rebuilds a manifest entry from its own known fields rather than
  merging into whatever is already there, so any field a study’s own
  tooling added to an entry is silently dropped the first time a cache
  miss (or any other call to
  [`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md))
  rewrites it. The parquet cache preserves `extract_date`, `source` and
  `sort_key` specifically, because losing those would clobber values
  [`study_init()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_init.md)
  sets explicitly; no other field is preserved. This is unchanged in
  this release — recorded here so it’s a known limitation rather than a
  surprise.

### Documentation

- [`proc_contents()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_contents.md)
  now documents that its `label` column is never `NA`: it falls back to
  the variable’s own name via
  `labelled::var_label(null_action = "fill")`, so an unlabelled variable
  is indistinguishable from one labelled with its own name. Callers
  recording the output as a durable description of a source dataset
  should read labels from the source attributes directly. Measured on an
  879-variable clinical build, 14 variables carry no label and would be
  recorded as labelled with their names.
- [`proc_contents()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_contents.md)
  also clarifies that name, label, `format.sas` and creation order
  survive a haven read *when the source carries them*, rather than being
  present on every variable. In the same build, 865 of 879 variables
  carry a label and 395 carry a `format.sas`, so an `NA` format reports
  an unformatted source variable rather than a lost attribute.

## hvtiRutilities 1.0.11

### Bug fixes

- `.Rbuildignore` now excludes `.remember`, the session-tooling
  directory. It was landing in the build and raising a “hidden files and
  directories” NOTE on every branch, which masks real NOTEs during
  release gating.

## hvtiRutilities 1.0.10

### New features

- [`parity_tolerance()`](https://ehrlinger.github.io/hvtiRutilities/reference/parity_tolerance.md),
  [`compare_parity()`](https://ehrlinger.github.io/hvtiRutilities/reference/compare_parity.md)
  and
  [`parity_headline()`](https://ehrlinger.github.io/hvtiRutilities/reference/parity_headline.md)
  — the comparison half of the SAS parity harness.
  [`compare_parity()`](https://ehrlinger.github.io/hvtiRutilities/reference/compare_parity.md)
  errors when a quantity is absent on either side, and reports `PASS` /
  `DIFFERS` / `R_BETTER`.

## hvtiRutilities 1.0.9

### New features

- [`preflight_report()`](https://ehrlinger.github.io/hvtiRutilities/reference/preflight_report.md)
  — environment audit naming every package a hazard-family analysis
  depends on, including `numDeriv`.

## hvtiRutilities 1.0.8

### New features

- [`study_init()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_init.md)
  initializes a study for reproducible analysis: it writes the
  `_study.yml` identity manifest that
  [`study_config()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md)
  reads, and seeds a `manifest.yaml` pinning the built dataset’s
  SHA-256. The cohort counts are derived from the dataset rather than
  supplied, because a hand-typed count is a count that can disagree with
  the data. `citation` is written as an explicit null, so a study that
  is later published has an obvious place to record its reference.

- [`study_status()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md)
  audits a study without writing anything, reporting whether it has a
  valid `_study.yml`, an `renv.lock`, a `manifest.yaml` whose checksums
  still match, and a provenance sidecar for every `.qmd` or `.Rmd`
  source. It never errors on an absent or malformed manifest — that is
  the finding, not a failure — and it distinguishes a check that could
  not run (`MISSING`) from one that ran and failed (`FAIL`).

- [`study_checklist()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_checklist.md)
  renders a
  [`study_status()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md)
  result as a markdown checklist, ticked where the study already
  complies.

- [`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)
  gains `strict = FALSE`. Under `strict = TRUE` an entry whose row count
  could not be re-derived is reported as `"FAIL"` rather than passing on
  its checksum alone, and the message names which of the three causes
  applies: the count is not recorded in the manifest, the file type
  cannot be counted at all, or heavy row counting is left disabled. Use
  it where the question is “did every check actually run” rather than
  “is the data intact”: a release gate, an archival gate, or a hand-off
  where a downstream reader will read `"OK"` as fully verified.

  The default is unchanged and stays permissive, because a check that
  cannot run is not a check that failed. Under it `"OK"` can still mean
  “checksum verified, row count not examined”, and `row_count_checked`
  remains the column that distinguishes the two.

### Bug fixes

- [`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)
  no longer reports `FAIL` for a `.sas7bdat` or Excel entry whose
  SHA-256 matches. Re-deriving the row count of those formats needs
  `options(manifest.allow_heavy_rowcount = TRUE)`, and without it the
  attempt errored and the error was reported as a failed entry. At the
  default `stop_on_error = TRUE` that halted analyses whose data was
  intact. The count is now skipped when it cannot be re-derived and the
  entry passes on its checksum; a file that cannot be read at all is
  still `FAIL`.

- [`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)
  gains a `row_count_checked` column, `TRUE` when the row count was
  re-derived from the file and compared with the manifest. The entry’s
  message notes a count that was not re-derived.

- [`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)
  no longer reports `SHA-256 match (n = )` for an entry whose manifest
  records no row count. An empty count field reads as a verified count
  of nothing; the message now says `no row count recorded`. Entries
  written by hand, or by a version that could not count rows, are the
  ones affected.

- [`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)
  no longer reports an entry that records no SHA-256 as a
  `SHA-256 mismatch` against a blank expected value. Such an entry still
  fails, because the checksum is the whole of what the function
  verifies, but the message now says none was recorded and names the
  algorithm the manifest used instead. A manifest written by an
  md5-based writer is the case this turns up on.

### Notes

- No new dependencies.
- [`study_init()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_init.md)
  does not run `renv::init()`. A missing `renv.lock` is reported as an
  open item instead: creating one restarts the R session and rewrites
  `.Rprofile`, which a function that writes two YAML files has no
  business doing.
- [`study_status()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md)
  reports a `manifest.yaml` entry as verified when its SHA-256 matches
  but its row count could not be re-derived, and says how many counts
  were skipped. For a `.sas7bdat` that is the normal case.

## hvtiRutilities 1.0.7

### New features

- [`study_config()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md)
  reads a study’s `_study.yml` manifest, found by walking up from a
  starting directory. It validates that every required key is present
  and errors otherwise, naming the key: a study without a complete
  manifest must not render, and a partial default would be a silent
  wrong answer.

- [`record_provenance()`](https://ehrlinger.github.io/hvtiRutilities/reference/record_provenance.md)
  writes a JSON sidecar beside a rendered output, recording the study
  manifest checksum, the R version and platform, every loaded package
  and its version, the `renv.lock` checksum, the input dataset’s
  SHA-256, and the cohort. `renv.lock` alone cannot say what produced a
  particular result — it is project-scoped and re-snapshotted through a
  study’s life — so the record is job-scoped and lives with the result.
  Failure to write it is an error, not a warning.

- The study data contract moves in from the per-study `R/` directories:
  [`study_root()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_root.md),
  [`sas_path()`](https://ehrlinger.github.io/hvtiRutilities/reference/sas_path.md),
  [`built_path()`](https://ehrlinger.github.io/hvtiRutilities/reference/built_path.md),
  [`built_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/built_manifest.md),
  [`read_built()`](https://ehrlinger.github.io/hvtiRutilities/reference/read_built.md),
  [`cohort_counts()`](https://ehrlinger.github.io/hvtiRutilities/reference/cohort_counts.md)
  and
  [`assert_cohort()`](https://ehrlinger.github.io/hvtiRutilities/reference/assert_cohort.md).
  All of them read study-specific values from `_study.yml` rather than
  from constants, so no study path, title, dataset name or cohort count
  appears in package code.

- [`r_dir_impurities()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_dir_impurities.md)
  reports top-level executable code in a directory that is sourced
  wholesale, where a stray call would run on every render.

### Notes

- New dependency: `jsonlite`, for the provenance sidecar.
- [`built_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/built_manifest.md)
  records `sha256` rather than the `md5` used by the earlier per-study
  version, matching the provenance record. One hash algorithm across the
  design, not two.

## hvtiRutilities 1.0.6

### Bug fixes

- [`sas_triage()`](https://ehrlinger.github.io/hvtiRutilities/reference/sas_triage.md):
  the excluded-subdirectory counts no longer include dot-directories. A
  local clone carries `.git`, whose loose-object files carry no
  extension and so matched none of the non-source suffixes, reporting 31
  files of “excluded SAS source” that were git internals. These counts
  exist to tell a human what triage did not look at, and `.git` is never
  that decision. `CVS/` is still reported: it is a legacy artifact
  committed into the corpus itself, not infrastructure of the clone.

## hvtiRutilities 1.0.5

### New features

- [`proc_means()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md)
  gains nine statistics from the SAS `unistats` vocabulary: `nobs`,
  `var`, `uss`, `css`, `skewness`, `kurtosis`, `sumwgt`, `qrange` and
  `mode`. `skewness` and `kurtosis` are the adjusted Fisher-Pearson
  forms SAS uses, cross-validated in the test suite against `e1071` with
  `type = 2`. `mode` returns the smallest of tied modes and `NA` when no
  value repeats, matching SAS.

- [`proc_means()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md)
  gains a `weights` argument naming a numeric column, mirroring the SAS
  `WEIGHT` statement. Weights apply within each `class` level.

  Weighting is not uniform, following `PROC MEANS`: `mean`, `std`,
  `var`, `cv`, `stderr`, `sum`, `uss`, `css`, `skewness`, `kurtosis` and
  `sumwgt` respond to weights; `n`, `nmiss`, `nobs`, `min`, `max`,
  `range`, `mode` and every quantile do not. `PROC MEANS` computes no
  weighted quantiles; that is `PROC UNIVARIATE`.

  A zero or negative weight raises an error naming the offending rows.
  SAS’s own handling of non-positive weights differs across procedures
  and versions, so this fails loudly rather than encode a guess.

  The `PROC UNIVARIATE` inference statistics remain out of scope. See
  `dev/specs/2026-08-14-proc-means-unistats-design.md`.

### Bug fixes

- [`proc_means()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md):
  `cv` now returns `NA` when the mean is zero, matching SAS. R’s
  arithmetic gives `Inf`, which asserts an infinite coefficient of
  variation where SAS reports the value as undefined.

### Internal changes

- [`proc_means()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md)
  statistics are dispatched through a `.STATS` registry that declares,
  per statistic, whether it responds to weights and whether it is
  integer-typed. The weighted set is asserted directly in the test
  suite.

## hvtiRutilities 1.0.4

### New features

- Phase 0 of the SAS macro canonicalization program:
  [`sas_triage()`](https://ehrlinger.github.io/hvtiRutilities/reference/sas_triage.md),
  [`sas_macro_defs()`](https://ehrlinger.github.io/hvtiRutilities/reference/sas_macro_defs.md),
  [`sas_macro_signature()`](https://ehrlinger.github.io/hvtiRutilities/reference/sas_macro_signature.md),
  [`write_macro_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/write_macro_manifest.md)
  and
  [`write_collision_report()`](https://ehrlinger.github.io/hvtiRutilities/reference/write_collision_report.md).
  Together they inventory a legacy SAS macro library, classify each
  definition public or private, and report the name collisions that make
  `%include` order-dependent. Pure R – no SAS dependency, so the
  inventory runs on the development workstation.

  Two design points are worth recording, because the obvious
  implementations of both are wrong for this corpus.

  **File discovery excludes known non-source suffixes rather than
  matching `.sas`.** The library uses dots as word separators in
  filenames – `deciles.hazard`, `lm.cprobs` and `kaplan.int` are names,
  not stems with extensions – and many macro files carry no extension at
  all. An extension-anchored pattern omits both populations silently,
  including `unistats`, whose statistic vocabulary is the closest
  analogue in the corpus to
  [`proc_means()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md).

  **Validity checking uses a stateful scanner, not pattern matching.**
  It tracks comment state (`/* */`, `* ... ;`), string state (`'...'`,
  `"..."`) and macro quoting (`%'`), so comments and literals spanning
  lines, apostrophes inside double-quoted strings, and the `%STR(%')`
  transpose idiom are not mistaken for syntax errors. Every rule reads
  the scanned source, so a `%macro` written inside a comment or a string
  literal is not counted as a definition. The check reports a file that
  ends inside a string literal *or* inside a comment, naming the line
  where it opened – an unclosed `/*` is the more destructive of the two,
  because every statement after it is inert while the file still looks
  like usable source. There is deliberately no do/end balance check:
  textual balance is not a validity property of macro source, since
  `%do`-guarded blocks emit DO and END from separate branches.

  **A macro redefined inside one file is resolved, not escalated.** SAS
  compiles definitions in order and the later one replaces the earlier,
  so the last definition in a file is what any `%include` of it actually
  gets. Rule 3 keeps that one and drops the rest, each carrying the line
  that supersedes it. This is deliberately not a name collision:
  [`write_collision_report()`](https://ehrlinger.github.io/hvtiRutilities/reference/write_collision_report.md)
  lists names found in more than one *file*, because those are the ones
  whose behaviour depends on `%include` order. On the reference corpus
  158 of the 816 definitions are shadowed this way, leaving 658 live.

  On the reference corpus of 336 files this inventories 816 macro
  definitions across 307 distinct names, rejecting 5 as genuinely
  defective: `bl_ord.norm.ci.sas`, `CR_compare_CP_test_AT.sas`,
  `rem.original`, `rem.uab` and `repeated.sas`.

  Those figures replace an earlier measurement of 866 definitions across
  250 names. The difference is not a change of policy but a correction:
  the earlier run counted `%macro` statements that the scanner had
  already established were comment or string content. The rejected set
  is the same size and different in membership – `xmacro.sas` leaves it,
  having been failed for an imbalance whose second definition is
  commented out, and `bl_ord.norm.ci.sas` enters it, whose
  `* NOT COMPLETE` header carries no semicolon and therefore swallows
  the `%MACRO BLORD` statement on the line below. The file says as much
  itself.

## hvtiRutilities 1.0.3

### Documentation

- New vignette, *PROC CONTENTS and PROC MEANS in R*, written for readers
  who run both languages. It walks
  [`proc_contents()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_contents.md)
  and
  [`proc_means()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md)
  beside the procedures they replace, covers the `QNTLDEF=5` quantile
  difference that changes quartiles without changing the median, and
  lists every behaviour where the R version departs from the SAS
  original.

- [`compare_datasets()`](https://ehrlinger.github.io/hvtiRutilities/reference/compare_datasets.md)
  is now demonstrated in *Dataset Version Tracking* rather than only
  named in its index table. The example covers the four kinds of drift
  it reports and why a label change is the one to watch.

## hvtiRutilities 1.0.2

### New features

- [`proc_contents()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_contents.md):
  a port of SAS `PROC CONTENTS`. Returns a dataset header (observations,
  variables, label) and a variables table carrying creation position,
  name, SAS type, format, label, R class, distinct-value count, and
  percent missing. `Len`, `Pos`, and `Informat` are deliberately omitted
  — `haven` cannot recover them from a `.sas7bdat`, and inferred values
  would disagree with the source dataset whenever its `LENGTH` statement
  differed from the default.

- [`proc_means()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md):
  a port of SAS `PROC MEANS`. Takes SAS statistic keywords (`n`,
  `nmiss`, `mean`, `std`, `min`, `max`, `sum`, `range`, `stderr`, `cv`,
  `median`, `q1`, `q3`, and any `pNN`), defaulting to SAS’s own five,
  and supports `CLASS` stratification with SAS’s default handling of
  missing class levels. Quantiles use `type = 2`, the R equivalent of
  SAS `QNTLDEF=5`; R’s default `type = 7` disagrees with SAS on small
  and even-numbered samples.

### Documentation

- [`proc_contents()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_contents.md)
  now documents that `pct_missing` is `NaN`, not a value in 0-100, when
  the input has columns but zero rows: the proportion of missing values
  among no values is undefined, and reporting `0` would assert that
  nothing is missing. Behaviour is unchanged and is inherited from
  [`data_dictionary()`](https://ehrlinger.github.io/hvtiRutilities/reference/data_dictionary.md);
  only the documented contract is now accurate, and a test pins it.

### Internal changes

- [`data_dictionary()`](https://ehrlinger.github.io/hvtiRutilities/reference/data_dictionary.md)
  is now a thin wrapper over
  [`proc_contents()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_contents.md)
  and the shared statistic engine. Its signature and output are
  unchanged, pinned by characterization tests added before the refactor.

## hvtiRutilities 1.0.1

### Breaking changes

- [`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)
  and
  [`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)
  are now **silent by default**. Both gained a `verbose` argument
  (default `FALSE`) that gates all informational
  [`message()`](https://rdrr.io/r/base/message.html) output: “Manifest
  entry added / updated” in
  [`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md),
  and the per-entry “— SHA-256 match (n = N)” and “Manifest contains no
  dataset entries.” lines in
  [`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md).
  Pass `verbose = TRUE` to restore the previous console output.

  This removes unconditional chatter from packages that call these
  functions in a loop (for example `hvtiRdatasets::snapshot_oracle()`,
  which called
  [`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)
  once per study), and brings the package in line with the CRAN policy
  against chatty
  [`message()`](https://rdrr.io/r/base/message.html)/[`cat()`](https://rdrr.io/r/base/cat.html)
  in function bodies.

  Failures are unaffected: a SHA-256 mismatch, a missing file, or a
  row-count mismatch still raises
  [`stop()`](https://rdrr.io/r/base/stop.html) (or
  [`warning()`](https://rdrr.io/r/base/warning.html) when
  `stop_on_error = FALSE`) regardless of `verbose`. The per-entry status
  text is also still returned in the `message` column of
  [`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)’s
  data frame, so silencing the console loses no information.

  `verbose` is appended last in both signatures, so existing positional
  calls are unaffected.

### Maintenance

- Maintainer contact is now `john.ehrlinger@gmail.com`. The redundant
  `Maintainer:` field was removed from DESCRIPTION — with `Authors@R`
  present the maintainer is derived from the `cre` role, and having both
  declared different addresses.
- README: the repostatus badge now uses `https://` (the `http://` form
  301-redirected, failing
  [`urlchecker::url_check()`](https://urlchecker.r-lib.org/reference/url_check.html)).
- DESCRIPTION `Date:` refreshed to the 1.0.1 release date.

### Bug fixes

- [`read_clinical_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/read_clinical_data.md):
  files with no extension now produce a clear error (“Cannot determine
  file type: … has no extension”) instead of the misleading
  `Unsupported file type: '..'` message. The unsupported-extension error
  also now includes the full file path for easier diagnosis.

### Tests

- `test-read_clinical_data.R`: strengthened the tibble-coercion
  assertion from `expect_true(is.data.frame(result))` (TRUE for tibbles)
  to `expect_equal(class(result), "data.frame")` so the test actually
  protects against
  [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) being
  removed or bypassed.

### Documentation

- `vignettes/reproducible-seeds.qmd`: section heading “Using the Seed
  with varpro” and narrative references to the package now use the
  correct CRAN casing `varPro`; function-name references (`varpro()`,
  `unsupv.varpro()`) remain lowercase as those are the exported function
  names.

## hvtiRutilities 1.0.0.9003

### Bug fixes

- Fixed `Suggests` entry for `varPro`: package name on CRAN is `varPro`
  (camelCase), not `varpro` (lowercase). The case mismatch caused `pak`
  lockfile resolution to fail with “Can’t find package called varpro”.
  Updated the corresponding
  [`varPro::varpro()`](https://www.randomforestsrc.org/reference/varpro.html)
  call in `vignettes/reproducible-seeds.qmd` to match.

## hvtiRutilities 1.0.0.9002

### Documentation

- All vignettes migrated from R Markdown (`.Rmd`) to Quarto (`.qmd`).
  Added `quarto` to `Suggests`.

### Bug fixes

- [`read_clinical_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/read_clinical_data.md):
  CSV files are now read with `check.names = FALSE` so column names
  containing spaces, hyphens, or special characters are preserved
  exactly as written, preventing silent name mangling that could break
  downstream label lookups.

## hvtiRutilities 1.0.0.9000

### Maintenance

- Start prerelease cycle at 1.0.0.9000.

## hvtiRutilities 0.4.1

### Maintenance

- Bumped package metadata for the upcoming release cycle.

## hvtiRutilities 0.1.4

### New Features

- Added
  [`generate_survival_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/generate_survival_data.md):
  generates a synthetic cardiac surgery survival cohort with 22 clinical
  variables, Weibull-distributed survival times, reoperation outcome,
  and variable labels

### Bug Fixes

- Fixed
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  silently corrupting Date, POSIXct, and POSIXlt columns that had
  exactly 2 unique values (they were converted to logical)
- Fixed
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  incorrectly converting constant columns (1 unique value) to logical;
  binary detection now requires exactly 2 unique values
- Fixed
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  producing a cryptic “missing value where TRUE/FALSE needed” error when
  `factor_size = NaN`
- Fixed
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  giving a misleading “not found in dataset” error when `skip_vars` was
  not a character vector
- Fixed
  [`generate_survival_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/generate_survival_data.md)
  producing `NaN` in `iv_reop` for patients with very short follow-up
  times
- Fixed
  [`generate_survival_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/generate_survival_data.md)
  permanently altering the global RNG state; the session’s RNG is now
  saved and restored on exit

### Improvements

- [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  now validates all inputs before doing any work, so errors are raised
  immediately with clear messages
- [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  input validation now explicitly checks that `dataset` is a data.frame,
  `skip_vars` is a character vector, and `factor_size` is not NaN
- [`generate_survival_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/generate_survival_data.md)
  now uses
  [`labelled::var_label()`](https://larmarange.github.io/labelled/reference/var_label.html)
  consistently to attach labels instead of
  [`attr()`](https://rdrr.io/r/base/attr.html) directly
- Removed leftover `if (interactive())` development block from
  `generate_survival_data.R`
- Added new vignette `survival-data` demonstrating
  [`generate_survival_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/generate_survival_data.md)
  and its integration with
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  and
  [`label_map()`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)

### Tests

- Added 27 tests for
  [`generate_survival_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/generate_survival_data.md)
  covering structure, column types, outcome validity, reproducibility,
  RNG side-effect safety, and variable labels
- Updated POSIXct test to verify preservation without `skip_vars` (the
  previous test only verified the `skip_vars` workaround)
- Strengthened idempotency test to assert full value equality across
  sequential conversions, not just column class equality
- Updated `skip_vars` type-error test to match the improved error
  message

## hvtiRutilities 0.1.3

### Bug Fixes

- Fixed critical bug in
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  where
  [`dplyr::na_if()`](https://dplyr.tidyverse.org/reference/na_if.html)
  was called with a vector instead of scalar values
- Fixed bug where character columns with 2 unique values were
  incorrectly converted to logical (returning all NAs)
- Fixed bug in
  [`sample_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/sample_data.md)
  where [`sample.int()`](https://rdrr.io/r/base/sample.html) parameters
  were reversed, causing errors for small sample sizes
- Fixed column order preservation bug in
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  when using `skip_vars` - columns now maintain original order
- Fixed silent parameter mutation bug where `factor_size > 50` was
  changed to 20 without user consent - now errors instead

### Improvements

- Removed unused `lubridate` dependency that was never actually used in
  the package
- Removed inappropriate use of
  [`invisible()`](https://rdrr.io/r/base/invisible.html) from
  [`label_map()`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)
  and
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  functions
- Implemented
  [`hvtiRutilities.news()`](https://ehrlinger.github.io/hvtiRutilities/reference/hvtiRutilities.news.md)
  function that was referenced but didn’t exist
- Completely rewrote test suite with modern testthat 3 syntax (removed
  deprecated `context()` calls)
- Expanded test coverage from 24 tests to 75 comprehensive tests
- Added proper examples to
  [`label_map()`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)
  documentation with `@examples` tag
- Improved error messages for better clarity and consistency
- Changed `== TRUE` comparisons to simpler boolean checks

### Documentation

- Complete rewrite of README.md with actual package description and
  usage examples
- Fixed
  [`label_map()`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)
  documentation (was incomplete sentence, wrong return type)
- Improved
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  documentation with clearer parameter descriptions
- Added comprehensive usage examples for all main functions

## hvtiRutilities 0.1.2

- Internal development version

## hvtiRutilities 0.1.1

- Internal development version

## hvtiRutilities 0.1.0

- Initial release
- Core functions:
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md),
  [`label_map()`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md),
  [`sample_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/sample_data.md)
