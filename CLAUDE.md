@AGENTS.md

# Claude Code specifics

[`AGENTS.md`](AGENTS.md), imported above, is the operational contract and applies in full. It is written
to be tool neutral so that Codex and other agents read the same rules. Only the Claude Code
affordances live here.

## Before you touch code

`AGENTS.md` says to orient on the public API surface before editing. In Claude Code the way
to do that is the codemap: it lives in the Obsidian vault under `Claude/repomaps/` and is
read via the `read-codemap` skill (`/codemap hvtiRutilities`). If the codemap looks stale,
say so and offer to refresh it (`/regenerate-codemap`) rather than working from a guess.

If the vault is not available, say so rather than staying quiet about it, then orient from
the repo itself — `NAMESPACE` exports, `R/`, the README and the vignettes — before editing.

## Prose

`AGENTS.md` points at the composed house style for the house voice. In Claude Code, apply
the `ehrlinger-writing` skill instead: it carries the same voice, reader persona and project
context, kept in sync from the vault sources the composed file is built from.
