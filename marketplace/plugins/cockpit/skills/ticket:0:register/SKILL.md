---
name: ticket:0:register
description: Register the cockpit card this session works on — resolve or create the card, raise or link an epic if it has none, then unlock the session's edit gate. Use at work start, when the require-ticket hook blocks an edit or command, or when the user says "ticket", "register ticket", or names a card id (FEAT-n) to work on.
---

# Ticket

Account for every session's work on the cockpit before editing or running commands. The `require-ticket.sh` PreToolUse hook denies write-capable tools and shell commands until a card is registered.

Every board read and write below goes through `"$HOME/.cockpit/scripts/board-card"`.

## What the card's column allows the session to write

Once the card is registered, the column it sits in decides what kind of output is permitted. Check which column it is in rather than judging whether "refinement is done".

- **Backlog**: no refinement output at all. The ticket is captured, not committed - never draft validation steps or tech steps for it, and never advance it. A person pulls it into refinement when they decide to.
- **BR columns** (Ready for BR by AI, In BR by AI, Ready for BR, In BR): only BR output is allowed - validation steps for features, replication/validation steps for bugs, expected outcome for timeboxes, and questions to clarify scope. No tech steps, no file paths, no code snippets, no implementation proposals.
- **TR columns** (Ready for TR by AI, In TR by AI, Ready for TR, In TR): only TR output is allowed - tech steps and complexity estimation. No file edits; code appears only inside the tech steps written to the card; commands are limited to reading the codebase and the `board-card` calls the TR skill names.
- **In Dev or later**: implementation is allowed - file edits, code generation, running builds and tests.

`require-dev-status.sh` hard-gates file edits until In Dev.

## Workflow

### 1. Resolve the input to a cockpit card

If no input was supplied, ask which card the user is working on. Otherwise resolve the argument as one of:

1. **Card id** (`FEAT-n`, `BUG-n` or `TIME-n`) — read it once with `"$HOME/.cockpit/scripts/board-card" show <card-id> --json`, confirm its name and continue to the epic gate. Exit 3 means no such card: say so and stop. An `EPIC-n` id is an epic, not a card - inform the user and invoke the `/cockpit:epic:0:register` skill with the id instead of continuing the ticket flow. Stop this skill's execution.
2. **A Notion URL** — the board no longer lives in Notion. Ask for the card id and stop.
3. **Title, free text or any other URL** — delegate card creation to `/cockpit:ticket:0:new`, passing: title (from the text, or the page a URL names), type (from step 2.5), and epic (from step 2). A URL is reference material: it goes in the card's `## Context`, and nothing reads or writes the page it names.

Case 3 has no card to read until it creates one. Run step 2's points 1 to 4 and step 2.5 first, answering them from the person's text, then delegate. Read the card it creates once with `"$HOME/.cockpit/scripts/board-card" show <card-id> --json` - that read is the step 1 read every later step refers to - and carry on at step 3.

Handle epic ambiguity only in the epic gate; do not ask twice.

### 2. Enforce the epic gate

Take the `epic` field from the step 1 read - never a second read of the card step 1 already read. A populated field goes to point 5. An empty one establishes the larger outcome before proceeding:

1. Answer these from the ticket itself - its title, body and `## Context` section - never in chat:
   - What larger outcome is this task part of?
   - Who asked for it, and what do they actually need?
   - Why now, and what breaks if it is not done?
   - Does an existing epic already cover it?
2. Search for a matching epic: run `"$HOME/.cockpit/scripts/board-card" list --kind epic`. Each line is an epic id, its status, its session and its name. Only an epic whose status is not `Epic Done` is a candidate - a closed epic is never a valid home for a new ticket.
3. If an epic fits, note its id for linking after registration (step 4.1). **When two open epics share the ticket's project, the kind of work decides, never the closer name.** A project typically runs a dev epic and a delivery epic whose names differ by one word. Work whose output is a diff on the product goes to the dev epic; work whose output is reporting, ceremony, or client-facing process goes to the delivery epic. Work that is genuinely both goes to the dev epic, named alongside the sibling it was picked over.
4. When none fits, file the ticket under the closest open epic anyway and name the gap in the comment below. Creating an epic is never the gate's move.
5. A populated field is read for the epic's status, not only its presence. Find the linked epic's id in the same `list --kind epic` output - no epic record is read on its own.
   - **`Epic Done`** - the epic has closed. Pick a replacement by points 1 to 4 above, note its id for step 4.1 to write, and post which epic had closed and which one the ticket moved to on the ticket, following `~/.claude-shared/templates/raise-a-decision.md`.
   - **Any other status** - the epic is open. Carry on.

### 2.5. Enforce the type gate

Case 1 - take `type` from the step 1 read. Populated, carry straight on; empty, pick one and hold it for step 4.1 to write.

Case 3 - no card exists yet, so pick one and hand it to `/cockpit:ticket:0:new`, which writes it at creation.

Read the title and whatever body there is, and pick without asking:

- `Bug` when the work names delivered behaviour that contradicts what a Done ticket's validation steps promised.
- `Timebox` when it names the time it is allowed to run for.
- `Feature` for everything else.

Step 5 reports the pick either way.

### 3. Auto-name the session

Read `~/.claude-shared/templates/session-name.md` and build the name it gives a session holding a ticket - the epic in the bracket, the ticket name after it. The epic's name is the last column of its line in the step 2 listing.

Set it before ticket registration, so the rename gate clears first.

If the session is already named under that convention, it already matches what this step would build - leave it.

### 4. Register the ticket

Run exactly:

```sh
"$HOME/.cockpit/scripts/ticket-register" "<card-id>"
```

### 4.1. Write what the gates picked

Only case 1 writes here. A card the workflow created carries the epic and the type the gates picked from its creation - never write either again here.

For case 1, write the epic when the gate picked one - for an empty field by points 1 to 4, or when point 5 picked a replacement for a closed one:

```sh
"$HOME/.cockpit/scripts/board-card" set <card-id> epic <EPIC-n>
```

An open epic the gate found already linked is right - skip the epic half of this step.

A `Type` picked at step 2.5 for a card that arrived without one is written with `board-card set <card-id> type <Type>`.

### 4.5. Store work item type

After registration, store the work item type. Run exactly:

```sh
"$HOME/.cockpit/scripts/ticket-register-type" ticket "<session-name>" "<ticket-type>"
```

Where `<ticket-type>` is the card's `Type` lowercased (e.g. `feature`, `timebox`, `bug`). Use the same session name passed to auto-rename in step 3.

### 4.6. Advance to In BR by AI

If the card's current status is `Ready for BR by AI`, advance it by invoking the `cockpit:ticket:x:status` skill with target `In BR by AI`.

Go through that skill, never a bare `board-card walk`. Its Record model step writes `models.BR` only for a column its own walk lands on, and the BR skill's walk starts from `In BR by AI`, so no later walk lands there to write it.

If the status is anything else (card re-registered mid-flight or picked up from a later column), skip this step silently.

`Backlog` is explicitly one of those. Registering a session against a captured ticket does not commit it to refinement - only a human pull does, so the card stays put.

### 4.65. Take the claim

Registration takes the same claim `/cockpit:ticket:0:copilot` takes at its step 3.

Read the card's `session` (already in the step 1 read) and act on what it holds:

- **Empty** - claim it:

  ```sh
  "$HOME/.cockpit/scripts/board-card" claim <card-id>
  ```

  It takes `ticket-claim-lock` and writes this session's id onto the card. Exit 0 means it is yours. Exit 1 means a session on this machine got there first. Say so and leave the card alone - registration itself still succeeds.

- **Already this session's claim** - nothing to do. A re-registration after a context reset lands here.

- **Another session's claim** - leave it alone and say who holds it. Registration goes ahead; two sessions on one card is the person's to resolve, not this skill's to block.

The claim is held from here to `Done`. `cockpit:ticket:x:status` releases it on the hop that lands on `Done`, and the SessionEnd hook releases it if the session ends first.

### 4.7. Record board column

After registration (and any status advance), store the card's current board column:

```sh
"$HOME/.cockpit/scripts/ticket-register-column" "<current-status>"
```

Use the card's current status (e.g. `In BR by AI` after step 4.6, or whatever its status was when read in step 1).

### 4.7.1. Arm the board watcher

Arm the watcher here, once. Call the `Monitor` tool with:

- `command`: `"$HOME/.cockpit/scripts/ticket-watch-column" "<card-id>"`.
- `description`: `cockpit ticket column changes`.
- `persistent`: `true` - never a timeout.

Arming is best-effort. A watcher that exits at once with an error line leaves registration standing. Report the line, do not retry the arm, and carry on with the remaining steps.

### 4.75. Check for pre-existing PR

Run this step only for a card at `In Dev` or later, and never for a card this run created. A card before `In Dev` has no branch of its own: the branch the session started on belongs to its checkout, not to the ticket, and a PR on it is other work.

If the session is in a git repository with a GitHub remote, check whether the current branch already has an open pull request:

```sh
gh pr view --json url -q .url 2>/dev/null
```

If a PR URL is returned, read the card's `PRs` with `board-card show <card-id> PRs`. If it already holds that URL, leave it. Otherwise write it back with the new URL on a line of its own after whatever was there:

```sh
"$HOME/.cockpit/scripts/board-card" set <card-id> prs "<existing urls and the new one>"
```

If the command fails (no git repo, no GitHub remote, no open PR), skip silently.

### 4.9. Auto-assign sprint

If the card's current status is `Sprint Backlog` or later in the canonical column order (Sprint Backlog, Daily Plan, In Dev, In CR by AI, ...), follow `~/.claude-shared/templates/sprint-auto-assign.md`. It owns the opt-out for a repo that skips the sprint columns, and the assignment itself.

Skip this step if the card has not yet reached Sprint Backlog (still in refinement or Ready for Sprint).

### 5. Confirm

Report the registered card id and its epic. If this workflow created a card, also report what was created and that it entered at Ready for BR by AI.

When the epic gate had to pick, post which epic it picked and what decided it as a comment on the card, following `~/.claude-shared/templates/raise-a-decision.md`. The chat is not where it lands - nobody is reading it.

A type the gate picked is posted the same way, in its own comment.

### 6. Hand the card to the BR skill

When step 4.6 advanced the card to `In BR by AI`, invoke `/cockpit:ticket:1:br` - after every step above, never in place of one.

A run that skipped step 4.6 invokes nothing.
