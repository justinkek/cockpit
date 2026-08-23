# Ticket page template

Read this template when writing or updating ticket page content on the cockpit board. It defines the canonical section order, formatting rules, and output structure for all ticket types.

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

Background, links, agent instructions. Use a `<details><summary>` toggle when the context is long.

### Details section

`## Details` is the last section on every ticket type. It contains:

1. **Complexity** - Fibonacci estimate with rationale and reference ticket comparison, equal to the sum of the Tech Steps layer points. Never a standalone `## Complexity` section. Its toggle's format is in the `/cockpit:ticket:2:tr` skill.
2. **Back from X summaries** - structured bounce-back records written by the `back-from-column` skill (nested toggles per gate, numbered per bounce).
3. **Preventions** - the proposal written when the ticket leaves `In Dev`: the pattern across its bounce-backs, which of their preventions to build, and which follow-up tickets to raise.

When `## Details` does not exist and needs to be created, insert it after Tech Steps (feature) or Context (timebox).

Subsequent bounces from the same gate append numbered entries inside the existing gate toggle (e.g. `Back from CR #2`).

The Back from X toggle's format is in the `/cockpit:ticket:x:back-from-column` skill.

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

All supporting work (research, analysis, plans, tables) goes here using nested toggles. Never mix this content into the Outcome section. Back from X summaries also live here (see Feature ticket > Details section for format).

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

5. **Notion formatting.** Use `<details><summary>` for toggles (not `>` blockquotes). Use `<table>` XML for tables (not markdown pipes). Each tag on its own line, children tab-indented.

6. **Write a section, never the whole page.** Use `update_content` against an `old_str` built from a fetch taken immediately before the call. `replace_content` is for one case only - clearing comments whose blocks are being rewritten anyway (see `~/.claude-shared/templates/page-comments.md`) - and its body is rebuilt from that same immediate fetch.

7. **Content that vanished between two reads was deleted by a person.** A human edits the page in the Notion UI while the agent drafts, so a line on an earlier read and absent from the current one is their edit, never a failed write. Leave it out of `new_str` and say it went; never put it back.
