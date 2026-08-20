# hvtiRutilities

Data utilities for the HVTI CORR group: type inference, variable labels,
dataset manifests and checksums, SAS `PROC` ports, the study data
contract, and the SAS-parity harness. It is the package the other
members of the family depend on, so a breaking change here is a breaking
change everywhere.

This file is the operational contract and applies in full. It is tool
neutral, so Codex and any other agent read the same rules. Claude Code
affordances live in `CLAUDE.md`, which imports this file.

## Definition of done

- [`devtools::test()`](https://devtools.r-lib.org/reference/test.html)
  passes. 42 test files against 30 source files; a change without a test
  is not done.
- [`devtools::check()`](https://devtools.r-lib.org/reference/check.html)
  is **0 errors, 0 warnings, 0 notes**. It reached 0/0/0 on 2026-08-20;
  do not let a NOTE creep back and become “the usual one”.
- [`devtools::document()`](https://devtools.r-lib.org/reference/document.html)
  has been run and `man/`, `NAMESPACE` and `DESCRIPTION` are committed
  with the source change. CI checks this and fails the PR otherwise.
- Every new export is in `_pkgdown.yml`. See the rules below — this one
  *errors*, it does not warn.
- Not “it looks right”. A run that finished is not a run that is
  correct.

## The automated gates

Six workflows. Know what each one fails on before you push:

| workflow | fails on |
|----|----|
| `R-CMD-check.yaml` | `R CMD check` on Linux (release, devel, oldrel-1), macOS, Windows |
| `check-manual.yaml` | the PDF manual build — catches raw Unicode in `.Rd` that `--no-manual` skips |
| `lint.yaml` | [`lintr::lint_package()`](https://lintr.r-lib.org/reference/lint.html), plus a **docs-current** job that runs `roxygenise()` and then `git diff --exit-code man/ NAMESPACE DESCRIPTION` |
| `pkgdown.yaml` | the site build, including a topic missing from the reference index |
| `house-style.yaml` | composes `.house-style-tools/compose-house-style.R` against `repos.yml`; it asserts the registry still contains this repo’s path rather than failing later with a misleading cause |
| `test-coverage.yaml` | coverage upload |

## Generated files: never hand-edit

`man/*.Rd` and `NAMESPACE` come from roxygen. Edit the roxygen block in
`R/` and run
[`devtools::document()`](https://devtools.r-lib.org/reference/document.html).
The **docs-current** job regenerates and diffs, so a hand-edit or a
forgotten `document()` fails the PR rather than landing quietly.

## Rules for this repo

- **Roxygen here is Rd markup, not markdown.** `DESCRIPTION` has no
  `Roxygen: list(markdown = TRUE)`, so backticks, `**bold**`, `*` bullet
  lists and `[fn()]` links land **literally** in the generated `.Rd` and
  render as garbage in the help page. Use `\code{}`, `\strong{}`,
  `\emph{}`, `\itemize{}` and `\link{}`. This shipped twice in one week
  and was caught by review both times.
- **Every exported object must be added to `_pkgdown.yml`.** The
  `reference:` index is explicit — 16 titled sections covering 40
  exports — and pkgdown **errors**, not warns, on a topic that is
  missing from it. The site build is a required check. ⚠️ Its sibling
  `hvtiRtemplates` deliberately does the **opposite** and has no
  `reference:` section so pkgdown auto-indexes. Do not carry a habit
  across.
- **Lines are 80 characters.** `lintr` enforces it. The package is not
  lint-clean overall, so a green lint is not the bar — do not *add*
  lints.
- **`testthat` edition 3.** `DESCRIPTION` sets
  `Config/testthat/edition: 3`.
- **`.Rbuildignore` excludes the session-tooling directories** —
  `.claude`, `.superpowers`, `.remember`, `.vscode`, `specs`. Add new
  tooling directories there when they appear; otherwise they land in the
  tarball as a NOTE.
- **`_study.yml` records the STUDY cohort, not a job’s cohort.**
  [`cohort_counts()`](https://ehrlinger.github.io/hvtiRutilities/reference/cohort_counts.md)
  derives from the whole built dataset. A job analysing a filtered
  subset has a different N, so
  [`assert_cohort()`](https://ehrlinger.github.io/hvtiRutilities/reference/assert_cohort.md)
  gates the wrong number — it passes while the job runs on a cohort
  nobody checked. Such a job must supply its own gate with counts from
  its own reference.
- **[`compare_parity()`](https://ehrlinger.github.io/hvtiRutilities/reference/compare_parity.md)’s
  `digits` is DECIMAL PLACES.** SAS commonly prints *significant
  figures*, so a flat `digits = 7` asserts a tolerance up to two orders
  of magnitude too tight for a value below 1 and reports agreeing
  references as a disagreement. Derive it per value:
  `sig - 1 - floor(log10(abs(x)))`.
- **A [`merge()`](https://rdrr.io/r/base/merge.html)-based parity join
  must assert it is COMPLETE**, not merely non-empty. A partial join
  silently shrinks the comparison while every surviving row still passes
  — the failure a parity harness is least able to notice.

## Gotchas

- **`object_usage_linter` resolves cross-file references against the
  INSTALLED package.** A function calling another function added in the
  same uncommitted change lints as “no visible global function
  definition” until the package is installed. That warning is an
  artifact, not a defect; `R CMD check` does its own codetools pass and
  is the real test.
- **`utils::` is used in several files while `utils` is not in
  `Imports`.** This is tolerated because `utils` is base-priority and
  attached by default. Do not “fix” it as drive-by work, and do not take
  it as licence to call an undeclared non-base package.
- **[`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)
  fails open**: it returns `OK` for entries it never checked when
  `n_rows` is absent. Awkward next to the word “compliance”; know it
  before relying on a green result.
- `VignetteBuilder` is **quarto**, not `knitr`. Vignettes are `.qmd`.

## Change discipline

1.  **Think before coding.** Do not assume, ask. If the request is
    ambiguous or a name, path or signature is uncertain, surface the
    confusion rather than running with a guess. One good clarifying
    question beats a confident wrong edit.
2.  **Simplicity first.** Write the minimum code that solves the stated
    problem. No speculative abstractions, no “while I am here”
    generalizing. Prefer the plain readable form a future reader can
    follow over the clever one.
3.  **Surgical changes.** Touch only what the task requires. Do not
    refactor, reformat or re-style adjacent code, and do not reorganize
    imports or rename things that were not asked for. If you spot
    something worth changing nearby, raise it separately rather than
    folding it in.
4.  **Goal-driven execution.** State what done looks like before
    starting, and use tests as the success criterion. If no test covers
    the change, add or propose one rather than declaring success from
    inspection.

## Git and versioning

- **Never push to `main`.** Branch, then open a PR and let the
  maintainer merge. A push rejected with “Changes must be made through a
  pull request” means branch — never force-push around it.
- **`main` is protected by a GitHub ruleset, and nothing in this repo
  records that.** A clone shows no trace of it, so it is stated here.
  The ruleset is named `protect main`, is identical across all twelve
  hvtiverse repositories, and enforces four rules on the default branch:
  no deletion, no force-push, pull-request-only, and an **automatic
  Copilot code review** on every PR. The rejection above comes from the
  server, not a local hook. ⚠️ It currently requires **zero approvals**.
  `require_code_owner_review` is set but inert because no repository in
  the family has a `CODEOWNERS` file, so a PR can merge unreviewed.
  Adding `CODEOWNERS` makes that flag live and changes who can merge
  what.
- Versions are **straight three digits** (`1.0.11`). Never a `.9000`
  suffix or a fourth digit.
- **Patch-digit bumps only**, as fixes land. The minor and major digits
  are the maintainer’s decision, taken when a feature set is
  consolidated into a release. Do not roll them.
- Bump `DESCRIPTION` and add the matching `NEWS.md` entry in the same
  commit.

## Prose

Documentation prose — vignettes, README, roxygen `@description` and
`@details`, release copy — follows the house voice composed into
`.house-style-tools/`. Apply it to any documentation text here.
