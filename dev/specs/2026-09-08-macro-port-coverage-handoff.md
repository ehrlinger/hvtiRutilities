# Handoff — macro port coverage, and the number nobody can re-derive

**Date:** 2026-09-08
**Repo:** `hvtiRutilities`, beside `sas_triage()` and `sas_macro_defs()`.
**Status:** not started. Nothing in this repo has changed.
**Origin:** the biostats deck reports "32 of 176 macro files ported, 104 to go, 35 with no
owner yet" and nobody could say where it came from. It came from a hand survey run once, three
weeks ago.

⚠️ No study, variable or patient identifier appears here, and none may appear in what this
builds. Counts and macro-library file names only.

🔴 **ERRATUM 2026-09-09 — 176 is not the library, and the denominator is the smaller half
of the problem.** `~/Documents/macro.library` holds **310 SAS source files** at its top level
(346 files in all). The scans behind every figure here globbed `*.sas` and read **176 — 57%**,
never opening 105 extensionless files (58 defining macros, 38 of them call sites) or 29
dot-named ones such as `kaplan.int` and `lm.cprobs`. 97 of the extensionless files have no
`.sas` counterpart at all.

So "32 of 176 ported, 104 to go, 35 unowned" is a fraction over a partial denominator, and the
slide carrying it **overstates coverage**. This does not weaken §1's argument — the number
still cannot be re-derived — it adds that the number is also wrong, in the flattering
direction.

**Fixed and re-run 2026-09-09** on
[hvtiRtemplates#94](https://github.com/ehrlinger/hvtiRtemplates/pull/94): the picker is now a
denylist, ported from this repo's own shipped `.sas_source_files()`. The allocation map went
176 → 310 files, 94 → 119 allocated, 73 → **178** corpus-only, with **no pre-existing file
changing tier or destination**. Full account in
`hvtiRtemplates/dev/specs/2026-09-09-macro-library-coverage-erratum.md`.

⚠️ **What that does NOT settle is exactly what this handoff is about.** PORTED / TO PORT /
RETIRE is a judgement the allocation scan does not make — it answers *who owns each file*, not
*what state the port is in*. The re-run gives the survey a correct file list to run against;
it does not re-derive the survey. Every number in §1 below still needs the tool §2 specifies,
and now needs it over 310 files rather than 176.

---

## 1. The problem, stated plainly

`Projects/SAS Macro Port Status.md` in the vault holds this table:

| State | Files |
|---|---|
| PORTED | 32 |
| TO PORT | 104 |
| RETIRE | 23 |
| THIRD-PARTY | 11 |
| DELETE (variant) | 6 |

176 files, 72 resolved, and the 35 unowned are a subset of the 104. It is the headline number
for the whole SAS migration and it appears on a slide shown to the department.

🔴 **Nothing re-derives it.** It was produced on 2026-08-18 by a session that read the packages
by hand. Since then `hvtiRbootstrap` shipped its selection core to 0.9.3, this package reached
1.1.10, `hvtiRtables` reached 1.0.0 and `ggBoostedTrees` appeared. The ported count is almost
certainly low and there is no command that says by how much.

⭐ **The pattern this family keeps hitting:** a number a human derived once, quoted onward for
weeks, with no way to ask it again. The corpus census, the two-studies gate and the per-folder
naming rule were all this shape. This one is the same shape and is easier to fix, because half
of it is mechanical.

## 2. What is already here, and what axis each thing answers

Do not assume this is half-built. Three functions in this package touch the same corpus and
none of them answer this question.

| function | what it answers |
|---|---|
| `sas_macro_defs(file)` | which `%macro` definitions a file contains, with a body hash |
| `sas_triage(dir)` | which **file** is canonical for a macro name, or whether that is ambiguous |
| `write_macro_manifest(x, path)` | serialises a `sas_triage()` table to YAML |

`sas_triage()`'s `decision` column is *canonical* / *ambiguous*. It is about which of several
copies to believe. It is **not** ported / to-port / retire, and a reader skimming for a
`decision` field will mistake one for the other.

The allocation scan in the sibling repo
(`hvtiRtemplates/dev/specs/artifacts/2026-08-14-macro-allocation-scan.py`) answers a third
question, *who owns each file*, and is current as of 2026-09-02: 94 allocated, 73 corpus-only,
5 travelling with a dependent, 4 blocked. ⚠️ **Its destination is not the receiver.** See §5e.

## 3. What to build

One function, and the artifact it emits.

**Input:** the macro library directory, and the set of package source trees to search.

**The signal, and it must be two signals:**

- the receiving package names the macro, `%name`, in `R/` or `man/`, **or**
- the receiving package names the file, `plot.sas`, in `R/` or `man/`.

**Output:** one row per macro-library file, carrying at minimum `file`, `ported` (logical),
`receiver` (the package, or `NA`), and `signal` (which of the two fired, or both).

**Emit counts only.** No paths outside the macro library, no study names. The artifact is
committed and this repo is public.

## 4. Why two signals, with the measurement

⭐ **Coverage went 25 → 32 when the file-name signal was added**, and the miss was caught by the
maintainer rather than by the scan: *"plot.sas was supposed to be covered in hvtiPlotR"*. It
was. `hvtiPlotR`'s package roxygen reads "an R port of the `plot.sas` macro suite", with a
vignette and a SAS-migration guide. The first pass keyed on `%macroname` tokens only, and
`hvtiPlotR` cites the file, not the macro.

🔴 **A package citing neither is still invisible, and that blind spot must be reported rather
than hidden.** The output should carry the count of files with no citation of either kind so a
reader can see the size of what the method cannot see. A coverage number that does not state
its own blind spot is the failure this family has already made twice.

## 5. The traps, each with the evidence behind it

**a. False positives are real, and were excluded by hand.** Three known classes, all from the
2026-08-18 pass:

- `hvtiRutilities/R/sas_lint.R` cites `gmatch.sas`, `xmacro.sas`, `repeated.sas` and others as
  **parser test fixtures**. A fixture is not a port.
- `hvtiPlotR`'s `trends.sas` hit is the *template* `tp.rp.trends.sas`, not the macro.
- A macro name that is also an ordinary English word will match prose.

⚠️ **This is the half that needs a designed rule rather than a grep**, and it is where a naive
implementation will quietly inflate the number. Decide what counts as a citation before
writing the matcher, and record the decision in a design note.

**b. Scope the directory walk explicitly, and say so in the output.** `sas_triage()` scans only
the top level of its `dir`. The 2026-08-18 reachability pass deliberately covered every file in
the macro library **including `archive/`, `jobs/` and `tests/`**. 🔴 These two are not wrong
together, but a new function that silently picks one is. This is the same defect class as the
one-level glob in the allocation scan that saw 231 of 244 template files while reporting a
confident result.

**c. It is a provenance claim, not a parity check.** "Ported" means the package says it ports
this macro. Only `boot_summary()` was ever held to exact parity against its SAS original. ⚠️ The
artifact must not be readable as "verified", and the field name should not invite it.

**d. The receiver is frequently not the allocation map's destination.** The map's tier-2 rule,
*reached by more than one prefix therefore `hvtiRutilities`*, was wrong in **every observed
case**: all six files it routed here were ported elsewhere, and this package had ported **zero**
of its thirteen assigned files as of 2026-08-18.

| file(s) | map said | actually ported in |
|---|---|---|
| `plot.sas`, `plot_8.sas`, `plot_emf.sas`, `plotjoan.sas` | hvtiRutilities | hvtiPlotR |
| `kaplan.int.sas`, `kaplan_jr.sas` | hvtiRutilities | hvtiPlotR |
| `nelsonl.sas` | hvtiRutilities | TemporalHazard |
| `bootstrap.summary.sas` | hvtiRutilities | hvtiRbootstrap |
| `nelsont.sas` | TemporalHazard | hvtiPlotR |

⭐ **So record the actual receiver, and emit the disagreement with the map as a finding.** That
disagreement is the most useful thing this scan can produce: it is evidence about the routing
rule, not just about coverage. Re-measure the "zero of thirteen" claim rather than repeating it;
it is three weeks old and this package has moved twice since.

**e. Some numbers are judgment and must stay written down.** RETIRE (23), THIRD-PARTY (11) and
DELETE-as-redundant-variant (6) are decisions, not measurements, and they belong in the vault
note rather than in a scan. The third-party set in particular is a fixed list of eleven files
that should be **data the scan reads**, not something it re-derives: four are SAS Institute
sample library, one is Mayo, and six have mature R equivalents. Re-deriving a judgment on every
run is how a judgment gets silently reversed.

## 6. Why this repo, and the case against

**For `hvtiRutilities`:** the corpus-reading layer already lives here. `sas_macro_defs()`,
`sas_triage()` and `sas_lint()` are here, `hvti_taxonomy()` moved down here from
`hvtiRtemplates` on the principle that shared vocabulary belongs in the lower layer, and
`job_files()` / `job_census()` established the pattern of a corpus sweep that keeps every row
and reports what it could not place.

**Against:** the allocation scan lives in `hvtiRtemplates`, and this new sweep has to read its
JSON to produce the disagreement in §5d. Two halves of one question in two repos is the
condition that produced the drift the job catalog was moved to `hvtiR` to fix.

⭐ **The test that decides it:** does anything outside the migration ever need to ask whether a
macro has an R port? If the answer is only ever the migration, it belongs beside the allocation
scan in `hvtiRtemplates` as an artifact script. If a package or a study would ask it, it is a
function and belongs here. **Check before committing.** This family has been wrong three times
in a month by inferring placement from where a related file already sits.

## 7. Fix on the way past

The vault note's own regenerate command pointed at `hvtiRtemplates/specs/artifacts/...` for
three weeks after those artifacts moved to `dev/specs/` on 2026-08-28. Corrected 2026-09-08. If
this work produces a command, put it in the note and make it the only place the command is
written.

## Definition of done

- [ ] Design note in `dev/specs/`, listed in its README, deciding the citation rule (§5a), the
      directory scope (§5b) and the placement question (§6)
- [ ] The sweep implemented wherever §6 lands it, emitting counts only
- [ ] Blind-spot count reported: files citing neither macro nor filename
- [ ] Disagreement with the allocation map emitted as its own output
- [ ] The eleven third-party files read as data, not re-derived
- [ ] `Projects/SAS Macro Port Status.md` regenerated from it, and its regenerate line updated
      to the one real command
- [ ] The deck's headline stat re-derived, and the delta from 32 recorded rather than quietly
      replaced
