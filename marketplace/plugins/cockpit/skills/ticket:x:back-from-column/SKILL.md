---
name: ticket:x:back-from-column
description: Handle a ticket defect (bounce-back from a gate). Owns the full flow - infer structured summary from session context, increment counter, write a nested subsection to the ticket, post short comment, set status. Invoked by cockpit:ticket:x:status on backward moves.
---

# back-from-column

Source of truth for ticket regressions. When a ticket bounces back from a gate (Dev, CR, FR, Validation), this skill handles the entire flow:

1. Infer the structured summary from session context
2. Increment the Back from counter
3. Write a nested subsection to the ticket under `## Details`
4. Post a short comment on the ticket
5. Set the ticket status directly (no intermediate walk)

## Inputs

The skill expects these values from the calling context (either `cockpit:ticket:x:status` delegation or direct invocation):

- **ticket id** - the session's registered ticket, e.g. `COC-123`
- **source column** - the gate being bounced from (e.g. `In CR`)
- **target column** - where the ticket is regressing to (e.g. `In Dev`). May equal the source column - see "In-place bounce" below.
- **reason** - short summary of why (inferred from session context)

### In-place bounce

A rejection raised in chat is a real bounce-back, but the ticket does not move: the user says the work is wrong, the agent fixes it, and the ticket stays in `In Dev` (or any BR or TR column, `In CR`, `In FR`, `Ready for Validation`) throughout. Target column equals source column in that case, and the flow still runs - the counter and the subsection are the whole point.

Only the status write differs; see step 6.

**What counts.** A defect in work already delivered at that gate. A preference, a scope change, or a new requirement is not a bounce-back - those stay a TR amendment or a new ticket. The counter is only useful while it stays honest.

**One bounce per defect, not per message.** A long back-and-forth about a single defect is one entry, not one per prompt.

**Never a ticket in `Done`.** `board-card` no longer refuses moving or bouncing one, so the stop is yours: leave it in `Done` and raise a new ticket for what is left with `/cockpit:ticket:0:new`.

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

Read the ticket with `"$HOME/.cockpit/scripts/board-card" show <id> --json` to get:

- Current page content, `.body` (to locate or create `## Details`)
- Ticket `Type`, `.type` (Feature, Bug or Timebox)

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

```
"$HOME/.cockpit/scripts/board-card" bounce <id> <BR|TR|Dev|CR|FR|Validation>
```

It adds 1 to the counter and prints the new count, which is used in the subsection title.

### 4. Write the structured subsection to the ticket

The summary is written as nested subsections under `## Details`:

```
## Details

### Back from CR

#### Back from CR #1

**Evidence:** [screenshot/image or "N/A — no visual component"]

- `[problem]` Root cause description
- `[fix]` What was done
- `[earlier detection]` How to catch sooner
- `[prevention]` How to prevent recurrence

**Blocked on:** [blocker or "Nothing — fix applied"]

Follow-up tickets: [ticket id or link] (or "None")
```

An image for **Evidence:** goes onto the board first with `"$HOME/.cockpit/scripts/board-card" attach <id> <file>`, and the path it prints is linked from the entry.

**Appending to an existing gate subsection** - if a `### Back from CR` subsection already exists (from a previous bounce), the new numbered `#### Back from CR #2` entry goes after the last one inside it: read the subsection with `board-card show <id> --section "Back from CR"`, leave out its heading line and the `[comment]` lines that read prints, and write it back with the new entry at its end.

Write it as "Writing under `## Details`" below says.

## Writing under `## Details`

Every subsection of `## Details` - this skill's, and the ones other skills send here - is one call:

```
"$HOME/.cockpit/scripts/board-card" section <id> "<subsection heading>" --under Details <<'CONTENT'
<the subsection's content, without its heading line>
CONTENT
```

It replaces a subsection of that heading where it stands, or adds it at the end of `## Details`, and adds `## Details` at the end of the ticket when the ticket has none. Every other subsection is left as it was.

### 5. Post the short comment

```
"$HOME/.cockpit/scripts/board-card" comment <id> <<'CONTENT'
🔙 Back from <column> (#<new_count>): <reason>
CONTENT
```

The reason is the one-line summary (same as the `[problem]` field, condensed).

### 6. Set the ticket status

**In-place bounce (target == source)** - skip this step entirely. Do not move the ticket and do not run `ticket-register-column`: the ticket is already in that column, so the move is a no-op.

**Otherwise** - move the ticket directly to the target column. Regressions do NOT walk backward through intermediate columns (that would create spurious date stamps), and `board-card walk` refuses a backward target anyway. One move:

```
"$HOME/.cockpit/scripts/board-card" move <id> "<target-column>"
```

Then record the landed column for the status line:

```
"$HOME/.cockpit/scripts/ticket-register-column" "<target-column>"
```
