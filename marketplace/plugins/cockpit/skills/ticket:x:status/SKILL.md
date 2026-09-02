---
name: ticket:x:status
description: Advance the session's cockpit ticket to a target Status — inferred from what the session is actually doing — by walking the board one column at a time, auto-advancing and reporting each move. Use when work reaches a new stage (refinement done, dev started, PR up + gates green, review requested…) and the card is behind where the work actually is.
---

# ticket-status

Registering a ticket never moves the card. This skill is the other half: it advances the registered ticket across the board as the session's work progresses.

- **You (the agent) own inference + the move.** Decide the target Status from what the session is doing, and move immediately.
- **This procedure owns correct execution.** Ordered walk, no skipping, and a poll after each hop so the board's async date-stamp actually lands.

## Board constants

- Board ids - read with `"$HOME/.cockpit/scripts/cockpit-board-id" get <key>`, following `~/.claude-shared/templates/board-ids.md`. This skill needs `tickets` and `sprints-view`.
- The session's ticket URL: read the marker written at registration — `~/.local/state/claude-ticket-sessions/<session_id>.ticket` (one line, the URL). If you already have the URL from this session's `/cockpit:ticket:0:register` step, use that.

## Canonical column order

```
Backlog
→ Ready for BR by AI → In BR by AI → Ready for BR → In BR
→ Ready for TR by AI → In TR by AI → Ready for TR → In TR
→ Ready for Sprint → Sprint Backlog → Daily Plan
→ In Dev
→ In CR by AI → Ready for CR → In CR
→ Ready for FR → In FR
→ Ready for Validation → Done
```

**Date-stamped columns** (the board auto-stamps `Date: <col>` as a datetime on _first_ arrival — poll these after setting them). The automation only stamps when the field is empty; re-entering a column preserves the original timestamp. Every column above has a `Date:` field EXCEPT `Backlog`, the `… by AI` columns and `Sprint Backlog` / `Daily Plan` — nothing to poll. `Backlog` is the entry column, so `createdTime` already is its arrival stamp; the rest move instantly:

`Ready for BR, In BR, Ready for TR, In TR, Ready for Sprint, In Dev, Ready for CR, In CR, Ready for FR, In FR, Ready for Validation, Done`

## Per-project walk config

Projects can skip columns by adding a `## Ticket walk skip` section to their `./AGENTS.md` with one column per `- ` list item:

```
## Ticket walk skip
- Ready for FR
```

**Validation:**

- Every listed column must appear in the canonical order above.
- `In Dev` and `Done` cannot be skipped — `In Dev` gates file edits, `Done` is the terminal state.
- If validation fails, report the error and use the full walk.

**Effect:** before computing the forward path (step 2 of the walk), read `./AGENTS.md` for `## Ticket walk skip`. If present, remove the listed columns from the canonical order. The walk then proceeds through the filtered order.

**Content gates** (`In BR` → Validation Steps; `In TR` → Tech Steps) only fire for columns that are NOT in the skip list. If a gate column is skipped, its content requirement is waived.

**No config = full walk** — backward compatible.

## Per-type walk config

When the ticket's `Type` property is `Timebox`, remove these columns from the walk automatically — timeboxes go straight from BR to Dev (no tech steps, no sprint ceremony):

- `Ready for TR by AI`
- `In TR by AI`
- `Ready for TR`
- `In TR`
- `Ready for Sprint`
- `Sprint Backlog`
- `Daily Plan`

These merge with (add to) any per-project skip list from `./AGENTS.md`. The same validation rules apply: `In Dev` and `Done` cannot be skipped regardless of type.

The ticket `Type` is already available from the step-1 query (or the initial fetch). No extra call needed.

## A timebox that produced no code

Remove `In CR by AI`, `Ready for CR` and `In CR` too, so the walk runs from `In Dev` to `Ready for FR`.

Read whether it produced code off the branch, once, while computing the forward path at step 2, and only when the status read at step 1 is `In Dev`:

    git log main..HEAD --oneline

No branch of its own, or no commits on it, is no code. Anything listed is code, whatever the files are.

Write the call onto the card in the same run, as a `Timebox output` toggle under `## Details`, naming which way it went and what the command returned.

A walk starting anywhere but `In Dev` reads nothing and removes nothing here — the card has already passed the CR columns or has not reached them, and the walk never goes back for them. So a timebox commits before the walk that leaves `In Dev`, not after it.

## Before you move: infer, then advance

1. **Infer the target** from what the session is doing right now — not a static event table. Examples: actively refining scope → `In BR`; writing the diff → `In Dev`; dev finished and the PR open → `In CR by AI`.
2. **Read the current Status** (step 1 below).
3. **Cross-board — write the source card first.** When `~/.local/state/claude-ticket-sessions/<session_id>.source-ticket` exists, the source ticket owns status and the cockpit only mirrors it. Map the inferred target onto a source status, write it there, then map back to get the cockpit column this walk targets — `~/.claude-shared/templates/mirror-source-status.md` holds both maps and the backward case. No such file means a native cockpit ticket: the inferred target stands as the walk's target.
4. **Move immediately** — no confirmation prompt. Execute the walk.

## Where the walk stops, and what takes it off course

- **Scope check** - if the session's work shifts to a concern not covered by the registered ticket (e.g. "add a rule" drifts into "add a hook"), stop and flag it. Do not proceed with the out-of-scope work. Instead:
  1. Name the new concern and why it's distinct from the registered ticket.
  2. Offer to create a new cockpit ticket stub for it, with a handoff prompt in the ticket body that a fresh session can pick up to continue the work.
  3. Return to the registered ticket's scope.
- **Reach In CR by AI, then stop at the human gate.** Dev is not finished until the card is in `In CR by AI`; what follows says where to stop, never that stopping short of it is allowed. The agent auto-advances up to and including `Ready for CR`. `In CR by AI` is where the machine gates run, so the card is carried out of it only once they have finished and the pull request is up - a card still sitting there means something has not cleared. `In CR` onward are human pulls - CR reviews the answer, FR checks the outcome, Validation checks the evidence. Never auto-advance past the first human-gated column.
- **Close the loop** on a completed task by auto-advancing to `In CR by AI` and reporting the move - don't wait for the user to remember. Landing there runs the machine gates, and clean gates then fire `/cockpit:ticket:4:ready-for-cr` on their own, so the loop closes on a pushed branch with a PR up rather than on a status write. A gate that found something unfixed stops the publish: say what is outstanding instead.

## The walk

1. **Current status and type** — **always read live from Notion**. Never use a previously-fetched or session-cached Status value. Run `"$HOME/.cockpit/scripts/ticket-read" <ticket-url> Status Type`; on a non-zero exit, `notion-fetch` on the ticket URL instead. Never the SQL query tool: Notion meters it per plan, and it answers nothing these do not. The valid status values for the walk come from `"$HOME/.cockpit/scripts/cockpit-cache-query" statuses`. On a non-zero exit, the two values just read and the canonical column order in this skill are sufficient - no separate schema fetch needed.
2. **Compute the forward path** — read `./AGENTS.md` for `## Ticket walk skip`; if present, remove listed columns from the canonical order (see "Per-project walk config" above). Then check the ticket's `Type`: if `Timebox`, also remove the per-type skip columns (see "Per-type walk config" above), and when the status is `In Dev` run the branch read in "A timebox that produced no code" above and remove the CR columns it names. Take the slice from _after_ current up to and including target.
3. **Guards** (all comparisons use the live status from step 1, never a session-cached value):
   - Target == current → no-op, say so. **One exception: `Done`.** The close-out hangs off the card being Done, not off the hop that put it there, so a card a person dragged arrives with the claim, the lock and the usage figures still outstanding. Run the close-out named in step 4 against it, then stop - there is no column left to walk.
   - Target is **behind** current → this is a **regression**. Follow `~/.claude-shared/templates/status-regression.md`. It carries which columns have a counter and the hand-off that owns the rest.
   - **Human-pull gate — leaving Backlog:** never walk a ticket forward out of `Backlog`. `Backlog` holds tickets that are captured but not committed to refinement, and committing is a human act. **Block the advance** and say the ticket has to be pulled into refinement by a person first.
   - **Content gate — leaving In BR or In TR:** before walking out of these columns, read each required section with `"$HOME/.cockpit/scripts/ticket-read" <ticket-url> --section "<heading>"`. Exit 7, or a section carrying none of the items below, **blocks the advance**: name it and do not proceed.
     - Leaving **In BR** — check by ticket Type:
       - Feature: `## Validation Steps` present with at least one checklist item.
       - Bug: `## Replication/Validation Steps` present with at least one checklist item.
       - Timebox: `## Expected Outcome` present
     - Leaving **In TR** (Feature and Bug only — Timeboxes skip this column via per-type walk config): `## Tech Steps` present with at least one step (toggle or checklist item). **A split parent is exempt** — a ticket whose `Dependent on` relation is populated legitimately has none; its sub-tickets carry them.
   - **Prevention review — leaving `In Dev`:** before the first hop out of `In Dev`, read every `Back from` gate toggle and any `Session summary` toggle under `## Details`, and write one `Preventions` toggle back into that section holding **Pattern:** what their `[prevention]` and `[earlier detection]` lines share, **Worth building:** which of them to build and where it goes, and **Follow-up tickets:** the ones to raise. A ticket with no bounces still gets the toggle, saying so. This never blocks the walk - the proposal is what CR reads, not a gate.
   - Otherwise walk the path.
4. **Step, one column at a time**, in order. For each hop:
   - Set `Status` via `notion-update-page` (`update_properties`).
   - **Record model** — if the column being set matches one of the entries below, include the corresponding `Model:` property in the same `update_properties` call. Value: your model ID from the system prompt (e.g. `claude-opus-4-6`).

     | Column set    | Property to write |
     | ------------- | ----------------- |
     | `In BR by AI` | `Model: BR`       |
     | `In TR by AI` | `Model: TR`       |
     | `In Dev`      | `Model: Dev`      |
     | `In CR by AI` | `Model: CR`       |
     | `In CR`       | `Model: CR`       |

     When more than one of these is in the walk path, only the first match writes `Model: CR` (the value is the same agent).

   - If the landed column is date-stamped (list above), **poll** its `Date:` field until it prints, before the next hop, with `"$HOME/.cockpit/scripts/ticket-read" <ticket-url> "Date: <landed column>"` — an unstamped field prints nothing, so any output is the stamp having landed. Never the SQL query tool. The stamp is eventual (~seconds), not synchronous — so **space the polls out and cap them** (e.g. up to ~3 tries, several seconds apart). Tight back-to-back reads trip Notion's rate limiter, which the read reports as exit 6 with the wait in its message: wait that long before the next call, and never count the refused read against the cap. If the stamp still hasn't landed after the cap, note it and continue — don't spin.
   - **On `Done` only** — whether this run moved the card there or found it there, follow `~/.claude-shared/templates/status-done-close-out.md`. It owns the claim release, the worktree give-back, the main checkout pull, the apply that makes it live, and the usage figures.

   - **Record column** — after each hop, update the local column state so the status line reflects the current board position:
     ```
     "$HOME/.cockpit/scripts/ticket-register-column" "<landed-column>"
     ```

5. (continued). **Auto-assign sprint** — if the walk landed on `In Dev` (or passed through Sprint Backlog, even if skipped), follow `~/.claude-shared/templates/sprint-auto-assign.md`. It owns the opt-out for a repo that skips the sprint columns, and the assignment itself.
6. **Confirm stage** — if the walk landed on `In Dev`, run:
   ```
   "$HOME/.cockpit/scripts/ticket-status-confirm" dev
   ```
   This writes the local stage marker that unlocks file edits (the `require-dev-status.sh` hook gates Edit/Write until this marker exists).
7. **Run the machine gates** — if the walk landed on `In CR by AI`, follow `~/.claude-shared/templates/status-machine-gates.md`. It owns the review, the level, where the findings land and the tree the step ends on.
8. **Bring the parent along** — if the ticket's `Dependency for` relation is populated, follow `~/.claude-shared/templates/status-parent-roll-up.md`. An empty relation — skip this step entirely.
9. **Report** only what the board does not already show - a stamp that never landed, a gate that refused, a scope shift. A walk that ran as intended reports nothing.

## The walk is right on the first pass or not at all

The date automation is **first-arrival-only and idempotent** — re-entering a status does NOT re-stamp it — and manual backfill is blocked (the `Date: <col>` property names contain colons and collide with the MCP `date:<name>:start` format). So a skipped column **cannot be repaired after the fact**: it leaves a `null` date and permanently inverted/negative `Duration:` formulas. Stepping in order, polling each stamp, is the only way to keep the board honest. Never jump.
