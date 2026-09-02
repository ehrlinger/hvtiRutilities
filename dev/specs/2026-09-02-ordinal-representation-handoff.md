# Handoff — ordinal variables: a decision, then a design

**Date:** 2026-09-02
**Repo:** hvtiRutilities
**Status:** not started, and **not ready to code**. Step 1 is a decision, not an implementation.
**Origin:** biostats training, 2026-09-02. John, in the room: *"Ordinals are an interesting phenomenon in R that we have to really process through because we don't have an ordinal data type… I've been thinking about that for years because I don't have a solution."*

⚠️ No study, variable or patient identifier appears here.

---

## 1. The problem, stated once

SAS carried ordinality in a numeric code plus a format. R has `ordered()` factors, but **the analysis tools largely ignore the ordering** — a point made from the floor and not disputed. So an ordinal variable arriving from a build has no representation that survives into a model without a deliberate choice.

Current practice is to **dichotomise**, and it is usually fine. From the floor: *"Typically we dichotomize those variables… but there are times when the statistician doesn't need or want that. They want it left ordinal."* So the default is adequate and the exception is real.

## 2. The three options that were aired, and what each costs

| Option | What it does | What it loses |
|---|---|---|
| **Order in the level name** | `01 home`, `02 rehab`, `03 SNF` — the sort order is lexical and survives everything | The order is a naming convention, not a type. Nothing enforces it and nothing can check it. |
| **`ordered()` factor** | R's own answer. Correct type, correct `<` semantics | Most modelling functions treat it as unordered, or emit polynomial contrasts nobody asked for. Correct and ignored. |
| **One-hot** | Every level becomes a boolean, works everywhere | Destroys ordinality by construction — becomes one-versus-rest per level. Named in the room as exactly this. |

**None of these is free, and the choice is statistical.** Which contrasts a model should use for an ordered predictor is not a packaging question. ⚠️ **Do not implement one and call it solved.**

## 3. What to actually do

**Step 1 — write the decision note, not the code.** `dev/specs/2026-09-0X-ordinal-representation-design.md`. State the three options, what each costs, and what CORR's default should be. Take it to Blackstone and the statisticians, because that is where the answer lives.

**Step 2 — whatever is decided, make the representation *inspectable*.** The failure this family keeps hitting is a value that means "fine" and a value that means "never looked" being the same value. Applied here: a variable that is ordinal but stored as an unordered factor must not be indistinguishable from one that is genuinely unordered. Whatever the decision, there should be a way to ask a dataset which of its variables are ordinal and be told, rather than inferring it from level names.

**Step 3 — only then, the helper.** Probably a converter plus a check, in `hvtiRutilities` alongside the label work. It should be able to report what it did and why, in the same spirit as `study_status()`.

## 4. Related decisions from the same meeting

These are separate items but land in the same code path and should be designed together, not serially:

- **Numeric-coded categoricals become factors with text levels.** Read the label, convert the codes to the label's text. This is the *nominal* half of the same conversion, and it was decided; the ordinal half is what is open.
- **Strip `0`/`1` prefixes off categorical labels for publication.** Asked directly, John: *"I think they should"* come off. Done by hand in every table today, which is where the typos come from.
- **Some REDCap labels enumerate ~8 mutually exclusive options.** Those carry ordering *and* level text in one string. See the label-length handoff — the two problems meet there.

## 5. Definition of done

- [ ] Design note written, listed in `dev/specs/README.md`, with the three options and their costs
- [ ] Taken to the statisticians; the decision recorded with who made it and when
- [ ] Ordinality is inspectable, not inferred from a naming convention
- [ ] Converter and check implemented only after the above
- [ ] Interaction with the nominal converter and with label trimming stated explicitly
