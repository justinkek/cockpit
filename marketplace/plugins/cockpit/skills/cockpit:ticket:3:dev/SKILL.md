---
name: cockpit:ticket:3:dev
description: Start dev on the registered ticket - advances to In Dev and unlocks file edits. Use when the require-dev-status hook blocks an edit.
---

# dev

Start development on the session's registered ticket. Advances the ticket to In Dev and unlocks the file-edit gate.

Read `~/.claude-shared/templates/cockpit-dev-gates.md` before the first edit.

Read `~/.claude-shared/templates/coding-conventions.md` before the first edit.

Read `~/.claude-shared/templates/cockpit-cross-board.md` when a source ticket is registered alongside the stub.

Read the ticket's open comments before the first edit, following `~/.claude-shared/templates/page-comments.md`.

## Prerequisite

A ticket must be registered for this session (marker file at `~/.local/state/claude-ticket-sessions/<session_id>.ticket`). If no ticket is registered, stop and tell the user to register one first (`/cockpit:ticket:0:register`).

Then check the ticket's outcome is not already in the codebase, following `~/.claude-shared/templates/already-done-check.md`. A hit stops dev before the status advance and before edits unlock.

## Workflow

1. **Check current status.** Fetch the registered ticket. If the status is already `In Dev` or later in the board walk, skip step 3 — there is nothing to walk — and go straight to step 4. Never stop here: a card claimed by `/cockpit:ticket:0:copilot` arrives already at `In Dev`, and so does one a person dragged there by hand, so stopping would leave file edits locked for the whole session.

2. **Refuse on a split parent.** If the ticket's `Dependent on` relation is populated, it has no Tech Steps and Complexity 0 - there is nothing here to build. Name why, list the sub-tickets, and tell the user to open a new session registered on the one they want. One ticket per session, so cost attributes to the part actually being built. Stop.

3. **Advance to In Dev.** Use the `cockpit:ticket:x:status` skill to walk the board from the current status to `In Dev`. This handles intermediate hops, date stamps, and skip-list filtering.

4. **Unlock file edits.** Run:

   ```
   "$HOME/.cockpit/scripts/ticket-status-confirm" dev
   ```

5. **Enter the ticket's worktree.** Refresh the remote reference first - the call below may branch from `origin/<default-branch>`, so it takes whatever the last fetch left behind:

   ```
   git fetch origin
   ```

   Read its exit status. A non-zero one means the remote reference is still whatever the last successful fetch left, and the call below cuts the branch off exactly that reference. So name what the fetch printed and stop - carrying on from a base of unknown age is the user's call, not the agent's. Never cut the branch on a failed fetch.

   Then call `EnterWorktree` with `name` set to the branch this ticket's work belongs on, in the same conventional form as a commit message's subject - `feat/agents-use-worktrees`. The diff is then written off the main checkout.

   The call names the branch after the worktree with a prefix of its own, so rename it to the name you passed:

   ```
   git branch --move <type>/<short-description>
   ```

   A branch of that name an earlier session on this ticket left behind makes the rename fail. Say which branch is in the way, and stop - the pull request lookup is by branch name, so carrying on under the auto-prefixed name opens a second pull request for the one ticket.

   Worktree and branch then read as the same name wherever either is shown. Skip the call and the rename when the session is already in a worktree - the call refuses a second create, and the one it is in is the one it claimed. The fetch above still runs, because a branch cut on the default setting starts from what it refreshes.

   Where the new branch starts is set by `worktree.baseRef`, which nothing here pins - `origin/<default-branch>` on its default, the local HEAD when it is set the other way. So read the base off the branch rather than name a reference the branch may not have been cut from. In a repo where commits land on main directly, check the main checkout for commits that never left it before building on that base:

   ```
   git merge-base HEAD main
   ```

   ```
   git log <the commit it printed>..main --oneline
   ```

   Two commands, because the worktree isolation gate refuses a command substitution - it cannot verify where the inner command points.

   Anything listed is missing from the worktree. Say so and let the user decide whether to push it first - never rebase or cherry-pick it in yourself.

6. **Read the tech steps off the ticket.** Fetch the ticket page and read `## Tech Steps` from that response. When this session drafted them during technical refinement, that draft is not the source - a person can amend the steps up to the moment the card lands In Dev, and the amendment exists only on the page. When the fetched steps differ from the drafted ones, say what changed before writing any code.

7. **Report.** Confirm dev is active and file edits are unlocked.

8. **Start implementing.** Immediately begin working on the tech steps read in step 6. Do not wait for a follow-up prompt - start writing code.

9. **Advance when the tech steps are built and committed.** Invoke the `cockpit:ticket:x:status` skill with target `In CR by AI`. Landing there runs the machine gates against the branch as it stands on the machine, so a finding is fixed before anything is published. Do not wait to be asked - a session that stops at `In Dev` leaves a reviewed-by-nobody branch behind.

   Go through that skill, never a direct `Status` write: landing on the column is what fires its step 7, and that step is the only thing that runs the review. A card moved by hand or by a property update arrives in the column with nothing run, and the session cannot tell the difference afterwards.

   The review is `/code-review low`, which this session runs itself. Name the level every time - left off, it reuses whatever a person last typed. The billed cloud form (`/code-review ultra`) is the user's to launch and is never a next step handed back to them.

10. **Publish once the gates are clean.** Invoke `/cockpit:ticket:4:ready-for-cr`, which pushes, opens the PR and links it to the ticket. Do not wait to be asked - a reviewed branch that never leaves the machine is not ready for anyone.

    Not when a gate came back with an unfixed defect - nothing published carries one they already named. Say what is outstanding and stop. A divergence from the tech steps is not a defect and holds nothing back: `status-machine-gates.md` says where it goes instead.

    **Clean means every finding is fixed, not that a further pass came back empty.** Publish on the fixes; never re-run the gates over them.

    That skill lands the card on `Ready for CR` once the PR is up. `In CR` is the human pull.
