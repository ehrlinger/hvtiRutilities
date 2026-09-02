# Handoff — label length, the fallback rule, and the exception that is not one

**Date:** 2026-09-02
**Repo:** hvtiRutilities (with a build-step piece in hvtiRdatabuild)
**Status:** not started. Nothing changed in either repo.
**Origin:** biostats training, 2026-09-02.

⚠️ No study, variable or patient identifier appears here.

---

## 1. What was decided in the room

**A 40-character label convention, exposed as a parameter.** Labels were capped at 40 characters historically; when the constraint lifted, long descriptive labels became normal, and they are now, in a participant's words, *"kind of a nightmare"* for tables. John committed on the spot: *"I'll put it in, I'll make it a parameter in the package."*

**The fallback rule, stated plainly:**

> hvtiPlotR will use labels for axis labels. hvtiRtables will use labels for tables. **If there isn't a label defined, it's going to go to the variable name.**

⭐ That fallback is deliberate and worth preserving as designed: seeing a bare variable name on a draft figure is the signal that a label is missing. It fails **visibly**. Do not substitute a prettified variable name, which would hide the gap.

**Strip `0`/`1` prefixes from categorical labels for publication.** Asked directly whether they should all come off: *"I think they should."* Today this is done by hand in every table — *"a lot of us do it manually every time"* — which is where the typos come from.

**Numeric-coded categoricals become factors with text levels.** The recipe John described: read the label, convert the numbers to what the label says, trim the label to 40, move on. This belongs in the build step.

**Variable names:** no longer capped at 8 characters, but *"that doesn't mean we need to go to 200"*. Keep the existing 8-char names — they are informative and understood. New ones may run 9–10. No spaces. They must **add** information rather than restate it, and stay consistent with the existing dictionary.

## 2. The exception, and why it is not an exception

Some REDCap variables carry roughly **eight mutually exclusive options enumerated inside the label** — the example given was ascending aorta only, ascending plus arch, and so on. Trimming that to 40 characters destroys the level definitions.

The proposal from the room: **put it in a different attribute**, not the label. *"There are other attributes that we can use. If we find that that information is in a label, we can put that in a different attribute."*

🔴 It was called *"an exception"* and then, in the same breath, *"very common in the aorta study."* By John's own rule stated later in the same meeting:

> If you have an exception and find out, oh wait, that's not an exception because I deal with them so often… then that is no longer an exception. It's your exception, but it's my standard.

**So this needs a designed home, not a special case.** An enumerated-levels attribute, separate from the display label, that the factor converter reads and the table renderer ignores.

## 3. What to build

**In hvtiRutilities:**

- `label_max` (or similar) parameter, default 40, applied at read/label time. Truncation must be reported, not silent — a label that was cut should be discoverable.
- The variable-name fallback, as designed above.
- The `0`/`1` prefix stripper for categorical labels.
- A place for enumerated level definitions that is **not** the label.

**In hvtiRdatabuild:**

- The label→factor conversion in the build step, since that is upstream of everywhere labels get used.
- REDCap conversion: **110 REDCap macros** exist in the corpus and are tracked as an open item. Part of the fix is upstream of code — data managers encoding REDCaps in a trackable way.

## 4. Why upstream matters

The motivating complaint, from the room: labels were being changed *while the paper was being published*. *"Wendy and I were changing labels on the fly and as we're publishing the paper, we're changing labels, which made me crazy."*

The fix is not a better renderer. It is that labels are settled **in the build or in `vars`**, before anything downstream reads them. Both hvtiPlotR and hvtiRtables consume labels, so a label changed late changes figures and tables that were already reviewed.

## 5. Sequencing

This work and the **ordinal** handoff land in the same code path and should be designed together. The nominal conversion (numeric codes → text factor levels) was decided; the ordinal case is open and blocked on a statistical decision. Do not build the nominal converter in a shape that makes the ordinal case awkward to add.

## 6. Definition of done

- [ ] Design note listed in `dev/specs/README.md`, covering label length, fallback, prefix stripping and the enumerated-levels attribute
- [ ] `label_max` parameter, default 40, with truncation discoverable rather than silent
- [ ] Variable-name fallback implemented and tested — including a test that asserts it does *not* prettify
- [ ] Enumerated level definitions have a home outside the label
- [ ] Build-step conversion in hvtiRdatabuild, with the REDCap path named
- [ ] Interaction with the ordinal design stated explicitly
- [ ] Versions bumped and `NEWS.md` updated in both repos
