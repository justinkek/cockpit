---
name: ticket:0:new
description: Create a new cockpit ticket with body content. The single creation path for all cockpit tickets - called directly for scope drift / follow-ups, or delegated to by the register skill.
---

# raise-ticket

The single creation path for cockpit tickets. Every code path that needs a new ticket goes through this skill so body content is always included.

Two calling contexts:

- **From a session** (scope drift, follow-up, bounce-back): the session stays bound to its existing ticket. This skill creates the ticket and reports.
- **From the register skill** (case 3): title, type and epic are already resolved. This skill creates the ticket with body content and returns its id for registration.

Read `~/.claude-shared/templates/ticket-page.md` before writing the body.

## Workflow

### 1. Gather context

Accept the concern as the skill argument (free text describing the new task). If no argument was supplied, ask:

- What is the concern or task?
- Why is it separate from the current ticket?

Infer a ticket title from the concern: succinct, the outcome not an instruction.

**From register:** title, type and epic are already resolved - use them directly.

### 2. Resolve the epic

Read the current session's ticket id from `~/.local/state/claude-ticket-sessions/<session_id>.ticket` with the Read tool, then its epic with `"$HOME/.cockpit/scripts/board-card" show <card-id> Epic`. Read that epic's status the way the register skill's epic gate does - its line in `"$HOME/.cockpit/scripts/board-card" list --kind epic`, no epic record read on its own. Default to the same epic unless its status is `Epic Done`, in which case pick from the open epics in that listing by the rule below and say on the new ticket which epic had closed.

If the concern clearly belongs to a different epic, pick the closest match among the open epics in that listing and post what decided it on the new ticket - never ask.

With no session ticket to take an epic from, pick the closest match among the open epics and post what decided it on the new ticket - never ask. Every ticket has an epic, so `board-card create` refuses one without `--epic`.

When no open epic fits a bug, a timebox or an improvement to finished work, it goes under its project's maintenance epic for the month instead of the closest match: run `"$HOME/.cockpit/scripts/board-card" maintenance <PRJ-n>` for the project the work belongs to - the project of the session ticket's epic, or with no session ticket the closest open epic's, read with `"$HOME/.cockpit/scripts/board-card" show <EPIC-n> Project` - and use the id it prints. Feature work that fits no open epic still goes under the closest match. Post what decided it on the new ticket either way - never ask.

Same-project siblings follow the epic gate's rule: pick by the kind of work (diff on the product → dev epic, reporting or process → delivery epic), never by the closer name.

**From register:** epic is resolved by register's epic gate - skip.

### 3. Create the card with body content

Every ticket is created with a non-empty body. Never create one without it.

```sh
"$HOME/.cockpit/scripts/board-card" create --name "<title>" --type <Type> --status "<column>" --epic <EPIC-n> --body - <<'EOF'
<body>
EOF
```

It prints the new ticket id, its epic's project's key and its number in that project, such as `COC-12`. It refuses a ticket whose epic's project has no key yet: name that project and stop, since giving a project its key is the person's call.

- `--name`: the inferred title.
- `--status`: depends on the calling context.
  - **From a session** (scope drift, follow-up, bounce-back next step): `Backlog`. The ticket is captured, not committed to refinement - only a human pull moves it on.
  - **From the register skill** (case 3): `Ready for BR by AI`. That session starts work on the ticket immediately, so it is committed by definition.
- `--epic`: the resolved epic id (from step 2).
- `--type`: `Feature` by default. Use `Bug` when the concern is a regression in delivered functionality - behavior that contradicts the validation steps of a Done ticket. Use `Timebox` only when the concern is explicitly time-bounded.

**Body** - a `## Context` section with enough detail for a fresh session to start without asking questions. Template varies by calling context:

**From a session** (handoff):

```markdown
## Context

### Handoff from [origin ticket name]

- **Origin:** [origin ticket id]
- **Reason:** [scope drift / follow-up / bounce-back next step]
- **What:** [description of the concern]
- **Session context:** [relevant details from the current session that the new session needs]
```

**From register** (quick-capture):

```markdown
## Context

### Task

- **What:** [the task description]
```

Keep content concise - enough to orient a new session, not a full specification.

### 4. Report

Report:

- The new ticket's id and title.
- **From a session:** that the current session remains on its original ticket (no registration change).
- **From register:** just the id (register handles the rest).
