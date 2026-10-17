---
name: epic:0:register
description: Register a cockpit epic for this session - scope the session to the epic and route to the right workflow (FD, TD, breakdown, or ticket pick) based on the epic's current status. Use when the user names an epic id (EPIC-n), or when cockpit:ticket:0:register detects one.
---

# Epic

Counterpart to `/cockpit:ticket:0:register` for epic-level work. Where `/cockpit:ticket:0:register` scopes a session to a single ticket (BR → TR → Dev), `/epic` scopes a session to an epic (FD → TD → Breakdown) and routes to the right workflow based on the epic's current status.

An epic is a local entity, `EPIC-n`, on columns of its own. `"$HOME/.cockpit/scripts/board-card" statuses --kind epic` prints them in walk order. `<epic-id>` below is the epic's id.

## Workflow

### 1. Resolve the input to a cockpit epic

Read it with `"$HOME/.cockpit/scripts/board-card" show <epic-id> Name Status Project`. Exit 3 means there is no such epic.

An id that does not start with `EPIC-` is not an epic. Stop and tell the user to use `/cockpit:ticket:0:register` instead.

### 2. Auto-name the session

The epic's `Project` is a project's id, `PRJ-n`. When it is set, read the project's name with `"$HOME/.cockpit/scripts/board-card" show <project-id> Name`.

Every epic has a project. One from before that rule may have none: ask the person which project it belongs to, from `"$HOME/.cockpit/scripts/board-card" list --kind project`, and set it with `"$HOME/.cockpit/scripts/board-card" set <epic-id> project <PRJ-n>` before going on.

Then read `~/.claude-shared/templates/session-name.md` and build the name it gives a session holding an epic - the project in the bracket and the epic name after it.

### 3. Register the epic

Reuse the existing session marker mechanism. Run exactly:

```sh
"$HOME/.cockpit/scripts/ticket-register" "<epic-id>"
```

This writes the session marker that unlocks the `require-ticket.sh` gate. The hook gates "is something registered", not "is it a ticket specifically" - an epic id works the same way.

### 3.5. Store work item type

After registration, store the work item type so the status line can show that this session is working on an epic.

Run exactly:

```sh
"$HOME/.cockpit/scripts/ticket-register-type" epic "<session-name>"
```

Use the same session name passed to auto-rename in step 2.

### 4. Route based on epic status

Read the epic's `Status` from step 1 and route to the appropriate workflow:

Every stage runs through the same four columns - `Ready for <stage> by AI`, `In <stage> by AI`, `Ready for <stage>`, `In <stage>` - for FD, TD and Ticket Breakdown. The two `by AI` columns are the agent's; the other two are a person's.

#### Backlog

The epic has not been pulled into refinement yet. Ask the person whether to start its functional design now. On a yes, advance it with `"$HOME/.cockpit/scripts/board-card" walk <epic-id> "Ready for FD by AI"` and carry on under the next heading; on a no, report that it stays in `Backlog` and stop.

#### Ready for FD by AI / In FD by AI

1. From `Ready for FD by AI`, advance with `"$HOME/.cockpit/scripts/board-card" walk <epic-id> "In FD by AI"`.
2. Invoke `/cockpit:epic:1:fd` to begin or continue functional design.

#### Ready for TD by AI / In TD by AI

1. From `Ready for TD by AI`, advance with `"$HOME/.cockpit/scripts/board-card" walk <epic-id> "In TD by AI"`.
2. Invoke `/cockpit:epic:2:td` to begin or continue technical design.

#### Ready for Ticket Breakdown by AI / In Ticket Breakdown by AI

0. From `Ready for Ticket Breakdown by AI`, advance with `"$HOME/.cockpit/scripts/board-card" walk <epic-id> "In Ticket Breakdown by AI"`.
1. Read the epic's content with `"$HOME/.cockpit/scripts/board-card" show <epic-id> --json` - FD sections (Flow Diagram, Edge Cases) and TD sections (Strategy Options, Solution Diagram, Uncertainties).
2. Propose a ticket set: for each ticket, show a title, type (Feature or Timebox), and a one-line description. Each ticket should map to a discrete slice of the epic's scope.
3. Creating the tickets is itself the approval, so never create them unasked. Write the proposed set onto the epic as its `## Ticket Breakdown` section with `board-card section <epic-id> "Ticket Breakdown"`, raise it there following `~/.claude-shared/templates/raise-a-decision.md`, advance the epic with `"$HOME/.cockpit/scripts/board-card" walk <epic-id> "Ready for Ticket Breakdown"` for the human pull, and stop. Steps 4 and 5 are what the person who approves the set runs, from `Ready for Ticket Breakdown` or `In Ticket Breakdown`, in whichever session picks the epic back up.
4. Create each ticket, its one-line description as its `## Context`:

   ```sh
   "$HOME/.cockpit/scripts/board-card" create --name "<title>" --type <Feature|Timebox> --status "Ready for BR by AI" --epic <epic-id> --body - <<'EOF'
   ## Context

   <description>
   EOF
   ```

5. Advance the epic with `"$HOME/.cockpit/scripts/board-card" walk <epic-id> "Ready for Dev"`. It moves on to `Tickets In Dev` by itself once its first feature or bug ticket reaches `In Dev`.

#### Ready for Dev / Tickets In Dev

1. List the epic's tickets with `"$HOME/.cockpit/scripts/board-card" list --epic <epic-id>`, one line each: id, status, session, name.
2. For each ticket, show its name and current status.
3. Let the user choose which ticket to work on.
4. Invoke `/cockpit:ticket:0:register` with the chosen ticket's id.

#### Other statuses

For statuses not listed above (Ready for FD, In FD, Ready for TD, In TD, Ready for Ticket Breakdown, In Ticket Breakdown, Epic Done):

- `Ready for FD` / `Ready for TD` / `Ready for Ticket Breakdown` - the epic is waiting for a human pull (refinement session). Report the status and that no AI work is needed.
- `In FD` / `In TD` / `In Ticket Breakdown` - a person is refining the epic. Report the status; for `In Ticket Breakdown`, steps 4 and 5 above are theirs to run when they approve the set.
- `Epic Done` - report that the epic is complete.

### 5. Confirm

Report the registered epic, its project, its status, and the action taken (which workflow was invoked or which ticket was selected).
