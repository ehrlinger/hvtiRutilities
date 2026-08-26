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

**Validity check.** Validity is decided by the entry's `role`, which is a fact
about whether SAS still builds the dataset, not a caching policy:

| state | how the read decides |
|---|---|
| `role: source` | source `size` + `mtime` from a `stat`; falls back to verifying the recorded `sha256` when `mtime` is ambiguous |
| `role: primary` | the parquet **is** the data. No source is consulted, and none need exist. |
| `refresh = TRUE` | re-read from the source and reconvert, whatever the manifest says |

Re-hashing the source on every read would read the whole file and defeat the
cache, so `sha256` is not the fast path. But `size` alone discriminates almost
nothing — a 20-row and a 5-row `.sas7bdat` are both exactly 16384 bytes,
because the format is page-aligned — which leaves `mtime` carrying the entire
decision.

Whether `mtime` can carry it is a property of the filesystem, and it is
**measured rather than assumed**. A filesystem that reports sub-second `mtime`
leaves a same-tick rewrite window of microseconds; one that reports whole
seconds leaves a window a full second wide, inside which a rewrite is
genuinely invisible. So: if the source's `mtime` carries a fractional part,
`mtime` is trusted; if it is a whole second, the recorded `sha256` is verified
instead.

Production runs server-side on a local filesystem, where `mtime` is
nanosecond-resolution and the fast path always applies. Development over an
SMB mount may land on whole-second stamps and pay for a hash. Neither is a
special case in the code — the same `stat` decides.

An earlier draft compared the source's `mtime` against a client-side
`Sys.time()` recorded at conversion. That was wrong for a reason worth keeping
written down: those are two different clocks whenever the files live on
another host, and a client running even one second fast makes every entry look
unambiguous forever. A validity rule may only compare readings of the same
clock — here, two `mtime`s from the same filesystem.

**Stat before reading, never after.** The source's `size`/`mtime` are captured
*before* the haven read begins. Captured afterwards, a source rewritten
during the read would be stamped with its new `mtime` against
partly-old data, and that pairing would validate forever. Stamped from
before, a mid-read change looks stale on the next call and self-heals.

`refresh` exists because "the source changed" is not always something a
timestamp can express — a rebuild that preserves `mtime`, a restored backup, a
correction applied out of band. It makes re-reading an explicit act rather
than an inference.

`built_manifest()` already returns `file / size_bytes / mtime / sha256`, which
is the fast key plus the fallback. The cache reuses it rather than introducing
a parallel mechanism.

**Miss path, in order:**

1. `stat` the source, recording `size` and `mtime`
2. haven read with `convert_types = FALSE`
3. write the schema sidecar and the manifest entry, recording the reader
   version alongside the hashes
4. write the parquet to a temporary name and rename into place
5. read the parquet back and verify it round-trips
6. return the frame

Steps 3 and 4 precede nothing that could contaminate them: the sidecar is
derived from the frame haven returned, never from the parquet, so it remains
an independent description of what the source contained.

Every write in steps 3 and 4 goes through a temporary name and a rename. Two
jobs racing on the first read of a shared dataset would otherwise let one hash
a sidecar the other is midway through truncating, recording a
`schema_sha256` that matches nothing on disk and putting the entry into
permanent verification failure.

**Step 5 exists because a promoted dataset has no second chance.** While an
entry is `role: source`, a bad conversion self-heals — the next invalidation
rewrites it from the source. Once the source is retired there is nothing left
to disagree with the parquet, so the single conversion that produced it must
be checked at the time it happens, by reading it back and comparing against
the frame haven returned. A hash of bytes just written proves only that the
write completed.

**The reader version is recorded.** `record_provenance()` captures R and
package versions per *rendered output*; a manifest entry captured none. Under
`role: primary` the parquet is the data, so the haven version that produced it
is part of its provenance: a reader defect discovered later is unfindable
otherwise, and re-reading the source is no longer an option.

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
  sha256: f90da65b…         # hash of built.sas7bdat
  n_rows: 378
  n_cols: 879
  schema_sha256: …

# after
- file: built.sas7bdat      # UNCHANGED: the dataset's identity, not its storage
  role: primary
  sha256: <parquet hash>    # role decides which file this hashes
  promoted_date: '2026-11-14'
  source_sha256: f90da65b…  # the retired source's hash, kept for custody
  n_rows: 378
  n_cols: 879
  schema_sha256: …          # unchanged: the same sidecar
```

**`file` does not change on promotion.** It names the dataset, not the file
that currently stores it; `role` says which physical file is authoritative and
therefore which one `sha256` describes. An earlier draft renamed `file` to
`built.parquet`, which broke promotion in a way worth recording: every lookup
in the read path keys on the source's basename, so a renamed entry became
invisible to `read_built()` while `verify_manifest()` — which resolves
`entry$file` directly — still found it. The two halves of the package assumed
different manifests. Renaming also contradicts the property the `role` field
exists for: promotion is a field change, not a migration.

`source_sha256` is retained so the chain of custody survives the source's
retirement.

Behaviour switches on `role`:

| | `role: source` | `role: primary` |
|---|---|---|
| `file` field | the dataset's identity | **the same value — never renamed** |
| authoritative file | `.sas7bdat` | `.parquet` |
| read validity | source `size`+`mtime`; `sha256` when `mtime` is whole-second | parquet is the data; source never consulted |
| `sha256` describes | the source | **the parquet** |
| `verify_manifest()` hashes | the source | the parquet, resolved via `.derived_paths()` |
| missing source file | an error | **expected — and `read_built()` must still serve the parquet** |
| a cache miss | reconvert from the source | **must not rewrite the entry from the source** |
| sidecar | regenerable | **durable — never regenerate** |

Two rows carry consequences that are easy to miss.

`sha256` describes whichever file the role makes authoritative, so
`verify_manifest()` must select its target by role rather than always hashing
`entry$file`. Because `file` never changes, that selection cannot be inferred
from the name.

A cache miss on a promoted entry — its parquet deleted while the retired
source happens to still be present — must not fall through to the ordinary
miss path. That path rewrites the entry from the source, replacing the
parquet's hash with the source's and dropping `promoted_date` and
`source_sha256`, after which verification fails permanently on a study whose
data was intact.

The "missing source file" row is a requirement on `read_built()`, not only on
`verify_manifest()`. A `role: primary` entry means the source has been
retired, so a read path that guards on the source existing would make
promotion unreachable — the one thing promotion exists for would be the one
thing it cannot do.

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
<study_root>/
├── _study.yml            study declaration
├── manifest.yaml         one entry per dataset, carrying its role
└── datasets/
    ├── built.sas7bdat    source        (retired after promotion)
    ├── built.parquet     derived       (authoritative after promotion)
    └── built.schema.csv  regenerable   (durable after promotion)
```

`manifest.yaml` sits at the study root, not in `datasets/` — that is where
`study_init()` writes it. Code must not derive the manifest path from a
dataset's directory. `verify_manifest()` correspondingly needs
`data_dir = file.path(root, "datasets")`, which is what `study_status()`
passes.

`built_path()` resolves `cfg$built` — an explicit filename from `_study.yml` —
rather than globbing, so a flat layout is unambiguous for the built dataset.

## Metadata fidelity

Verified against arrow 24.0.0 / haven 2.5.5, and again against **arrow
23.0.1.2** on the production host. A parquet round trip preserves:

- `label` and `format.sas` attributes
- `haven_labelled` class and its value labels
- `POSIXct` including timezone
- column classes

Arrow stores these as R-specific schema metadata. A non-R reader (pandas,
duckdb) sees the values but not the labels. This is acceptable while the
datasets are R-side; it is the constraint to revisit if they become a
cross-language asset.

The stronger evidence is not the fixture. `.verify_parquet_roundtrip()`
compares each column with `identical()`, which compares attributes as well as
values, and it runs on every conversion. preserve_root's `built.sas7bdat` —
378 rows, 879 variables, 865 labels, 395 SAS formats — converted cleanly on
the production host, which is a per-column attribute check across the whole
real dataset rather than a hand-built frame.

**Measured on that conversion**, server-side on a local filesystem:

| | |
|---|---|
| `built.sas7bdat` | 67.2 MB |
| `built.parquet` | 0.7 MB |
| `built.schema.csv` | 0.1 MB |
| first read (haven parse + convert) | 2.1 s |
| second read (parquet) | 0.2 s |

**Do not generalise the 96× size ratio.** A `.sas7bdat` is page-aligned and
pads heavily — the same property that makes file size useless as a change
signal, where a 20-row and a 5-row file are both 16384 bytes. At 378 rows,
most of those 67.2 MB are padding, so the ratio mostly measures padding
removal rather than compression, and it will fall sharply on a dataset with
enough rows to fill its pages. The ~10× read speedup is the figure that should
carry over, since it is parse cost rather than storage.

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
