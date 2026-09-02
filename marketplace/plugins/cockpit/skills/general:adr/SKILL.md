---
name: general:adr
description: Author Architecture Decision Records (ADRs) to a consistent house style, and keep each repo's ADR template/instructions in sync with the canonical copy bundled in this skill. Use when the user wants to write an ADR, record a technical decision, scaffold ADR docs into a repo, or check a repo's ADR template against the canonical one.
---

# adr

Write ADRs the same way in every project, and keep each repo's `TEMPLATE.md` / `INSTRUCTIONS.md` aligned with one canonical source.

The canonical conventions live in this skill at `assets/INSTRUCTIONS.md` and `assets/TEMPLATE.md`. They are the source of truth **across** projects. Inside a project, the repo's committed copy is the authority (projects are free to override — see Re-sync).

## Usage

```
/adr                 # author an ADR (default), scaffolding docs first if the repo has none
/adr sync            # report drift between this repo's ADR docs and the canonical copy
```

## Locating a repo's ADR directory

1. If `.docs/architecture-decision-records/` exists, use it.
2. Else, if any directory contains `adr-*.md` or an `INSTRUCTIONS.md` + `TEMPLATE.md` pair, use that.
3. Else there is no ADR setup — default to `.docs/architecture-decision-records/` and scaffold (see below).

## Mode: Scaffold (repo has no ADR docs)

If the ADR directory has no `TEMPLATE.md` / `INSTRUCTIONS.md`, copy them verbatim from this skill's `assets/` into the directory, then tell the user they are ready to commit so teammates share the same conventions. Do this before authoring the first ADR in a fresh repo.

## Mode: Author (default)

1. Read the **repo's** `INSTRUCTIONS.md` and `TEMPLATE.md` — they are the authority for this project. Fall back to this skill's `assets/` only if the repo has none (and scaffold as above).
2. Draft the ADR to a new file named `adr-YYYY-MM-DD-<slug>.md` (today's date).
3. Follow the conventions strictly. The rules most often gotten wrong:
   - **One decision per ADR.** If a second decision keeps creeping in, stop and propose a separate ADR.
   - **Problem Statement is a single sentence** naming the decision needed, in plain language a non-technical reader could follow.
   - **Context is a separate section** providing background, constraints, and why this decision matters.
   - **Keep sections pure** — drivers are criteria only; options are described only (no verdicts, no evaluative language); verdicts live in Evaluation and Decision Outcome.
   - **One evaluation table, one legend.**
   - **Each option includes a code example** showing how it would be used.
   - **Keep it tight** — the evaluation table is the payload; prose only supports it. Context is one short paragraph; Decision Outcome is one sentence plus bullets, never prose paragraphs. Delete empty sections rather than padding.
   - **Write for the merged result, not the branch.** State the enabling fact, not the journey - a reader who only ever sees main has no trace of work that lived on the branch alone. Where a rejected option's code never reached main, link the pull request commit so it stays reachable.
   - **A cost every option carries is not a cost of the decision.** Before listing one, check whether the rejected options avoid it. If they do not, it belongs in Context or the Evaluation table.

### Self-check

Before showing the ADR, verify:

1. **Context** — one short paragraph, no sentence restating a Decision Driver.
2. **Decision Outcome** — opens with one sentence naming the option chosen, then bullets. No prose paragraph.
3. **Costs** — every cost listed is one a rejected option would have avoided.
4. **Merged-result read** — no sentence depends on the branch's own history; each either states the enabling fact instead, or links the commit.
5. **Sections pure** — drivers are criteria only, options described only, verdicts only in Evaluation and Decision Outcome.

If any check fails, fix the ADR before showing it.

## Mode: Re-sync (`/adr sync`) — report only

Projects may override anything; this mode never writes. It reports drift in both directions so the user can decide, by hand, what to do:

1. Diff the repo's `TEMPLATE.md` against this skill's `assets/TEMPLATE.md`; do the same for `INSTRUCTIONS.md`.
2. Present the differences grouped by direction:
   - **Canonical → repo** — improvements in the skill the repo lacks (candidates to pull down).
   - **Repo → canonical** — changes in the repo not in the skill; for each, note whether it looks like an intentional project override (keep divergent) or a general improvement worth promoting upstream into `assets/`.
3. Recommend a direction per difference, but **make no edits** — the user applies changes themselves.

## Scope

- Authoring, scaffolding, and drift-reporting for ADRs. It does not commit, and in `sync` mode it does not edit files.
- The canonical `assets/` copy is edited directly in this skill (in `~/.claude-shared`), so improvements sync to every project via the normal shared-config sync.
