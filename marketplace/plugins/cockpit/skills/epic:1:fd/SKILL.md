---
name: epic:1:fd
description: Write FD (functional design) output for a cockpit epic - Flow Diagram (BPMN 2.0), Edge Cases, and Macro Estimate. Use when an epic enters FD by AI.
---

# FD

Write the functional design output for an epic on the cockpit board. FD captures _what the user does and sees_ - business logic, user flows, edge cases - never _how the system implements it_ (that's TD).

FD is the epic-level equivalent of BR: it answers the same "what and why" question but at a higher altitude, covering the full scope of an epic rather than a single ticket.

The epic is a local entity, `EPIC-n`; `<epic-id>` below is its id. Read its open comments with `"$HOME/.cockpit/scripts/board-card" comments <epic-id>` before drafting, following `~/.claude-shared/templates/page-comments.md`.

Read `~/.claude-shared/templates/cockpit-operating-contract.md` first.

## Prerequisites

Before writing FD, verify all three. Block and name any that fail.

1. **Epic scope.** The id must start with `EPIC-`, not a ticket's prefix. If invoked on a ticket, say FD only works on epics and stop.
2. **Problem and goal.** The epic body must contain a problem statement and a goal. If the body is blank or missing either, list what's needed and stop.
3. **Single user.** The epic must focus on one user type interacting with the system. If the body names two or more distinct user types (e.g. admin + end user, operator + customer), block and recommend splitting the epic by user before proceeding. One user per epic keeps the flow diagram focused enough to catch every edge case.

## Output

FD writes exactly three sections on the epic:

```
## Flow Diagram
## Edge Cases
## Macro Estimate
```

No `## Tech Steps`, `## Architecture`, `## Risks`, or any other heading. Those belong in TD.

### Flow Diagram

A BPMN 2.0 process diagram showing the user's journey through the epic's functionality. The diagram must show:

- **Happy path** from start event to end event
- **Alternative paths** (gateways) for each decision point
- **Error paths** for each thing that can go wrong
- **Lanes** separating the user from the system (and any third parties)

Write the output in two parts:

1. **Visual diagram** - use the `generate-web-diagram` skill to produce an HTML flow diagram of the BPMN process. Copy it onto the board with `"$HOME/.cockpit/scripts/board-card" attach <epic-id> <file>`, which prints the path to link it by, and put that link at the top of the `## Flow Diagram` section so reviewers see it immediately.

2. **BPMN 2.0 XML** - write standard BPMN 2.0 in an `xml` code block under a `### BPMN 2.0 XML (paste into bpmn.io to edit)` subsection below the visual.

   Three things are this workspace's choice rather than the standard's:

   - Two participants, `User` and `System`, each with its own process, neither executable.
   - Every gateway exit carries its condition as its label.
   - When the diagram-interchange coordinates are awkward, leave that section out entirely and let bpmn.io lay the diagram out on import. Say so in the subsection heading: `BPMN 2.0 XML (paste into bpmn.io to edit - auto-layout will apply)`.

### Edge Cases

A bulleted list of every edge case identified during the flow analysis. Each item names the edge case and its impact:

```
## Edge Cases
- **Empty input** - user submits the form with no data filled in; system must
  show field-level validation errors, not a generic failure
- **Concurrent edit** - two users edit the same record simultaneously; last
  write wins, but the overwritten user must see a conflict notification
```

#### Edge case identification methodology

Work through the flow diagram with three test design techniques, then sweep the dependencies:

1. **Boundary value analysis** - empty/null inputs, maximum values, minimum values, exactly-at-limit values, concurrent operations, timeout/slow responses.
2. **Equivalence partitioning** - every gateway branch, the indeterminate condition, and the external data a gateway reads being unavailable.
3. **State transition testing** - before the first action, never reaching the end, reaching it twice, back button, refresh, close tab mid-flow, switch device, duplicate submission, browser autofill interference.
4. **External dependencies** - third-party API down, payment provider rejects, email delivery fails, file upload exceeds size limit.

### Macro Estimate

A T-shirt size estimate of the epic's overall scope:

```
## Macro Estimate
**S** (1-3 days) - single flow with few decision points, minimal integration
```

| Size  | Duration   | Characteristics                                                             |
| ----- | ---------- | --------------------------------------------------------------------------- |
| **S** | 1-3 days   | Single user flow, few gateways, no external integrations                    |
| **M** | 1-2 weeks  | Multiple flows or decision points, some integrations                        |
| **L** | 1-3 months | Complex flows, many gateways, multiple integrations, significant edge cases |

Base the estimate on the flow diagram complexity: count the gateways, tasks, and lanes. More boxes and arrows = more complexity. This is a macro estimate for epic-level planning, not a Fibonacci ticket estimate.

## Workflow

1. **Read the epic** - `"$HOME/.cockpit/scripts/board-card" show <epic-id> --json` gives its status and content; confirm it's an epic.
2. **Check prerequisites** - verify problem/goal present and single user scope.
3. **Identify user flows** - from the problem and goal, map out the user's journey: what they do, what they see, what can go wrong.
4. **Generate BPMN 2.0 XML** - model the flows as a BPMN process with lanes, gateways, and events.
5. **Generate visual diagram** - invoke `generate-web-diagram` to produce an HTML flow diagram, then attach it to the epic.
6. **Identify edge cases** - walk the flow diagram using the methodology above.
7. **Estimate macro size** - count diagram elements, assess integration complexity, assign T-shirt size.
8. **Write to the epic** - write `## Flow Diagram`, `## Edge Cases`, and `## Macro Estimate`, each with `"$HOME/.cockpit/scripts/board-card" section <epic-id> "<heading>"` and its content on stdin. A section that already exists is replaced in place, so nothing is duplicated.
9. **Auto-advance epic status** - after all self-checks pass, if the epic's `Status` (from the step 1 read) is `Ready for FD by AI` or `In FD by AI`, advance it with `"$HOME/.cockpit/scripts/board-card" walk <epic-id> "Ready for FD"`. If the status is anything else, skip.

## Self-check

After writing FD content to the epic, verify:

1. **Sections** - only the three allowed sections exist as new `##` headings added by FD: Flow Diagram, Edge Cases, Macro Estimate. No ad-hoc headings.
2. **Visual present** - a rendered diagram is attached to the epic and linked from `## Flow Diagram` (not just the XML).
3. **BPMN XML** - valid XML inside the code block, with at least one startEvent, one endEvent, tasks, and gateways.
4. **Edge case coverage** - every gateway in the flow diagram has at least one corresponding edge case. Boundary conditions are addressed.
5. **Macro estimate** - present with a T-shirt size and one-line rationale.
6. **No implementation details** - scan for API names, file paths, function names, database schemas, or framework references. These belong in TD, not FD.

If any check fails, fix the content before moving on.
