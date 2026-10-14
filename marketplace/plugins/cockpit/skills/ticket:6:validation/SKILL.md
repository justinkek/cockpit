---
name: ticket:6:validation
description: Move the session's cockpit ticket to Ready for Validation, and tick on the card each validation step the build was seen to satisfy.
---

# ready-for-validation

Move the registered cockpit ticket to the `Ready for Validation` column, and record on its validation steps what the build was seen to do. This is a user-triggered action - never invoke it automatically.

## Workflow

### 1. Guard: valid source status

`"$HOME/.cockpit/scripts/board-card" show <id> Status` reads the card's column, and the column decides whether the walk to `Ready for Validation` runs:

- **The one the card's walk puts right before `Ready for Validation`** - `In FR`, unless the project's `## Ticket walk skip` removes it - carries on to step 2.
- **`Ready for Validation`** skips the walk and goes straight to step 3.
- **`Done`** needs nothing: say so and stop.
- **Any other column** blocks: name it, and say that each column between it and `Ready for Validation` is a person's pull.

### 2. Advance to Ready for Validation

Invoke the `cockpit:ticket:x:status` skill with target `Ready for Validation`. The skill handles the ordered walk and its date stamps.

### 3. Tick the steps the build satisfies

The evidence lives on the card's own steps, in `## Validation Steps` - on a Bug `## Replication/Validation Steps`, which both calls below name instead. No second list of them is written anywhere else on the card, under `## Details` or outside it.

Read the section fresh, after the walk:

```sh
"$HOME/.cockpit/scripts/board-card" show <id> --section "Validation Steps"
```

Write it back from that read with each step this run saw hold switched from `- [ ]` to `- [x]`, and what was seen hanging one level under the step it proves. Every step keeps its wording, a step this run did not see stays `- [ ]`, and the heading line and any `[comment` line the read printed are left out:

```sh
"$HOME/.cockpit/scripts/board-card" section <id> "Validation Steps" <<'CONTENT'
- [x] AaUser
- [x] Given I have two tickets on the board
- [x] When I open the board
- [x] Then I see each card in its column
	- Seen: FEAT-12 under In Dev and FEAT-13 under Done
CONTENT
```

A screenshot goes onto the board first with `"$HOME/.cockpit/scripts/board-card" attach <id> <file>`, and the line under the step links the path it prints.

A Timebox carries `## Expected Outcome` instead, whose numbered items have no box: what was seen hangs under the item it proves.

### 4. A step that does not hold

A step the build does not satisfy, or a tech step whose summary the build does not deliver, is a defect on this card. Name it to the person, then send the card back through `/cockpit:ticket:x:back-from-column` with `Ready for Validation` as the source column and the column the fix is made in as the target. It is never written up as seen in passing, and its step stays `- [ ]`.
