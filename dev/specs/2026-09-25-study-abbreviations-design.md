# Study abbreviation lists: one list per study, over a group default

**Date:** 2026-09-25
**Status:** design. Sections 2 and 3 decided by John Ehrlinger on 2026-09-25.
Section 8 is open. Nothing is built.
**Packages:** `hvtiRutilities` (the default list, the accessor, `label_map()`),
`hvtiRtemplates` (the job-level `EDIT:` point and the provenance record).
Nothing in `hvtiRdatabuild`.
**Reads with:** `2026-09-02-label-length-and-fallback-design.md` §4.2, smart
truncation, which consumes these lists. **Supersedes** its §4.2.1, the
snapshot-per-analysis-set route (see section 3).
**Release:** planned for hvtiRutilities 1.4.2 and hvtiRtemplates 1.2.3
(hvtiRtemplates `dev/specs/2026-09-25-release-eda-complete-plan.md`, Phase 2b).

This note is self-contained. It assumes no memory of the session that produced
it.

⚠️ No study, variable or patient identifier appears here.

## 1. What this is for

Smart truncation (§4.2) shortens a label that is over the cap, first by
abbreviating a heading several labels share (`Surgical procedure:` to `SP:`),
and before that by any abbreviation it is given. Without a list, every job
repeats the same `c("Coronary artery bypass graft" = "CABG", ...)` in an
`EDIT:` point, and two jobs in one study can abbreviate the same phrase two
ways. A study should say it once, and most of what it says is the same across
studies, so the group should say that once too.

## 2. Decided: a group default, which a study overrides

`hvtiRutilities` ships a curated **group default list** of phrase and
abbreviation pairs common across HVTI studies. A study's own list adds to it
and overrides it. A job can add to both. Decided 2026-09-25.

Precedence, highest first:

1. the job's `ABBREVIATIONS` `EDIT:` point (hvtiRtemplates);
2. the study's `abbreviations:` in `_study.yml`;
3. the group default;
4. §4.2's initials rule, for a shared heading no list covers.

A phrase appears once in the merged list: a higher level replaces a lower
level's entry for the same phrase, compared ignoring case. A study removes a
default it does not want by mapping the phrase to `null`.

## 3. Decided: read the list live, record it per job

A job reads the merged list **when it renders**, for whatever dataset it reads,
and **records the list it used in its provenance**. Decided 2026-09-25.

This replaces §4.2.1's route, which copied the list into each analysis set's
`.set.yml` when the set was written. Reasons, in order of weight:

- **An EDA job can read the whole study dataset**, which has no analysis-set
  record to carry a list. §4.2.1 left that case open; reading live closes it.
- **An edit reaches every job on its next render**, instead of only the sets
  written after the edit.
- **Reproducibility moves to where it is cheaper.** A job's provenance sidecar
  already records what the render used; the abbreviation list joins it, so an
  old report can still say exactly which list shaped its labels.
- **No `hvtiRdatabuild` change**, so the feature can ship in 1.4.2 and 1.2.3.

§4.2.1's other rule stands unchanged: **the list is a display input, never
written into the stored labels.**

## 4. The pieces

### 4.1 The group default: `inst/extdata/abbreviations.yml`

A YAML mapping, phrase to abbreviation, shipped in `hvtiRutilities`:

```yaml
Coronary artery bypass graft: CABG
Left ventricular: LV
Aortic valve: AV
Mitral valve: MV
Tricuspid valve: TV
New York Heart Association: NYHA
Ejection fraction: EF
```

⚠️ **Those seven are an example, not the list.** The starter list is John's to
curate (section 8.1). A test holds the file to the rules of section 4.4.

### 4.2 The study list: `abbreviations:` in `_study.yml`

```yaml
abbreviations:
  Surgical procedure: SP
  Left ventricular outflow tract: LVOT
  Ejection fraction: ~        # drop the default for this study
```

**Why `_study.yml` and not `labels_overrides.yml`.** `apply_label_overrides()`
already reads a per-study `labels_overrides.yml`, but it maps **variable names
to whole labels**, and it is found by working-directory path. An abbreviation
list maps **phrases to short forms** inside any label, and `study_config()`
already reads `_study.yml` from the study root, wherever the job sits. Two
mappings of different kinds in one file would be read wrongly sooner or later.

**Order against overrides.** Overrides decide a variable's full label;
abbreviations shorten labels for display. So overrides apply first, and the
abbreviation step sees the overridden label as `label_full`.

### 4.3 The accessor: `study_abbreviations()`

```r
study_abbreviations(cfg = study_config(), extra = NULL, defaults = TRUE)
```

Merges **all three levels in one place**: the group default (unless
`defaults = FALSE`), the study list, and `extra`, the job's own entries. A job
passes its `ABBREVIATIONS` as `extra` rather than merging them itself, so that:

- the section 4.4 checks run on the list the job actually uses, including a job
  entry that collides with a study or default entry (a job adding
  `Systolic pressure = SP` where the study already has `Surgical procedure = SP`);
- the case-insensitive merge rules live in one function, not copied into every
  template;
- the level each entry came from is known, for provenance (section 4.6).

**Return shape:** a named character vector, phrase to abbreviation, ready for
`label_map(abbreviations = )`, carrying an attribute `source`: a character
vector of the same length, each element `"job"`, `"study"` or `"default"`.
`null` removals are applied and do not appear in the result.

### 4.4 Validation

`study_abbreviations()` and a test on the default file enforce:

- a phrase is one non-empty string, and its abbreviation is one non-empty
  string **or `null`**. `null` is allowed in the study list and in `extra`,
  where it removes a lower level's entry for that phrase; a `null` entry is
  exempt from the remaining checks, since it adds no abbreviation. `null` in
  the group default file is an error;
- a phrase appears once per list, compared ignoring case;
- **two different phrases may not share an abbreviation** in the merged list:
  `SP` for both `Surgical procedure` and `Systolic pressure` would make a
  shortened label ambiguous. That is an error naming both phrases and the
  level each came from;
- an abbreviation is not longer than its phrase.

An invalid study list stops the render with a message naming every bad entry at
once, the house rule for validation errors.

### 4.5 In a job (hvtiRtemplates)

```r
# EDIT: phrases this job abbreviates beyond the study's list, or NULL.
ABBREVIATIONS <- NULL
...
abbrev <- hvtiRutilities::study_abbreviations(.cfg, extra = ABBREVIATIONS)
labels <- label_map(d, label_max = LABEL_MAX, abbreviations = abbrev)
```

The template does no merging of its own; section 4.3 says why.

### 4.6 Provenance

The job adds the merged list, with its `source` attribute giving each
entry's level, to its provenance record (`hvtiRtemplates:::.embed_provenance(extra = ...)`). Only the
entries that `label_map()` actually used also appear in the report, as the
abbreviation key under each section (§4.2's `abbreviations` attribute).

## 5. Matching

The matching rules are §4.2's, restated so this note stands alone:

- whole words, case-insensitive, **longest phrase first**, so
  `Left ventricular outflow tract` wins over `Left ventricular`;
- applied only to a label that is over the cap, or to every member of a
  shared-heading group that has one member over the cap;
- the abbreviation is written exactly as the list spells it.

## 6. Tests

- `study_abbreviations()`: default only; a study addition; a study override of
  a default, differing only in case; a `null` removal, in the study list and
  in `extra`; `extra` overriding a study entry; `defaults = FALSE`; the
  `source` attribute naming each entry's level.
- A collision introduced by `extra` alone (a job phrase sharing a study
  phrase's abbreviation) is caught.
- Every validation rule in section 4.4, each with an error naming the entry and
  its level; several bad entries reported in one error.
- The default file passes section 4.4.
- A study with no `abbreviations:` key gets the default list, not an error.
- hvtiRtemplates: a job's `ABBREVIATIONS`, passed as `extra`, beats the
  study's entry for the same phrase; the merged list and its `source` appear
  in the job's provenance.

## 7. What ships where

| package | release | adds |
|---|---|---|
| hvtiRutilities | 1.4.2 | `inst/extdata/abbreviations.yml`; `study_abbreviations()`; `_study.yml` `abbreviations:` validated by `study_config()`; `label_map(abbreviations = )` from §4.2 |
| hvtiRtemplates | 1.2.3 | `ABBREVIATIONS` `EDIT:` point in `dp-postage` and `dp-eda`, passed as `extra`; the provenance record |

## 8. Open

1. **The starter list.** Which phrases the group default holds on day one.
   Proposed: start small, from phrases that appear in labels across several
   studies' built datasets (a census, as for the templates), rather than from
   memory.
2. **Who curates it after.** A change to the default changes every study's
   labels on its next render. It should go through a PR like any other change,
   with a NEWS line naming the entries added or changed.
3. **A helper to edit a study's list** (`add_abbreviation()`), or hand-editing
   `_study.yml` only. Proposed: hand-editing for now; `study_config()` already
   validates the file.
