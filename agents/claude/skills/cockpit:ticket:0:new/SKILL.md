---
name: cockpit:ticket:0:new
description: Create a new cockpit ticket with body content. The single creation path for all cockpit tickets - called directly for scope drift / follow-ups, or delegated to by the register skill for stubs.
---

# raise-ticket

The single creation path for cockpit tickets. Every code path that needs a new ticket page goes through this skill so body content is always included.

Two calling contexts:

- **From a session** (scope drift, follow-up, bounce-back): the session stays bound to its existing ticket. This skill creates the stub and reports.
- **From the register skill** (cases 2 and 3): title, type, epic, user ID, and optional source URL are already resolved. This skill creates the page with body content and returns the URL for registration.

Read `~/.claude-shared/templates/notion-writing.md` before writing to the page.

## Board constants

Read each with `"$HOME/.claude-shared/cockpit-board-id" get <key>`, following `~/.claude-shared/templates/board-ids.md`.

This skill needs: `tickets-data-source`, `epics-data-source`. Both are read for the board step 3.6 resolves, which is this checkout's own unless the ask named another.

## Workflow

### 1. Gather context

Accept the concern as the skill argument (free text describing the new task). If no argument was supplied, ask:

- What is the concern or task?
- Why is it separate from the current ticket?

Infer a ticket title from the concern: succinct, the outcome not an instruction.

**From register:** title, type, epic, user ID, and optional source URL are already resolved - use them directly.

### 2. Resolve the connected user

Run `"$HOME/.claude-shared/cockpit-cache-query" user-id`. A non-zero exit means the cache is missing or has no such key - call `notion-fetch` with `id: "self"` to get the user ID instead.

**From register:** user ID is already resolved - skip.

### 3. Resolve the epic

Fetch the current session's ticket (the one registered via `/cockpit:ticket:register`) and read its `Epic` relation, then read that epic's status the way the register skill's epic gate does - `"$HOME/.claude-shared/cockpit-cache-query" epic-statuses`, no page fetch. Default to the same epic unless its status is `Epic Done`, in which case pick from `epics` by the rule below and say on the new ticket which epic had closed.

If the concern clearly belongs to a different epic, search the cockpit cache via `"$HOME/.claude-shared/cockpit-cache-query" epics` for a match - it returns open epics only. Pick the closest match and post what decided it on the new ticket - never ask.

Same-project siblings follow the epic gate's rule: pick by the kind of work (diff on the product → dev epic, reporting or process → delivery epic), never by the closer name.

**From register:** epic is resolved by register's epic gate - skip.

### 3.5. Detect cross-board context (from a session only)

Check whether the session's registered ticket is cross-board by reading `~/.local/state/claude-ticket-sessions/<session_id>.source-ticket`. If this file exists:

1. Look up the source board's data source URL by running `"$HOME/.claude-shared/cockpit-cache-query" project-boards`. Use the `collection://` URL from the registered session's source ticket.
2. Create a page on the source board via `notion-create-pages`:
   - `Name`: the inferred title (from step 1).
   - Icon: a fitting emoji.
   - `Status`: the first status in the source board's cached `statuses` list.
3. Note the new source page URL - step 4 will use it as `Source Ticket URL`.

If the source-ticket file does not exist, the session is not cross-board - skip to step 4.

**From register:** skip - register handles source ticket URL directly.

### 3.6. Resolve the board the ticket is created on

The board serving this checkout is the default, and nothing is asked for it. A board named in the ask overrides it - "raise a cockpit ticket" from a project session means the Cockpit board.

Run `"$HOME/.claude-shared/cockpit-board-id" boards`. It prints one configured board name per line. Match those names against the words of the ask, case insensitively.

A match is the board, and every id below is read with that name as the third argument. No match leaves the checkout's own board standing. Two names matched is the one case to ask about, naming both.

### 4. Create the stub with body content

Create a page in the Tickets data source via `notion-create-pages`. The call MUST include both properties AND a non-empty `content` field. Never create a ticket page without body content.

**Properties:**

- `Name`: the inferred title.
- Icon: a fitting emoji.
- `Status`: depends on the calling context. On a board the ask named over this checkout's, the first status that board carries: run `"$HOME/.claude-shared/cockpit-cache-query" project-boards`, find the entry keyed by that board's `tickets-data-source`, and take the first of its `statuses`.
  - **From a session** (scope drift, follow-up, bounce-back next step): `Backlog`. The ticket is captured, not committed to refinement - only a human pull moves it on.
  - **From the register skill** (cases 2 and 3): `Ready for BR by AI`. That session starts work on the ticket immediately, so it is committed by definition.
- `Assignee`: the connected user's ID (from step 2).
- `Epic`: the resolved epic URL (from step 3), and only when step 3.6 left the checkout's own board standing. Another board keeps its own epics, and an id from this one is refused by the creation call.
- `Type`: `Feature` by default. Use `Bug` when the concern is a regression in delivered functionality - behavior that contradicts the validation steps of a Done ticket. Use `Timebox` only when the concern is explicitly time-bounded.
- `Source Ticket URL`: the source URL when present (register case 2).

**Content** - a `## Context` toggle with enough detail for a fresh session to start without asking questions. Template varies by calling context:

**From a session** (handoff):

```
## Context

<details>
<summary>Handoff from [origin ticket name]</summary>
	**Origin:** [origin ticket URL]
	**Reason:** [scope drift / follow-up / bounce-back next step]
	**What:** [description of the concern]
	**Session context:** [relevant details from the current session that the new session needs]
</details>
```

**From a session (cross-board split)** - when step 3.5 created a source board page, use this template instead of the standard handoff:

```
## Context

<details>
<summary>Handoff from [origin ticket name]</summary>
	**Origin:** [origin ticket URL]
	**Source ticket:** [new source board page URL from step 3.5]
	**Reason:** [scope drift / follow-up / bounce-back next step]
	**What:** [description of the concern]
	**Session context:** [relevant details from the current session that the new session needs]
</details>
```

**From register with source URL** (cross-board stub):

```
## Context

<details>
<summary>Source</summary>
	**Source ticket:** [source ticket URL]
	**What:** [source ticket title or description]
</details>
```

**From register without source URL** (quick-capture):

```
## Context

<details>
<summary>Task</summary>
	**What:** [the task description]
</details>
```

Keep content concise - enough to orient a new session, not a full specification.

### 5. Report

Report:

- The new ticket's URL and title.
- **From a session:** that the current session remains on its original ticket (no registration change).
- **From register:** just the URL (register handles the rest).
