---
name: cockpit:ticket:5:fr
description: Move the session's cockpit ticket to Ready for FR.
---

# ready-for-fr

Move the registered cockpit ticket to `Ready for FR`. User-triggered only - never invoke automatically.

## Workflow

### 1. Guard: valid source status

Fetch the ticket's current `Status`. Only proceed if the ticket is at `In CR`. If it is at an earlier column, block and name the current status. If it is already at `Ready for FR` or later, report that and stop.

### 2. Advance to Ready for FR

Invoke the `cockpit:ticket:x:status` skill with target `Ready for FR`. It handles the ordered walk, date-stamp polling, and source ticket sync.
