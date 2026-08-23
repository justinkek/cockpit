---
name: cockpit:ticket:4:ready-for-cr
description: Push the session's branch, open a PR for its cockpit ticket, and link it - after the machine gates have already run. Fires on clean gates.
---

# ready-for-cr

Push the branch, open a PR for the registered cockpit ticket, and link it to the ticket. Invoked two ways: by the dev skill once the machine gates come back clean, and by the user saying `/ready-for-cr`.

The card is already at `In CR by AI` by the time this runs - finishing dev puts it there, and landing on the column runs the machine gates against the branch as it stands on the machine. This skill publishes a branch whose findings have already been fixed, and then carries the card to `Ready for CR` - the last column before the human pull.

Read `~/.claude-shared/templates/pull-request-to-ticket.md` before opening the pull request.

## Board constants

- Board ids - read with `"$HOME/.claude-shared/cockpit-board-id" get <key>`, following `~/.claude-shared/templates/board-ids.md`. This skill needs `tickets-data-source`.

## Workflow

### 1. Guard: valid source status

Read the session marker at `~/.local/state/claude-ticket-sessions/$CLAUDE_SESSION_ID.ticket` to get the ticket URL.

Read the ticket's current `Status` with `"$HOME/.claude-shared/ticket-read" <ticket-url> Status`, falling back to `notion-fetch` on a non-zero exit. Only proceed if the ticket is at `In Dev` or `In CR by AI`. If it is at an earlier column, block and name the current status. If it is already at `Ready for CR` or later, report that and stop.

`In CR by AI` is the expected one - finishing dev advances the card and runs the gates. `In Dev` is accepted so a card that never got advanced is not stranded: walk it to `In CR by AI` with the `cockpit:ticket:x:status` skill first, which runs the gates. Carry on to step 2 only when every finding they named is fixed - a finding still open leaves the card at `In CR by AI` and stops this skill, the same as step 6 does.

### 2. Check git state

Run these checks in order:

1. `git branch --show-current` - get the current branch name. If on `main` or `master`, block: "Cannot create a PR from the default branch." Nothing in a project's `./AGENTS.md` overrides this - PRs require a feature branch.
2. `git status --porcelain` - check for uncommitted changes. If any exist, block: "Uncommitted changes found - commit first (`/commit`)."
3. `git rev-parse --abbrev-ref @{u} 2>/dev/null` - check if upstream tracking exists.
4. If tracking exists: `git log @{u}..HEAD --oneline` - check for unpushed commits.

### 3. Push if needed

If the branch has commits ahead of remote (or no upstream at all):

```sh
git push -u origin <branch>
```

### 4. Create or find PR

Check for an existing PR on this branch:

```sh
gh pr list --head "$(git branch --show-current)" --json url,state --jq '.'
```

- **PR exists** - note its URL, skip creation.
- **No PR** - create a PR:

```sh
gh pr create \
  --title "<type>(<scope>): <short description>" \
  --body "<the body>"
```

Title it and write its body as `~/.claude-shared/templates/pull-request-to-ticket.md` says.

### 4.5. Post the open findings on the PR

Read the `Machine gates` toggle under the ticket's `## Details` and take every line opening with `unfixed -`. Each carries the `path/to/file.ext:123` the review reported, so it goes beside the line it is about rather than into the conversation tab - one call per finding:

```sh
gh api repos/<owner>/<repo>/pulls/<number>/comments --method POST \
  --field path=<path> --field line=<line> --field side=RIGHT \
  --field commit_id=<head sha> --field body=<the finding>
```

A finding with no `path:line` has nothing to anchor to - post those together with `gh pr comment <pr-url> --body "<one line per finding>"`.

No such line means the gates left nothing open - post nothing.

### 5. Link PR to ticket

Follow `~/.claude-shared/templates/pull-request-to-ticket.md`.

### 5.5. Arm the checks watcher

Call the `Monitor` tool with `command` set to `"$HOME/.claude-shared/pr-watch-checks" "<pr-url>"`, `description` `pull request checks`, and `persistent` false - the script ends itself once every check has concluded.

Arming is best-effort. A failure to arm leaves the PR up and the card where it is: report the line and carry on with step 6.

The watcher prints one line, in one of two shapes. A passed line is a report - take it into account and carry on. A failed line names the checks and the skill that reopens dev: invoke it, fix them, and the backward move records the bounce on its own. Neither is a user message, and the active thread finishes first.

### 5.6. Arm the base watcher

Call the `Monitor` tool with `command` set to `"$HOME/.claude-shared/pr-catch-up-with-base"`, `description` `pull request behind its base`, `persistent` true, and `PR_CATCH_UP_INTERVAL` in the environment - the script polls on that cadence and the pull request stays open for as long as review takes.

Arming is best-effort, as in step 5.5.

The script prints nothing while the branch already carries its base, so a silent watcher is the normal case rather than a failed arm. A line it does print names which operation ran; nothing is invoked in response.

### 6. Advance to Ready for CR

Once the gates have run and the PR is up, walk the card on with the `cockpit:ticket:x:status` skill targeting `Ready for CR`, and stop there - `In CR` is the human pull.

Only on a PR that is actually up. A step that blocked - no push, no PR, a gate finding still open - leaves the card at `In CR by AI`.

### 7. Report

Confirm:

- PR URL (created or existing), and the move to `Ready for CR`
- What the machine gates found before the push, what was fixed in response, and what went onto the PR as still open
