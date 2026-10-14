---
name: ticket:2:tr
description: Write TR (technical refinement) output for a cockpit ticket - Tech Steps and Complexity. Use when a ticket enters TR by AI.
---

# TR

Write the technical refinement output for the registered cockpit ticket. TR captures _how_ (implementation) - never _what/why_ (that's BR). `<id>` below is the registered card's id, e.g. `FEAT-123`.

Read `~/.claude-shared/templates/ticket-page.md` before writing.

Read `~/.claude-shared/templates/cockpit-operating-contract.md` first.

Read `~/.claude-shared/templates/cockpit-estimating.md` before proposing Complexity.

Read `~/.claude-shared/templates/coding-conventions.md` before drafting the code a tech step shows.

Before drafting, read the card's open comments with `"$HOME/.cockpit/scripts/board-card" comments <id>`, following `~/.claude-shared/templates/page-comments.md`.

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

| Layer   | Who runs it                                                                         |
| ------- | ----------------------------------------------------------------------------------- |
| `Board` | the local cockpit board - `board-card`, its records and fields, the app in `board/` |

It carries no concern level - the layer is already the division.

### Details

`## Details` holds Complexity. If the section already exists (e.g. from a prior bounce-back), append to it rather than replacing.

**Complexity** - Fibonacci estimate with rationale and reference comparison.

Output format - a `###` subsection under the fixed heading `Complexity Breakdown`, the arithmetic on its first line and one line per layer below it:

```
### Complexity Breakdown

3 = FE 2 + Testing 1

- **FE 2** - matches [reference ticket name]: [why]
- **Testing 1** - matches [reference ticket name]: [why]
```

The figure stays out of the heading: a redraft that changes it writes to the same heading and replaces the subsection in place, rather than adding a second one beside the old.

Estimation procedure:

1. Read the reference tickets with `"$HOME/.cockpit/scripts/board-card" list --kind reference --json`. Each carries its `points`, `why`, `description`, `domain`, `stack` and the `card` it was taken from. An empty list means estimate without references and say the comparison was skipped.
2. Compare each layer's scope (number of files, conceptual difficulty, blast radius) against references at each Fibonacci level - never the ticket as a whole.
3. Sum the layer points. The per-layer breakdown is the rationale; no independent whole-ticket figure is proposed.
4. A sum landing off the Fibonacci scale rounds up to the next value on it - 4 rounds to 5, 7 rounds to 8. Never down: rounding down hides a split.
5. The proposed value is a suggestion; the human adjusts during the TR session.

### Split threshold

Propose splitting the ticket before finalizing tech steps when the summed Complexity crosses the threshold in `~/.claude-shared/templates/cockpit-estimating.md`. Name the split boundaries and suggest ticket titles, then invoke `/cockpit:ticket:x:split` to execute it - that skill owns the parent convention.

## Workflow

1. **Move the card into In TR by AI** - when its status is `Ready for TR by AI`, invoke `/cockpit:ticket:x:status` targeting `In TR by AI`, so the walk's Record model step writes `models.TR`. A card in any other column stays where it is.
2. **Read the ticket** - read the BR section with `"$HOME/.cockpit/scripts/board-card" show <id> --section "<heading>"`, and confirm it is present. Exit 7 is the block named under Prerequisite.
3. **Understand the codebase** - read the files and patterns relevant to the implementation. Grep callers of functions you plan to touch. When the steps introduce a shared procedure, grep the other skills for the concept too and make every call site its own step - a procedure wired into one caller and missed on another is the defect, not the missing caller.
4. **Draft tech steps** - write the nested toggles covering every scenario from `## Validation Steps` (features) or `## Replication/Validation Steps` (bugs).
5. **Estimate complexity** - price each layer against the reference database, then sum.
6. **Write the tree, then the sequence flow** - both are code blocks this step writes itself. The drafted steps are the input to both, so this runs before the write below, not after it. A change touching one call skips the sequence flow.
7. **Write to the ticket** - write `## Tech Steps` and `## Details` with `board-card section`, which keeps canonical section order (BR section → Tech Steps → Context → Details):

   - **Tech Steps**: placed straight after the BR section:

     ```sh
     "$HOME/.cockpit/scripts/board-card" section <id> "Tech Steps" --after "<BR heading>" <<'EOF'
     ...
     EOF
     ```

   - **Details**: the `Complexity Breakdown` subsection is written the way `~/.cockpit/skills/ticket:x:back-from-column/SKILL.md` says under "Writing under `## Details`", which leaves every other subsection there as it was. A breakdown an older draft wrote in another form - a `- Complexity Breakdown: <figure>` bullet with its indented lines, or a `### Complexity Breakdown: <figure>` heading - is not one that write replaces, so take it out straight after: read the section with `"$HOME/.cockpit/scripts/board-card" show <id> --section Details`, then write it back with `"$HOME/.cockpit/scripts/board-card" section <id> "Details"`, its `## Details` line left off, the older breakdown dropped and every other line as it was.

8. **Set the Complexity field** - `"$HOME/.cockpit/scripts/board-card" set <id> complexity <n>`, the same Fibonacci number written to the body.
9. **Self-check** - verify the output (see below).
10. **Advance** - invoke `/cockpit:ticket:x:status` targeting Ready for TR. This advances the ticket out of In TR by AI so the board reflects that TR drafting is complete and the card is ready for human review.

## Self-check

After writing TR content to the card, verify:

1. **Sections** - only the allowed sections for the ticket type exist as top-level `##` headings: Validation Steps (feature) or Replication/Validation Steps (bug), Tech Steps, Context (optional), Details. No ad-hoc headings. Verify `## User Story` is absent.
2. **Section order** - `##` headings appear in canonical order: BR section → Tech Steps → Context → Details (per the ticket page template). If any section is out of order, fix it before proceeding.
3. **Tech steps format** - nested toggles organized by layer and concern. No flat lists, no empty layer toggles, no numbered sub-items. Every change that can be shown as code carries its own toggle with one code block inside; a block stacking several changes, a showable change described in prose, or more than five change toggles sitting flat under one path, fails this check. A change that cannot be shown as code, such as a generated lockfile, is a plain bullet under the toggles and passes. Every top-level layer summary ends with a bold point figure in round brackets, and no nested toggle carries one. Read every step and change summary on its own: it says what the change achieves. One naming the defect the step removes fails this check. The tree is the first thing under the heading and is a diff code block, every file it shows is named by an `In <path>` toggle or by a bullet for a change that cannot be shown as code, and each is marked `+`, `-` or `!` then carries the sentence its step's summary already states. The sequence flow below it is there only when the change spans more than one call, and every lane named for a file the steps touch is a file the tree already shows - a file the flow only calls through, such as one the unshaded call either side of the shaded run reaches, has no line in the tree. Every thing the ticket does has its own tree under its own heading centred in a 120 character rule of `=`, one line per file, and every sentence in a tree starting at the same column. Every tree is in one `diff` block and each flow in its own `mermaid` block below, in the order the trees are in. Every summary opens on one of the five verbs, names the thing it acts on, and carries no `so` clause.
4. **Complexity** - inside `## Details`, not a standalone section, and `## Details` holds exactly one breakdown: one `### Complexity Breakdown`, with no `- Complexity Breakdown:` bullet or `### Complexity Breakdown: <figure>` heading left from an older draft. The figure on its first line equals the sum of the layer points.
5. **Coverage** - every scenario from the BR section (`## Validation Steps` or `## Replication/Validation Steps`) is addressed by at least one tech step.
6. **BR untouched** - the BR section is identical to before TR ran.

If any check fails, fix the content before moving on.
