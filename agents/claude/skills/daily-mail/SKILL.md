---
name: daily-mail
description: Generate a copy-pasteable daily status email from the cockpit sprint board.
---

# Daily Mail

Generate a copy-pasteable daily status email in the team's standardised format by querying the cockpit sprint board for current ticket state.

## Board constants

- Board ids - read with `"$HOME/.claude-shared/cockpit-board-id" get <key>`, following `~/.claude-shared/templates/board-ids.md`. This skill needs `tickets-data-source`.
- Sprint statuses (tickets on the Sprint Board): `Sprint Backlog`, `Daily Plan`, `In Dev`, `In CR by AI`, `Ready for CR`, `In CR`, `Ready for FR`, `In FR`, `Ready for Validation`

## Workflow

### 1. Query sprint tickets

Query the Tickets data source for all tickets whose `Status` is one of the sprint statuses listed above. Select `Name`, `Status`, `Blocked`, `Assignee`, and `Type`.

If the query limit is hit, fall back to `notion-fetch` on the Tickets data source and say in the mail which sprint could not be determined, naming what was found instead. A mail that names its gap can still be sent.

Group tickets by `Status` column.

### 2. Detect blockers

From the query results, find tickets where `Blocked` equals `"Blocked"`.

For each blocked ticket, fetch its page and look for the most recent `notion-get-comments` entry that starts with `**Blocked:**`. Extract the one-line blocker summary from that comment.

If no blocked tickets exist, the Dependencies section will say "No blockers."

### 3. Determine traffic light

Use these heuristics on the sprint board state:

- **🔴 Blocked** — any ticket has `Blocked` = `"Blocked"`.
- **🟠 Off track** — no blocked tickets, but any ticket has `Overrunning` that evaluates to a truthy value (the formula flags tickets that have been in their current column longer than expected).
- **🟢 On track** — neither of the above.

Include a one-line explanation after the traffic light emoji.

### 4. Format output

Output the daily mail as a fenced text block the user can copy-paste directly. Use today's day name for the greeting.

Template:

```
Happy <day of week> team!

*Dependencies*
<for each blocked ticket: "- [ticket name]: [blocker summary from comment]">
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
