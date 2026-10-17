---
name: daily-mail
description: Generate a copy-pasteable daily status email from the cockpit sprint board.
---

# Daily Mail

Generate a copy-pasteable daily status email in the team's standardised format by reading the cockpit sprint board for current ticket state.

## Board constants

- Sprint statuses (tickets on the Sprint Board): `Sprint Backlog`, `Daily Plan`, `In Dev`, `In CR by AI`, `Ready for CR`, `In CR`, `Ready for FR`, `In FR`, `Ready for Validation`

## Workflow

### 1. Read sprint tickets

```sh
"$HOME/.cockpit/scripts/board-card" list --json
```

Keep the cards whose `status` is one of the sprint statuses listed above, and read `name`, `status`, `blocked`, `due`, `overrunning`, `days_in_column` and `type` off each. `board-card` works out `overrunning` and `days_in_column` as it reads, so take them as it gives them and never work either out from the card's dates.

Group tickets by `status`.

### 2. Detect blockers

A ticket is blocked when its `blocked` field is set. The field holds the blocker reason, so that is the one-line summary - nothing else is read for it.

If no blocked tickets exist, the Dependencies section will say "No blockers."

### 3. Determine traffic light

Use these heuristics on the sprint board state:

- **🔴 Blocked** — any ticket has `blocked` set.
- **🟠 Off track** — no blocked tickets, but any ticket is `overrunning` or has a `due` date before today.
- **🟢 On track** — neither of the above.

Include a one-line explanation after the traffic light emoji. For 🟠, it names each ticket that put the light there, with its `days_in_column` in working days for a ticket that is `overrunning`, or its `due` date for one that is past it.

### 4. Format output

Output the daily mail as a fenced text block the user can copy-paste directly. Use today's day name for the greeting.

Template:

```
Happy <day of week> team!

*Dependencies*
<for each blocked ticket: "- [ticket name]: [blocker summary]">
<if none: "No blockers.">

*Status Update*
<traffic light emoji> <one-line explanation>

*Ticket Board*
<insert screenshot of board>

<if problem-solving summaries exist:>
*Problem Solving*
<for each: one-line summary + actions taken>

Please feel free to reach out if you have any questions/concerns :)
```

Rules:

- Use ticket names verbatim from the board — do not rewrite or summarise them.
- The `<insert screenshot of board>` placeholder stays as literal text for the user to replace manually.
- If no problem-solving content is found, omit the Problem Solving section entirely.
- Output the result as plain text in a fenced code block so the user can copy-paste it.
