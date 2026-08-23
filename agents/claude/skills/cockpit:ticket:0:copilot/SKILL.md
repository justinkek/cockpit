---
name: cockpit:ticket:0:copilot
description: Take an unclaimed cockpit ticket waiting for an agent - in a by-AI refinement column, or dragged into In Dev - and register it for this session. Use when a session starts with no ticket.
---

# copilot

Give a session with no registered ticket the next piece of work waiting for an agent. `/cockpit:ticket:0:register` needs a URL the user already has; this skill finds one on the board instead — a card in a by-AI refinement column, or one dragged into `In Dev`, that no other session is holding.

Read `~/.claude-shared/templates/copilot-finding.md` - nobody is reading the chat of the session this starts.

## Board constants

- Board ids - read with `"$HOME/.claude-shared/cockpit-board-id" get <key>`, following `~/.claude-shared/templates/board-ids.md`. This skill needs `tickets-data-source`.
- **The boards:** the entries in `~/.local/state/cockpit/boards.json` that serve the checkout this session was opened in, which is usually one. A project board runs the same columns and the same claim property, and a card waiting there is taken exactly like a cockpit card — but only from a session in that project. A checkout no board claims is a question, not a default: step 2a asks which board serves it and records the answer. The scripts below apply this themselves, so the set they return is already the right one. Never widen it by reading the file directly.
- Claim property: `Agent: Session Id` (text). Empty means free to take.

## The board decides membership; nothing here interprets filters

Never read the view's filter rules and evaluate them. Ask Notion which cards the view contains and use that as a set:

```sh
"$HOME/.claude-shared/ticket-board-members"
```

One id per line, across every configured board, filters already applied, pagination handled. A card absent from that list is not on its board and must never be claimed, whatever any other source says.

That reading only holds when the script exited 0. A non-zero exit means at least one board could not be read to the end, so the list is short and absence from it proves nothing. Say which board failed and stop — never fall through to step 6 as though the queue were empty, and never claim a card off a list you know is incomplete.

A board with no view id in the config has no view to hide anything, so the script returns every row in its database and every one of them is a member. That is the honest answer for an unfiltered board, not a fallback.

**Run the script; do not hand-roll the call.** Neither an improvised `curl … | jq …` pipeline nor the MCP database-view tool is a substitute.

## Order is not available — do not invent one

The response above is not in board order, and no supported surface exposes the manual top-to-bottom order of a column: not the data source query, not the view query, not the view object (`group_by.sort.type: "manual"` says _that_ the order is manual, never what it is), and not automations, which have no reorder trigger.

So when more than one card is claimable, any of them is a correct pick. **Say how many there were** in the report. Never sort by a date, an id or a creation time and present it as priority.

## Workflow

### 0. Do not name the session

The session name is built from the ticket — `/cockpit:ticket:0:register` sets it at its step 3, under `~/.claude-shared/templates/session-name.md`, and it needs the claimed card to do that. Naming the session for the listening itself burns the one name on a placeholder.

**Reading is free before the session is named** — Read, Glob and Grep, and the shell commands that only read (`ls`, `cat`, `grep`, `jq`, …). One path is the exception: `redirect-state-to-read-write.sh` denies shell reads under `~/.local/state/`, so step 1's marker check uses the Read tool.

Every script this skill runs is cross-allowed by name in both gates, as is the Notion claim write. If a gate denies something here, that is a bug in the gate, not a reason to rename: adding a step that runs a new script means adding that script to both cross-allow lists in the same change.

### 1. Refuse if this session already has a ticket

If `~/.local/state/claude-ticket-sessions/<session_id>.ticket` exists, this session is bound to that ticket. Say so and stop — one ticket per session.

### 2. Build the candidate set

The cards an agent can pick up — the four by-AI refinement columns, and `In Dev` for a card someone dragged there without a session on it. An `In … by AI` column is in the set too; the liveness field below is what tells a card whose session ended apart from one a session is still drafting:

```sh
"$HOME/.claude-shared/ticket-waiting-cards"
```

One tab-separated line per card: board, page id, status, claim (`-` when free), name, liveness (`live`, `stale`, or `-` when there is no claim). The board decides what happens after the claim — a card on the cockpit is registered directly, a card on any other board needs a cockpit stub first (step 4).

**Do not use the SQL query tool for this.** `query_data_sources` is capped on this workspace's plan and stops answering once the quota is spent; the script uses the classic database endpoint, which has no cap.

**Exit 3 means no board claims this checkout** — go to step 2a and ask. It is not an empty queue and not a failure; the script printed which checkout it could not place. Exit 4 means a `COCKPIT_BOARD` you passed names no board in the file, and exit 5 means the file configures no boards at all. Neither of those is a question for the user — fix the name or the file.

**Run it bare.** Appending `; echo "EXIT=$?"` chains a second command, which both gates deny before the session is named — the cross-allow only recognises a standalone invocation. You do not need it: the exit code comes back with the tool result, and the script names the checkout on stderr. No output and a clean exit means the boards for this checkout have no cards waiting.

Then intersect with the view's id set from the section above. Claimable = waiting **and** on the board **and** unheld — `Agent: Session Id` empty, or holding a claim this step may expire.

**Expiring a claim.** A claim is held from pickup to Done, so the column a card sits in says nothing about whether its holder is alive — a person can move a claimed card back into `Ready for TR by AI` hours after pickup while the session holding it is still working. Never expire a claim on the column.

Read the liveness field `ticket-waiting-cards` prints instead — the last column on each line. A claim is expirable only when it reads `stale`: the session left no heartbeat in the last 30 minutes **and** the claim is over an hour old. A claim reading `live` is never taken over, whatever column the card is in.

The heartbeat is written on this machine only, so a claim held by a session elsewhere reads `stale` once it is an hour old.

Treat a `stale` claim as unheld and overwrite it, and say in the report that a claim was taken over.

### 2a. When no board claims this checkout, ask

Ask which board serves it, listing the names from `~/.local/state/cockpit/boards.json` so the user picks rather than types. Then record the answer, always - never leave it unrecorded and ask again:

```sh
"$HOME/.claude-shared/cockpit-board-claim" <board-name>
```

That writes the checkout into that board's `repos`. Re-run step 2 afterwards — the board now claims this checkout, so nothing needs passing by hand.

**Never pick for the user, and never guess from the checkout's name.** If the user declines to choose, say the skill cannot pick a board and stop — do not fall back to any board.

`COCKPIT_BOARD=<name>` forces a board for one command without recording it. Use it only when the user explicitly wants a one-off; the recorded claim is the normal path.

### 3. Claim one

Pick any claimable card. On it:

1. **Take the local lock first.** `mkdir` is atomic, so exactly one session on this machine can win it:

   ```sh
   "$HOME/.claude-shared/ticket-claim-lock" take <page-id>
   ```

   Exit 0 means it is yours. Exit 1 means another session got there first — leave that card alone and try the next one down. Do not write anything to Notion for a card you did not win.

2. Only then write `Agent: Session Id` to `claiming-<4 random chars> @ <iso formatted datetime>`, and `Assignee` to the connected user (`"$HOME/.claude-shared/cockpit-cache-query" user-id`).
3. If the session has a source ticket, write both properties to the source card too.

**Both, never one.** The lock arbitrates between sessions on this machine; the property is what tells a session on another machine that a card is taken.

If nothing is claimable, go to step 6 and wait.

### 4. Register and hand off

A card claimed on the cockpit is registered directly. A card claimed on any other board is not a cockpit ticket and has no stub, so registration has nothing to attach the session's cost and status to — create one first by invoking `/cockpit:ticket:0:new` with the claimed card's title, its type, and its URL as the source ticket. That skill returns the stub URL; register that.

Then invoke `/cockpit:ticket:0:register` with the URL, followed by the skill the claimed column maps to:

| Claimed column       | Then invoke             |
| -------------------- | ----------------------- |
| `Ready for BR by AI` | `/cockpit:ticket:1:br`  |
| `In BR by AI`        | `/cockpit:ticket:1:br`  |
| `Ready for TR by AI` | `/cockpit:ticket:2:tr`  |
| `In TR by AI`        | `/cockpit:ticket:2:tr`  |
| `In Dev`             | `/cockpit:ticket:3:dev` |

Registration records the source ticket for a stub created this way, so the refinement content is written to the claimed card and only the tracking data stays on the cockpit.

Registration arms `ticket-watch-column` itself (its step 4.7.1). **Do not arm a second watcher here.**

From the claim onward this session is unattended: nothing it writes to the chat reaches anyone. A defect, a blocker or a question it cannot resolve goes on the registered ticket - see "a finding in a copilot session" in base.AGENTS.md. That holds for the skills invoked above too, for the rest of the session.

### 5. Replace the claim token with the session id

Registration writes `<session_id>.ticket` into `~/.local/state/claude-ticket-sessions/`. The session id is the name of the file whose contents are the claimed ticket URL — read it, and set `Agent: Session Id` to `<session id> @ <iso formatted datetime>`, replacing the token from step 3.

### 6. When nothing was claimed, listen

Unless step 3 claimed a card, this step always runs. Never end this skill with "nothing to do".

Arm the board listener with the `Monitor` tool:

- `command`: `"$HOME/.claude-shared/ticket-watch-board"`
- `description`: `unclaimed cockpit work`
- `persistent`: `true`

The listener polls every 60s and emits one line when unclaimed work appears:

```text
[ticket-listen] 2 ticket(s) waiting for an agent - invoke /cockpit:ticket:0:copilot to take one.
```

It ends itself at that line, so there is nothing to stop after a successful pickup. Re-enter this skill when the line lands, and arm it again whenever this skill ends without a claim.

The listener counts only cards the board shows, but it does not test the claim, so a line can still land on a card another session took between the poll and the pick. When step 2 then finds nothing claimable, re-arm as usual and name it: "every card the listener counted is already held".

A missing credential makes the listener print one `[ticket-listen] no credential` line and exit; report it and stop rather than re-arming.

## Report

Name the claimed ticket, the board it came from, the column it was in, how many cards were claimable, and the skill now running on it. Say plainly that the pick among them was arbitrary — the board's order is not readable.

When nothing was claimed, say that the listener is armed and what will happen when work appears. That is a complete, successful outcome for this skill, not a failure to find work.
