---
name: ticket:x:status
description: Advance the session's cockpit ticket to a target Status — inferred from what the session is actually doing — by walking the board one column at a time, auto-advancing and reporting each move. Use when work reaches a new stage (refinement done, dev started, dev committed, review requested…) and the card is behind where the work actually is.
---

# ticket-status

Registering a ticket makes one move, and makes it through this skill: a card at `Ready for BR by AI` goes to `In BR by AI` as registration hands on to BR. Every other move is this skill's own, advancing the registered ticket across the board as the session's work progresses.

- **You (the agent) own inference + the move.** Decide the target Status from what the session is doing, and move immediately.
- **This procedure owns correct execution.** Ordered walk, no skipping, every column's date stamped as the card lands on it.

## Board constants

- The session's card id: read the marker written at registration — `~/.local/state/claude-ticket-sessions/<session_id>.ticket` (one line, the id, e.g. `FEAT-123`). If you already have the id from this session's `/cockpit:ticket:0:register` step, use that.

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

**Date-stamped columns** (`board-card` stamps `Date: <col>` on _first_ arrival, in the same call that moves the card). Re-entering a column preserves the original timestamp. Every column above has a `Date:` field EXCEPT `Backlog`, the `… by AI` columns but `Ready for TR by AI`, and `Sprint Backlog` / `Daily Plan`. `Backlog` is the entry column, so the card's creation time already is its arrival stamp:

`Ready for BR, In BR, Ready for TR by AI, Ready for TR, In TR, Ready for Sprint, In Dev, Ready for CR, In CR, Ready for FR, In FR, Ready for Validation, Done`

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

The ticket `Type` is already available from the step-1 read. No extra call needed.

## A timebox that produced no code

Remove `In CR by AI`, `Ready for CR` and `In CR` too, so the walk runs from `In Dev` to `Ready for FR`.

Read whether it produced code off the branch, once, while computing the forward path at step 2, and only when the status read at step 1 is `In Dev`:

    git log main..HEAD --oneline

No branch of its own, or no commits on it, is no code. Anything listed is code, whatever the files are.

Write the call onto the card in the same run, as a `### Timebox output` subsection of `## Details`, naming which way it went and what the command returned. Write it the way `~/.cockpit/skills/ticket:x:back-from-column/SKILL.md` says under "Writing under `## Details`".

A walk starting anywhere but `In Dev` reads nothing and removes nothing here — the card has already passed the CR columns or has not reached them, and the walk never goes back for them. So a timebox commits before the walk that leaves `In Dev`, not after it.

## Before you move: infer, then advance

1. **Infer the target** from what the session is doing right now — not a static event table. Examples: actively refining scope → `In BR`; writing the diff → `In Dev`; dev finished and committed → `In CR by AI`; PR up → `Ready for CR`.
2. **Read the current Status** (step 1 below).
3. **Move immediately** — no confirmation prompt. Execute the walk.

## Where the walk stops, and what takes it off course

- **Scope check** - if the session's work shifts to a concern not covered by the registered ticket (e.g. "add a rule" drifts into "add a hook"), stop and flag it. Do not proceed with the out-of-scope work. Instead:
  1. Name the new concern and why it's distinct from the registered ticket.
  2. Offer to create a new cockpit ticket stub for it, with a handoff prompt in the ticket body that a fresh session can pick up to continue the work.
  3. Return to the registered ticket's scope.
- **In BR and In TR are left by a person.** Either a person drags the card out, or the person asks in this session for a walk that leaves one - asking for a skill whose walk does, such as `/cockpit:ticket:3:dev` or `/cockpit:ticket:x:destock`, is that ask. A walk the agent reached for on its own stops before leaving either and asks, whichever skill runs it: the edit gate sending the session to `/cockpit:ticket:3:dev` is the agent's reach, not the person's ask. The one exemption is a split parent walked by step 8's roll-up, which follows sub-tickets a person has already let out. The content gate in step 3 guards the agent's walk; a drag never passes through it.
- **Reach In CR by AI, then stop at the human gate.** Dev is not finished until the card is in `In CR by AI`; what follows says where to stop, never that stopping short of it is allowed. The agent auto-advances up to and including `Ready for CR`. `In CR by AI` is where the machine gates run, so the card is carried out of it only once they have finished and the pull request is up - a card still sitting there means something has not cleared. `In CR` onward are human pulls - CR reviews the answer, FR checks the outcome, Validation checks the evidence. Never auto-advance past the first human-gated column.
- **Close the loop** on a completed task by auto-advancing to `In CR by AI` and reporting the move - don't wait for the user to remember. Landing there runs the machine gates, and step 9 of the walk then invokes `/cockpit:ticket:4:ready-for-cr`, so the loop closes on a pushed branch with a PR up rather than on a status write.

## The walk

1. **Current status and type** — **always read live from the board**. Never use a previously-fetched or session-cached Status value. Run `"$HOME/.cockpit/scripts/board-card" show <id> Status Type`. The valid status values for the walk come from `"$HOME/.cockpit/scripts/board-card" statuses`.
2. **Compute the forward path** — read `./AGENTS.md` for `## Ticket walk skip`; if present, remove listed columns from the canonical order (see "Per-project walk config" above). Then check the ticket's `Type`: if `Timebox`, also remove the per-type skip columns (see "Per-type walk config" above), and when the status is `In Dev` run the branch read in "A timebox that produced no code" above and remove the CR columns it names. Take the slice from _after_ current up to and including target. Every removed column becomes one `--skip "<column>"` on the walk in step 4.
3. **Guards** (all comparisons use the live status from step 1, never a session-cached value):
   - Target == current → no-op, say so. **One exception: `Done`.** The close-out hangs off the card being Done, not off the hop that put it there, so a card a person dragged arrives with the claim, the lock and the usage figures still outstanding. Record the column first, for the reason step 4 gives, with `"$HOME/.cockpit/scripts/ticket-register-column" "Done"` on its own - there is no walk to chain it to. Then run the close-out named in step 4 against it, and stop - there is no column left to walk.
   - Target is **behind** current → this is a **regression**. Follow `~/.claude-shared/templates/status-regression.md`. It carries which columns have a counter and the hand-off that owns the rest.
   - **Human-pull gate — leaving Backlog:** never walk a ticket forward out of `Backlog`. `Backlog` holds tickets that are captured but not committed to refinement, and committing is a human act. **Block the advance** and say the ticket has to be pulled into refinement by a person first.
   - **Content gate — leaving In BR or In TR:** before walking out of these columns, read each required section with `"$HOME/.cockpit/scripts/board-card" show <id> --section "<heading>"`. Exit 7, or a section carrying none of the items below, **blocks the advance**: name it and do not proceed.
     - Leaving **In BR** — check by ticket Type:
       - Feature: `## Validation Steps` present with at least one checklist item.
       - Bug: `## Replication/Validation Steps` present with at least one checklist item.
       - Timebox: `## Expected Outcome` present
     - Leaving **In TR** (Feature and Bug only — Timeboxes skip this column via per-type walk config): `## Tech Steps` present with at least one step (a subsection, a list item, a checklist item or a `<details>` layer toggle). **A split parent is exempt** — a ticket whose `Dependent on` is populated legitimately has none; its sub-tickets carry them.
   - **Prevention review — leaving `In Dev`:** before the first hop out of `In Dev`, read every `Back from` gate subsection and any `Session summary` subsection under `## Details`, and write one `### Preventions` subsection back into that section, the way "A timebox that produced no code" above writes its own, holding **Pattern:** what their `[prevention]` and `[earlier detection]` lines share, **Worth building:** which of them to build and where it goes, and **Follow-up tickets:** the ones to raise. A ticket with no bounces still gets the subsection, saying so. This never blocks the walk - the proposal is what CR reads, not a gate.
   - Otherwise walk the path.
4. **Walk** the path and record the column it lands on, in one call - the walk steps every column in order, stamps each date-stamped column on first arrival before the next hop, and refuses with exit 4 a target behind the card, and the `&&` records the landing only once the walk has succeeded:

   ```
   "$HOME/.cockpit/scripts/board-card" walk <id> "<target>" --skip "<column>" ... && "$HOME/.cockpit/scripts/ticket-register-column" "<target>"
   ```

   **Record column** in that same call, never in a call of its own. The record is what the status line shows, and the column watcher reads it too: it disarms on the first poll that reads `Done`, and a record that does not read `Done` by then makes it tell the session to invoke `/cockpit:ticket:7:done` - a second close-out of a card this run is already closing out. A model turn between two calls leaves that poll room to land.

   A hand-off that needs something done on a column the walk passes through walks to that column first, does it, then walks on - every one of those walks carries its own record.
   - **Record model** — for every column in the path that matches one of the entries below, write the corresponding `Model:` field. Value: your model ID from the system prompt (e.g. `claude-opus-4-6`).

     ```
     "$HOME/.cockpit/scripts/board-card" set <id> models.<stage> "<model-id>"
     ```

     | Column landed | Field written |
     | ------------- | ------------- |
     | `In BR by AI` | `models.BR`   |
     | `In TR by AI` | `models.TR`   |
     | `In Dev`      | `models.Dev`  |
     | `In CR by AI` | `models.CR`   |
     | `In CR`       | `models.CR`   |

     When more than one of these is in the walk path, only the first match writes `models.CR` (the value is the same agent).

   - **On `Done` only** — whether this run moved the card there or found it there, follow `~/.claude-shared/templates/status-done-close-out.md`. It owns the claim release, giving the worktree back, the main checkout pull, the apply that makes it live, and the usage figures.

5. (continued). **Auto-assign sprint** — if the walk landed on `In Dev` (or passed through Sprint Backlog, even if skipped), follow `~/.claude-shared/templates/sprint-auto-assign.md`. It owns the opt-out for a repo that skips the sprint columns, and the assignment itself.
6. **Confirm stage** — if the walk landed on `In Dev`, run:
   ```
   "$HOME/.cockpit/scripts/ticket-status-confirm" dev
   ```
   This writes the local stage marker that unlocks file edits (the `require-dev-status.sh` hook gates Edit/Write until this marker exists).
7. **Run the machine gates** — if the walk landed the session's own card on `In CR by AI`, follow `~/.claude-shared/templates/status-machine-gates.md`. It owns the review, the level, where the findings land and the tree the step ends on. A split parent that step 8's roll-up walks there runs none: dev never happens on a parent, so it has no branch to review.
8. **Bring the parent along** — if the ticket's `Dependency for` relation is populated, follow `~/.claude-shared/templates/status-parent-roll-up.md`. An empty relation — skip this step entirely.
9. **Publish** — if step 7 ran the gates, invoke `/cockpit:ticket:4:ready-for-cr`, unless they left an unfixed line that `status-machine-gates.md` says holds the publish. It comes after step 8 because the publish walks the card on to `Ready for CR` and brings the parent along there: run first, it would leave this run's roll-up walking the parent back to `In CR by AI`. Skip this step when `/cockpit:ticket:4:ready-for-cr` step 1 started this walk - that run publishes once the walk returns to it, and a second one inside it would post every `unfixed -` line on the PR twice and arm both of its watchers twice.
10. **Report** only what the board does not already show - a gate that refused, a walk `board-card` refused, a scope shift. A walk that ran as intended reports nothing.

## The walk is right on the first pass or not at all

The date stamp is **first-arrival-only and idempotent** — re-entering a status does NOT re-stamp it — and no command backfills one. So a skipped column **cannot be repaired after the fact**: it leaves a `null` date and permanently inverted/negative durations. `board-card walk` stepping in order is the only way to keep the board honest. Never jump with `board-card move` on a forward walk.
