---
name: ticket:x:destock
description: End-of-day de-stocking - commit, push, draft PR, link to ticket, reconcile status. Use when wrapping up for the day or when the user says "destock", "de-stock", or "save my work".
---

# Destock

Save work in progress at the end of the day: commit, push, open a draft PR, link it to the cockpit ticket, and make sure the ticket status reflects reality.

Reference: the "De-stock at the end of the day" standard.

## Workflow

### 1. Check ticket registration

Take the ticket id from this session's `/cockpit:ticket:0:register` step, or Read the session marker at `~/.local/state/claude-ticket-sessions/<session id>.ticket` with the Read tool.

If neither gives one, tell the user to register a ticket first (`/cockpit:ticket:0:register`) and stop.

### 2. Read the ticket

Run `"$HOME/.cockpit/scripts/board-card" show <id> Name Status PRs` with the ticket id from step 1, and take:

- `Name` (ticket title)
- `Status` (current column)
- `PRs` (existing PR links, if any)
- The ticket id

### 3. Check git state

Run these checks in order:

1. `git branch --show-current` - get the current branch name. If on `main` or `master`, report "nothing to de-stock from the default branch" and stop.
2. `git status --porcelain` - check for uncommitted changes (staged or unstaged).
3. `git rev-parse --abbrev-ref @{u} 2>/dev/null` - check if upstream tracking exists.
4. If tracking exists: `git log @{u}..HEAD --oneline` - check for unpushed commits.
5. `gh pr list --head "$(git branch --show-current)" --json url,state --jq '.'`
   - check for an existing PR on this branch.

### 4. Commit if needed

If step 3.2 found uncommitted changes:

1. Follow the standard commit flow from `CLAUDE.md`:
   - `git status` (no `-uall`)
   - `git diff` (staged + unstaged)
   - `git log` (recent messages for style)
   - Draft a commit message following `<type>(<scope>): <short description>`
   - Stage the relevant files and commit
2. The commit uses the existing session conventions - the user reviews and approves the commit as normal.

### 5. Push if needed

If the branch has commits ahead of remote (or no upstream at all):

```sh
git push -u origin <branch>
```

### 6. Create or find PR

From step 3.5:

- **PR exists** - note its URL, skip creation.
- **No PR** - create a draft PR:

```sh
gh pr create --draft \
  --title "<ticket-name>" \
  --body "<the body>"
```

Follow `~/.claude-shared/templates/pull-request-to-ticket.md`, taking the ticket name from step 2 as the description.

### 7. Link PR to ticket

Follow `~/.claude-shared/templates/pull-request-to-ticket.md`.

### 8. Reconcile ticket status

If the ticket's current `Status` is behind `In Dev` in the board's column order, invoke the `cockpit:ticket:x:status` skill to advance it to `In Dev`.

If already at `In Dev` or beyond, skip.

### 9. Summarise problems and fixes

Write a structured summary of bug fixes to the ticket when the session included fix commits.

1. List branch commits: `git log main..HEAD --oneline`.
2. Filter for commits whose message starts with `fix(` (conventional commit type prefix). If none, skip this step entirely.
3. For each fix commit, use the commit message and session context to produce a structured entry:
   - `[problem]` - root cause
   - `[fix]` - what was done
   - `[earlier detection]` - how to catch sooner
   - `[prevention]` - how to prevent recurrence
4. Format the entries as a subsection:

```
### Session summary

- `[problem]` Root cause of first fix
- `[fix]` What was done
- `[earlier detection]` How to catch sooner
- `[prevention]` How to prevent recurrence

- `[problem]` Root cause of second fix
- `[fix]` What was done
- `[earlier detection]` How to catch sooner
- `[prevention]` How to prevent recurrence
```

5. Write it into `## Details` - creating the section at the end of the page when it does not exist - the way `~/.cockpit/skills/ticket:x:back-from-column/SKILL.md` says under "Writing under `## Details`". A `### Session summary` already there keeps its entries and gains the new ones.

### 10. Confirm

Report a summary:

- What was committed (if anything)
- What was pushed
- PR URL (created or existing)
- Ticket status (advanced or unchanged)
- Whether a session summary was written to the ticket
- Final line: "You're de-stocked."

If nothing needed doing (clean tree, pushed, PR exists), just confirm: "Already de-stocked - nothing to do."
