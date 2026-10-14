---
name: ticket:6:validation
description: Move the session's cockpit ticket to Ready for Validation, and tick on the card each validation step the build was seen to satisfy.
---

# ready-for-validation

Move the registered cockpit ticket to the `Ready for Validation` column, and record on its validation steps what the build was seen to do. This is a user-triggered action - never invoke it automatically.

## Workflow

### 1. Guard: valid source status

`"$HOME/.cockpit/scripts/board-card" show <id> Status Type` reads the card's column and its type. The type picks the section step 3 records on, and the column decides whether the walk to `Ready for Validation` runs:

- **The one the card's walk puts right before `Ready for Validation`** - `In FR`, unless the project's `## Ticket walk skip` removes it - carries on to step 2.
- **`Ready for Validation`** skips the walk and goes straight to step 3.
- **`Done`** needs nothing: say so and stop.
- **Any other column** blocks: name it and the column the card has to reach first, and stop.

### 2. Advance to Ready for Validation

Invoke the `cockpit:ticket:x:status` skill with target `Ready for Validation`. The skill handles the ordered walk and its date stamps.

### 3. Record what the build was seen to do

The evidence lives on the card's own steps, in `## Validation Steps`. Both calls below name another section on the other two types: `Replication/Validation Steps` on a Bug, and `Outcome` on a Timebox. This run writes no list of its own anywhere else on the card, under `## Details` or outside it.

Read the section fresh, after the walk:

```sh
"$HOME/.cockpit/scripts/board-card" show <id> --section "Validation Steps"
```

Write it back from that read with each step this run saw hold switched to `- [x]`, and what was seen hanging one level under the step it proves. Every line keeps its wording, and the heading line and any `[comment` line the read printed are left out:

```sh
"$HOME/.cockpit/scripts/board-card" section <id> "Validation Steps" <<'CONTENT'
- [x] AaUser
- [x] Given I have two tickets on the board
- [x] When I open the board
- [x] Then I see each card in its column
	- Seen: FEAT-12 under In Dev and FEAT-13 under Done
CONTENT
```

Every box and every `Seen:` line is written from what this run saw. One already on the read can be an earlier run's, made against a build a bounce has changed since: a step this run did not see hold goes back to `- [ ]` and loses its `Seen:` line, and one it did see carries this run's `Seen:` line in place of the old one.

A screenshot goes onto the board first with `"$HOME/.cockpit/scripts/board-card" attach <id> <file>`, and the line under the step links the path it prints.

On a Bug, the `Then ... (bug)` step names the broken behaviour, and it holds once the build no longer does it. The `Instead of ... (fix)` step nested under it holds once the build does what it names. What was seen for the pair hangs under the `(fix)` step:

```
- [x] Then the export button opens a blank page (bug)
	- [x] Instead of downloading the report (fix)
		- Seen: report.csv downloaded, and no blank page opened
```

A Timebox has no boxes. Its `## Outcome` gives each `## Expected Outcome` item a verdict, and what was seen hangs under the numbered Outcome item whose verdict it bears out. `## Expected Outcome` is left as BR wrote it.

### 4. A step that does not hold

Each of these is a defect on this card: a step the build does not satisfy, a tech step whose summary the build does not deliver, a Timebox verdict the evidence does not bear out, and a Timebox with no `## Outcome` to check. Name it to the person, then send the card back through `/cockpit:ticket:x:back-from-column` with `Ready for Validation` as the source column and the column the fix is made in as the target. It is never written up as seen in passing: no `Seen:` line hangs under it, and a box it has stays `- [ ]`.
