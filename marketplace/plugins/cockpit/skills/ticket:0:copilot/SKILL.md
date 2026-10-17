---
name: ticket:0:copilot
description: Take an unclaimed cockpit ticket waiting for an agent - in a by-AI refinement column, or dragged into In Dev - and register it for this session. Use when a session starts with no ticket.
---

# copilot

Give a session with no registered ticket the next piece of work waiting for an agent. `/cockpit:ticket:0:register` needs a ticket id the user already has; this skill finds one on the board instead — a ticket in a by-AI refinement column, or one dragged into `In Dev`, that no other session is holding.

Read `~/.claude-shared/templates/copilot-finding.md` - nobody is reading the chat of the session this starts.

The board is the local one `"$HOME/.cockpit/scripts/board-card"` manages, and the claim is the ticket's `session` field. Empty means free to take.

## Pick the first line

When more than one ticket is claimable, take the first one the script below prints. **Say how many there were** in the report. Never re-sort by a date, an id or a creation time and present that as priority.

## Workflow

### 0. Do not name the session

The session name is built from the ticket — `/cockpit:ticket:0:register` sets it at its step 3, under `~/.claude-shared/templates/session-name.md`, and it needs the claimed ticket to do that. Naming the session for the listening itself burns the one name on a placeholder.

**Reading is free before the session is named** — Read, Glob and Grep, and the shell commands that only read (`ls`, `cat`, `grep`, `jq`, …). One path is the exception: `redirect-state-to-read-write.sh` denies shell reads under `~/.local/state/`, so step 1's marker check uses the Read tool.

Every script this skill runs is cross-allowed by name in both gates. If a gate denies something here, that is a bug in the gate, not a reason to rename: adding a step that runs a new script means adding that script to both cross-allow lists in the same change.

### 1. Refuse if this session already has a ticket

If `~/.local/state/claude-ticket-sessions/<session_id>.ticket` exists, this session is bound to that ticket. Say so and stop — one ticket per session.

### 2. Build the candidate set

The tickets an agent can pick up — the four by-AI refinement columns, and `In Dev` for a ticket someone dragged there without a session on it. An `In … by AI` column is in the set too; the liveness field below is what tells a ticket whose session ended apart from one a session is still drafting. A blocked ticket is left out, because it is waiting on a person rather than an agent:

```sh
"$HOME/.cockpit/scripts/ticket-waiting-cards"
```

One tab-separated line per ticket: ticket id, status, claim (`-` when free), name, liveness (`live`, `stale`, or `-` when there is no claim).

**Run it bare.** Appending `; echo "EXIT=$?"` chains a second command, which both gates deny before the session is named — the cross-allow only recognises a standalone invocation. You do not need it: the exit code comes back with the tool result. No output and a clean exit means no ticket is waiting.

Claimable = waiting **and** unheld — claim `-`, or holding a claim this step may expire.

**Expiring a claim.** A claim is held from pickup to Done, so the column a ticket sits in says nothing about whether its holder is alive — a person can move a claimed ticket back into `Ready for TR by AI` hours after pickup while the session holding it is still working. Never expire a claim on the column.

Read the liveness field `ticket-waiting-cards` prints instead — the last column on each line. A claim is expirable only when it reads `stale`: the session left no heartbeat in the last 30 minutes **and** the claim is over an hour old. A claim reading `live` is never taken over, whatever column the ticket is in.

Treat a `stale` claim as unheld, and say in the report that a claim was taken over.

### 3. Claim one

Take the first claimable ticket:

```sh
"$HOME/.cockpit/scripts/board-card" claim <card-id>
```

It takes `ticket-claim-lock` first - `mkdir` is atomic, so exactly one session on this machine can win it - and only then writes this session's id onto the ticket. Exit 0 means it is yours. Exit 1 means another session holds the lock, a stale one whose lock is still on this machine included — leave that ticket alone and try the next one down.

If nothing is claimable, go to step 5 and wait.

### 4. Register and hand off

Invoke `/cockpit:ticket:0:register` with the ticket id, followed by the skill the claimed column maps to:

| Claimed column       | Then invoke             |
| -------------------- | ----------------------- |
| `Ready for BR by AI` | `/cockpit:ticket:1:br`  |
| `In BR by AI`        | `/cockpit:ticket:1:br`  |
| `Ready for TR by AI` | `/cockpit:ticket:2:tr`  |
| `In TR by AI`        | `/cockpit:ticket:2:tr`  |
| `In Dev`             | `/cockpit:ticket:3:dev` |

Registration finds this session's claim already on the ticket and leaves it as it is.

Registration arms `ticket-watch-column` itself (its step 4.7.1). **Do not arm a second watcher here.**

From the claim onward this session is unattended: nothing it writes to the chat reaches anyone. A defect, a blocker or a question it cannot resolve goes on the registered ticket - see "a finding in a copilot session" in base.AGENTS.md. That holds for the skills invoked above too, for the rest of the session.

### 5. When nothing was claimed, listen

Unless step 3 claimed a ticket, this step always runs. Never end this skill with "nothing to do".

Arm the board listener with the `Monitor` tool:

- `command`: `"$HOME/.cockpit/scripts/ticket-watch-board"`
- `description`: `unclaimed cockpit work`
- `persistent`: `true`

The listener emits one line when unclaimed work appears:

```text
[ticket-listen] 2 ticket(s) waiting for an agent - invoke /cockpit:ticket:0:copilot to take one.
```

It ends itself at that line, so there is nothing to stop after a successful pickup. Re-enter this skill when the line lands, and arm it again whenever this skill ends without a claim.

The listener does not test the claim, so a line can still land on a ticket another session took between the listener's read and the pick. When step 2 then finds nothing claimable, re-arm as usual and name it: "every ticket the listener counted is already held".

## Report

Name the claimed ticket, the column it was in, how many tickets were claimable, and the skill now running on it.

When nothing was claimed, say that the listener is armed and what will happen when work appears. That is a complete, successful outcome for this skill, not a failure to find work.
