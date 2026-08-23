# Closing a ticket out on Done

Read this on the hop that lands the card on `Done` - and on a card found there, which a person dragged and left every one of these outstanding. Nothing here fires on any other column.

## Release the claim

Clear `Agent: Session Id` in the same `update_properties` call that sets the status (and on the source ticket when the session has one), and release the local lock:

```
"$HOME/.claude-shared/ticket-claim-lock" release <page-id>
```

Both: the lock stops two sessions on this machine taking the same card, the property tells a person and any session elsewhere that it is taken.

`Done` is the only hop that ends the claim - never a refinement column boundary. The other end is the session itself: the SessionEnd hook releases whatever it was still holding.

## Give the worktree back

Leave the worktree first when this session entered it (`ExitWorktree` with `action: "keep"` - a silent no-op in any other session), then:

```
"$HOME/.claude-shared/worktree-give-back" <worktree-path> <branch>
```

It runs the checks and then removes both, so there is nothing to verify first and no raw `git worktree remove` or `git branch --delete --force` to reach for - both are denied. It refuses unless every one of these holds:

- the path is a worktree this repository knows, and is not the main checkout;
- `git -C <worktree-path> status --porcelain` prints nothing on exit 0;
- the branch is neither the default branch nor checked out in another worktree;
- the branch is an ancestor of `origin/<default-branch>`, **or** its pull request is `MERGED` and its `headRefOid` still matches `git rev-parse <branch>`.

That last pair is why comparing content is not one of them. A squash merge lands the work as one new commit, so `git branch --merged origin/<default-branch>` never lists the branch and `ExitWorktree` with `action: "remove"` refuses on the commit count - and the moment a later commit touches the same files, the diff against main is non-empty even though the work is on main.

**Refused** - the worktree and the branch stay, and the exit line names the check that failed. Never `discard_changes`: a card reaching Done is not a licence to throw away work nobody has looked at.

## Bring the main checkout forward

Merging into the default branch happens on GitHub, so nothing here merges: the checkout only takes what the remote already holds. The checkout is not necessarily the directory the session is in, so resolve it before the removal above - a session launched inside the worktree has none to run from afterwards:

```

git rev-parse --path-format=absolute --git-common-dir

```

That names the main checkout's `.git`; its parent is the checkout. Reading the session's own directory instead is how a walk that kept the worktree reports on the ticket branch and pulls nothing.

```

git -C <main-checkout> branch --show-current

```

Only when that answers with the default branch:

```

git -C <main-checkout> pull --ff-only

```

- **Nothing printed** - the checkout is on no branch at all, which the command reports by saying nothing and succeeding. Say so and leave it; empty output is never a reason to carry on to the pull.
- **Not on the default branch** - say which branch it is on and leave it there. Checking one out moves a working tree nobody asked you to touch.
- **The pull refuses** - say what it printed. Only a non-fast-forward reading means the checkout carries commits that never reached the remote; a dirty working tree, a branch with no upstream and a failed fetch each refuse for their own reason, and reporting any of them as unpushed commits is a false statement about the user's repo. Never `--force`, and never a merge to reconcile the two.
- **Say where it landed** - name the branch and the commit it moved to, in the same run report as the give-back.

## Make it live

A checkout that generates the live config has moved on disk without coming into effect, so the pull is only half the hop. Skip this when the pull moved nothing. Otherwise ask whether this is that kind of checkout:

```

git -C "$HOME/.claude-shared" rev-parse --path-format=absolute --git-common-dir

```

The same answer as the main checkout's own `--git-common-dir` above means this repo generates the live profiles. A different answer, or a failure, means it generates nothing - say nothing and carry on.

```

"$HOME/.claude-shared/sync.sh" --apply

```

No check pass first and no question: the pull already moved, and the apply names the concerns it found in sync alongside the ones it wrote. It needs no assume-yes flag either - its own prompt answers itself when there is no terminal, which is every agent session.

- **Say what came into effect** - name each concern the apply wrote, in the same run report as the pull.
- **A concern that refused** - name it and what it printed. The walk carries on; a card reaching Done is not held up by one concern.

## Record usage

Safe to repeat: both totals are recomputed from the session usage files and overwritten, so a second run writes the same numbers.

```

"$HOME/.claude-shared/ticket-done-usage" <ticket-url>

```

Parse the JSON output (`cost_usd`, `tokens_k`) and update the ticket via `notion-update-page` (`update_properties`):

- `Session Cost (USD)` ← `cost_usd` (if not null)
- `Session Tokens (k)` ← `tokens_k`

If `cost_usd` is `null`, do not set `Session Cost (USD)` - leave the property blank to signal that cost data was unavailable.

```

```
