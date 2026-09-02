---
name: cockpit:ticket:0:register
description: Register the cockpit ticket this session works on — resolve or create the ticket stub, raise or link an epic if it has none, then unlock the session's edit gate. Use at work start, when the require-ticket hook blocks an edit or command, or when the user says "ticket", "register ticket", or pastes a ticket URL to work on.
---

# Ticket

Account for every session's work on the cockpit before editing or running commands. The `require-ticket.sh` PreToolUse hook denies write-capable tools and shell commands until a ticket is registered.

## Board constants

Read each with `"$HOME/.cockpit/scripts/cockpit-board-id" get <key>`, following `~/.claude-shared/templates/board-ids.md` - it covers the key list, the unrecorded case, and every exit code.

This skill needs: `page`, `tickets-data-source`, `epics-data-source`, `projects-data-source`, `sprints-view`.

Exit 3 on the first of them is answered before step 1.

## What the card's column allows the session to write

Once the ticket is registered, the column it sits in decides what kind of output is permitted. Check which column it is in rather than judging whether "refinement is done".

- **Backlog**: no refinement output at all. The ticket is captured, not committed - never draft validation steps or tech steps for it, and never advance it. A person pulls it into refinement when they decide to.
- **BR columns** (Ready for BR by AI, In BR by AI, Ready for BR, In BR): only BR output is allowed - validation steps for features, replication/validation steps for bugs, expected outcome for timeboxes, and questions to clarify scope. No tech steps, no file paths, no code snippets, no implementation proposals.
- **TR columns** (Ready for TR by AI, In TR by AI, Ready for TR, In TR): only TR output is allowed - tech steps, complexity estimation, and risks. No file edits, no code generation, no running commands beyond reading the codebase to inform the tech steps.
- **In Dev or later**: implementation is allowed - file edits, code generation, running builds and tests.

`require-dev-status.sh` hard-gates file edits until In Dev.

## Workflow

### 0. Resolve the connected user

Run `"$HOME/.cockpit/scripts/cockpit-cache-query" user-id`. A non-zero exit means the cache is missing or has no such key - fall back to calling `notion-fetch` with `id: "self"`. Store the user ID for use in stub creation (step 1, cases 2 and 3) to auto-assign the ticket.

### 1. Resolve the input to a cockpit ticket

If no input was supplied, ask which ticket the user is working on. Otherwise resolve the argument as one of:

1. **Cockpit ticket URL** — fetch the page, verify its `parent-data-source` matches the Tickets data source (the `tickets` id). If it matches, confirm its title and continue to the epic gate. If it does not match, check whether the `parent-data-source` matches the Epics data source (the `epics` id). If it's an epic, inform the user and invoke the `/cockpit:epic:0:register` skill with the URL instead of continuing the ticket flow. Stop this skill's execution. If it matches neither data source (e.g. a Notion URL from a different board), treat it as case 2 below.
2. **External URL** — resolve the source ticket title (fetch when readable, otherwise ask). The type gate below settles the type. Delegate stub creation to `/cockpit:ticket:0:new`, passing: title, type (from step 2.5), source URL, user ID (from step 0), and epic (from step 2). The skill creates the page with body content and returns the URL. Do not copy the source content into the stub — the stub is a tracking card only. All content (BR, TR, dev) will be written to the source ticket.
3. **Title or free text** — delegate stub creation to `/cockpit:ticket:0:new`, passing: title (from the free text), type (from step 2.5), user ID (from step 0), and epic (from step 2). No source URL.

Handle epic ambiguity only in the epic gate; do not ask twice.

### 2. Enforce the epic gate

Take the `Epic` relation from the step 1 fetch - never a second fetch of the page step 1 already read. A populated relation goes to point 5. An empty one establishes the larger outcome before proceeding:

1. Answer these from the ticket itself - its title, body and `## Context` toggle - never in chat:
   - What larger outcome is this task part of?
   - Who asked for it, and what do they actually need?
   - Why now, and what breaks if it is not done?
   - Does an existing epic already cover it?
2. Search for a matching epic: run `"$HOME/.cockpit/scripts/cockpit-cache-query" epics`. It returns open epics only - a closed epic is never a valid home for a new ticket, and the Ticket Kanban hides tickets filed under one - and it warns on stderr when the list is more than a day old, which is when to run `/cockpit:cache` and ask again. Query the Epics data source via `query-data-sources` when the script exits non-zero, when it returns an empty list, or when no epic in it matches. If the query quota is exhausted, pick from the list on hand and say in the comment below that it could not be refreshed.
3. If an epic fits, note its URL for linking after registration (step 4.1). **When two open epics share the ticket's project, the kind of work decides, never the closer name.** A project typically runs a dev epic and a delivery epic whose names differ by one word. Work whose output is a diff on the product goes to the dev epic; work whose output is reporting, ceremony, or client-facing process goes to the delivery epic. Work that is genuinely both goes to the dev epic, named alongside the sibling it was picked over.
4. When none fits, file the ticket under the closest open epic anyway and name the gap in the comment below. Creating an epic is never the gate's move.
5. A populated relation is read for the epic's status, not only its presence. Run `"$HOME/.cockpit/scripts/cockpit-cache-query" epic-statuses` and find the linked epic's url in what it returns. No page is fetched: the cache already carries every epic's status, and `epics` is the same list with the closed ones dropped.
   - **`Epic Done`** - the epic has closed. Pick a replacement from `epics` by points 1 to 4 above, note its URL for step 4.1 to write, and post which epic had closed and which one the ticket moved to on the ticket, following `~/.claude-shared/templates/raise-a-decision.md`.
   - **Any other status** - the epic is open. Carry on.
   - **Absent** - the cache predates the epic. Carry on, and say `/cockpit:cache` is due.

### 2.5. Enforce the type gate

Case 1 - take `Type` from the step 1 fetch. Populated, carry straight on; empty, pick one and hold it for step 4.1 to write.

Cases 2 and 3 - no card exists yet, so pick one and hand it to `/cockpit:ticket:0:new`, which writes it at creation.

Read the title and whatever body there is, and pick without asking:

- `Bug` when the work names delivered behaviour that contradicts what a Done ticket's validation steps promised.
- `Timebox` when it names the time it is allowed to run for.
- `Feature` for everything else.

Step 5 reports the pick either way.

### 3. Auto-name the session

Read `~/.claude-shared/templates/session-name.md` and build the name it gives a session holding a ticket - the epic in the bracket, the ticket name after it.

Set it before ticket registration, so the rename gate clears first.

If the session is already named under that convention, it already matches what this step would build - leave it.

### 4. Register the ticket

Run exactly:

```sh
"$HOME/.cockpit/scripts/ticket-register" "<cockpit-ticket-url>"
```

### 4.1. Write what the gates picked

If the epic gate (step 2) identified an epic for a newly created stub, link it now via `notion-update-page` (`update_properties`, set `Epic` to the epic's URL).

For case 1 (existing cockpit ticket), write the epic only when point 5 picked a replacement for a closed one. A relation the gate left alone is already right - skip the epic half of this step.

A `Type` picked at step 2.5 for a card that arrived without one is set in that same call. A stub the workflow created carries the gate's pick already, written at creation - never overwrite it here.

### 4.5. Store work item type

After registration, store the work item type. Run exactly:

```sh
"$HOME/.cockpit/scripts/ticket-register-type" ticket "<session-name>" "<ticket-type>"
```

Where `<ticket-type>` is the ticket's `Type` property lowercased (e.g. `feature`, `timebox`, `bug`). Use the same session name passed to auto-rename in step 3.

### 4.6. Register source ticket (case 2 only)

If the ticket was created from an external URL (case 2), register the source ticket for this session:

```sh
"$HOME/.cockpit/scripts/ticket-register-source-ticket" "<source-ticket-url>"
```

Then read the source ticket's `parent-data-source`. When the cockpit cache already holds a `project_boards` entry under that `collection://` URL **with a non-empty `statuses` list**, take its `Status` options from there and make no call. A board the cache does not have, and one whose cached `statuses` list is empty, are both fetched with `notion-fetch` on that data source URL - an empty list is what a board with no `Status` property was recorded as, and it is indistinguishable from one that has since gained one. Either way, those options are what the `cockpit:ticket:x:status` skill maps cockpit column transitions onto.

After discovering the schema, write the project board to the cockpit cache at `~/.local/state/cockpit/cache.json`. This is the one step that opens the file rather than asking `cockpit-cache-query` for a key, because it writes the whole file back - and it opens it **with the Read and Write tools, not Bash**: `redirect-state-to-read-write.sh` hard-denies a shell read or write under `~/.local/state/`. Read the existing cache (if any), add or update the entry under `project_boards` keyed by the data source's `collection://` URL, and write the file back. Include the board name and its `Status` select options. Create the directory with `mkdir -p` if needed.

If the source ticket's data source has no `Status` select property, note that source status sync will be skipped for this session (still cache the board entry with an empty `statuses` array).

Skip this step entirely for cases 1 and 3 (no source ticket).

### 4.6. Advance to In BR by AI

If the ticket's current Status is `Ready for BR by AI`, advance it to `In BR by AI` via `notion-update-page` (`update_properties`).

If the status is anything else (ticket re-registered mid-flight or picked up from a later column), skip this step silently.

`Backlog` is explicitly one of those. Registering a session against a captured ticket does not commit it to refinement - only a human pull does, so the card stays put.

### 4.65. Take the claim

Registration takes the same claim `/cockpit:ticket:0:copilot` takes at its step 3.

Read the ticket's `Agent: Session Id` (already fetched in step 1) and act on what it holds:

- **Empty** - take the local lock, then write the claim:

  ```sh
  "$HOME/.cockpit/scripts/ticket-claim-lock" take "<page-id>"
  ```

  Exit 0 means it is yours: set `Agent: Session Id` to `<session id> @ <iso formatted datetime>` via `notion-update-page` (`update_properties`), and the same on the source ticket when the session has one. The session id is the name of the marker file written in step 4.

  Exit 1 means a session on this machine got there first. Say so and leave the property alone - registration itself still succeeds.

- **Already this session's claim** - nothing to do. A re-registration after a context reset lands here.

- **Another session's claim** - leave it alone and say who holds it. The user asked for this card by URL, so registration goes ahead; two sessions on one card is theirs to resolve, not this skill's to block.

A card claimed by `/cockpit:ticket:0:copilot` arrives here already carrying that skill's `claiming-<4 chars>` token, so this step is a no-op for it and its step 5 replaces the token as usual.

The claim is held from here to `Done`. `cockpit:ticket:x:status` releases it on the hop that lands on `Done`, and the SessionEnd hook releases it if the session ends first.

### 4.7. Record board column

After registration (and any status advance), store the ticket's current board column:

```sh
"$HOME/.cockpit/scripts/ticket-register-column" "<current-status>"
```

Use the ticket's current `Status` value (e.g. `In BR by AI` after step 4.6, or whatever the ticket's status was when fetched in step 1).

### 4.7.1. Arm the board watcher

Arm the watcher here, once. Call the `Monitor` tool with:

- `command`: `"$HOME/.cockpit/scripts/ticket-watch-column" "<ticket-page-id>"`, where `<ticket-page-id>` is the id from the ticket URL. When the session has a source ticket (case 2, registered at step 4.6), pass its page id as a second argument — a person moves whichever card is in front of them, and watching only the cockpit stub misses every move made on the source board.
- `description`: `cockpit ticket column changes`.
- `persistent`: `true` - never a timeout.

Arming is best-effort. A missing Keychain credential makes the watcher emit one `[ticket-watch] no credential` line and exit non-zero — registration still succeeds. Report the line, do not retry the arm, and carry on with the remaining steps.

### 4.75. Check for pre-existing PR

If the session is in a git repository with a GitHub remote, check whether the current branch already has an open pull request:

```sh
gh pr view --json url -q .url 2>/dev/null
```

If a PR URL is returned, update the ticket's `PRs` property via `notion-update-page` (`update_properties`). If the `PRs` property already has content, append the URL on a new line; otherwise set it to the URL.

If the command fails (no git repo, no GitHub remote, no open PR), skip silently.

### 4.8. Catch up to source ticket (case 2 only)

After recording the board column, check whether the source ticket's current status implies the cockpit stub should be further along than `In BR by AI`. The source ticket's status was already fetched in step 4.6 during schema discovery.

1. Map the source status to the nearest cockpit column with the table in `~/.claude-shared/templates/mirror-source-status.md`.

2. If the mapped cockpit column is ahead of the stub's current status (appears later in the canonical column order), invoke the `cockpit:ticket:x:status` skill to walk the stub forward to that column. The walk handles column recording, date stamping, and content gates at each hop.

3. If the mapped column is at or behind the stub's current status, no catch-up is needed — skip silently.

Skip this step entirely for cases 1 and 3 (no source ticket).

### 4.9. Auto-assign sprint

If the ticket's current Status is `Sprint Backlog` or later in the canonical column order (Sprint Backlog, Daily Plan, In Dev, In CR by AI, ...), follow `~/.claude-shared/templates/sprint-auto-assign.md`. It owns the opt-out for a repo that skips the sprint columns, and the assignment itself.

Skip this step if the ticket has not yet reached Sprint Backlog (still in refinement or Ready for Sprint).

### 5. Confirm

Report the registered ticket link and its epic. If this workflow created a stub, also report what was created and that it entered at Ready for BR by AI.

When the epic gate had to pick, post which epic it picked and what decided it as a comment on the ticket, following `~/.claude-shared/templates/raise-a-decision.md`. The chat is not where it lands - nobody is reading it.

A type the gate picked is posted the same way, in its own comment.

### 6. Hand the card to the BR skill

When step 4.6 advanced the card to `In BR by AI`, invoke `/cockpit:ticket:1:br` - after every step above, never in place of one.

A run that skipped step 4.6 invokes nothing.
