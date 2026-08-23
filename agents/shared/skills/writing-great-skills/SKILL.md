---
name: writing-great-skills
description: Guidelines for writing predictable, well-structured AI agent skills. Use when creating a new skill, revising an existing one, or diagnosing why a skill underperforms.
---

# writing-great-skills

Actionable guidelines for writing skills that produce consistent process - not identical output each run, but reliable behavior. Read this before writing or revising any skill.

## 1. Choose the invocation mode

Every skill is either model-invoked or user-invoked. Pick one; never leave it ambiguous.

| Mode          | Mechanism                           | Tradeoff                                         |
| ------------- | ----------------------------------- | ------------------------------------------------ |
| Model-invoked | Description always visible to model | Autonomous triggering, but consumes token budget |
| User-invoked  | No description overhead             | Zero token cost at rest, but human must remember |

**Default to user-invoked** unless the skill must fire without human intervention. As skills accumulate, cognitive load (remembering which skill to invoke) becomes the binding constraint - address it with a router skill that catalogs available skills and their triggers, not by making everything model-invoked.

Write the `description` field in frontmatter accordingly:

- Model-invoked: describe the trigger condition so the model can match it autonomously (e.g. "Use when the user asks to create a chart or visualization").
- User-invoked: describe the purpose so a human scanning a skill list knows when to reach for it.

## 2. Use leading words

A leading word is a single, familiar concept from the model's training data that anchors both execution and discovery with minimal token overhead. Examples: "tight", "red", "tracer bullet".

- Pick one leading word per skill that captures its core intent.
- Place it early in the skill body so it primes the model's behavior from the first line.
- Reuse the same word in the `description` field so the skill is discoverable by keyword.

A good leading word is concrete and action-oriented. Avoid abstract labels ("optimization", "enhancement") that could apply to anything.

## 3. Organize by information hierarchy

Structure skill content in three tiers, each progressively farther from the model's immediate attention:

1. **In-skill steps** - the instructions the model executes directly. These are the core of the skill and should be self-contained enough to follow without external reads.
2. **Internal references** - files in the repo or dotfiles that the skill reads at invocation time (e.g. `Read ~/.agents-shared/includes/foo.md`). Use when content is shared across skills or changes independently.
3. **External materials** - URLs or context pointers the model fetches only when needed. Place behind a conditional ("if X is unclear, read Y") to avoid unnecessary fetches.

Keep the top tier readable. If a skill's in-skill steps exceed ~80 lines, move stable reference content to tier 2.

## 4. Prune ruthlessly

A skill's output is what it writes: the ticket page, the properties it sets, the comments it posts, the files it changes, the commands it runs, and what it reports. A line changes nothing when no run of the skill produces different output depending on whether the agent read it.

Take one sentence at a time. The first of these that answers yes cuts it:

1. **Single source of truth** - is this information stated elsewhere (another skill, CLAUDE.md, a template)? If yes, reference it instead of duplicating.
2. **Another line already requires it** - the behaviour is entailed by another sentence in the same file, or by a template the file already tells the agent to read.
3. **It states a reason, a benefit or a mechanism the agent never acts on** - "so a reviewer can edit it in place", "the hook intercepts this command and writes the marker".
4. **It is background the agent cannot branch on** - a fact about another component, true or false, that reaches no decision in this skill.

The counter-test keeps a line: name a concrete run where the agent behaves differently with and without it. If you can name one, it stays.

Four kinds look cuttable and are not:

- A **counter-case** narrowing an existing rule.
- A **consequence** that gates a decision.
- A **worked example**, which sets the shape of the output.
- A **negative instruction** where the thing forbidden is the plausible default.

Grep the test suite for the sentence before cutting it. A test asserting a line is present is a caller of that line.

Prune after every revision, not just at creation. Skills accumulate sediment (outdated instructions that were once relevant) and sprawl (edge cases added one at a time that bloat the happy path).

## 5. Diagnose failure modes

When a skill underperforms, classify the failure before fixing:

| Failure mode         | Symptom                                         | Fix                                                |
| -------------------- | ----------------------------------------------- | -------------------------------------------------- |
| Premature completion | Model stops before all steps are done           | Add explicit step count or completion checklist    |
| Duplication          | Same logic in multiple skills, drifting apart   | Extract to a shared reference (tier 2)             |
| Sediment             | Old instructions conflict with current behavior | Prune the outdated content                         |
| Sprawl               | Skill grew too long, model skips or misweights  | Split into focused skills or move detail to tier 2 |
| No-op                | Skill runs but produces no observable effect    | Check that steps produce output, not just read     |

Fix one failure mode at a time. Verify the fix with a test invocation before moving on.
