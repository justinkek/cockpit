---
name: ticket:7:done
description: Move the session's cockpit ticket to Done.
---

# done

Move the registered cockpit ticket to the `Done` column. Two things trigger it: the user, and the watcher's line when a person dragged the card to Done. In the second case the card is already there, so the status skill runs the close-out without moving anything.

Read the card's open comments before step 3 walks it, with `"$HOME/.cockpit/scripts/board-card" comments <id>`, by `~/.claude-shared/templates/page-comments.md`. Every gate is behind a card on its way to `Done`, so a decision a session raised and nobody answered is resolved there. Any other comment still open is feedback the closed card would carry unread: name it and ask the person whether to close the card out anyway, as step 2 asks about work that has not merged.

## Workflow

### 1. Guard: valid source status

`"$HOME/.cockpit/scripts/board-card" show <id> Status Type "Dependent on"` reads the card's column, its type and its sub-tickets. The type and the sub-tickets pick the check step 2 makes, and the column decides whether the walk to `Done` runs:

- **The one the card's walk puts right before `Done`** - `Ready for Validation`, unless the project's `## Ticket walk skip` removes it - carries on to step 2.
- **`Done`** is the close-out of a card a person dragged there: it skips the merge check and goes straight to step 3.
- **Any other column** blocks: name it and the column the card has to reach first, and stop.

### 2. Check the work merged

A Timebox whose `### Timebox output`, read with `"$HOME/.cockpit/scripts/board-card" show <id> --section "Timebox output"`, says it produced no code has no pull request to check, and goes straight to step 3.

A split parent, whose `Dependent on` lists its sub-tickets, has no pull request of its own - the sub-tickets carry the code. It reads each one's column with `"$HOME/.cockpit/scripts/board-card" show <sub-ticket id> Status` instead, and a sub-ticket short of `Done` is a part still open.

Every other card reads its pull requests, and where each one stands:

```sh
"$HOME/.cockpit/scripts/board-card" show <id> PRs
gh pr view <url> --json state --jq .state
```

An empty `PRs`, or any URL answering other than `MERGED`, is work that has not reached the default branch. Name what is missing - no pull request at all, which one and its state, or which sub-ticket and its column - and ask the person whether to walk to `Done` anyway. Walk only on their yes.

### 3. Walk to Done

Invoke the `cockpit:ticket:x:status` skill with target `Done`. The skill handles the ordered walk, its date stamps, and the close-out with its usage recording.
