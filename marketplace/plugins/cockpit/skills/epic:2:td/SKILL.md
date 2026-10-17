---
name: epic:2:td
description: Write TD (technical design) output for a cockpit epic - Strategy Options, Solution Diagram, Uncertainties, and an Epic Estimate summed from a high-level estimate on each ticket. Use when an epic enters TD.
---

# TD

Write the technical design output for an epic on the cockpit board. TD captures _what the technical strategy is_ - architecture decisions, evaluated options, resolved uncertainties - never _how to implement it_ at the ticket level (that's TR) or _what the user does_ (that's FD).

TD is the epic-level counterpart to TR: it answers "what is the right technical approach for this epic?" by evaluating multiple strategies, producing solution diagrams, and resolving technical uncertainties before tickets are broken down.

This skill maps to the Epic Tech Strategy standard.

The epic is a local entity, `EPIC-n`, and `<epic-id>` below is its id. Before drafting, read its open comments with `"$HOME/.cockpit/scripts/board-card" comments <epic-id>`, following `~/.claude-shared/templates/page-comments.md`.

Read `~/.claude-shared/templates/cockpit-operating-contract.md` first.

## Prerequisites

Before writing TD, verify all three. Block and name any that fail.

1. **Epic scope.** TD runs on an `EPIC-` id, never a ticket's. If invoked on a ticket, say TD only works on epics and stop.
2. **FD content.** The epic body must contain FD output: `## Flow Diagram` and `## Edge Cases`. If either is missing, list what FD content is needed and stop. FD defines the user flows that TD must support technically.
3. **Problem and goal.** The epic body must contain a problem statement and a goal. If the body is missing either, list what's needed and stop.

## Output

TD writes exactly four sections on the epic, after the FD sections:

```
## Strategy Options
## Solution Diagram
## Uncertainties
## Epic Estimate
```

No `## Tech Steps`, `## Implementation Plan`, `## Tickets`, or any other heading. Those belong in TR (ticket-level) or breakdown.

### Strategy Options

At least two technical strategies evaluated against quality metrics. Each strategy is a `###` subsection with a consistent structure:

```
## Strategy Options

**Recommended: Option A - [name]**
[One-line rationale for the recommendation]

### Option A - [name]

**Description:** What this strategy achieves (the technical outcome, not implementation steps)

**Evaluation:**

| Metric          | Assessment                                         |
| --------------- | -------------------------------------------------- |
| Safe Software   | [How this strategy addresses user safety]          |
| Quality         | [How this strategy supports software quality]      |
| Minimal Costs   | [Cost implications - scope, time, infrastructure]  |
| Maintainability | [Long-term maintenance burden]                     |

**Trade-offs:** [Key trade-offs vs other options]

### Option B - [name]

[Same structure as above]
```

#### Quality metrics

Evaluate each strategy against the metrics from the Epic Tech Strategy standard:

| Metric          | What to assess                                                 |
| --------------- | -------------------------------------------------------------- |
| Safe Software   | User safety, edge cases, data integrity, failure modes         |
| Quality         | Testability, reliability, correctness, separation of concerns  |
| Minimal Costs   | Scope of change, time to deliver, infrastructure/runtime costs |
| Maintainability | Complexity, coupling, future extensibility, team familiarity   |

#### Strategy evaluation rules

1. At least two strategies. If only one viable approach exists, the second option is "do nothing / accept the limitation" with its trade-offs.
2. Each strategy shows the _what_ (technical outcome), not the _how_ (implementation steps). "Use a message queue for async processing" is a strategy. "Install RabbitMQ, create an exchange, bind queues" is implementation.
3. The recommendation names the winning option and gives a one-line rationale.
4. When an ADR already exists for this decision, reference it. When the decision warrants a new ADR (significant, hard to reverse, or cross-cutting), note that an ADR should be authored separately via `/cockpit:adr`.

### Solution Diagram

A visual diagram showing the technical outcome of the recommended strategy. The diagram type depends on what the epic changes:

| Epic changes             | Diagram type          | Shows                                        |
| ------------------------ | --------------------- | -------------------------------------------- |
| System boundaries        | Architecture diagram  | Services, integrations, data flows           |
| Data flow through system | Sequence diagram      | Actors, messages, order                      |
| Data model               | ER diagram            | Entities, relationships, cardinality         |
| Multiple of the above    | Architecture + detail | High-level architecture + one detail diagram |

Write the output in two parts:

1. **Visual diagram** - use the `generate-web-diagram` skill to produce an HTML diagram. Copy it onto the board with `"$HOME/.cockpit/scripts/board-card" attach <epic-id> <file>` and link the path it prints at the top of the `## Solution Diagram` section.

2. **Diagram description** - a brief textual description below the visual, naming the key components and their relationships. This serves as alt-text and makes the diagram searchable.

#### Diagram rules

1. Show the state _after_ the recommended strategy is applied, not the current state. If the current state matters for context, include a "before" note in the description.
2. Show the _what_ (components, boundaries, data flows), not the _how_ (code structure, file layout, class hierarchy).
3. Keep architecture diagrams up to date - the Epic Tech Strategy standard requires this. Note in the description if this diagram supersedes a previous version.

### Uncertainties

A bulleted list of technical uncertainties identified during strategy analysis. Each item names the uncertainty and its resolution:

```
## Uncertainties
- **[Uncertainty name]** - [description of the unknown]. **Resolved:** [finding
  from investigation, with evidence]
- **[Uncertainty name]** - [description of the unknown]. **Blocker:** [why this
  cannot be resolved now, and what is needed to unblock]
```

#### Uncertainty identification methodology

Work through the strategy systematically:

1. **Feasibility** - can the recommended strategy actually be built? Are there API limitations, platform constraints, or missing capabilities?
2. **Integration points** - where does the strategy touch external systems? What are the contracts, rate limits, failure modes?
3. **Scale** - does the strategy hold at the expected load? Are there bottlenecks, resource limits, or degradation points?
4. **Data** - are there migration concerns, consistency requirements, or schema constraints?
5. **Security** - does the strategy introduce new attack surfaces, permission models, or data exposure?

#### Resolution rules

1. Every uncertainty must have a status: either **Resolved** with a finding, or **Blocker** with what's needed to unblock.
2. Investigate before flagging as a blocker. Read docs, check APIs, test assumptions. Only flag as a blocker when the answer genuinely cannot be determined without external input.
3. When an uncertainty is a blocker, name who or what can unblock it.

### Epic Estimate

TD gives every ticket on the epic a high-level estimate, and the epic estimate is their sum. The epic carries no estimate of its own: the board works the same sum out from its open tickets wherever it shows the epic.

1. **List the tickets** - `"$HOME/.cockpit/scripts/board-card" list --epic <epic-id> --json`. When the recommended strategy needs work no ticket covers yet, raise it with `"$HOME/.cockpit/scripts/board-card" create --name "<name>" --epic <epic-id>`.
2. **Estimate each one** - every ticket that is not `Done`, not `Deprioritised` and not a timebox gets `"$HOME/.cockpit/scripts/board-card" set <ticket-id> estimate <points>`, a Fibonacci number on the scale in `~/.claude-shared/templates/cockpit-estimating.md`. A timebox takes none. TR's `complexity` replaces the estimate on the plan once it is set, so the estimate is a high-level figure and never a guess at the Tech Steps.
3. **State the sum** - write the section from the figures just set, never a number of its own:

```
## Epic Estimate
**21 points** - the sum of the TD estimates on 6 tickets: COC-12 (8), COC-13 (5), COC-14 (3), COC-15 (2), COC-16 (2), COC-17 (1).
Similar in scope to [delivered epic], which came to [its sum] points.
```

When other epics on the board are done, compare the sum to one of theirs; `"$HOME/.cockpit/scripts/board-card" list --kind epic --status "Epic Done"` lists them. A ticket raised later in BR or TR carries no estimate unless someone sets one, and the plan counts it as unsized until then.

## Workflow

1. **Read the epic** - `"$HOME/.cockpit/scripts/board-card" show <epic-id> --json` gives its status and content; confirm it is an epic.
2. **Check prerequisites** - verify FD content present and problem/goal present.
3. **Understand the system** - read the FD flow diagram and edge cases. If the epic references a codebase, read the relevant architecture, existing patterns, and constraints.
4. **Identify strategies** - from the FD flows and the current system, identify at least two technical approaches to deliver the epic's outcome. Consider the trade-offs against the quality metrics.
5. **Evaluate and recommend** - evaluate each strategy against the quality metrics. Recommend the strongest option with a rationale.
6. **Generate the solution diagram** - invoke `generate-web-diagram` to produce a visual of the recommended strategy's architecture/data flow/ER, and attach it to the epic.
7. **Identify and resolve uncertainties** - work through the uncertainty methodology. Investigate each unknown; resolve what you can, flag what you can't.
8. **Estimate** - give each open ticket a high-level estimate through `board-card set <ticket-id> estimate`, raising any ticket the strategy needs, and state the epic estimate as their sum.
9. **Write to the epic** - write `## Strategy Options`, `## Solution Diagram`, `## Uncertainties`, and `## Epic Estimate` with `"$HOME/.cockpit/scripts/board-card" section <epic-id> "<heading>" --after "<previous heading>"`, the first after `Macro Estimate` and each next after the one before it. Each one already on the epic is rewritten where it stands rather than added twice.
10. **Auto-advance epic status** - after all self-checks pass, if the epic's `Status` (from the step 1 read) is `Ready for TD by AI` or `In TD by AI`, advance it with `"$HOME/.cockpit/scripts/board-card" walk <epic-id> "Ready for TD"`. If the status is anything else, skip.

## Self-check

After writing TD content to the epic, verify:

1. **Sections** - only the four allowed sections exist as new `##` headings added by TD: Strategy Options, Solution Diagram, Uncertainties, Epic Estimate. No ad-hoc headings.
2. **Strategy count** - at least two strategies are presented with evaluations.
3. **Quality metrics** - each strategy is evaluated against all four metrics (Safe Software, Quality, Minimal Costs, Maintainability).
4. **Recommendation** - a recommended option is named with a rationale.
5. **Visual present** - a rendered diagram is attached to the epic and linked from `## Solution Diagram` (not just a text description).
6. **Diagram type** - the diagram type matches what the epic changes (architecture for system boundaries, sequence for data flow, ER for data model).
7. **Uncertainties addressed** - every uncertainty has a status (Resolved or Blocker). No uncertainty is left without a status.
8. **Estimate present** - every open ticket that is not a timebox has an estimate on the board, and `## Epic Estimate` states their sum with no figure of its own.
9. **No implementation details** - scan for file paths, function names, class names, code patterns, specific library APIs, or database schemas. These belong in TR, not TD. The strategy shows _what_ the system will look like, not _how_ to build it.
10. **FD untouched** - `## Flow Diagram`, `## Edge Cases`, and `## Macro Estimate` are identical to before TD ran.

If any check fails, fix the content before moving on.
