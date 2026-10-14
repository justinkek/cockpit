---
name: ticket:4:ready-for-cr
description: Push the session's branch, open a PR for its cockpit ticket, and link it - after the machine gates have already run. Fires once the gates leave no defect open.
---

# ready-for-cr

Push the branch, open a PR for the registered cockpit ticket, and link it to the ticket. Invoked three ways: by the dev skill and by the status skill's step 7 once the machine gates leave no defect open, and by the user typing `/ready-for-cr`.

The card is already at `In CR by AI` by the time this runs - finishing dev puts it there, and landing on the column runs the machine gates against the branch as it stands on the machine. This skill publishes a branch whose defects have already been fixed, and then carries the card to `Ready for CR` - the last column before the human pull.

Read `~/.claude-shared/templates/pull-request-to-ticket.md` before opening the pull request.

## Workflow

### 1. Guard: valid source status

Take the card id from this session's `/cockpit:ticket:0:register` step, or Read `~/.local/state/claude-ticket-sessions/<session id>.ticket` with the Read tool.

Read the ticket's current `Status` with `"$HOME/.cockpit/scripts/board-card" show <id> Status`. Only proceed if the ticket is at `In Dev` or `In CR by AI`. If it is at an earlier column, block and name the current status. If it is already at `Ready for CR` or later, report that and stop.

`In CR by AI` is the expected one - finishing dev advances the card and runs the gates. `In Dev` is accepted so a card that never got advanced is not stranded: walk it to `In CR by AI` with the `cockpit:ticket:x:status` skill first, which runs the gates. Carry on to step 2 unless they left a finding still open that is a defect - an unfixed divergence from the tech steps does not hold the publish (`~/.claude-shared/templates/status-machine-gates.md`). A defect still open leaves the card at `In CR by AI` and stops this skill, the same as step 6 does.

### 2. Check git state

Run these checks in order:

1. `git branch --show-current` - get the current branch name. If on `main` or `master`, block: "Cannot create a PR from the default branch." Nothing in a project's `./AGENTS.md` overrides this - PRs require a feature branch.
2. `git status --porcelain` - check for uncommitted changes. If any exist, block: "Uncommitted changes found - commit first (`/commit`)."
3. Settle the base the PR publishes against. Once a PR is open on this branch, the base is that PR's own, which `gh pr list --head <branch> --json baseRefName --jq '.[0].baseRefName // empty'` prints - the same base `pr-catch-up-with-base` keeps the branch on. With no PR open, it is the branch the user named if they chose to stack on it at this check, and the default branch otherwise.
4. `git fetch origin <base>`, then `git log --no-merges origin/<base>..HEAD --oneline` - check the branch carries only this ticket's work. The PR publishes every commit this lists, whether the machine gates reviewed it or not, and a branch cut from the local HEAD carries whatever that HEAD held. `--no-merges` leaves out the commit `pr-catch-up-with-base` makes when it merges the base into a reviewed PR. If it lists a commit that is not this ticket's work, name those commits and stop before the push. Whether to stack the PR on the branch they came from, or wait for that branch to merge, is the user's call.
5. `git rev-parse --abbrev-ref @{u} 2>/dev/null` - check if upstream tracking exists.
6. If tracking exists: `git log @{u}..HEAD --oneline` - check for unpushed commits.

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
  --base <base> \
  --title "<type>(<scope>): <short description>" \
  --body "<the body>"
```

`<base>` is the one step 2 settled, so the PR carries exactly the commits that check listed. Title it and write its body as `~/.claude-shared/templates/pull-request-to-ticket.md` says.

### 4.5. Post the open findings on the PR

Read the `### Machine gates` subsection under the ticket's `## Details`, from `"$HOME/.cockpit/scripts/board-card" show <id> --section "Machine gates"`, and take every line opening with `unfixed -`. Each carries the `path/to/file.ext:123` the review reported, so it goes beside the line it is about rather than into the conversation tab - one call per finding:

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

Call the `Monitor` tool with `command` set to `"$HOME/.cockpit/scripts/pr-watch-checks" "<pr-url>"`, `description` `pull request checks`, and `persistent` false - the script ends itself once every check has concluded.

Arming is best-effort. A failure to arm leaves the PR up and the card where it is: report the line and carry on with step 6.

The watcher prints one line, in one of two shapes. A passed line is a report - take it into account and carry on. A failed line names the checks and the skill that reopens dev: invoke it, fix them, and the backward move records the bounce on its own. Neither is a user message, and the active thread finishes first.

### 5.6. Arm the base watcher

Call the `Monitor` tool with `command` set to `"$HOME/.cockpit/scripts/pr-catch-up-with-base" --every 300`, `description` `pull request behind its base`, and `persistent` true - the script polls every 300 seconds, and the pull request stays open for as long as review takes. Pass the interval as that argument rather than an environment variable in front of the command: the allowlist matches the script's path at the start of the command, and without an interval the script runs one pass and exits.

Arming is best-effort, as in step 5.5.

The script prints nothing while the branch already carries its base, so a silent watcher is the normal case rather than a failed arm. A line it does print names which operation ran; nothing is invoked in response.

### 6. Advance to Ready for CR

Once the gates have run and the PR is up, walk the card on with the `cockpit:ticket:x:status` skill targeting `Ready for CR`, and stop there - `In CR` is the human pull.

Only on a PR that is actually up. A step that blocked - no push, no PR, a gate finding still open that is a defect as step 1 reads it - leaves the card at `In CR by AI`. A finding step 1 let through is already on the PR from step 4.5 and holds nothing here.

### 7. Report

Confirm:

- PR URL (created or existing), and the move to `Ready for CR`
- What the machine gates found before the push, what was fixed in response, and what went onto the PR as still open
