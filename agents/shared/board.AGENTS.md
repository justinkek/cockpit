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
- **Mid-dev divergence from the tech steps** is a 60-second human amendment decision - never silently absorbed by the agent. Post it as a comment anchored to the step it changes, following `~/.claude-shared/templates/raise-a-decision.md`, for the person to answer on that thread, and once they have, follow that template's `## Once it is answered`.
- **All ticket creation goes through `/cockpit:ticket:0:new`.** Never call `board-card create` directly to create a ticket, on any path - scope-drift stub, follow-up, or bounce-back next step. An epic's ticket breakdown is the one exception: `/cockpit:epic:0:register` creates the approved set itself.
- **Crossing Ready for Sprint → Sprint Backlog** anywhere but the weekly ceremony is a process violation. Tripwire: a Done ticket with an empty "Date: Ready for Sprint" was smuggled, unless its walk skipped that column on purpose - the `cockpit:ticket:x:status` skill skips it for every timebox, and for every card in a repository whose `./AGENTS.md` lists it under `## Ticket walk skip`. A split parent is exempt too.
- **A timebox verdict of success requires zero uncertainty** - any open question, unconfirmed datum or unresolved follow-up makes it partial success. Never write the Outcome while resolvable uncertainty remains and time is left.

## Cockpit - advance the ticket as you work

Registering a ticket (the `/cockpit:ticket:0:register` skill) only gets it onto the board; it does not move it. As the session's work changes stage, keep the card's `Status` in step with reality - don't leave it parked where it entered.

The walk, the skip list, where to stop and what a scope shift means are in the `cockpit:ticket:x:status` skill. Invoke it whenever the card is behind the work.

- **Auto-advance.** When a trigger point is reached, infer the target status and move the ticket immediately, saying nothing about it - the board is where the column is read. No confirmation prompt - for any direction, including backward moves.
- **Trigger points** - after each of these, check whether the ticket status is behind where the work actually is, and if so advance it:
  - ticket registered (should it skip ahead of Ready for BR by AI?)
  - requirements clarified / scope locked
  - BR/TR skill completed
  - first code edit (`require-dev-status.sh` refuses it until `/cockpit:ticket:3:dev` has run)
  - commit
  - PR created
  - review requested
- **Close the loop** - when a task's implementation work is complete (committed, or the card updated), do not end the turn without addressing the ticket status.

### When a board event lands

A line starting `[ticket-watch]` or `[ticket-listen]` is answered by following `~/.claude-shared/templates/board-event.md`.

## Cockpit - a finding in a copilot session

A finding in a session started by `/cockpit:ticket:0:copilot` follows `~/.claude-shared/templates/copilot-finding.md`.

## Cockpit - replying to a comment on a ticket

A reply posted on a ticket follows `~/.claude-shared/templates/ticket-comment-reply.md`.

## Cockpit - Blocked flag

Work that cannot proceed without input from outside the session sets the `Blocked` flag - follow `~/.claude-shared/templates/blocked-flag.md`.

## Cockpit id-first - always

When the user's first message names a cockpit card or epic id - `FEAT-123`, `EPIC-3` - invoke `/cockpit:ticket:0:register` with that id before doing anything else - before reading the card, before reading surrounding text, before acting on any other instruction in the message. The ticket skill handles rename, registration, and epic gating in one pass; skipping it breaks all three. An epic id is redirected to `/cockpit:epic:0:register` automatically.

This applies regardless of what other text accompanies the id. Additional context in the same message is follow-up work after registration, not a reason to skip it.

## One ticket per session

Once a ticket is registered for a session, that session is bound to it. Do not register a different ticket in the same session - refuse the request and suggest starting a new session for the new ticket. Re-registering the same ticket (e.g. after a context reset) is fine; only a _different_ ticket id is blocked.

## PR review comments

Read PR review threads through `/cockpit:ticket:4:cr:comments`, never the REST comments endpoint - it cannot tell a resolved thread from an open one.

## Carrying the main checkout forward

`pull-main.sh` moves a checkout onto its remote only when that is a fast-forward on a clean tree, and only while the checkout is on the default branch. A checkout sitting on another branch, a dirty tree, a diverged branch and a fetch that failed each stop it, and each says which one it was. A checkout already current says nothing at all.

Given no argument it takes the checkout `~/.claude-shared` resolves into, never the session's own tree, so a session working in a worktree still carries main forward. Given a directory it takes the repository that directory sits in.

It runs at two points. `SessionStart` fires it with no argument, before a session does anything else. `pull-main-before-refinement.sh` fires it on the `Skill` tool with the session's own directory, for the BR and TR skills alone - a refinement draft opens files off the working tree, and nothing else moves that tree once the session is running. A card dragged into a by-AI column hours later is otherwise drafted against what the checkout held when the session opened.

A refusal goes to the transcript and not to the agent, because a `PreToolUse` hook that exits clean says nothing the model reads. So a session whose checkout sits on a feature branch drafts against that branch and is never told - the pull covers the checkout that is on the default branch, which is where a refinement session normally sits, and covers nothing else.

Only the checkout `~/.claude-shared` resolves into is followed by an apply: the profile directories are generated output, so moving the tree on its own reaches nothing the agent reads. The config this session started on is the copy from before that apply, so the rebuilt one is what the next session gets. Any other repository is moved and nothing is rebuilt from it.

## The local board

The cockpit board is a folder of markdown files, `~/.local/state/cockpit/board`, a git repository of its own that is never pushed. `board-card` is its one writer, run as `"$HOME/.cockpit/scripts/board-card"`, and `board-card init` makes it. Every write goes through the script, so the board works with the app stopped. Nothing reaches Notion.

| Folder        | Holds                                                      | Id                           |
| ------------- | ---------------------------------------------------------- | ---------------------------- |
| `cards/`      | a ticket card, its prefix naming its type                  | `FEAT-12`, `BUG-7`, `TIME-3` |
| `epics/`      | an epic, on columns of its own                             | `EPIC-3`                     |
| `projects/`   | a project an epic belongs to                               | `PRJ-2`                      |
| `sprints/`    | a sprint a card is planned into                            | `SPR-1`                      |
| `references/` | a reference ticket a complexity figure is compared against | `REF-4`                      |

`ticket-waiting-cards` prints the cards waiting in a by-AI column, one line each in the order they are picked, and `--claimed-by <session-id>` prints the ones a session holds.

Feature, bug and timebox cards share one number sequence, and `board-card set <id> type` renames a card to its new prefix, carrying its links, comments and claim with it.

A card id is accepted wherever a ticket URL was: `ticket-register` records it, `ticket-read` answers for it, and `ticket-claim-lock` locks it. `board-card statuses [--kind epic]` prints the columns in walk order.

`board-card move` lands on one column, and `board-card walk` steps every column up to the target and refuses to go backwards. Each stamps a column's date on first arrival only. `Deprioritised` sits outside the walk: `move` puts a card there or takes it out, and `walk` refuses either. A card's place within its column is its `rank`, lowest first; a card with none sorts as the negative of its ticket number, so the newest comes first.

`board-card section <id> <heading>` replaces one section of the content with what arrives on stdin and leaves the rest. A section not there yet is added before `--before <heading>` or after `--after <heading>`, and at the end when given neither or when the heading it names is not there. `--under <heading>` does all of that inside one section, a level deeper, so the end is that section's end, and adds that section at the end of the body when it is missing. `board-card bounce <id> <gate>` adds one to that gate's `Back from` counter.

A comment sits in `<id>.comments.jsonl` beside its record, one line each. `board-card comment <id> --anchor <text>` pins it to that text in the content, `--reply <comment-id>` adds it to a thread, and no flag puts it on the whole page. `board-card comments <id>` lists the open threads and `board-card resolve` closes one. `show --section` prints the open comments anchored inside that section.

Every write stamps `updated` on the record it changes, a comment or an attachment included, and a write that changes nothing leaves the stamp as it was.

A record whose front matter does not parse is never written over or read past: any command that reaches it, `list` included, exits 8 and names the file, which is then fixed by hand.

`board-card set <id> icon <emoji>` gives any record one emoji to show before its name, `create --icon` gives it one from the start, and anything that is not a single emoji is refused. A symbol drawn as text unless asked otherwise, such as `♀`, counts only when the emoji variation selector follows it, as the emoji picker writes it.

`board-card set <id> timebox_mins <minutes>` gives a card its budget in whole minutes, read back as `Timebox (mins)`, and a timebox card starts with 60 unless `create --timebox-mins` names another. A card whose type is set to `Timebox` starts with 60 too, unless it already holds a budget.

A sprint takes `start` and `end` as `YYYY-MM-DD` and `dev_days` and `speed` as numbers, through `board-card set` or `create --kind sprint --start --end --dev-days --speed`, and an end before the start is refused. A sprint and a reference ticket have no status, so `create` refuses `--status` for either, and `board-card set <id> status ''` clears one either was given before.

A project has no columns, so `board-card set <id> status` moves it between `Not started`, `In progress` and `Done`, and `priority` (a whole number) and `repo` (a URL) are set the same way or given to `create --kind project`.

A reference ticket's `points` (a Fibonacci number), `why`, `description`, `domain` (`Tech` or `Bizdev`), `stack` and `card` (the card it was taken from) are each set with `board-card set`, which also accepts them as `reference.<key>`.

`board-card archive <id>` moves a record, its comments and its attachments under `archive/`, where `list` passes it by unless given `--archived`. It refuses a card still linked to another, and any record another one still names as its epic, project, sprint or card, so nothing on the board is left pointing at an id it cannot read. `board-card unarchive <id>` puts an archived record back on the board, and `board-card path <id>` names the file a record lies in, archived or not.

`board-card duplicate <id>` makes a new card or epic of the same type named `Copy of <name>`, carrying its content, epic, icon, complexity and timebox, in the first column unless `--name` or `--status` say otherwise. An epic or project no longer on the board is left off the copy.

`board-card history <id>` prints the commits that touched a record, under every id it has held and in or out of the archive, newest first, one line each holding the commit, its time and its subject. `board-card undo <id>` writes the record, its comments and its attachments back as they stood before the last of those commits, as a commit of its own, so a second undo takes back the first. Any other record that commit changed is left as it is, but for the card across a link the undo makes or takes away, which gains or loses its own side of it. The claim lock is taken or let go to match the session the record then names, and an undo naming one session while another holds the lock is refused. `--since <commit>`, given a commit from that history, writes the record back as it stood at that commit instead, taking back every change after it in one commit - the board app uses it to take back a drop that both moved and reordered a card. `--until <commit>`, given the last commit of the change being taken back, refuses the undo when a later commit has touched the record, so a change made from another tab or by an agent is never taken back with it.

Undoing a rename gives the card its old id back, and every record naming it follows. Undoing an archive or an unarchive moves the record back to where it lay, and is refused while another record names it. A link the undone version held at a card's old id is read at the id that card holds now, so an undo never leaves a record pointing at an id that is gone, and an undo that would change nothing is refused.

`show --json` and `list --json` give each card two values worked out at read time and never stored, counting working time as 09:30 to 18:00 UTC on weekdays: `days_in_column`, the whole working days since it last reached its current column, which a column's date stamp alone cannot say because a stamp keeps its first arrival (0 in a column Notion never timed: `Backlog`, `Sprint Backlog`, `Daily Plan`, `Deprioritised`, `Done` and every by-AI column but `Ready for TR by AI`), and `overrunning`, true once its working minutes from `In Dev` to `Ready for CR` (or now) plus the time since it came back to `In Dev` when it is there again after `Ready for CR`, pass its `timebox_mins` when it is a timebox, or 102 for each point of complexity otherwise.

The app in `board/` reads and writes through `board-card` alone. Start it with `npm --prefix board run dev`; it listens on every interface at port 4646.

## Claim locks

A session holds a card by taking a lock under `~/.local/state/claude-ticket-claims`, through `ticket-claim-lock`. Only the session holding one may release it, and a session whose id resolves to nothing can release a lock nobody owns and no other.

**A claimed card stays with the session that picked it up until it reaches Done.** Both entry paths take the claim - `/cockpit:ticket:0:copilot` when it takes a waiting card, `/cockpit:ticket:0:register` on every card it registers, one it created included - and only two things release it: the status hop that lands on `Done`, and the SessionEnd hook when the session ends first. Never a refinement column boundary, which puts the card back in the pool between stages for a second session to claim while the first still carries it. A claim is expired on whether its session is still alive, never on which column the card is sitting in.

## The status line's running step

The third thing the status line shows beside the work item type and the board column is the step the agent is running, read from a `.step` sidecar next to the `.column` and `.type` files.

`record-running-step.sh` is its only writer: it runs on every `Skill` tool call and writes the skill's name with the namespace stripped, so the line reads `/ready-for-cr` rather than the full path to it. A skill that wrote its own name would be describing itself, and would still be describing itself after it returned.

The turn ending is what clears it, because nothing fires when a skill returns. So a step that finishes early keeps showing until the agent stops, and a step that invoked another is not named again on the way back out.

## What a Warp tab is called

The title is the session's name with the bracketed epic dropped. The glyph in front of it is the state `tab-status.sh` was called with, and neither half reads the other.

`session-name-lib.sh` is the one reader of that name: the transcript's last rename, then the name recorded at registration, then the directory basename.

## A decision nobody is there to answer

`agents/claude/templates/raise-a-decision.md` owns both halves: where the comment goes, and what the session does once it is posted. A branch names that template and its own default; it never restates the ask. A skill with no ticket to write on - the daily mail - names the gap in what it produces instead.

## The end of a dev turn

A commit is not the end of dev - several land while the tech steps are being built - so what carries the card to In CR by AI is the turn ending with one behind it. `remind-ticket-status.sh` records a commit that exited 0 as a `.dev-committed` sidecar, and `advance-after-dev.sh` notes the turn end while that sidecar sits beside a card still reading In Dev.

The note takes the sidecar away, so it costs one line per commit and never twice for the same one: a session with steps left says what is left, and the next commit arms it again.

## What the watcher announces

`ticket-watch-column` compares the live column against the one recorded for the session, and a mismatch counts only once it has held two polls - a hop the agent made itself is recorded by the time the second one asks. A card no session registered has no record, so each new landing announces. `TICKET_WATCH_INTERVAL` sets the cadence a hand check runs at.

A landing in `In Dev` names `/cockpit:ticket:3:dev`, alongside the two refinement columns and `In CR by AI`. Every other column is announced as a move and names nothing.

## Giving the worktree back unattended

`git worktrees-clean --include-locked <worktree-path>` is the only way an agent ends a worktree: it decides whether the work reached the default branch, calls git itself, and says why when it keeps one. It is installed separately, with `brew install justinkek/tap/git-worktrees-clean`, and run with no path it checks every worktree of the repository, so a session that ended before its card reached Done is collected on the next run. Both raw commands, `git worktree remove` and `git branch --delete --force`, stay denied, so there is no second route to keep in step with it. The exit codes are listed in `agents/claude/templates/status-done-close-out.md`.

## A pull request's checks

`pr-watch-checks` says once whether the checks on a pull request passed, naming the failing ones. `gh pr checks --watch` does the waiting, so nothing polls. `/cockpit:ticket:4:ready-for-cr` arms it and says what each line means.

## A branch behind the base its pull request targets

`pr-catch-up-with-base` picks by what the open pull request already carries. No review on it and the branch is rebased onto the base and force-pushed with a lease. A review on it and the base is merged in and pushed plainly, so no inline comment is marked outdated and none is orphaned. Either way the pull request ends up carrying the same commits as the branch. `/cockpit:ticket:4:ready-for-cr` arms it as a watcher when the pull request goes up, so it polls and acts with no prompt behind it.

A tree carrying uncommitted changes is left where it is, a rebase or a merge that stops on a conflict is undone rather than left half-applied, and a push the remote refuses is named rather than swallowed - the branch is never found in a state nobody chose.

## What a pull request description holds

`agents/claude/templates/pull-request-to-ticket.md` carries the rule and the body that shows it, and both paths that open a pull request read it rather than writing one of their own.

## Reading a ticket's properties

`ticket-read` and `board-card show` print the properties named on the command line, under the names the board has always used - `Status`, `Complexity`, `Date: In Dev` - and no other. `board-card show <id> --json` is what a read of the whole body goes through.

`--section` prints one heading, what sits under it, the open comments anchored inside it and the comments on the whole page, with no property alongside. It exits 7 when the card has no such heading. A heading given with its `##` marker reads the same section as the bare form.

## What a tech steps write is held to

The tech-ref plugin carries the guard, and `rules/tech-steps.md` in it carries every rule the guard holds. The board owns only how it is reached: `spawn-plugin-guard.sh` fires on `board-card section <id> "Tech Steps"`, finds the plugin's guard under the account's plugin directory, and hands it the content arriving on stdin. The plugin registers on file edits alone and never learns which command this board writes through.

A `section` write carries that one section and nothing else, so the guard reads all of it.

## Cockpit status gates what output is allowed

Which column allows which output is in the `cockpit:ticket:0:register` skill. Do not _propose_ implementation - code snippets, "here's what I'd change", file-level plans - while the card is in a BR column, or in a TR column anywhere but the tech steps written to the card.

## Writing a reply about the board

The unsolicited-text plugin holds how a reply reads. These are the clauses of those rules that name the board, and they stay here.

- Write `TRed` not `technically refined`, and `BR` not `business refinement`. BR, TR and CR are shared vocabulary and are not expanded on first use.
- Name the stage or the output, whichever you mean. BR and TR are the refinement stages. Validation steps and tech steps are what they produce, and tech steps are what dev consumes. So a defect in the drafted implementation is a tech step defect, and dev diverging from what was drafted is a divergence from the tech steps - never "from the TR", which names the stage that is already over.
- No board IDs. Name the ticket, or link to it so the link carries its name - never write the board's own identifier on its own. "FEAT-424" makes the reader open the board to find out which ticket it is. An ID already written into code stays as it is - that is not writing for a reader.
- A queued item leaves the list the moment a ticket is raised for it - name it once, in the reply that raised it, and never again.
- "raise a ticket for it" is an explicit instruction to act on a queued item, the same way "do the queued one" is.
- A reply cut to the line ceiling carries what came off as a follow-up ticket.
- `note-unflagged-question.sh` reads the queue for a question the ticket is not yet flagged Blocked for, and `advance-after-dev.sh` records a dev turn that ended on a commit. Both record through `hook-stop-note-lib.sh`, and `replay-stop-notes.sh` prints what they found as the next prompt arrives.
