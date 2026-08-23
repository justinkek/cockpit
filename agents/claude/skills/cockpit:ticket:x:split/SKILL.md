---
name: cockpit:ticket:x:split
description: Split a ticket into sub-tickets - keep the original as a validation-only parent, create one sub-ticket per part, move the content across, and link both ways. Use when a ticket carries more than one scenario at BR, or when a TR estimate exceeds daily speed.
---

# split

The original ticket is never closed, and never becomes one of the parts. It stays as the **parent**: it keeps the validation steps that assert the whole outcome, and gives up everything that describes how to build it.

That asymmetry is the point. The parent is what Validation checks at the end; the sub-tickets are what Dev and CR work on. Collapsing the two loses the whole-outcome assertion.

Read `~/.claude-shared/templates/cockpit-operating-contract.md` first.

Read `~/.claude-shared/templates/cockpit-estimating.md` before deciding whether the ticket splits.

Read `~/.claude-shared/templates/cockpit-cross-board.md` when the ticket being split has one on another board.

## Board constants

- Board ids - read with `"$HOME/.claude-shared/cockpit-board-id" get <key>`, following `~/.claude-shared/templates/board-ids.md`. This skill needs `tickets-data-source`.

## Two modes

The parent convention below is the same either way. What moves out differs, and so does what the parent keeps.

|                     | Scope split (BR)                                        | Effort split (TR)                      |
| ------------------- | ------------------------------------------------------- | -------------------------------------- |
| Trigger             | the ticket carries more than one scenario               | summed Complexity exceeds 5            |
| What moves out      | each extra scenario, as a sub-ticket's Validation Steps | each Tech Steps layer, with its points |
| Parent keeps        | the golden path                                         | the whole-outcome validation steps     |
| Parent's Complexity | none yet - do not set one                               | `0`                                    |

At BR there are no Tech Steps to move and no estimate to zero out, so steps 4 and 5 only touch validation steps. Everything else runs the same.

## Workflow

### 1. Name the boundaries

One sub-ticket per part. At TR, split along the Tech Steps layers - they were drawn along execution contexts, which is where the work actually divides. At BR, split along scenarios.

Propose the titles and what each absorbs, and get the user's confirmation before creating anything. A split is cheap to propose and expensive to undo: four date stamps land per sub-ticket and none can be repaired.

### 2. Create each sub-ticket

Invoke `/cockpit:ticket:0:new` per part, passing the parent's epic. Each stub enters at `Ready for BR by AI`.

**Cross-board sessions** carry the pattern through: `/cockpit:ticket:0:new` detects the session's source ticket and creates the source-board page first, so the sub-ticket stubs stay tracking-only like their parent.

### 3. Walk each sub-ticket up to the parent's column

Advance each new sub-ticket to the parent's current column via `/cockpit:ticket:x:status`, one column at a time. Never set the status directly: a skipped column leaves a null date and permanently inverted `Duration:` formulas, and cannot be repaired afterward.

The stamps this produces are compressed - they describe the split, not the refinement the content came from. That is honest and expected; do not backdate them.

### 4. Move the content

Each sub-ticket gets:

- its own `## Validation Steps`, asserting only its part;
- the `## Tech Steps` layers it absorbed, copied whole (TR mode only);
- a `## Context` toggle naming the parent and what this part covers.

Set each sub-ticket's `Complexity` to the sum of the layers it absorbed (TR mode only). If any sub-ticket still exceeds 5, split it again before moving on.

### 5. Strip the parent

- Delete the parent's `## Tech Steps` section outright. Not emptied, not left as a pointer - removed. Tech steps live on the sub-tickets.
- Set the parent's `Complexity` to `0` (TR mode only). Not blank and not the sum: blank reads as un-estimated, and the sum would double-count against every sprint total.

The parent keeps `## Validation Steps`, `## Context` and `## Details` unchanged.

### 6. Link both ways

- Set the parent's `Dependent on` relation to the new pages; each of them picks up the parent under `Dependency for`. This is the link that matters: it is queryable, shows on the board, and is what the dev refusal, the In TR gate exemption, and the parent roll-up all read.
- Add a `## Sub-Tickets` section to the parent where `## Tech Steps` was, holding one line pointing at that property. The section is a signpost for a reader on the page; it is not the source of truth and must not restate the points or the absorbed sections - those drift.

### 7. Report

Report the parent, each sub-ticket with what it absorbed, and where the points went.

## After the split

- **Dev never happens on the parent.** `/cockpit:ticket:3:dev` refuses when the registered ticket has `Dependent on`. Start a new session on the sub-ticket you want to build - one ticket per session, so cost attributes to the part actually being built.
- **The parent follows its sub-tickets.** `/cockpit:ticket:x:status` walks the parent to a column once every sub-ticket has reached it (last-in, never first-in), so the parent collects its own date stamps instead of sitting stale.
