---
name: ticket:7:done
description: Move the session's cockpit ticket to Done.
---

# done

Move the registered cockpit ticket to the `Done` column. Two things trigger it: the user, and the watcher's line when a person dragged the card to Done. In the second case the card is already there, so the status skill runs the close-out without moving anything.

## Workflow

### 1. Guard: valid source status

`"$HOME/.cockpit/scripts/board-card" show <id> Status` reads the card's column, and the column decides whether the walk to `Done` runs:

- **The one the card's walk puts right before `Done`** - `Ready for Validation`, unless the project's `## Ticket walk skip` removes it - carries on to step 2.
- **`Done`** is the close-out of a card a person dragged there: it skips the merge check and goes straight to step 3.
- **Any other column** blocks: name it, and say that each column between it and `Done` is a person's pull.

### 2. Check the pull request merged

A Timebox whose `### Timebox output`, read with `"$HOME/.cockpit/scripts/board-card" show <id> --section "Timebox output"`, says it produced no code has no pull request to check, and goes straight to step 3.

Every other card reads its pull requests, and where each one stands:

```sh
"$HOME/.cockpit/scripts/board-card" show <id> PRs
gh pr view <url> --json state --jq .state
```

An empty `PRs`, or any URL answering other than `MERGED`, is work that has not reached the default branch. Name what is missing - no pull request at all, or which one and its state - and ask the person whether to walk to `Done` anyway. Walk only on their yes.

### 3. Walk to Done

Invoke the `cockpit:ticket:x:status` skill with target `Done`. The skill handles the ordered walk, its date stamps, and the close-out with its usage recording.
