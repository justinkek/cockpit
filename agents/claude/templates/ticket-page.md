# Ticket page template

Read this template when writing or updating a cockpit ticket's body. The body is plain markdown in the ticket's file, and this defines the canonical section order, formatting rules, and output structure for all ticket types.

## Feature ticket

Section order (top to bottom):

```
## Validation Steps
## Tech Steps
## Context
## Details
```

A **split parent** swaps `## Tech Steps` for `## Sub-Tickets` - one line pointing at the `Dependent on` property, which holds the live links. The rest is unchanged, and its Complexity is 0. See the `/cockpit:ticket:x:split` skill.

### Validation Steps (BR output)

Format and rules are in the `/cockpit:ticket:1:br` skill. Invoke it when writing BR content.

### Tech Steps (TR output)

Format, rules and worked example are in the `/cockpit:ticket:2:tr` skill. Invoke it when writing TR content.

### Context

Background, links, agent instructions. Split it under `### ` subheadings when the context is long.

### Details section

`## Details` is the last section on every ticket type. It contains:

1. **Complexity** - Fibonacci estimate with rationale and reference ticket comparison, equal to the sum of the Tech Steps layer points. Never a standalone `## Complexity` section. Its subsection's format is in the `/cockpit:ticket:2:tr` skill.
2. **Back from X summaries** - structured bounce-back records written by the `back-from-column` skill (a `### ` subsection per gate, numbered per bounce).
3. **Preventions** - the proposal written when the ticket leaves `In Dev`: the pattern across its bounce-backs, which of their preventions to build, and which follow-up tickets to raise.
4. **Machine gates** - what the In CR by AI reviews found and fixed, written by `~/.claude-shared/templates/status-machine-gates.md`.

`### Timebox output`, from the `/cockpit:ticket:x:status` skill, and `### Session summary`, from the `/cockpit:ticket:x:destock` skill, sit here too, in the order they are written.

When `## Details` does not exist and needs to be created, insert it after Tech Steps (feature) or Context (timebox).

Subsequent bounces from the same gate append numbered entries inside the existing gate subsection (e.g. `Back from CR #2`).

The Back from X subsection's format is in the `/cockpit:ticket:x:back-from-column` skill.

## Bug ticket

Section order (top to bottom):

```
## Replication/Validation Steps
## Tech Steps
## Context
## Details
```

### Replication/Validation Steps (BR output)

Format and rules are in the `/cockpit:ticket:1:br` skill. Invoke it when writing BR content.

### Tech Steps (TR output)

Same format as Feature tickets - see above.

### Context

Same as Feature tickets - see above.

### Details section

Same as Feature tickets - see above.

## Timebox ticket

Section order (top to bottom):

```
## Expected Outcome
## Outcome
## Context
## Details
```

### Expected Outcome

Numbered items defining what success looks like.

### Outcome

Verdict on the first line, then numbered status items, then Next Steps:

```
**Success** / **Partial Success** / **Failure**

1. ✅ First expected outcome item met
2. ⚠️ Second item partially met — [brief reason]
3. ❌ Third item not met — [brief reason]

- Next Steps: [concrete action, usually a ticket]
```

Questions and uncertainties go in their own section, not nested under Outcome. Next Steps stay a sub-bullet of Outcome, pointing at something concrete - usually a ticket raised.

### Details section

All supporting work (research, analysis, plans, tables) goes here under `### ` subheadings. Never mix this content into the Outcome section. Back from X summaries also live here (see Feature ticket > Details section for format).

Push detail down here rather than into Outcome: bizdevs scan the Outcome, devs dig into the Details. When the explanation spans more than one item (option comparisons, architecture flows, data analysis, research findings), draw it with the `generate-web-diagram` skill instead of writing bullet lists or paragraphs. Skip it only when the answer is a single statement.

## Formatting rules

1. **No standalone Complexity section.** It belongs inside `## Details`, never as its own `##` heading. Risks are not written at all.

2. **No numbered items inside checkboxes.** Checkboxes use `- [ ]` syntax. If a checkbox has sub-points, use indented checkboxes (not numbered items):

   Wrong:

   ```
   - [ ] Validate the API
     1. Check auth endpoint
     2. Check data endpoint
   ```

   Right:

   ```
   - [ ] Validate the API
     - [ ] Check auth endpoint
     - [ ] Check data endpoint
   ```

   If sub-points are not individually checkable, use plain indented bullets:

   ```
   - [ ] Validate the API
     - Auth endpoint returns 200
     - Data endpoint returns expected schema
   ```

3. **Section order is fixed.** Follow the order defined above for each ticket type. Do not reorder, merge, or add ad-hoc top-level sections.

4. **BR and TR content do not mix.** BR is _what and why_; TR is _how_. See the `/cockpit:ticket:1:br` skill for BR rules and the exclusion list.

5. **Plain markdown.** Collapsible sections are `### ` subheadings or nested lists, and tables are markdown pipe tables. `## Tech Steps` is the one exception: its toggles are `<details>` blocks, each opening on a `<summary>` line, and the board draws them collapsed and nested. The board would draw a toggle in any other section too, so keeping them to `## Tech Steps` is the writer's job. HTML other than a toggle shows as plain text.

6. **Write a section, never the whole body.** Replace one section with `"$HOME/.cockpit/scripts/board-card" section <ticket-id> "<heading>" [--before "<heading>" | --after "<heading>"]`, the new content on stdin. A section that does not exist yet lands before the `--before` heading or after the `--after` heading, and at the end of the body with neither flag or when the heading it names is absent. Build it from a `board-card show <ticket-id> --section "<heading>"` taken immediately before the write.

7. **Content that vanished between two reads was deleted by a person.** A human edits the ticket on the board while the agent drafts, so a line on an earlier read and absent from the current one is their edit, never a failed write. Leave it out of the section you write back and say it went; never put it back.
