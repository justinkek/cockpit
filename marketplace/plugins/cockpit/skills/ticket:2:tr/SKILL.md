---
name: ticket:2:tr
description: Write TR (technical refinement) output for a cockpit ticket - Tech Steps and Complexity. Use when a ticket enters TR by AI.
---

# TR

Write the technical refinement output for the registered cockpit ticket. TR captures _how_ (implementation) - never _what/why_ (that's BR).

Read `~/.claude-shared/templates/ticket-page.md` before writing.

Read `~/.claude-shared/templates/cockpit-operating-contract.md` first.

Read `~/.claude-shared/templates/cockpit-estimating.md` before proposing Complexity.

Read `~/.claude-shared/templates/coding-conventions.md` before drafting the code a tech step shows.

Read `~/.claude-shared/templates/cockpit-cross-board.md` when the session has a source ticket.

Read `~/.claude-shared/templates/notion-writing.md` before writing to the page.

Read the ticket's open comments before drafting, following `~/.claude-shared/templates/page-comments.md`.

A decision the draft cannot settle is raised on the ticket, beside the line it concerns - never in a chat nobody is reading. Follow `~/.claude-shared/templates/raise-a-decision.md`.

## Prerequisite

The ticket must have BR content before TR can start:

- Feature: `## Validation Steps` present with at least one checklist item.
- Bug: `## Replication/Validation Steps` present with at least one checklist item.
- Timebox: timeboxes skip TR entirely (no tech steps). If invoked on a timebox, say so and stop.

If BR content is missing, block and name what's missing.

Then check the outcome is not already delivered, following `~/.claude-shared/templates/already-done-check.md`. A hit stops the draft.

## Output

TR writes into exactly two sections - no others:

```
## Tech Steps
## Details
```

Never add `## Risks`, `## Complexity`, `## Implementation Notes`, or any other heading. Complexity goes inside `## Details`; Risks are not written at all.

Never modify `## Validation Steps` - that is BR output.

### Tech Steps

Read `rules/tech-steps.md` from the tech-ref plugin before drafting - the pointer its session start hook prints carries the absolute path. It states the file tree, the sequence flow, the layer and concern tables, the nine format rules, the worked example, the five opening verbs and the layer-sum arithmetic.

One layer is this board's own, and is not in that table:

| Layer   | Who runs it                                          |
| ------- | ---------------------------------------------------- |
| `Board` | the Notion cockpit - schema, properties, automations |

It carries no concern level - the layer is already the division.

### Details

`## Details` holds Complexity. If the section already exists (e.g. from a prior bounce-back), append to it rather than replacing.

**Complexity** - Fibonacci estimate with rationale and reference comparison.

Output format - a toggle whose summary carries the arithmetic:

```
<details>
<summary>Complexity Breakdown: 3 = FE 2 + Testing 1</summary>
	**FE 2** - matches [reference ticket name]: [why]
	**Testing 1** - matches [reference ticket name]: [why]
</details>
```

Estimation procedure:

1. Read reference tickets by running `"$HOME/.cockpit/scripts/cockpit-cache-query" reference-tickets`. On a non-zero exit or an empty list, fetch from the `reference-tickets` id (see `~/.claude-shared/templates/board-ids.md`).
2. Compare each layer's scope (number of files, conceptual difficulty, blast radius) against references at each Fibonacci level - never the ticket as a whole.
3. Sum the layer points. The per-layer breakdown is the rationale; no independent whole-ticket figure is proposed.
4. A sum landing off the Fibonacci scale rounds up to the next value on it - 4 rounds to 5, 7 rounds to 8. Never down: rounding down hides a split.
5. If the query limit is hit, estimate without references and note that the reference comparison was skipped.
6. The proposed value is a suggestion; the human adjusts during the TR session.

### Split threshold

Propose splitting the ticket before finalizing tech steps when the summed Complexity crosses the threshold in `~/.claude-shared/templates/cockpit-estimating.md`. Name the split boundaries and suggest ticket titles, then invoke `/cockpit:ticket:x:split` to execute it - that skill owns the parent convention.

## Workflow

1. **Read the ticket** - read the BR section with `"$HOME/.cockpit/scripts/ticket-read" <ticket-url> --section "<heading>"`, and confirm it is present. Exit 7 is the block named under Prerequisite.
2. **Understand the codebase** - read the files and patterns relevant to the implementation. Grep callers of functions you plan to touch. When the steps introduce a shared procedure, grep the other skills for the concept too and make every call site its own step - a procedure wired into one caller and missed on another is the defect, not the missing caller.
3. **Draft tech steps** - write the nested checklist covering every scenario from `## Validation Steps` (features) or `## Replication/Validation Steps` (bugs).
4. **Estimate complexity** - price each layer against the reference database, then sum.
5. **Write the tree, then the sequence flow** - both are code blocks this step writes itself. The drafted steps are the input to both, so this runs before the write below, not after it. A change touching one call skips the sequence flow.
6. **Write to the ticket** - insert `## Tech Steps` and `## Details` in the correct positions to maintain canonical section order (BR section → Tech Steps → Context → Details):
   - **Tech Steps**: if a later section (`## Context` or `## Details`) already exists on the page, use `update_content` to insert `## Tech Steps` and its content before that section's heading. If no later section exists, use `insert_content` at position `end`.
   - **Details**: always insert at position `end` (it is the last section). If `## Details` already exists, append to it rather than creating a duplicate.
7. **Set the Complexity database property** - call `notion-update-page` (`update_properties`) with `{"Complexity": <numeric value>}` using the same Fibonacci number written to the page body.
8. **Self-check** - verify the output (see below).
9. **Advance** - invoke `/cockpit:ticket:x:status` targeting Ready for TR. This advances the ticket out of In TR by AI so the board reflects that TR drafting is complete and the card is ready for human review.

## Self-check

After writing TR content to the ticket page, verify:

1. **Sections** - only the allowed sections for the ticket type exist as top-level `##` headings: Validation Steps (feature) or Replication/Validation Steps (bug), Tech Steps, Context (optional), Details. No ad-hoc headings. Verify `## User Story` is absent.
2. **Section order** - `##` headings appear in canonical order: BR section → Tech Steps → Context → Details (per the ticket page template). If any section is out of order, fix it before proceeding.
3. **Tech steps format** - nested toggles organized by layer and concern. No flat lists, no empty layer toggles, no numbered sub-items. Every change carries its own toggle with one code block inside; a block stacking several changes, an item describing its change in prose, or more than five change toggles sitting flat under one path, fails this check. Every top-level layer summary ends with a bold point figure in round brackets, and no nested toggle carries one. Read every step and change summary on its own: it says what the change achieves. One naming the defect the step removes fails this check. The tree is the first thing under the heading and is a diff code block, every file it shows is a file an `In <path>` toggle names, and each is marked `+`, `-` or `!` then carries the sentence that toggle's step summary already states. The sequence flow below it is there only when the change spans more than one call, and every lane it draws is a file the tree already shows. Every thing the ticket does has its own tree under its own heading centred in a 120 character rule of `=`, one line per file, and every sentence in a tree starting at the same column. Every tree is in one `diff` block and each flow in its own `mermaid` block below, in the order the trees are in. Every summary opens on one of the five verbs, names the thing it acts on, and carries no `so` clause.
4. **Complexity** - inside `## Details`, not a standalone section. The figure equals the sum of the layer points.
5. **Coverage** - every scenario from the BR section (`## Validation Steps` or `## Replication/Validation Steps`) is addressed by at least one tech step.
6. **BR untouched** - the BR section is identical to before TR ran.

If any check fails, fix the content before moving on.
