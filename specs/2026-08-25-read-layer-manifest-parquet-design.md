# Read layer, dataset manifest, and lazy parquet cache

**Date:** 2026-08-25
**Status:** Design, approved in outline
**Repo:** hvtiRutilities

## Problem

Three defects share one cause: nothing records what a `.sas7bdat` actually
contains, so nothing can tell whether a read, a conversion, or a migration
changed it.

1. **The read layer coerces by default.** `read_clinical_data(file,
   convert_types = TRUE, ...)` applies `r_data_types()` to every column,
   including event and censoring flags. `r_data_types()` converts
   "numeric/integer columns with exactly 2 unique values" to `logical`, so a
   SAS 0/1 event indicator arrives as `TRUE`/`FALSE` and `hzr_kaplan()`
   rejects it. Downstream code works around this rather than preventing it:
   the shipped `ac` template scatters `as.numeric()` coercions at call sites,
   and `assert_cohort_gate()` in the preserve_root study is written with
   comparisons (`d$idead == 1`, `%in% TRUE`) that survive a logical column.

2. **Two readers disagree in the same study.** `read_built()` already passes
   `convert_types = FALSE` and coerces residual logicals back to integer. The
   preserve_root study's own `read_preserve_root()` calls
   `read_clinical_data(path)` with the default. The R_hazard chain and the
   `ac` template therefore see different types for the same columns.

3. **The manifest records too little to detect a format migration.**
   `update_manifest()` records `file / extract_date / n_rows / sha256 /
   source / sort_key`. It has no `n_cols` (a dropped column preserves the row
   count) and no column types, names, labels or formats. Moving these
   datasets to parquet is a content-preservation question, and the manifest
   currently cannot answer it.

The datasets are large enough that the migration is also a performance
matter: preserve_root's `datasets/` holds 40 `.sas7bdat` totalling 2.7 GB,
the largest 376 MB. Reading those through haven has no column pruning and no
predicate pushdown.

## Scope

**In scope.** The read layer, the dataset manifest, the schema sidecar, and a
lazy parquet cache.

**Out of scope.** Porting `%vars`. `datasets/vars.sas` is 1,183 lines and is a
shared cross-study macro; this design defines where an R `vars` layer plugs in
and what it may not touch, and stops there.

## Architecture

Three layers. The parquet cache is internal to the read layer and invisible
above it.

| layer | responsibility | event/time variables |
|---|---|---|
| **read** | `.sas7bdat` (or `.xlsx`, `.csv`, `.rds`) to `data.frame`. Labels carried. Nothing coerced. | untouched |
| **vars** *(future)* | derivations, imputation, transformations, interaction terms, declared type coercion | **excluded by rule** |
| **job** | cohort filter, analysis | consumes raw event/time variables |

The events exclusion mirrors the SAS side rather than inventing a boundary.
The preserve_root study records that `iu_dead`, `il_dead`, `ic_dead`, `idead`
and `im_dead` "are not defined anywhere in `datasets/vars.sas`; they already
exist in the built dataset" — event and censoring variables bypass `%vars`
today.

## Components

### 1. Schema sidecar

A new exported function, `dataset_schema()`, returns one row per column:
creation position, name, R class, SAS type, `format.sas`, and label. Its
output is written as CSV.

It deliberately does not wrap `proc_contents()`. That function fills absent
labels with the variable's own name (see below), which is right for a printed
listing and wrong for a durable record — and its `n_unique` and `pct_missing`
columns describe the data rather than the schema, so they would change between
two reads of the same unchanged file.

The schema is captured from the **haven read**, never from the parquet. A
baseline derived from the converted file cannot test the conversion.

What haven loses is the storage layer: SAS `LENGTH`, `POS`, informat and the
dataset's created/modified timestamps. Those describe how SAS stores a value,
not what the value is, and parquet has no use for them. They are absent from
the sidecar rather than inferred.

What survives — name, label, `format.sas`, creation order — survives *when the
source carries it*. Measured on preserve_root's `built.sas7bdat`: of 879
variables, 865 carry a label (784 of them genuinely informative rather than an
echo of the name) and 395 carry a `format.sas`.

**The sidecar must not take its `label` column from `proc_contents()`.**
`proc_contents()` calls `labelled::var_label(null_action = "fill")`, which
substitutes the variable's own name when no label exists. That is right for a
printed listing and wrong for a durable record: it would write 14 fabricated
labels into built's sidecar, and after promotion (below) that fabrication
becomes the only surviving account of the SAS dataset. The sidecar reads
`attr(x, "label")` directly and records `NA` where there is none.

### 2. Manifest extension

`update_manifest()` gains three fields:

- `n_cols` — integer.
- `schema_sha256` — sha256 of the sidecar file, so the manifest-to-sidecar
  link is tamper-evident.
- `role` — `source` or `primary`. See *Promotion*, below. The field exists
  from the first release even though every entry starts as `source`: adding it
  later would mean migrating manifest files already scattered across studies,
  which is the schema-drift problem the manifest exists to prevent,
  reintroduced one level up.

`verify_manifest()` checks both, and additionally reports a **derived-path
collision**: two manifest entries whose source files share a stem and
therefore claim the same `.parquet` and `.schema.csv` paths. This is possible
because `datasets/` holds `.xlsx` alongside `.sas7bdat`. All 40 current
`.sas7bdat` stems are unique, so this is a guard, not a present defect.

### 3. Lazy parquet cache

Conversion happens on first read of a dataset, not in a bulk sweep. Datasets
that are never read are never converted, so stale and superseded copies cost
nothing.

**Validity check.** Re-hashing the source on every read would read the whole
file and defeat the cache. So:

- **fast key** — source `size` and `mtime`, from a `stat`. Decides hit/miss.
- **`sha256`** — computed once at conversion, recorded in the manifest,
  verified only on demand by `verify_manifest()`.

`built_manifest()` already returns `file / size_bytes / mtime / sha256`, which
is exactly this triple. The cache reuses it rather than introducing a parallel
mechanism.

**Miss path, in order:**

1. haven read with `convert_types = FALSE`
2. write the schema sidecar and the manifest entry
3. write the parquet to a temporary name and rename into place
4. return the frame

Step 3 is atomic because two jobs can race on the first read of a shared
dataset. Steps 1 and 2 precede step 3 so the baseline is independent of the
conversion.

**Hit path:** read the parquet, return the frame.

### 4. `convert_types` default

`read_clinical_data()`'s `convert_types` default changes from `TRUE` to
`FALSE`.

Reliance on the old default is detectable with `missing(convert_types)`: a
caller who passed the argument explicitly is unaffected, and one who did not
gets a one-time deprecation warning naming the change. The warning is removed
in a later release.

This is a breaking change for direct callers and requires a NEWS entry. The
whole of this design ships under `1.1.0`, at the maintainer's direction.

### 5. Study-side follow-up

`read_preserve_root()` in the preserve_root study switches to `read_built()`,
ending the split in defect 2. This is a file edit in the study tree, not a
change in this repo.

### 6. Collision guards

Two distinct name collisions can produce a silently wrong result. Both are
absent from preserve_root today; both are guards, not fixes.

**Lowercased column names.** `read_built()` applies
`names(d) <- tolower(names(d))` unconditionally. A source carrying both `FOO`
and `foo` yields two columns named `foo`, and every downstream `d$foo` selects
the first. Built's 879 variables are unique both as-is and lowercased, but
this runs across every study. The read layer checks `anyDuplicated()` after
lowercasing and errors, naming the colliding pair.

**Derived paths.** `datasets/` holds `.xlsx` alongside `.sas7bdat`, and
`read_clinical_data()` reads both. Two sources sharing a stem would claim the
same `.parquet` and `.schema.csv`. All 40 current `.sas7bdat` stems are
unique. Rather than uglify derived names to `built.sas7bdat.parquet`, the
manifest disambiguates: each entry records its source `file`, and
`verify_manifest()` reports two entries claiming the same derived paths.

## Promotion

When SAS stops rebuilding a dataset, its parquet stops being a cache and
becomes the data. This is a per-entry field change, not a migration, and it
happens dataset by dataset as each SAS job retires.

```yaml
# before
- file: built.sas7bdat
  role: source
  sha256: f90da65b…
  n_rows: 378
  n_cols: 879
  schema_sha256: …

# after
- file: built.parquet
  role: primary
  sha256: <parquet hash>
  promoted_date: '2026-11-14'
  source_file: built.sas7bdat
  source_sha256: f90da65b…
  n_rows: 378
  n_cols: 879
  schema_sha256: …          # unchanged: the same sidecar
```

`source_sha256` is retained so the chain of custody survives the source's
retirement.

Behaviour switches on `role`:

| | `role: source` | `role: primary` |
|---|---|---|
| authoritative file | `.sas7bdat` | `.parquet` |
| cache validity | source `size`+`mtime` | not applicable |
| `verify_manifest()` hashes | the source | the parquet |
| missing source file | an error | expected |
| sidecar | regenerable | **durable — never regenerate** |

That last row is the one with teeth. Before promotion the sidecar is a derived
artifact that can be rebuilt from the source at any time. After promotion the
source may be gone, and the sidecar becomes the only surviving record of what
the SAS dataset contained — column order, SAS types, `format.sas`, and the
labels distinguished from their fallbacks. Regenerating it from the parquet
would launder the parquet's schema into the historical record and destroy the
thing it exists to preserve. `verify_manifest()` refuses to regenerate a
sidecar for a `primary` entry.

This is also why the sidecar is captured on first read rather than at
promotion: the ability to produce it disappears with the source, and a lazy
cache means "first read" may be the only read that happens while the source
still exists.

## File layout

Derived files sit flat in `datasets/`, beside their source. When SAS stops
rebuilding these datasets the parquet is already in the canonical location and
nothing moves.

```
datasets/
├── built.sas7bdat        source        (retired after promotion)
├── built.parquet         derived       (authoritative after promotion)
├── built.schema.csv      regenerable   (durable after promotion)
└── manifest.yaml         one entry per dataset, carrying its role
```

`built_path()` resolves `cfg$built` — an explicit filename from `_study.yml` —
rather than globbing, so a flat layout is unambiguous for the built dataset.

## Metadata fidelity

Verified against arrow 24.0.0 and haven 2.5.5. A parquet round trip preserves:

- `label` and `format.sas` attributes
- `haven_labelled` class and its value labels
- `POSIXct` including timezone
- column classes

Arrow stores these as R-specific schema metadata. A non-R reader (pandas,
duckdb) sees the values but not the labels. This is acceptable while the
datasets are R-side; it is the constraint to revisit if they become a
cross-language asset.

## Testing

- **round trip** — a frame carrying `haven_labelled` with value labels, a
  variable label, a `format.sas` attribute and a `POSIXct` column survives
  write and read unchanged. Pins the behaviour above against an arrow upgrade.
- **events untouched** — a 0/1 event column is still numeric after the read
  layer, with `convert_types` at its new default.
- **cache invalidation** — touching the source changes `mtime`, and the next
  read must miss and regenerate.
- **manifest-to-sidecar linkage** — editing the sidecar makes
  `verify_manifest()` fail on `schema_sha256`.
- **derived-path collision** — two entries whose sources share a stem are
  reported by `verify_manifest()`.
- **lowercase collision** — a source carrying `FOO` and `foo` errors in the
  read layer rather than returning two columns named `foo`.
- **atomic write** — a failed or interrupted conversion leaves no partial
  `.parquet` in place.
- **label fidelity** — a variable with no label is recorded `NA` in the
  sidecar, not as its own name. Guards against a future refactor reaching for
  `proc_contents()$variables$label`, which fills.
- **role switching** — `verify_manifest()` hashes the source for a `source`
  entry and the parquet for a `primary` one; a missing source file is an error
  for the former and expected for the latter.
- **sidecar durability** — regenerating a sidecar for a `role: primary` entry
  is refused.

## Consequences

The manifest becomes self-populating: it fills in as jobs migrate rather than
requiring a 2.7 GB sweep, and its contents are an empirical record of which
datasets are actually live.

Recording raw haven types is not only documentation. It is the baseline that
shows the read layer coerced nothing, and it is what a future `vars` layer's
output is diffed against to show exactly which columns that layer touched.
