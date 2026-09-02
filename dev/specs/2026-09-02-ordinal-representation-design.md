# Ordinal variables — the representation decision

**Date:** 2026-09-02
**Status:** **Decision note. Not a plan, and not ready to implement.** §7 is a
recommendation for the statisticians to accept, amend or reject. Nothing in
this package changes until they have.
**Package:** `hvtiRutilities`, with a build-step piece in `hvtiRdatabuild`
**Implements:** step 1 of `dev/specs/2026-09-02-ordinal-representation-handoff.md`
**Reads with:** `dev/specs/2026-09-02-label-length-and-fallback-design.md` —
the two land in the same code path (§6), and one of them breaks the other today
(§6.1).

This note is self-contained. It assumes no memory of the session that produced
it.

⚠️ No study, variable or patient identifier appears here.

---

## 1. The question this answers

SAS carried ordinality in a numeric code plus a format. R has `ordered()`
factors, but the modelling tools largely ignore the ordering — a point made
from the floor at the 2026-09-02 biostats training and not disputed. So an
ordinal variable arriving from a build has no representation that survives
into a model without a deliberate choice.

The question is **which representation CORR adopts as its default**, and that
is a statistical decision, not a packaging one. Which contrasts a model should
use for an ordered predictor is not something this package gets to settle by
picking an implementation.

Current practice is to dichotomise, and it is usually fine. From the floor:
*"Typically we dichotomize those variables… but there are times when the
statistician doesn't need or want that. They want it left ordinal."* The
default is adequate; the exception is real and has no home.

## 2. What the code does today

Not a proposal — this is the current behaviour, read from the source and
confirmed by running it on 2026-09-02.

| step | file | what happens to an ordinal |
|---|---|---|
| type inference, binary | `R/r_data_types.R:101` | numeric with exactly 2 distinct values → **logical**. This is the dichotomised default, in code. |
| type inference, multi-level | `R/r_data_types.R:109` | numeric with more than 2 and **fewer than** `factor_size` distinct values → `factor(., exclude = NA)`, **unordered**. The bound is strict, so the default `factor_size = 10` converts 3 to 9. |
| type inference, already ordered | `R/r_data_types.R:101-113` | an `ordered()` factor is `is.factor()`, so every branch skips it. It **passes through untouched.** |
| covariate audit | `R/covariates.R` | reports `storage = class(col)[1]`, so an ordered factor reads `"ordered"` |
| covariate conversion | `R/covariates.R` | a factor whose levels all parse as numbers → `as.numeric(as.character(col))`, so it **enters a model linearly** |

Two things follow, and both matter more than they look.

**The ordering survives by accident, and only the ordering.** `factor()` sorts
numeric levels numerically, so a `surg_num` coded 1, 2, 3, 4 comes out of
`r_data_types()` with its levels in the right sequence. It looks correct. What
is lost is not the order but the **intent**: nothing in the resulting object
distinguishes a variable that is ordinal from one that is not, so nothing
downstream can act on it and nothing can check it. This is the package's
recurring failure class — a value that means "fine" and a value that means
"nobody looked" being the same value — in a new place.

**There is a fourth option already shipping.** The handoff lists three (name
prefixes, `ordered()`, one-hot). `covariates_to_numeric()` is a fourth:
**integer scoring**, the ordinal entering the model as a single linear term.
`covariate_audit()` reports it in as many words —
`action = "factor -> numeric, enters linearly"`. It is the treatment the SAS
jobs specify, `R/covariates.R:57` already names the case
(*"a `surg_num` with levels 1, 2, 3, 4 is a number of previous operations, not
four unordered categories"*), and any decision that ignores it is deciding
against something already in production without saying so.

## 3. The options, and what each costs

| option | what it does | what it costs | in this package today |
|---|---|---|---|
| **Dichotomise** | collapse to a threshold, one boolean | throws away every distinction but one; the threshold is a clinical choice made per variable and rarely recorded | the default for 2-level numerics (`R/r_data_types.R:101`) |
| **Order in the level name** | `01 home`, `02 rehab`, `03 SNF` — lexical sort survives everything | the order is a naming convention, not a type. Nothing enforces it, nothing can check it, and a renamed level silently reorders the variable | not used |
| **`ordered()` factor** | R's own answer. Correct type, correct `<` semantics | most modelling functions treat it as unordered, or emit polynomial contrasts nobody asked for. `model.matrix(~ x)` on an ordered 3-level factor yields `x.L` and `x.Q`, not the two dummies the analyst expected. Correct and ignored, or correct and surprising | `generate_survival_data()` makes `nyha_class` ordered; nothing consumes the ordering except `proc_means()` row order |
| **Integer score** | one linear term, the SAS treatment | asserts equal spacing between adjacent levels. Defensible for a count of prior operations, indefensible for a discharge disposition | `covariates_to_numeric()` |
| **One-hot** | every level a boolean, works everywhere | destroys ordinality by construction — becomes one-versus-rest per level | not used |

None of these is free. **Do not implement one and call the problem solved.**

## 4. Scope of this note

**In:** the representation decision, the record that makes ordinality
inspectable (§5), and the interaction with the nominal converter and label
trimming (§6).

**Out, and deliberately:** any converter, any contrast policy, any change to
`r_data_types()`. Those are step 3 of the handoff and depend on §7 being
answered.

**Out, tracked elsewhere:** the enumerated-levels attribute for REDCap labels
that carry ~8 mutually exclusive options. That is the label-length design note's
§5. It supplies level *text*; ordinality is about level *sequence and intent*.
They meet but they are not the same problem.

## 5. Whatever is decided, ordinality must be inspectable

This part does **not** depend on §7 and can be designed now.

The requirement: a variable that is ordinal but stored as an unordered factor
must not be indistinguishable from one that is genuinely unordered. It must be
possible to ask a dataset which of its variables are ordinal and be **told**,
rather than inferring it from level names or from a coincidence of sort order.

Three constraints, from this package's own precedent:

1. **The record is a declaration, not an inference.** A heuristic that guesses
   ordinality from level names reintroduces exactly the ambiguity being fixed.
   `dataset_schema()` already takes this line for labels — it reads the
   attribute directly and leaves `NA` where the source carries none,
   specifically because `proc_contents()`'s fill-with-the-variable-name is
   *"right for a printed listing, wrong for a record that outlives the source
   dataset"*.
2. **Three states, not two.** Ordinal, not ordinal, and **not declared**. An
   undeclared variable must not read as "not ordinal". Compare
   `covariate_audit()`'s `noninteger_levels`, where a blank means "no such
   level" and `NA` means *"not looked for"*, and `verify_manifest()`, which
   fails open and is called out in `AGENTS.md` for it.
3. **Reported, never raised.** `study_status()` reports every check and raises
   none. An ordinality report should behave the same way: it tells you what it
   found and what it would do, and the caller decides.

**Half the surface already exists.** `class(ordered(x))[1L]` is `"ordered"`, so
`dataset_schema()`'s `class` column and `covariate_audit()`'s `storage` column
already distinguish an ordered factor from a plain one with no code change.
What is missing is the declaration for variables that are ordinal but *not*
stored as `ordered()` — which, given §2, is all of them.

The obvious shape, by analogy with `covariate_audit()`: one row per variable,
with the declared ordinality, the storage found, and an `action` saying what a
converter *would* do. That makes the gap between intent and storage visible
before anything acts on it. **Where the declaration is written** — a column
attribute, `vars`, `_study.yml`, or the schema sidecar — is an open question,
listed in §8.

## 6. Interaction with the nominal converter and label trimming

The label-length handoff decided the **nominal** half of the same conversion:
read the label, convert numeric codes to the label's text, trim the label to
40 characters. That decision is made; the ordinal half is what is open. Its
§5 says the two must be designed together and that the nominal converter must
not be built in a shape that makes the ordinal case awkward to add.

### 6.1 The collision, confirmed by running it

Recoding numeric levels to text **breaks the covariate path**, silently.
`covariates_to_numeric()` guards on every level parsing as a number and skips
the column when one does not. Run on 2026-09-02 against this branch:

| input | `covariate_audit()` `action` | `covariates_to_numeric()` |
|---|---|---|
| `factor(c(1, 2, 3, 1))` | `factor -> numeric, enters linearly` | numeric 1, 2, 3, 1 |
| `factor(c("1 prior", "2 prior", "3 prior", "1 prior"))` | `ERROR: factor with non-numeric levels` | **returns the factor unchanged, no warning** |

So the moment the nominal converter runs, every recoded variable that used to
enter a model as a linear term stops doing so. `covariate_audit()` says
`ERROR` if anyone asks it, which is the good half; `covariates_to_numeric()`
returns the column untouched and says nothing, which is the bad half. A job
that calls the converter and fits the result gets a different model with a
different parameter count and no message.

**This is not a reason to reject the nominal decision.** It is a constraint on
sequencing: the ordinal declaration (§5) has to be in place before, or with,
the text recode, so that a recoded ordinal can still be scored or contrasted
deliberately. Recoding first and adding ordinality later means a window in
which the linear terms quietly disappear.

### 6.2 Label trimming

Trimming a label to 40 characters must not touch level text. The label
describes the variable; the levels are the variable's values. The
enumerated-levels declaration from the label-length design note's §5 exists for
exactly this reason, and an ordinal's level sequence should travel with it
rather than with the display label.

## 7. Recommendation to take to the statisticians

⚠️ **Draft. This is the section that needs John's judgment and then the
statisticians' sign-off — it is written to be argued with, not adopted.**

The recommendation is **not** to pick one representation. It is:

1. **Keep dichotomisation as the default.** It is current practice, it is
   usually right, and it is honest about what it discards. Nothing here
   proposes changing what most jobs do.
2. **Make the exception declarable rather than special.** A variable declared
   ordinal is stored as `ordered()`, so the type says what it is, and the
   declaration is recorded where §5 puts it.
3. **Make the model treatment an explicit per-analysis choice, not a property
   of the stored variable.** Score, dummy, or polynomial contrast is the
   statistician's call at fit time. The stored representation's job is to
   preserve the information and record the intent, not to pre-decide the
   contrast.
4. **Default the contrast to treatment, not polynomial.** R's default for
   `ordered()` factors is `contr.poly`, which produces `x.L`/`x.Q` terms most
   readers of a CORR table will not expect. If ordered storage is adopted, the
   surprising default should be neutralised deliberately rather than
   discovered in an output.

The open question for the statisticians, stated in one line:

> When a variable is left ordinal rather than dichotomised, what should the
> default model treatment be — linear score, treatment contrasts against a
> reference level, or polynomial contrasts?

Record the answer with **who made it and when**, in this note.

## 8. What is not decided here

- Where the ordinality declaration lives — column attribute, `vars`,
  `_study.yml`, or the schema sidecar. Each has a different blast radius and a
  different answer to "does it survive a parquet round trip".
- Whether the declaration carries the level sequence or only the fact of
  ordinality.
- Whether `r_data_types()` gains an argument or a companion function. §5's
  report is the seam either way; adding a `factor_size`-style parameter is a
  breaking change to a function the whole family depends on.
- The REDCap path. 110 REDCap macros are an open item in the label-length
  handoff, and the enumerated-option labels are where the two problems meet.

## 9. Definition of done for this note

- [x] Written and listed in `dev/specs/README.md`
- [x] The options and their costs stated, including the integer-score option
      already shipping
- [x] Current behaviour recorded with file references and confirmed by running
      it
- [x] Interaction with the nominal converter and label trimming stated, with
      the silent-failure collision named
- [ ] **Taken to the statisticians; §7 answered, with who decided and when**
- [ ] Follow-on design note for the declaration's location (§8), once §7 is
      answered
- [ ] Only then: converter and check, with tests

No `NEWS.md` entry and no version bump. Nothing in `R/` changed.
