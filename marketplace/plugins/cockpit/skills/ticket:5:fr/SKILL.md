---
name: ticket:5:fr
description: Move the session's cockpit ticket to Ready for FR.
---

# ready-for-fr

Move the registered cockpit ticket to `Ready for FR`. User-triggered only - never invoke automatically.

Before the walk, read what is still open on the card with `"$HOME/.cockpit/scripts/board-card" comments <id>` and act on it as `~/.claude-shared/templates/page-comments.md` says. A comment that leaves open is named in the report, and the move still goes ahead - the person asked for it.

## Workflow

### 1. Guard: valid source status

`"$HOME/.cockpit/scripts/board-card" show <id> Status` gives the current column. Only proceed if the ticket is at `In CR`. If it is at an earlier column, block and name the current status. If it is already at `Ready for FR` or later, report that and stop.

### 2. Advance to Ready for FR

Invoke the `cockpit:ticket:x:status` skill with target `Ready for FR`. It handles the ordered walk and its date stamps.
