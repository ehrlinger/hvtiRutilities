# Handoff — `hvtiGraphics` documents a `label_map()` shape that no longer exists

**Date:** 2026-09-04
**Execute in:** `hvtiGraphics` — **not** this repo
**Status:** open. Nothing changed in `hvtiGraphics` yet, deliberately.
**Origin:** verification of the v1.1.9 release, 2026-09-04. Found while
checking a claim in
`2026-09-02-label-length-and-fallback-design.md` that turned out to be wrong;
see its §9.1.

⚠️ No study, variable or patient identifier appears here.

---

## 1. The problem, in one paragraph

`hvtiRutilities` v1.1.9 gave `label_map()` a `label_max` argument defaulting to
40 and two new columns, `label_full` and `truncated`. `hvtiGraphics` is the
**only** repository in the family that *executes* the function — other mentions
across the family are `dev/specs/` design prose — and its chapter
`data_governance.qmd` now contradicts itself:

- **line 79** — prose: *"`label_map()` returns the current variable-to-label
  mapping as a two-column (`key`, `label`) data frame."*
- **line 87** — a live chunk: `lm <- label_map(dat)` then `gt(head(lm, 10))`,
  which as of v1.1.9 renders **four** columns directly beneath that sentence.

Nothing errors. The chapter simply tells the reader one thing and shows
another, which is worse in a recipe book than a failure would be.

## 2. Why the published site does not show this yet

`hvtiGraphics` commits `_freeze/` and CI never executes a chunk. The frozen
output for `data_governance` was written against `hvtiRutilities` **1.1.8**, so
the site currently serves a two-column table that matches the prose. The
contradiction appears the moment anyone re-renders that chapter — including
someone re-rendering it for an unrelated reason.

This is checkable without rendering anything:
`_freeze/data_governance/execute-results/html.json` and its `tex.json` sibling
both contain the two-column sentence and the frozen chunk output. Read them
first if you want to confirm the state before you start.

🔴 That is the repo's own named failure mode: *"Stale `_freeze/` publishes a
lie that nothing can detect."* Here it is publishing a *true-looking* page
built from stale output, which is the same defect wearing a friendlier face.

## 3. Decisions already taken — do not relitigate

**Do not pass `label_max = Inf` in the chunk.** Decided by John Ehrlinger,
2026-09-04. The chapter should show what a reader actually gets from a default
call. Disabling the cap to make the old prose true again would document a
configuration nobody uses and hide the feature the release added.

So the **prose changes, the call does not**.

## 4. What to write

Replace the two-column sentence. The paragraph has to carry three facts the
reader now needs, in the chapter's existing voice and without turning a
narrative step into a reference page:

1. The map is `key`, `label`, `label_full`, `truncated`.
2. `label` is trimmed to 40 characters by default, because a long descriptive
   label has nowhere to go on an axis or a column header.
3. The untrimmed text survives in `label_full`, and `subset(lm, truncated)`
   answers "which labels will a figure abbreviate" before a reviewer asks it.

Two short paragraphs is the right size. Do not document the variable-name
fallback or `apply_value_labels()` here — different chapter, different job.

## 5. The operational constraint that makes this more than a one-line edit

⚠️ **Read `hvtiGraphics`'s `AGENTS.md` before starting.** The parts that decide
the work:

- **`pr-check.yml` fires on any source change to a chunk-bearing chapter,
  prose included**, because `freeze: auto` invalidates the cache on any change
  to the `.qmd`. A prose-only edit without a `_freeze/` update **fails the
  PR**.
- **There is no command that renders one chapter.** `quarto render
  data_governance.qmd` rebuilds the whole book in both formats. That is still
  the command to run: `freeze: auto` re-executes only the changed chapter, so
  it should touch exactly one `_freeze/` directory. Measured there at ~1m 16s.
- **Read the freeze diff before staging** and narrow it if it is wider than the
  one chapter. `AGENTS.md` gives the `git add` / `checkout` / `clean` recipe
  and warns that it destroys everything else under `_freeze/`.

## 6. The prerequisite that will silently produce the wrong answer

🔴 **Install `hvtiRutilities` >= 1.1.9 before rendering.** Rendering against
1.1.8 regenerates a two-column freeze, the diff looks plausible, the gate goes
green, and the chapter stays wrong — with a fresh cache asserting it is right.

```r
packageVersion("hvtiRutilities")   # must be >= 1.1.9
```

Installed at 1.1.9 on this machine on 2026-09-04, from the `v1.1.9` tag. A
different machine will need it done again.

Note also that other chapters' caches remain built against whatever was
installed when they last executed. That divergence is expected and documented
in `hvtiGraphics`'s `AGENTS.md`; do **not** force a full re-render to tidy it
as part of this change.

## 7. Definition of done

- [ ] `data_governance.qmd` prose describes the four-column return and the
      40-character default
- [ ] The chunk is unchanged — still a plain `label_map(dat)`
- [ ] `hvtiRutilities` >= 1.1.9 installed, verified before rendering
- [ ] Book re-rendered; `_freeze/data_governance/` updated and the diff
      confirmed to be that chapter only
- [ ] PR opened against `hvtiGraphics`, never a push to `main`
- [ ] No version change — `hvtiGraphics`'s version is an edition badge in
      `README.md` and is the maintainer's call

## 8. What is not in scope

- The `NEWS.md` 1.1.9 entry in `hvtiRutilities`, which names the wrong
  consumers. It is tagged; §9.1 of the design note is the correction of record.
- Any other chapter. `data_governance.qmd` is the only one that calls
  `label_map()`.
- `apply_value_labels()`, which no chapter uses yet and which may deserve its
  own recipe later.
