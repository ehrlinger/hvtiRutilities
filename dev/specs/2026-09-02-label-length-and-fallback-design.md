# Labels — length, fallback, value labels, and what `r_data_types()` is doing wrong

**Date:** 2026-09-02
**Status:** **Approved.** §7 answered on 2026-09-02 by John Ehrlinger:
option **B, then C**. All of §4, §5, §6 and §7 are buildable as designed;
an implementation plan is the next artifact.
**Package:** `hvtiRutilities`, with a build-step piece in `hvtiRdatabuild`
**Implements:** `dev/specs/2026-09-02-label-length-and-fallback-handoff.md`
**Reads with:** `dev/specs/2026-09-02-ordinal-representation-design.md`. The two
land in the same code path, and they converge on the same rule — §7.1.

This note is self-contained. It assumes no memory of the session that produced
it.

⚠️ No study, variable or patient identifier appears here.

---

## 1. What the handoff asked for, and what is actually wrong

The handoff lists five things to build: a `label_max` parameter defaulting to
40, the variable-name fallback, a `0`/`1` prefix stripper, a home for
enumerated level definitions, and the numeric-code-to-text conversion in the
build step.

Reading the code and running it changes the shape of the problem. Two of the
five are already done, and underneath the other three is a single defect that
the handoff describes symptom-first:

> **The package throws away the value labels, then asks people to reconstruct
> them by hand from the variable label.**

That is why REDCap labels enumerate eight options. It is why the prefixes are
there to strip. It is why the same conversion is done by hand in every table.
The label is being used as a value-label catalogue because the real catalogue
is never read.

## 2. What the code does today

Read from the source and confirmed by running it on 2026-09-02.

### 2.1 Already done — the fallback

`label_map()` (`R/label_map.R:55`) uses
`labelled::var_label(null_action = "fill")`, which fills an absent label with
the variable's **own name, verbatim**. It does not prettify. `proc_means()`
does the same (`R/proc_means.R:106`), and `proc_contents()` documents the
behaviour and its cost at `R/proc_contents.R:57`:

> `label` is never `NA`: it falls back to the variable's own name when the
> source carries no label […] An unlabelled variable is therefore
> indistinguishable here from one whose label equals its name.

So the handoff's fallback requirement is **satisfied as designed**, and
deliberately so: a bare variable name on a draft figure is the signal that a
label is missing, and it fails visibly. `label_map()` additionally warns when
more than 50% of columns lack real labels.

`dataset_schema()` is the counterweight — it reads the attribute directly and
leaves `NA` where there is none, because fill is *"right for a printed
listing, wrong for a record that outlives the source dataset"*
(`R/dataset_schema.R:48`).

**What is missing is a test**, asserting that the fallback returns the variable
name unchanged and does not title-case, expand or de-underscore it. That is
the whole of the work here.

### 2.2 The defect — value labels are read, then discarded

`haven` represents a SAS numeric-plus-format variable as a `haven_labelled`
vector carrying the code-to-text mapping. `labelled::to_factor()` turns it into
exactly the factor the handoff asks for, in one call.

`r_data_types()` destroys it instead. Run on 2026-09-02:

```r
x <- haven::labelled(c(1, 2, 1, 3),
                     labels = c(Home = 1, Rehab = 2, SNF = 3),
                     label  = "Discharge disposition")
str(r_data_types(data.frame(disp = x)))
#> $ disp: Factor w/ 3 levels "1","2","3": 1 2 1 3
#>   ..- attr(*, "label")= chr "Discharge disposition"
```

`Home`, `Rehab` and `SNF` were attached to the column and are gone. The
variable label survives; the level text does not. `labelled::to_factor(x)`
on the same input returns `Home Rehab Home SNF`.

The cause is at `R/r_data_types.R:109`: the multi-level branch tests
`n_distinct(x) < factor_size & !is.factor(x) & is.numeric(x)` and calls
`factor(., exclude = NA)`. A `haven_labelled` vector is `is.numeric()` and is
not a factor, so it takes that branch and `factor()` sees only the codes.

### 2.3 The upstream gap — the catalogue is never requested

`read_clinical_data()` calls `haven::read_sas(file)` (`R/read_clinical_data.R:96`).
`haven::read_sas()`'s second argument is `catalog_file`, and it defaults to
`NULL`. The `.sas7bcat` format catalogue is where SAS keeps the code-to-text
mapping; without it, a `.sas7bdat` yields the format **name** in `format.sas`
(`YESNOF.`) and no values.

So today the mapping arrives only if the source was already `haven_labelled`
— and §2.2 then discards it. From a plain `.sas7bdat` read it never arrives at
all. **`hvtiRutilities` has never read a SAS format catalogue.**

That is the honest answer to the handoff's "exception that is not one". Nobody
put eight mutually exclusive options in a label out of preference. They did it
because the label is the only field that survives the read.

## 3. Scope

**In:** `label_max` and where truncation belongs (§4), the fallback test
(§2.1), value labels as the code-to-text source (§5), the prefix question
(§6), and the `r_data_types()` decision (§7).

**Out:** the ordinal representation, which is
`2026-09-02-ordinal-representation-design.md` and blocked on a statistical
decision. The two notes' §7s must be answered together — see §7.1.

**Out, and belonging to `hvtiRdatabuild`:** running the conversion in the
build step, and the 110 REDCap macros. This note defines what
`hvtiRutilities` must expose for that to be a call rather than a
reimplementation.

## 4. `label_max`: truncation is a view, not a change to the data

The handoff says the 40-character cap should be *"applied at read/label time"*.
**Applied at read time it is lossy and irreversible** — the full label is gone
from the object and cannot be recovered by any downstream consumer that wants
it, including the schema sidecar whose whole job is to outlive the source.

The package already separates these two seams and should keep them separate:

| seam | function | what it owes the caller |
|---|---|---|
| **storage** | `dataset_schema()` | the label as the source carried it, or `NA`. Never truncated. |
| **display** | `label_map()`, `proc_contents()`, `proc_means()` | a label fit to print |

**Design:** `label_max` is a parameter of the *display* seam, default 40,
`Inf` or `NA` to disable. `dataset_schema()` never gains it.

**Truncation must be discoverable.** Three states again, as in the ordinal
note's §5: truncated, not truncated, and not checked. The minimum is a
`truncated` logical column on the label map, so a caller can ask. A companion
report — every variable whose label was cut, with both forms — follows the
precedent of `covariate_audit()` and `write_collision_report()`: it reports,
it does not raise.

⚠️ Truncating at exactly 40 characters mid-word produces
`"Ascending aorta only versus ascending plu"`. If `label_max` ships, it should
break on a word boundary and mark the cut, not `substr()`. That is a detail,
but it is the detail that decides whether the parameter gets used.

### 4.1 The name fallback is exempt from the cap

🔴 `label_max` applies to labels. It must **never** apply to a variable name
standing in for one.

§2.1 establishes that an unlabelled variable falls back to its own name,
verbatim, and that this is the design: a bare `hgb_bs` on a draft figure is the
visible signal that a label is missing. But that fallback happens *inside*
`label_map()`, which §4 has just given a `label_max`. Without an exemption the
two compose badly:

| variable | label | `label_map(label_max = 40)` returns |
|---|---|---|
| `age` | `"Age at operation (years)"` | `"Age at operation (years)"` |
| `preop_creatinine_clearance_calculated` | *none* | `"preop_creatinine_clearance_calculat"` ← **wrong** |

The truncated name is neither a label nor a variable name. It matches nothing
in the data, so it cannot be looked up, and it reads as a deliberately short
label rather than as a missing one — destroying precisely the signal §2.1
exists to preserve. The failure is silent and it looks like success.

**Rule:** truncation applies to a label only. Where `label_map()` has filled
from the variable name, the name passes through whole, however long, and
`truncated` is `FALSE`.

This interaction is not in the handoff. It falls out of combining the cap with
the fallback, and it is invisible to a review that reads §2.1 and §4 as
separate decisions.

## 5. Value labels are the code-to-text source

The handoff's recipe — *"read the label, convert the numbers to what the label
says"* — is a workaround for §2.3. The designed version has two inputs, in
priority order:

1. **`labelled::val_labels()`**, when the column carries them. This is the
   real mapping, machine-readable, and `labelled::to_factor()` already
   consumes it. Requires §2.2 to stop discarding it and §2.3 to start
   requesting the catalogue.
2. **An explicit declaration**, when it does not. The enumerated-levels
   attribute the handoff asks for — level text keyed by code, held **separately
   from the display label**, written where the ordinal note's §5 declaration is
   written, and read by the converter while the table renderer ignores it.

**Parsing the mapping out of label text is not a third input.** It is what is
being done by hand today, it is where the typos come from, and designing it in
makes the label load-bearing for two different jobs. The migration path is to
parse existing labels **once**, into declarations, and report what it did.

`read_clinical_data()` should expose `catalog_file`, passed through to
`haven::read_sas()`. That is a small, additive change and it is the highest-
leverage item in this note.

### 5.1 The design does not depend on the catalogues existing

Whether the studies hold `.sas7bcat` catalogues alongside their `.sas7bdat`
files is **open** — referred to the data managers on 2026-09-02 (§8). The
distinction is one letter and it decides how much input 1 is worth: a
`.sas7bdat` stores the format's **name** in `format.sas` (`YESNOF.`), and the
code-to-text mapping lives only in the catalogue. No catalogue, no
`val_labels` from a read, however the read is written.

Nothing above blocks on that answer, and it must stay that way:

- **`catalog_file` is additive.** It defaults to `NULL`, which is what
  `read_clinical_data()` already passes implicitly. Exposing it changes no
  existing call and is worth doing whether or not a catalogue is ever supplied.
- **Input 2 is the load-bearing one either way.** If the catalogues exist,
  the declaration covers what the catalogue misses. If they do not, it covers
  everything. Its design does not change; only how much of the corpus reaches
  it does.
- **The converter must say which input it used** — §7.1's second clause. That
  is what makes the answer to this question observable from a report rather
  than from asking around, and it is the reason not to wait for it.

**Contingency, if there are no catalogues.** The formats are likely defined by
`PROC FORMAT` in the SAS corpus, and this package already reads SAS source —
`sas_variable_block()` and `sas_macro_defs()` are the idiom. Mining `PROC
FORMAT` into declarations would be a third input, additive to input 2 rather
than a replacement for it. ⚠️ Do not build it speculatively; it is written
down so that a "no" from the data managers has an answer ready, not so that it
gets started now.

## 6. The `0`/`1` prefix — an ambiguity to settle before building

Asked directly whether the prefixes should come off, John said *"I think they
should."* The reading matters, and the handoff supports both:

| reading | example | consequence |
|---|---|---|
| **level text** | levels `0 No`, `1 Yes` → `No`, `Yes` | cosmetic, safe, reversible, and what a table shows |
| **variable label** | label `0=No 1=Yes Prior stroke` → `Prior stroke` | destroys the mapping unless §5 has already captured it |

**Recommended: level text only, and only after §5 has captured the mapping.**
Stripping a prefix off a label is the same operation as truncating it — it
throws away the only surviving copy of information the package failed to read
properly. Order matters: capture, then strip.

Note also that once level text becomes non-numeric, `covariates_to_numeric()`
silently stops converting the column and `covariate_audit()` reports
`ERROR: factor with non-numeric levels`. That is the collision documented in
the ordinal note's §6.1, and it applies to every variable this section touches.

### 6.1 The matching rule: a separator is required

§6 settles *what* gets stripped. This settles *how* it is matched, and the
distinction is load-bearing in this domain.

The example above — `0 No`, `1 Yes` → `No`, `Yes` — is a leading integer
followed by a space. A rule general enough to match it also matches real level
text in a cardiac surgery package:

| level text | digit-then-space rule | separator-required rule |
|---|---|---|
| `"1. Yes"` | `"Yes"` | `"Yes"` |
| `"0 = No"` | `"No"` | `"No"` |
| `"01 - home"` | `"home"` | `"home"` |
| `"1 vessel disease"` | `"vessel disease"` ← **wrong** | unchanged |
| `"2 vessel"` | `"vessel"` ← **wrong** | unchanged |
| `"3 vessel"` | `"vessel"` ← **wrong** | unchanged |

🔴 The digit-then-space rule turns three distinct levels into two identical
strings. Nothing errors. A downstream `table()` or model merges them, and the
factor's level count silently stops matching the data dictionary — the failure
presents as data, not as a bug.

**Rule:** strip a leading integer only when a separator follows it — `.`, `:`,
`=`, `)` or `-`, with optional surrounding whitespace. A bare digit-then-space
is left alone.

**The cost, stated plainly.** Unpunctuated `0 No` / `1 Yes` are *not* stripped
and still print with their prefix. That is the intended trade: a missed strip
is visible in the output and fixable by stating the level text in the §5
catalogue, whereas a wrong strip is silent and corrupts the level set. It also
means §5 does the real work here and §6 only tidies what §5 could not reach.

**Ordering, for §7.** Stripping is a display operation and never rewrites
stored level text, so a level named `01 home` keeps its ordering prefix in the
data while the table prints `home`. That is what keeps the
order-in-the-level-name option of the ordinal note's §2 available rather than
quietly foreclosed.

## 7. Rethinking `r_data_types()`

✅ **Decided 2026-09-02 by John Ehrlinger: option B, then C** (§7.3). B lands
first as a non-breaking argument on the existing function; C follows as a
separate declaration-first converter with `r_data_types()` deprecated in
place. D was ruled out.

### 7.1 The principle both notes arrive at

`r_data_types()` **infers a variable's type from its contents** — how many
distinct values it has — while the metadata that *declares* the type sits on
the column being ignored. A `haven_labelled` column knows it is categorical
and knows its levels. `format.sas` knows the format. The function reads
neither and counts distinct values instead.

The ordinal note reached the same rule from the other direction: ordinality
must be **declared, not inferred**, because inference from level names or sort
order cannot be checked. Stated once, for both:

> **Prefer the declaration. Fall back to inference only when there is none,
> and say which happened.**

The second clause is the part this package keeps getting wrong. A column that
became a factor because it was declared one, and a column that became a factor
because it happened to have seven distinct values, are currently the same
object.

### 7.2 What is wrong, concretely

- `haven_labelled` columns lose their value labels (§2.2).
- `factor_size` is a guess about the data that stands in for a fact about the
  variable. On a small dataset an ordinary continuous column crosses the
  threshold and becomes a factor — `age` with four distinct values in a
  four-row frame does exactly that.
- The binary branch converts any two-valued numeric to `logical`. That
  default already caused enough harm that `read_clinical_data()` flipped
  `convert_types` to `FALSE` with a deprecation warning naming *"0/1 event and
  censoring flags"* (`R/read_clinical_data.R:66`).
- Nothing in the output records which rule fired on which column.

### 7.3 Options

| option | what it costs |
|---|---|
| **A. Patch the branch order** — check `val_labels()` before the numeric branch, use `to_factor()` when present | smallest diff, keeps the guessing for everything else. Fixes §2.2 and nothing else. |
| **B. Add a `use_value_labels` argument**, default `FALSE` now and flipped later | the `convert_types` playbook, already proven in this package. Two releases, one warning, no surprises. |
| **C. New function beside it** — a declaration-first converter; `r_data_types()` deprecated in place | honest about being a different contract. Costs a name and a migration across the family. |
| **D. Change `r_data_types()`'s contract outright** | ⛔ It is exported, re-exported, used in three vignettes and by `read_clinical_data()`, and `AGENTS.md` is explicit that *"a breaking change here is a breaking change everywhere"*. Not without a deliberate decision. |

**Decided: B, then C.** B fixes the defect on the family's own deprecation
pattern without breaking a caller. C is where this ends up, because the two
behaviours really are different contracts and pretending otherwise is what
produced a `factor_size` parameter in the first place. D is ruled out.

**What B commits to.** A `use_value_labels` argument on `r_data_types()`,
default `FALSE` in the release that introduces it, warning once when it is
not supplied — the shape of the `convert_types` warning at
`R/read_clinical_data.R:66`, which named the harm in plain terms rather than
saying "deprecated". The default flips to `TRUE` in a later release. Until it
flips, no existing caller changes behaviour.

**What C commits to.** A separate converter whose contract is
declaration-first: value labels, then declaration, then inference, with the
rule that fired recorded per column. `r_data_types()` is deprecated in place
at that point, not removed — it is exported, re-exported, and used in three
vignettes and by `read_clinical_data()`.

⚠️ **B is not a licence to skip the report.** The reporting requirement below
applies to B as much as to C: an argument that silently changes which rule
fires is the same defect in a new place.

**Whichever is chosen, the converter must report.** One row per column: the
rule that fired, the source of the levels (value labels, declaration, or
inference), and what it produced. Without that, §7.1's second clause is
unimplemented and this note has fixed the symptom again.

## 8. What is not decided here

- Where the enumerated-levels declaration lives — the same open question as
  the ordinal note's §8, and it must get **one** answer, not two.
- **Whether `.sas7bcat` catalogues are available for the studies in the
  corpus.** Referred to the data managers on 2026-09-02; John did not know.
  §5's first input is worth little if they are not. §5.1 says why nothing
  blocks on the answer, and what the fallback is. This is a question for the
  data managers, not for the code — record the answer here when it comes.
- The REDCap path, and the upstream fix — data managers encoding REDCaps in a
  trackable way.

## 9. Definition of done

- [x] Design note written and listed in `dev/specs/README.md`
- [x] Current behaviour recorded with file references and confirmed by running it
- [x] The label-length, fallback and prefix items covered
- [x] Interaction with the ordinal design stated explicitly (§6, §7.1)
- [x] **§7 answered — B then C, John Ehrlinger, 2026-09-02**
- [ ] `catalog_file` exposed on `read_clinical_data()` (§5) — additive, can go
      first, and does not wait on the catalogue question
- [ ] **Data managers asked whether `.sas7bcat` catalogues exist (§5.1)**;
      answer recorded in §8
- [ ] B: `use_value_labels` on `r_data_types()`, default `FALSE`, warning once,
      with the per-column report (§7.3)
- [ ] Test asserting the fallback does not prettify (§2.1)
- [ ] `label_max` on the display seam, with truncation discoverable (§4)
- [ ] Test asserting a variable name longer than `label_max` is **not**
      truncated when it stands in for a missing label (§4.1)
- [ ] Prefix stripping requires a separator; test asserts
      `"1 vessel disease"` and `"2 vessel"` survive unchanged (§6.1)
- [ ] One home for the enumerated-levels declaration, shared with the ordinal note
- [ ] Build-step conversion in `hvtiRdatabuild`, calling this package rather than
      reimplementing it
- [ ] Versions bumped and `NEWS.md` updated in both repos **when code lands** —
      nothing to bump for this note

No `NEWS.md` entry and no version bump. Nothing in `R/` changed.
