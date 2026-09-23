# hvtiRutilities

Data utilities for the HVTI CORR group: type inference, variable labels, dataset manifests
and checksums, SAS `PROC` ports, the study data contract, and the SAS-parity harness. It is
the package the other members of the family depend on, so a breaking change here is a
breaking change everywhere.

This file is the operational contract and applies in full. It is tool neutral, so Codex and
any other agent read the same rules. Claude Code affordances live in `CLAUDE.md`, which
imports this file.

## Definition of done

- `devtools::test()` passes. 42 test files against 30 source files; a change without a test
  is not done.
- `devtools::check()` is **0 errors, 0 warnings, 0 notes**. It reached 0/0/0 on 2026-08-20;
  do not let a NOTE creep back and become "the usual one".
- `devtools::document()` has been run and `man/`, `NAMESPACE` and `DESCRIPTION` are committed
  with the source change. CI checks this and fails the PR otherwise.
- Every new export is in `_pkgdown.yml`. See the rules below — this one *errors*, it does not
  warn.
- Not "it looks right". A run that finished is not a run that is correct.

## The automated gates

Six workflows. Know what each one fails on before you push:

| workflow | fails on |
|---|---|
| `R-CMD-check.yaml` | `R CMD check` on Linux (release, devel, oldrel-1), macOS, Windows |
| `check-manual.yaml` | the PDF manual build — catches raw Unicode in `.Rd` that `--no-manual` skips |
| `lint.yaml` | `lintr::lint_package()` under `LINTR_ERROR_ON_LINT`, which is what makes it **fail** rather than merely report — see the 80/135 bullet below. Plus a **docs-current** job that runs `roxygenise()` and then `git diff --exit-code man/ NAMESPACE DESCRIPTION` |
| `pkgdown.yaml` | the site build, including a topic missing from the reference index |
| `house-style.yaml` | composes `.house-style-tools/compose-house-style.R` against `repos.yml`; it asserts the registry still contains this repo's path rather than failing later with a misleading cause |
| `test-coverage.yaml` | coverage upload |

## Generated files: never hand-edit

`man/*.Rd` and `NAMESPACE` come from roxygen. Edit the roxygen block in `R/` and run
`devtools::document()`. The **docs-current** job regenerates and diffs, so a hand-edit or a
forgotten `document()` fails the PR rather than landing quietly.

## Rules for this repo

- **Roxygen here is Rd markup, not markdown.** `DESCRIPTION` has no
  `Roxygen: list(markdown = TRUE)`, so backticks, `**bold**`, `*` bullet lists and `[fn()]`
  links land **literally** in the generated `.Rd` and render as garbage in the help page.
  Use `\code{}`, `\strong{}`, `\emph{}`, `\itemize{}` and `\link{}`. This shipped twice in
  one week and was caught by review both times.
- **Every exported object must be added to `_pkgdown.yml`.** The `reference:` index is
  explicit — 16 titled sections covering 40 exports — and pkgdown **errors**, not warns, on
  a topic that is missing from it. The site build is a required check.
  ⚠️ Its sibling `hvtiRtemplates` deliberately does the **opposite** and has no `reference:`
  section so pkgdown auto-indexes. Do not carry a habit across.
- **Lines are 135 characters, and the package IS lint-clean.** Both halves of this bullet
  changed on 2026-09-17, and the previous version was wrong about the more important one.
  ⚠️ **`lintr` did NOT enforce anything until then.** There was no `.lintr` file at all, so
  lintr fell back to its defaults, and `lint_package()` *prints* its result rather than
  failing on it — the step exited 0 while reporting **290 lints** on `main`, and every
  `lint.yaml` run in the repo's history had concluded `success`. The job could not have gone
  red. This is the same failure shape as a green `R-CMD-check` hiding a skipped test: read
  what a step *does*, never what its name or its check mark implies.
  The repair was three parts. `lint.yaml` now sets `LINTR_ERROR_ON_LINT`, so lintr's print
  method calls `quit("no", 31L, FALSE)` on a non-empty result. A `.lintr` sets the width to
  135, because `hvti_taxonomy()` is a data table written as code whose column alignment is
  the only thing making it readable, and it alone accounts for 45 of the 196 line-length
  lints; the widest line in the package is 132, the same measurement hvtiRtemplates records
  for the same table. Of the 69 lints left after that, **67 were fixed** in the source; the
  other two are a standalone nested block that `brace_linter` cannot express, covered by
  `allow_single_line = TRUE` rather than by touching the test.
  ⚠️ So **a green lint IS now the bar**, and the old advice to merely not *add* lints is
  withdrawn. `.lintr` grants exactly two exemptions, `commented_code_linter` and
  `object_name_linter`, each with its reasoning recorded in the file, and **no path
  exclusions at all**. Keep it that way: a path key is invisible in a passing run, and
  renaming nine files in hvtiRtemplates took its lint count from 0 to 86 in one step.
  ⚠️ `.lintr` is **DCF**, not R. `read.dcf()` parses it, so an indented `#` inside the
  `linters:` value terminates the record and the file fails to load. Comments go at column 0,
  above the key.
- **`testthat` edition 3.** `DESCRIPTION` sets `Config/testthat/edition: 3`.
- **`.Rbuildignore` excludes the session-tooling directories** — `.claude`, `.superpowers`,
  `.remember`, `.vscode`, `dev`. Add new tooling directories there when they appear;
  otherwise they land in the tarball as a NOTE. `ROADMAP.md` is listed for the same
  reason: it sits at the root but is not one of the files `R CMD check` expects there.
- **`_study.yml` records registered datasets, not a study-wide cohort.**
  `cohort_counts(d, event, time)` observes that job's cohort counts;
  `assert_cohort(d, expected, event, time)` compares them with that job's reference. Reusing
  whole-dataset expected counts for a filtered job can pass when the three totals match even
  though the actual analysis cohort was never checked. Derive expected counts from the job's
  own reference.
- **`compare_parity()`'s `digits` is DECIMAL PLACES.** SAS commonly prints *significant
  figures*, so a flat `digits = 7` asserts a tolerance up to two orders of magnitude too
  tight for a value below 1 and reports agreeing references as a disagreement. Derive it per
  value: `sig - 1 - floor(log10(abs(x)))`.
- **A `merge()`-based parity join must assert it is COMPLETE**, not merely non-empty. A
  partial join silently shrinks the comparison while every surviving row still passes — the
  failure a parity harness is least able to notice.

## Gotchas

- **`object_usage_linter` resolves cross-file references against the INSTALLED package.** A
  function calling another function added in the same uncommitted change lints as "no visible
  global function definition" until the package is installed. That warning is an artifact,
  not a defect; `R CMD check` does its own codetools pass and is the real test.
  ⚠️ **This also means a local lint run overstates the count unless you install first.**
  `lint.yaml` passes `local::.` to `setup-r-dependencies` for exactly this reason, so CI does
  install. Measured 2026-09-17: `.cache_key` and `.cache_key_diff` reported as undefined from
  a bare working tree and resolved once the package was installed. Run
  `R CMD INSTALL --no-docs .` before trusting a number you intend to act on.
  ⚠️ It inspects **closures only**, which is why bare `skip_if_not_installed()` passes 39
  times in `tests/` and yet flags twice. A call inside `test_that("...", { ... })` sits in an
  unevaluated expression, not a function, so codetools never sees it; the two that flagged
  were the suite's only top-level helper *function definitions*. Qualify `testthat::` in a
  helper closure rather than reaching for an exclusion.
- **`utils::` is used in several files while `utils` is not in `Imports`.** This is tolerated
  because `utils` is base-priority and attached by default. Do not "fix" it as drive-by work,
  and do not take it as licence to call an undeclared non-base package.
- **`verify_manifest()` fails open**: it returns `OK` for entries it never checked when
  `n_rows` is absent. Awkward next to the word "compliance"; know it before relying on a
  green result.
- `VignetteBuilder` is **quarto**, not `knitr`. Vignettes are `.qmd`.

## Change discipline

1. **Think before coding.** Do not assume, ask. If the request is ambiguous or a name, path
   or signature is uncertain, surface the confusion rather than running with a guess. One
   good clarifying question beats a confident wrong edit.
2. **Simplicity first.** Write the minimum code that solves the stated problem. No
   speculative abstractions, no "while I am here" generalizing. Prefer the plain readable
   form a future reader can follow over the clever one.
3. **Surgical changes.** Touch only what the task requires. Do not refactor, reformat or
   re-style adjacent code, and do not reorganize imports or rename things that were not
   asked for. If you spot something worth changing nearby, raise it separately rather than
   folding it in.
4. **Goal-driven execution.** State what done looks like before starting, and use tests as
   the success criterion. If no test covers the change, add or propose one rather than
   declaring success from inspection.

## Git and versioning

- **Never push to `main`.** Branch, then open a PR and let the maintainer merge. A push
  rejected with "Changes must be made through a pull request" means branch — never
  force-push around it.
- **`main` is protected by a GitHub ruleset, and nothing in this repo records that.** A clone
  shows no trace of it, so it is stated here. The ruleset is named `protect main` and enforces
  five rules on the default branch: no deletion, no force-push, pull-request-only, an
  **automatic Copilot code review** on every PR, and **required status checks**. The rejection
  above comes from the server, not a local hook.

  Because the file is the only record, it is the one thing here with no way to detect its own
  drift. **Verified against the live ruleset on 2026-09-23**; re-verify with

  ```
  gh api repos/ehrlinger/hvtiRutilities/rules/branches/main \
    --jq '.[] | {type, params: .parameters}'
  ```

  **A PR needs zero approving reviews.** `required_approving_review_count` is **0**, so a PR
  reaches `mergeStateStatus=CLEAN` once its required checks pass, with no approval at all. It
  was **1** until at least 2026-09-02; the change applies across the family (see the table
  below). ⚠️ So `CLEAN` means the checks passed, **not** that anyone reviewed the change. An
  agent must still not merge its own PR: the maintainer merges, per the bullet above.
  `require_extra_approval_for_unattributed_changes` is **true**, which can still ask for an
  approval on commits GitHub cannot attribute to a verified author.

  The required status checks are the ten CI jobs `docs-current`, `house-style`, `lint`,
  `pkgdown`, `test-coverage` and the five `R CMD check` platforms. ⚠️ `check-manual` is
  **not** among them, so a PDF-manual failure does not block a merge. Read its result
  yourself.

  `require_code_owner_review` is **false** here. Adding a `CODEOWNERS` file would not by itself
  change anything until that flag is turned on; doing both changes who can approve what.

  **Copilot reviews on open and does not re-review when you push.**
  `copilot_code_review.review_on_push` is `false`, so a review posted when the PR opened stays
  as posted after you fix what it found — pushing does not clear it, and re-requesting the
  reviewer through the API does not reliably re-trigger it. Say in the PR what you changed and
  why instead of waiting for a second pass. In the other direction,
  `dismiss_stale_reviews_on_push` and `require_last_push_approval` are both `false`, so a human
  approval **survives** later pushes to the branch. Nothing re-gates after an approval lands.

  ⚠️ **The family is not uniform. Do not carry these facts to a sibling repo unchecked.**
  All fourteen `hvti*` repositories were checked on 2026-09-23 (approval count and code-owner
  flag only; the other rules were read for this repo alone):

  | repos | state |
  |---|---|
  | 11 active repos | `protect main`, active, **zero** approvals, `require_code_owner_review: false`. `hvtiGraphics`, the odd one out on 2026-09-02, now matches |
  | `hvtiBoostmtree` | **archived**; `protect main` still active with **one** approval |
  | `hvtiEDAreports` | **archived**; ruleset named `main`, **`enforcement: disabled`** |
  | `hvtiRforests` | empty repository: no branches and no ruleset |
- Versions are **straight three digits** (`1.0.11`). Never a `.9000` suffix or a fourth
  digit.
- **Patch-digit bumps only**, as fixes land. The minor and major digits are the maintainer's
  decision, taken when a feature set is consolidated into a release. Do not roll them.
- **Bump when you name a version, not when you merge.** A pull request lands without touching
  `Version:`. Its entry goes under a `# hvtiRutilities (unreleased)` heading in `NEWS.md`,
  which you add when it is not already there. A separate commit then renames that heading to
  the new version and updates `DESCRIPTION`, at most once a day. The heading is gone again
  after a bump, so the next change re-adds it. `.claude/house-style.md` carries the rule and
  the reasoning.
- **A change that ships nothing gets no `NEWS.md` entry and no bump.** That is a pull request
  whose every changed file is left out of the tarball `R CMD build` produces, meaning the base
  branch's `.Rbuildignore` excludes it: here `.github/`, `AGENTS.md` and `CLAUDE.md` among
  others. One shipped file means the change ships, and the usual rules apply. No user can
  observe a change that ships nothing, so the pull request and its commit message are the
  record. Read `.Rbuildignore` rather than judging by feel.

## Prose

Documentation prose — vignettes, README, roxygen `@description` and `@details`, release
copy — follows the house voice composed into `.house-style-tools/`. Apply it to any
documentation text here.
