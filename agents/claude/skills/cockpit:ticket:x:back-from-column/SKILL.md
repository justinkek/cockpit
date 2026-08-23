---
name: cockpit:ticket:x:back-from-column
description: Handle a ticket defect (bounce-back from a gate). Owns the full flow - infer structured summary from session context, increment counter, write nested toggle to ticket page, post short comment, set status. Invoked by cockpit:ticket:x:status on backward moves.
---

# back-from-column

Source of truth for ticket regressions. When a ticket bounces back from a gate (Dev, CR, FR, Validation), this skill handles the entire flow:

1. Infer the structured summary from session context
2. Increment the Back from counter
3. Write a nested toggle to the ticket page under `## Details`
4. Post a short Notion comment
5. Set the ticket status directly (no intermediate walk)

Read `~/.claude-shared/templates/notion-writing.md` before writing to the page.

## Inputs

The skill expects these values from the calling context (either `cockpit:ticket:x:status` delegation or direct invocation):

- **ticket URL** - the session's registered ticket
- **source column** - the gate being bounced from (e.g. `In CR`)
- **target column** - where the ticket is regressing to (e.g. `In Dev`). May equal the source column - see "In-place bounce" below.
- **reason** - short summary of why (inferred from session context)

### In-place bounce

A rejection raised in chat is a real bounce-back, but the card does not move: the user says the work is wrong, the agent fixes it, and the ticket stays in `In Dev` (or any BR or TR column, `In CR`, `In FR`, `Ready for Validation`) throughout. Target column equals source column in that case, and the flow still runs - the counter and the toggle are the whole point.

Only the status write differs; see step 6.

**What counts.** A defect in work already delivered at that gate. A preference, a scope change, or a new requirement is not a bounce-back - those stay a TR amendment or a new ticket. The counter is only useful while it stays honest.

**One bounce per defect, not per message.** A long back-and-forth about a single defect is one entry, not one per prompt.

## Regression source to counter mapping

| Source column          | Counter property       |
| ---------------------- | ---------------------- |
| `In BR by AI`          | `Back from BR`         |
| `Ready for BR`         | `Back from BR`         |
| `In BR`                | `Back from BR`         |
| `In TR by AI`          | `Back from TR`         |
| `Ready for TR`         | `Back from TR`         |
| `In TR`                | `Back from TR`         |
| `In Dev`               | `Back from Dev`        |
| `In CR`                | `Back from CR`         |
| `In FR`                | `Back from FR`         |
| `Ready for Validation` | `Back from Validation` |

## Procedure

### 1. Read current state

Fetch the ticket page to get:

- Current counter value for the relevant `Back from` property
- Current page content (to locate or create `## Details`)
- Ticket `Type` (Feature or Timebox)

Read the ticket's open comments here too, following `~/.claude-shared/templates/page-comments.md`.

### 2. Infer the structured summary

From the session context (the conversation so far), infer:

- **Evidence:** — screenshot or image showing the problem. If the blocker has no visual component (e.g. a logic error with no UI), write "N/A — no visual component". Never omit this field.
- `[problem]` - root cause of the bounce-back (single statement)
- `[fix]` - what was done to address it
- `[earlier detection]` - how this class of defect could have been caught sooner
- `[prevention]` - how to stop this class of defect from recurring
- **Blocked on:** — what is preventing progress (person, decision, external dependency, or "Nothing — fix applied"). Never omit this field.
- **Follow-up tickets** - any new tickets created or needed (omit if none)

Do not ask the user for these fields. Infer them from the session's work. If a field genuinely cannot be inferred (e.g. no fix was applied yet), write "TBD" for that field.

### 3. Increment the counter

Read the current counter value and increment by 1 via `notion-update-page` (`update_properties`). The new count is used in the toggle title.

### 4. Write the structured toggle to the ticket page

On a cross-board session the content goes to the source ticket, not the cockpit stub, which carries status and cost but no content. Read the source ticket URL from `~/.local/state/claude-ticket-sessions/<session_id>.source-ticket` and write there when the file exists; write to the cockpit ticket when it does not.

The summary is written as nested toggles under `## Details`:

```
## Details
<details>
<summary>Back from CR</summary>
	<details>
	<summary>Back from CR #1</summary>
		**Evidence:** [screenshot/image or "N/A — no visual component"]
		`[problem]` Root cause description
		`[fix]` What was done
		`[earlier detection]` How to catch sooner
		`[prevention]` How to prevent recurrence
		**Blocked on:** [blocker or "Nothing — fix applied"]
		Follow-up tickets: [link] (or "None")
	</details>
</details>
```

**Inserting `## Details`** - if the section does not exist yet, insert it at the correct position based on ticket type:

- **Feature:** after `## Tech Steps` (or after `## Validation Steps` if no Tech Steps yet, or after `## Context` as last resort)
- **Timebox:** after `## Context`

**Appending to existing gate toggle** - if a `Back from CR` toggle already exists (from a previous bounce), append the new numbered entry inside it:

```
<details>
<summary>Back from CR</summary>
	<details>
	<summary>Back from CR #1</summary>
		...existing...
	</details>
	<details>
	<summary>Back from CR #2</summary>
		...new entry...
	</details>
</details>
```

**Appending to existing `## Details`** - if the section exists but has no toggle for this gate yet, add a new gate toggle inside it.

Use `update_content` (search-and-replace) to insert precisely. If the page structure does not match expectations, fall back to `insert_content` at the end.

### 5. Post the short comment

Create a Notion comment via `notion-create-comment`:

```
🔙 Back from <column> (#<new_count>): <reason>
```

The reason is the one-line summary (same as the `[problem]` field, condensed).

### 6. Set the ticket status

**In-place bounce (target == source)** - skip this step entirely. Do not write `Status` and do not run `ticket-register-column`: the card is already in that column, so the write is a no-op that only risks disturbing the date stamp.

**Otherwise** - set `Status` directly to the target column via `notion-update-page` (`update_properties`). Regressions do NOT walk backward through intermediate columns (that would create spurious date stamps). One `update_properties` call.

When the **source** column is `In BR by AI` or `In TR by AI`, clear `Agent: Session Id` in that same call (and on the source ticket when the session has one), and release the local lock:

```
"$HOME/.claude-shared/ticket-claim-lock" release <page-id>
```

This skill bypasses the walk, so it does not inherit the walk's release step - and a card bounced out of a by-AI column while still locked or still marked as claimed is a card `cockpit:ticket:0:copilot` will never offer again.

Then record the landed column for the status line:

```
"$HOME/.claude-shared/ticket-register-column" "<target-column>"
```
