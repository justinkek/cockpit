---
name: cockpit:epic:2:td
description: Write TD (technical design) output for a cockpit epic - Strategy Options, Solution Diagram, Uncertainties, and Epic Estimate. Use when an epic enters TD.
---

# TD

Write the technical design output for an epic on the cockpit board. TD captures _what the technical strategy is_ - architecture decisions, evaluated options, resolved uncertainties - never _how to implement it_ at the ticket level (that's TR) or _what the user does_ (that's FD).

TD is the epic-level counterpart to TR: it answers "what is the right technical approach for this epic?" by evaluating multiple strategies, producing solution diagrams, and resolving technical uncertainties before tickets are broken down.

This skill maps to the Epic Tech Strategy standard.

Read the epic's open comments before drafting, following `~/.claude-shared/templates/page-comments.md`.

Read `~/.claude-shared/templates/cockpit-operating-contract.md` first.

Read `~/.claude-shared/templates/notion-writing.md` before writing to the page.

## Board constants

- Board ids - read with `"$HOME/.cockpit/scripts/cockpit-board-id" get <key>`, following `~/.claude-shared/templates/board-ids.md`. This skill needs `epics-data-source`.

## Prerequisites

Before writing TD, verify all three. Block and name any that fail.

1. **Epic scope.** The page must be an epic (parent-data-source matches the Epics data source above), not a ticket. If invoked on a ticket, say TD only works on epics and stop.
2. **FD content.** The epic body must contain FD output: `## Flow Diagram` and `## Edge Cases`. If either is missing, list what FD content is needed and stop. FD defines the user flows that TD must support technically.
3. **Problem and goal.** The epic body must contain a problem statement and a goal. If the body is missing either, list what's needed and stop.

## Output

TD writes exactly four sections on the epic page, after the FD sections:

```
## Strategy Options
## Solution Diagram
## Uncertainties
## Epic Estimate
```

No `## Tech Steps`, `## Implementation Plan`, `## Tickets`, or any other heading. Those belong in TR (ticket-level) or breakdown.

### Strategy Options

At least two technical strategies evaluated against quality metrics. Each strategy is presented in a toggle with a consistent structure:

```
## Strategy Options
**Recommended: Option A - [name]**
[One-line rationale for the recommendation]

<details>
<summary>Option A - [name]</summary>
	**Description:** What this strategy achieves (the technical outcome, not
	implementation steps)

	**Evaluation:**
	<table>
	<colgroup>
	<col width="200">
	<col width="500">
	</colgroup>
	<tr><td>Safe Software</td><td>[How this strategy addresses user safety]</td></tr>
	<tr><td>Quality</td><td>[How this strategy supports software quality]</td></tr>
	<tr><td>Minimal Costs</td><td>[Cost implications - scope, time, infrastructure]</td></tr>
	<tr><td>Maintainability</td><td>[Long-term maintenance burden]</td></tr>
	</table>

	**Trade-offs:** [Key trade-offs vs other options]
</details>

<details>
<summary>Option B - [name]</summary>
	[Same structure as above]
</details>
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

1. **Visual diagram** - use the `generate-web-diagram` skill to produce an HTML diagram. Upload the resulting file to the epic page via `notion-create-attachment`. Place the image at the top of the `## Solution Diagram` section.

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

A relative estimate of the epic's technical scope compared to other epics:

```
## Epic Estimate
**M** (1-2 weeks) - similar scope to [reference epic name]; [number] integration
points, [number] new components, moderate uncertainty
```

| Size  | Duration   | Characteristics                                                  |
| ----- | ---------- | ---------------------------------------------------------------- |
| **S** | 1-3 days   | Single component change, no new integrations, low uncertainty    |
| **M** | 1-2 weeks  | Multiple components, some integrations, moderate uncertainty     |
| **L** | 1-3 months | Cross-system changes, many integrations, significant uncertainty |

Base the estimate on:

1. **Strategy complexity** - how many components does the strategy touch?
2. **Integration points** - how many external systems or APIs?
3. **Uncertainty count** - how many blockers remain?
4. **Comparison** - how does this compare to completed epics on the board?

When other epics exist on the board with known durations, reference one as a comparison point. If no comparable epics exist, estimate on the characteristics alone.

## Workflow

1. **Read the epic** - fetch the page, confirm it's an epic (check parent-data-source against the Epics data source).
2. **Check prerequisites** - verify FD content present and problem/goal present.
3. **Understand the system** - read the FD flow diagram and edge cases. If the epic references a codebase, read the relevant architecture, existing patterns, and constraints.
4. **Identify strategies** - from the FD flows and the current system, identify at least two technical approaches to deliver the epic's outcome. Consider the trade-offs against the quality metrics.
5. **Evaluate and recommend** - evaluate each strategy against the quality metrics. Recommend the strongest option with a rationale.
6. **Generate the solution diagram** - invoke `generate-web-diagram` to produce a visual of the recommended strategy's architecture/data flow/ER. Upload to the epic page.
7. **Identify and resolve uncertainties** - work through the uncertainty methodology. Investigate each unknown; resolve what you can, flag what you can't.
8. **Estimate** - compare the epic's scope against other epics on the board. Assign a T-shirt size with rationale.
9. **Write to the epic page** - insert `## Strategy Options`, `## Solution Diagram`, `## Uncertainties`, and `## Epic Estimate` after the FD sections. If these sections already exist, update them (use `update_content` not `insert_content`) to avoid duplication.
10. **Auto-advance epic status** - after all self-checks pass, if the epic's `Status` (from the step 1 fetch) is `Ready for TD by AI`, advance it to `Ready for TD` via `notion-update-page` (`update_properties`). If the status is anything else, skip.

## Self-check

After writing TD content to the epic page, verify:

1. **Sections** - only the four allowed sections exist as new `##` headings added by TD: Strategy Options, Solution Diagram, Uncertainties, Epic Estimate. No ad-hoc headings.
2. **Strategy count** - at least two strategies are presented with evaluations.
3. **Quality metrics** - each strategy is evaluated against all four metrics (Safe Software, Quality, Minimal Costs, Maintainability).
4. **Recommendation** - a recommended option is named with a rationale.
5. **Visual present** - a rendered diagram is attached to the page (not just a text description).
6. **Diagram type** - the diagram type matches what the epic changes (architecture for system boundaries, sequence for data flow, ER for data model).
7. **Uncertainties addressed** - every uncertainty has a status (Resolved or Blocker). No uncertainty is left without a status.
8. **Estimate present** - T-shirt size with rationale and comparison point.
9. **No implementation details** - scan for file paths, function names, class names, code patterns, specific library APIs, or database schemas. These belong in TR, not TD. The strategy shows _what_ the system will look like, not _how_ to build it.
10. **FD untouched** - `## Flow Diagram`, `## Edge Cases`, and `## Macro Estimate` are identical to before TD ran.

If any check fails, fix the content before moving on.
