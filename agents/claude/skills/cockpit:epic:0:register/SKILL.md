---
name: cockpit:epic:0:register
description: Register a cockpit epic for this session - scope the session to the epic and route to the right workflow (FD, TD, breakdown, or ticket pick) based on the epic's current status. Use when the user pastes an epic URL, or when cockpit:ticket:0:register detects an epic URL.
---

# Epic

Counterpart to `/cockpit:ticket:0:register` for epic-level work. Where `/cockpit:ticket:0:register` scopes a session to a single ticket (BR → TR → Dev), `/epic` scopes a session to an epic (FD → TD → Breakdown) and routes to the right workflow based on the epic's current status.

## Board constants

Read each with `"$HOME/.claude-shared/cockpit-board-id" get <key>`, following `~/.claude-shared/templates/board-ids.md`.

This skill needs: `epics-data-source`, `tickets-data-source`, `projects-data-source`.

### Epic status column order

```
Ready for FD by AI → In FD → Ready for FD
→ Ready for TD by AI → In TD → Ready for TD
→ Ready for Ticket Breakdown by AI → Ready for Ticket Breakdown
→ Tickets In Dev → Epic Done
```

## Workflow

### 0. Resolve the connected user

Run `"$HOME/.claude-shared/cockpit-cache-query" user-id`. A non-zero exit means the cache is missing or has no such key - fall back to calling `notion-fetch` with `id: "self"`.

### 1. Resolve the input to a cockpit epic

Fetch the page. Verify its `parent-data-source` matches the Epics data source (the `epics` id).

If it does not match, this is not an epic. Stop and tell the user to use `/cockpit:ticket:0:register` instead.

### 2. Auto-name the session

Read the epic's `Project` relation. If populated, fetch the project page to get its name.

Then read `~/.claude-shared/templates/session-name.md` and build the name it gives a session holding an epic - the project in the bracket, or `epic` when none is linked, and the epic name after it.

### 3. Register the epic

Reuse the existing session marker mechanism. Run exactly:

```sh
"$HOME/.claude-shared/ticket-register" "<epic-url>"
```

This writes the session marker that unlocks the `require-ticket.sh` gate. The hook gates "is something registered", not "is it a ticket specifically" - an epic URL works the same way.

### 3.5. Store work item type

After registration, store the work item type so the status line can show that this session is working on an epic.

Run exactly:

```sh
"$HOME/.claude-shared/ticket-register-type" epic "<session-name>"
```

Use the same session name passed to auto-rename in step 2.

### 4. Route based on epic status

Read the epic's `Status` property and route to the appropriate workflow:

#### Ready for FD by AI

1. Advance to `In FD` via `notion-update-page` (`update_properties`).
2. Poll `Date: In FD` until non-null (same pattern as cockpit:ticket:x:status: up to ~3 tries, seconds apart, respect 429s).
3. Invoke `/cockpit:epic:1:fd` to begin functional design.

#### Ready for TD by AI

1. Advance to `In TD` via `notion-update-page` (`update_properties`).
2. Poll `Date: In TD` until non-null.
3. Invoke `/cockpit:epic:2:td` to begin technical design.

#### Ready for Ticket Breakdown by AI

1. Read the epic page content - FD sections (Flow Diagram, Edge Cases) and TD sections (Strategy Options, Solution Diagram, Uncertainties).
2. Propose a ticket set: for each ticket, show a title, type (Feature or Timebox), and a one-line description. Each ticket should map to a discrete slice of the epic's scope.
3. Creating the tickets is itself the approval, so never create them unasked. Write the proposed set onto the epic, raise it there following `~/.claude-shared/templates/raise-a-decision.md`, leave the epic in its column for the human pull, and stop. Steps 4 to 6 are what the person who approves the set runs, in whichever session picks the epic back up.
4. Create each ticket in the Tickets data source:
   - `Name`: the proposed title.
   - Icon: a fitting emoji.
   - `Status`: `Ready for BR by AI`.
   - `Type`: the proposed type.
   - `Epic`: relation to this epic.
   - `Assignee`: the connected user's ID (from step 0).
5. Advance the epic to `Tickets In Dev` via `notion-update-page`.
6. Poll `Date: Tickets in Dev` until non-null.

#### Tickets In Dev

1. Fetch the epic's `Ticket Kanban` relation to get linked tickets.
2. For each ticket, show its name and current status.
3. Let the user choose which ticket to work on.
4. Invoke `/cockpit:ticket:0:register` with the chosen ticket URL.

#### Other statuses

For statuses not listed above (Ready for FD, In FD, Ready for TD, In TD, Ready for Ticket Breakdown, Epic Done):

- `In FD` / `In TD` - the epic is mid-refinement. Invoke the corresponding skill (`/cockpit:epic:1:fd` or `/cockpit:epic:2:td`) to continue.
- `Ready for FD` / `Ready for TD` / `Ready for Ticket Breakdown` - the epic is waiting for a human pull (refinement session). Report the status and that no AI work is needed.
- `Epic Done` - report that the epic is complete.

### 5. Confirm

Report the registered epic, its project, its status, and the action taken (which workflow was invoked or which ticket was selected).
