## Commits

Commit directly via `/cockpit:ticket:4:commit` - never suggest a message for the user to copy-paste. The skill owns format, atomicity, and guardrails.

## Worktrees

Dev on a ticket happens in that ticket's own worktree, never in the main checkout. `/cockpit:ticket:3:dev` enters one, the status walk gives it back on the hop that lands on Done, and `require-dev-status.sh` refuses an edit made from the main checkout.

A session that ends still inside its worktree keeps it, a copilot session with nobody to ask included.

Two sessions in one checkout share its branch, so the second to start dev moves the first onto a branch that is not its own.

## BR and TR output standards

Invoke `/cockpit:ticket:1:br` for BR work and `/cockpit:ticket:2:tr` for TR work - each carries its own format rules, examples and self-check. Auto-invoke on entry to the matching by-AI column.

## Ticket page template

When writing ticket content on the cockpit, read `~/.claude-shared/templates/ticket-page.md` first.

## Cockpit - operating contract

Read `~/.claude-shared/templates/cockpit-operating-contract.md` before drafting an FD, a TD, a BR, a TR, or code against a ticket.

These stay here, because each fires when no skill has been invoked to load them:

- **A rejection in chat is a bounce-back.** When the user says delivered work is wrong and the agent fixes it in place, invoke `/cockpit:ticket:x:back-from-column` without being asked, source and target both the current column. A defect in delivered work is a bounce-back; a preference, a scope change or a new requirement is not. One per defect, not per message.
- **Mid-dev divergence from the tech steps** is a 60-second human amendment decision, noted on the ticket - never silently absorbed by the agent.
- **All ticket creation goes through `/cockpit:ticket:0:new`.** Never call `create-pages` directly to create a ticket, on any path - scope-drift stub, follow-up, or bounce-back next step.
- **Crossing Ready for Sprint → Sprint Backlog** anywhere but the weekly ceremony is a process violation. Tripwire: a Done ticket with an empty "Date: Ready for Sprint" was smuggled. A split parent is the one exemption.
- **A timebox verdict of success requires zero uncertainty** - any open question, unconfirmed datum or unresolved follow-up makes it partial success. Never write the Outcome while resolvable uncertainty remains and time is left.

## Cockpit - advance the ticket as you work

Registering a ticket (the `/cockpit:ticket:0:register` skill) only gets it onto the board; it does not move it. As the session's work changes stage, keep the card's `Status` in step with reality - don't leave it parked where it entered.

The walk, the skip list, where to stop and what a scope shift means are in the `cockpit:ticket:x:status` skill. Invoke it whenever the card is behind the work.

- **Auto-advance.** When a trigger point is reached, infer the target status and move the ticket immediately, saying nothing about it - the board is where the column is read. No confirmation prompt - for any direction, including backward moves.
- **Trigger points** - after each of these, check whether the ticket status is behind where the work actually is, and if so advance it:
  - ticket registered (should it skip ahead of Ready for BR by AI?)
  - requirements clarified / scope locked
  - BR/TR skill completed
  - first code edit (auto-advanced by hook)
  - commit
  - PR created
  - review requested
- **Close the loop** - when a task's implementation work is complete (committed, or Notion updated), do not end the turn without addressing the ticket status.

### When a board event lands

A line starting `[ticket-watch]` or `[ticket-listen]` is answered by following `~/.claude-shared/templates/board-event.md`.

## Cockpit - a finding in a copilot session

A finding in a session started by `/cockpit:ticket:0:copilot` follows `~/.claude-shared/templates/copilot-finding.md`.

## Cockpit - replying to a comment on a ticket

A reply posted on a ticket follows `~/.claude-shared/templates/ticket-comment-reply.md`.

## Cockpit - Blocked flag

Work that cannot proceed without input from outside the session sets the `Blocked` flag - follow `~/.claude-shared/templates/blocked-flag.md`.

## Cockpit cache

Read cockpit board reference data with `"$HOME/.cockpit/scripts/cockpit-cache-query" <key>` - never the cache file, and never the Tickets data source for what a property is called or what type it is. Call the Notion API only when the script exits non-zero. The two paths that rewrite the cache open it whole: `/cockpit:cache`, and the register skill's project-board discovery.

## Cockpit - metered queries

Never reach for the SQL query tool to read board data another call already answers:

- A ticket's own properties (`Status`, `Type`, a `Date:` stamp) - `"$HOME/.cockpit/scripts/ticket-read"`, naming each one. `notion-fetch` on the ticket URL is for the body, and carries every property alongside it.
- Every row of a small database (Sprints) - `notion-query-database-view` on its view. `notion-fetch` on a data source returns the schema, never the rows.
- The tickets board's rows - the board scripts (`ticket-waiting-cards`, `ticket-board-members`), which call the unmetered classic endpoint.

## Cockpit URL-first - always

When the user's first message contains a Notion URL from the cockpit (Tickets or Epics data source), invoke `/cockpit:ticket:0:register` with that URL before doing anything else - before fetching the page, before reading surrounding text, before acting on any other instruction in the message. The ticket skill handles rename, registration, and epic gating in one pass; skipping it breaks all three. If the URL turns out to be an epic, `/cockpit:ticket:0:register` detects this and redirects to `/cockpit:epic:0:register` automatically.

This applies regardless of what other text accompanies the URL. Additional context in the same message is follow-up work after registration, not a reason to skip it.

## One ticket per session

Once a ticket is registered for a session, that session is bound to it. Do not register a different ticket in the same session - refuse the request and suggest starting a new session for the new ticket. Re-registering the same ticket (e.g. after a context reset) is fine; only a _different_ ticket URL is blocked.

## PR review comments

Read PR review threads through `/cockpit:ticket:4:cr:comments`, never the REST comments endpoint - it cannot tell a resolved thread from an open one.

## Carrying the main checkout forward

`pull-main.sh` moves a checkout onto its remote only when that is a fast-forward on a clean tree, and only while the checkout is on the default branch. A checkout sitting on another branch, a dirty tree, a diverged branch and a fetch that failed each stop it, and each says which one it was. A checkout already current says nothing at all.

Given no argument it takes the checkout `~/.claude-shared` resolves into, never the session's own tree, so a session working in a worktree still carries main forward. Given a directory it takes the repository that directory sits in.

It runs at two points. `SessionStart` fires it with no argument, before a session does anything else. `pull-main-before-refinement.sh` fires it on the `Skill` tool with the session's own directory, for the BR and TR skills alone - a refinement draft opens files off the working tree, and nothing else moves that tree once the session is running. A card dragged into a by-AI column hours later is otherwise drafted against what the checkout held when the session opened.

A refusal goes to the transcript and not to the agent, because a `PreToolUse` hook that exits clean says nothing the model reads. So a session whose checkout sits on a feature branch drafts against that branch and is never told - the pull covers the checkout that is on the default branch, which is where a refinement session normally sits, and covers nothing else.

Only the checkout `~/.claude-shared` resolves into is followed by an apply: the profile directories are generated output, so moving the tree on its own reaches nothing the agent reads. The config this session started on is the copy from before that apply, so the rebuilt one is what the next session gets. Any other repository is moved and nothing is rebuilt from it.

## Claim locks

A session holds a card by taking a lock under `~/.local/state/claude-ticket-claims`, through `ticket-claim-lock`. Only the session holding one may release it, and a session whose id resolves to nothing can release a lock nobody owns and no other.

## The status line's running step

The third thing the status line shows beside the work item type and the board column is the step the agent is running, read from a `.step` sidecar next to the `.column` and `.type` files.

`record-running-step.sh` is its only writer: it runs on every `Skill` tool call and writes the skill's name with the namespace stripped, so the line reads `/ready-for-cr` rather than the full path to it. A skill that wrote its own name would be describing itself, and would still be describing itself after it returned.

The turn ending is what clears it, because nothing fires when a skill returns. So a step that finishes early keeps showing until the agent stops, and a step that invoked another is not named again on the way back out.

## Collecting the worktrees left behind

`git worktrees-clean` walks every worktree and hands each one to `worktree-give-back`, so a session that ended before its card reached Done is collected on the next run. It decides nothing itself beyond skipping a worktree a running session holds a lock on, and each survivor is reported with the give-back's own refusal as its reason.

## What a Warp tab is called

The title is the session's name with the bracketed epic dropped. The glyph in front of it is the state `tab-status.sh` was called with, and neither half reads the other.

`session-name-lib.sh` is the one reader of that name: the transcript's last rename, then the name recorded at registration, then the directory basename.

## A decision nobody is there to answer

`agents/claude/templates/raise-a-decision.md` owns both halves: where the comment goes, and what the session does once it is posted. A branch names that template and its own default; it never restates the ask. A skill with no ticket to write on - the daily mail - names the gap in what it produces instead.

## The end of a dev turn

A commit is not the end of dev - several land while the tech steps are being built - so what carries the card to In CR by AI is the turn ending with one behind it. `remind-ticket-status.sh` records a commit that exited 0 as a `.dev-committed` sidecar, and `advance-after-dev.sh` notes the turn end while that sidecar sits beside a card still reading In Dev.

The note takes the sidecar away, so it costs one line per commit and never twice for the same one: a session with steps left says what is left, and the next commit arms it again.

## What the watcher announces

`ticket-watch-column` compares the live column against the one recorded for the session, and a mismatch counts only once it has held two polls - a hop the agent made itself is recorded by the time the second one asks. A page no session registered has no record, so each new landing announces. `TICKET_WATCH_INTERVAL` sets the cadence a hand check runs at.

A landing in `In Dev` names `/cockpit:ticket:3:dev`, alongside the two refinement columns and `In CR by AI`. Every other column is announced as a move and names nothing.

## Giving the worktree back unattended

`worktree-give-back` is the only way an agent ends a worktree: it takes the path and the branch, runs every check, and calls git itself. Both raw commands are denied, so there is no second route to keep in step with it and no command string for a guard to re-parse. The checks it runs are listed in `agents/claude/templates/status-done-close-out.md`, and each exit code names the one that refused.

## A pull request's checks

`pr-watch-checks` says once whether the checks on a pull request passed, naming the failing ones. `gh pr checks --watch` does the waiting, so nothing polls. `/cockpit:ticket:4:ready-for-cr` arms it and says what each line means.

## A branch behind the base its pull request targets

`pr-catch-up-with-base` picks by what the open pull request already carries. No review on it and the branch is rebased onto the base and force-pushed with a lease. A review on it and the base is merged in and pushed plainly, so no inline comment is marked outdated and none is orphaned. Either way the pull request ends up carrying the same commits as the branch. `/cockpit:ticket:4:ready-for-cr` arms it as a watcher when the pull request goes up, so it polls and acts with no prompt behind it.

A tree carrying uncommitted changes is left where it is, a rebase or a merge that stops on a conflict is undone rather than left half-applied, and a push the remote refuses is named rather than swallowed - the branch is never found in a state nobody chose.

## What a pull request description holds

`agents/claude/templates/pull-request-to-ticket.md` carries the rule and the body that shows it, and both paths that open a pull request read it rather than writing one of their own.

## Cockpit cache keys

The routing rule is above, and `cockpit-cache-query` itself carries the key list, the refusal on a key it cannot answer, and the age warning.

## Reading a ticket's properties

`ticket-read` prints the properties named on its command line and can print no other. A formula and a rollup have no branch in its filter, so neither reaches stdout however it is called. It reads through the board poller's own read-only credential, so it spends no agent tokens on what it drops.

`--section` prints one heading, what sits under it, and the comments hanging off both, through that same credential and with no property alongside. It exits 7 when the page has no such heading. A heading given with its `##` marker reads the same section as the bare form. `notion-fetch` stays what a write builds its `old_str` from, and what a read of the whole body goes through.

## What a tech steps write is held to

`guard-tech-steps.sh` reads a write to `## Tech Steps` and refuses it on every line breaking a rule it can check: the opening verb of a summary, a `so ...` clause, a tree line's marker, a file line joined to no folder above it, a heading's width, the sentence column, a path written twice in one tree, a flow missing `title` or `autonumber`, and a shading colour outside the two allowed. Every rule it holds is stated in the `cockpit:ticket:2:tr` skill; the guard states none of them itself.

A write carrying more than that section is read for its `## Tech Steps` heading, and every line under another heading passes unread - a whole-page write is held to the rules over its tech steps alone. A heading inside a fenced code block is code rather than a heading, and switches nothing off. A write carrying no heading at all is read whole, which is what a write of the tech steps on their own is.

## Cockpit status gates what output is allowed

Which column allows which output is in the `cockpit:ticket:0:register` skill. Do not _propose_ implementation - code snippets, "here's what I'd change", file-level plans - while the card is in a BR or TR column.

## Writing a reply about the board

The unsolicited-text plugin holds how a reply reads. These are the clauses of those rules that name the board, and they stay here.

- Write `TRed` not `technically refined`, and `BR` not `business refinement`. BR, TR and CR are shared vocabulary and are not expanded on first use.
- Name the stage or the output, whichever you mean. BR and TR are the refinement stages. Validation steps and tech steps are what they produce, and tech steps are what dev consumes. So a defect in the drafted implementation is a tech step defect, and dev diverging from what was drafted is a divergence from the tech steps - never "from the TR", which names the stage that is already over.
- No board IDs. Name the ticket, or link to it so the link carries its name - never write the board's own identifier on its own. "COC-424" makes the reader open the board to find out which ticket it is, and a cross-board ticket has two such IDs, neither recognisable on sight. This covers every board's numbering, the cockpit's and a project's alike. An ID already written into code stays as it is - that is not writing for a reader.
- A queued item leaves the list the moment a ticket is raised for it - name it once, in the reply that raised it, and never again.
- "raise a ticket for it" is an explicit instruction to act on a queued item, the same way "do the queued one" is.
- A reply cut to the line ceiling carries what came off as a follow-up ticket.
- `note-unflagged-question.sh` reads the queue for a question the ticket is not yet flagged Blocked for, and `advance-after-dev.sh` records a dev turn that ended on a commit. Both record through `hook-stop-note-lib.sh`, and `replay-stop-notes.sh` prints what they found as the next prompt arrives.
