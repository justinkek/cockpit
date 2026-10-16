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

Registering a ticket (the `/cockpit:ticket:0:register` skill) gets it onto the board, and its one move is from `Ready for BR by AI` to `In BR by AI` when it hands the card on to BR. As the session's work changes stage, keep the card's `Status` in step with reality - don't leave it parked where it entered.

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

Every write `board-card` makes is committed to that repository. Writes to one record that land close together are held and go in as one commit for that record a few seconds after the last of them, as `COCKPIT_COMMIT_DELAY` in `board-card` sets, and writes to different records never share a commit - except one `board-card` call that changes several records at once, such as a link, an epic's target holding its cards' due dates or a rename, which is one commit holding all of them. `history` commits what is held for the record it reads, and `undo` and `board-card flush --now` commit everything held before they read. Exit 6 means the write is on disk but the repository refused the commit: never repeat the write, say what it printed, and leave it - the next write commits what was left over.

| Folder        | Holds                                                      | Id                           |
| ------------- | ---------------------------------------------------------- | ---------------------------- |
| `cards/`      | a ticket card, its prefix naming its type                  | `FEAT-12`, `BUG-7`, `TIME-3` |
| `epics/`      | an epic, on columns of its own                             | `EPIC-3`                     |
| `projects/`   | a project an epic belongs to                               | `PRJ-2`                      |
| `sprints/`    | a sprint a card is planned into                            | `SPR-1`                      |
| `references/` | a reference ticket a complexity figure is compared against | `REF-4`                      |
| `milestones/` | a dated marker across the plan, such as a launch           | `MS-1`                       |

`ticket-waiting-cards` prints the cards waiting in a by-AI column with no `blocked` reason on them, one line each in the order they are picked, and `--claimed-by <session-id>` prints the ones a session holds. That order puts an urgent card first, then each epic's cards in the order of the epics' `rank`, and within one epic the cards by their own `rank`, a card with no epic coming after every epic's cards.

Feature, bug and timebox cards share one number sequence, and `board-card set <id> type` renames a card to its new prefix, carrying its links, comments and claim with it.

Every card has an epic and every epic a project. `create` refuses a card without `--epic` and an epic without `--project`, `set` refuses to clear either, and `duplicate` refuses a record whose epic or project is no longer on the board. `create --project` gives a card or an epic its project from the start.

A card id is accepted wherever a ticket URL was: `ticket-register` records it, `ticket-read` answers for it, and `ticket-claim-lock` locks it. `board-card statuses [--kind epic]` prints the columns in walk order.

`board-card move` lands on one column, and takes several records of one kind before it as one commit that each of them can be undone from on its own, while `board-card walk` steps every column up to the target and refuses to go backwards. Each stamps a column's date on first arrival only. `Deprioritised` sits outside the walk: `move` puts a card there or takes it out, and `walk` refuses either. A card's place within its column is its `rank`, lowest first; a card with none sorts as the negative of its ticket number, so the newest comes first.

`board-card section <id> <heading>` replaces one section of the content with what arrives on stdin and leaves the rest. A section not there yet is added before `--before <heading>` or after `--after <heading>`, and at the end when given neither or when the heading it names is not there. `--under <heading>` does all of that inside one section, a level deeper, so the end is that section's end, and adds that section at the end of the body when it is missing. `board-card bounce <id> <gate>` adds one to that gate's `Back from` counter.

A comment sits in `<id>.comments.jsonl` beside its record, one line each. `board-card comment <id> --anchor <text>` pins it to that text in the content, `--reply <comment-id>` adds it to a thread, and no flag puts it on the whole page. `board-card comments <id>` lists the open threads and `board-card resolve` closes one. `show --section` prints the open comments anchored inside that section.

The board keeps the names that are the person's own in `me` at its root, one a line: `board-card me` prints them, `board-card me <name>...` sets the whole list, and `board-card me ''` puts back the default of the login name and `Justin Kek (Notion)`. `board-card inbox` takes a comment under any of those names, or under the name it writes as, as the reader's own and leaves it out, never counts a move or a block made under one as unread, and a comment written under one name on the list can be edited or deleted under another.

The board app's saved views live in `views.json` at the board's root, each a name, the board it belongs to (`card` or `epic`) and the filters, grouping, sort and layout it recalls. `board-card views` lists them one a line as the board and the name, `--json` prints the whole file, `board-card views save <name> [--kind card|epic]` stores the JSON object on stdin under that name, replacing a view of the same name on the same board, and `board-card views delete <name> [--kind card|epic]` takes one off, the file going with the last of them. A name that starts with `--` follows a `--`, which ends the options.

Every write stamps `updated` on the record it changes, a comment or an attachment included, and a write that changes nothing leaves the stamp as it was.

A record whose front matter does not parse is never written over or read past: any command that reaches it, `list` included, exits 8 and names the file, which is then fixed by hand.

`board-card set <id> icon <emoji>` gives any record one emoji to show before its name, `create --icon` gives it one from the start, and anything that is not a single emoji is refused. A symbol drawn as text unless asked otherwise, such as `♀`, counts only when the emoji variation selector follows it, as the emoji picker writes it.

`board-card set <id> urgent true` flags a card urgent, read back as `Urgent`, and `''` takes the flag off, leaving no field behind. The flag only overrides the order cards are picked in, which stays each card's place on the board otherwise, and an epic is never flagged.

`board-card set <id> labels "<label>, <label>"` gives a card or an epic its labels, a list separated by commas and kept trimmed with each label once, read back as `Labels`, and `''` takes them all off.

The app's card board draws every urgent card in a red Urgent swimlane above the rest, and groups the rest into swimlanes by epic, project, type, sprint or label when asked, the Epics board by project or label. A drop into a swimlane sets that field as well as the column: into Urgent flags the card and out of it takes the flag off, into a label's lane swaps the label the card came from for that one and `No label` takes them all off, a card's project lane follows its epic and is never set by a drop, and a lane with no epic or no project refuses one. A card with several labels sits in its first label's lane.

`board-card set <id> timebox_mins <minutes>` gives a card its budget in whole minutes, read back as `Timebox (mins)`, and a timebox card starts with 60 unless `create --timebox-mins` names another. A card whose type is set to `Timebox` starts with 60 too, unless it already holds a budget.

`board-card set <id> estimate <points>` gives a card the high-level estimate TD sets, a Fibonacci number above 0 kept apart from the `complexity` TR sets and read back as `Estimate`; it is null until set and cleared with `''`, an epic takes none of its own, and a timebox takes none and drops any it held when its type becomes `Timebox`.

A sprint takes `start` and `end` as `YYYY-MM-DD` and `dev_days` and `speed` as numbers, through `board-card set` or `create --kind sprint --start --end --dev-days --speed`, and an end before the start is refused. A sprint and a reference ticket have no status, so `create` refuses `--status` for either, and `board-card set <id> status ''` clears one either was given before.

An epic takes `target` as `YYYY-MM-DD`, `confidence` (`On track`, `At risk - plan in place` or `At risk - no plan`) and `learning` (free text) through `board-card set`, and its target through `create --kind epic --target` too, and a target before its start is refused.

An epic's priority is its `rank`, one number that orders it within its column on the Epics board and across the plan alike, lowest first, so a drag in either place writes the same rank. A new epic is ranked below every other, and `board-card set <id> plan_rank` is refused with a pointer to `rank`.

An epic starts in `Backlog`, where it waits until it is pulled into refinement, and its first move out of `Backlog` stamps its `start` with that day unless it holds one already. An epic created in a later column takes the day it is created as its `start`. The stamp is the only way an epic gets a start: `set <id> start` and `create --kind epic --start` are refused, and the app shows the start without letting it be changed.

`board-card set <id> track <n>` pins an epic to that track of its project on the plan, a whole number above 0 read back as `Track` and cleared with `''` to let the plan place it, and a pin past the project's tracks is kept for the plan to warn about.

Setting an epic's `target` holds each of its cards that is neither `Done` nor `Deprioritised` to it: a card with no due date or a later one takes the target as its `due`, marked with `due_from` naming the epic, a later date of the card's own is kept as `due_own` and given back once the target moves past it or lets the card go, a due date the target set follows it and is cleared with it, an earlier date of the card's own is left, and `set` prints each card it changed. A card joining or leaving an epic is held to its target or let go the same way, and setting `due` by hand makes the date the card's own again.

A milestone is created with `create --kind milestone --name <name> --date <date>`, moves with `board-card set <id> date`, and comes off the plan with `board-card archive`.

A project has no columns, so `board-card set <id> status` moves it between `Not started`, `In progress` and `Done`, and `priority` (a whole number) and `repo` (a URL) are set the same way or given to `create --kind project`.

The board has one count of tracks, how many epics the person can run at once, kept in `tracks` at the board's root and printed, or set when given one, by `board-card tracks [<n> | '']`. Each project's `tracks`, a whole number above 0 read back as `Tracks`, is its share of them, and a project whose share is null has none. A share that would take the projects' shares past the board's count is refused, and so is a count below the shares added up, so the count drops only once a project has given a share up. Until the count is set, or once it is cleared with `''`, it reads as the shares added up.

A reference ticket's `points` (a Fibonacci number), `why`, `description`, `domain` (`Tech` or `Bizdev`), `stack` and `card` (the card it was taken from) are each set with `board-card set`, which also accepts them as `reference.<key>`.

`board-card archive <id>` moves a record, its comments and its attachments under `archive/`, where `list` passes it by unless given `--archived`. It refuses a card still linked to another, and any record another one still names as its epic, project, sprint or card, so nothing on the board is left pointing at an id it cannot read. `board-card unarchive <id>` puts an archived record back on the board, and `board-card path <id>` names the file a record lies in, archived or not.

`board-card duplicate <id>` makes a new card or epic of the same type named `Copy of <name>`, carrying its content, epic, icon, complexity, estimate and timebox, in the first column unless `--name` or `--status` say otherwise. A card's own project no longer on the board is left off the copy.

`board-card history <id>` prints the commits that touched a record, under every id it has held and in or out of the archive, newest first, one line each holding the commit, its time and its subject. `board-card undo <id>` writes the record, its comments and its attachments back as they stood before the last of those commits, as a commit of its own, so a second undo takes back the first. Any other record that commit changed is left as it is, but for the card across a link the undo makes or takes away, which gains or loses its own side of it. The claim lock is taken or let go to match the session the record then names, and an undo naming one session while another holds the lock is refused. `--since <commit>`, given a commit from that history, writes the record back as it stood at that commit instead, taking back every change after it in one commit - the board app uses it to take back a drop that both moved and reordered a card. `--until <commit>`, given the last commit of the change being taken back, refuses the undo when a later commit has touched the record, so a change made from another tab or by an agent is never taken back with it.

Undoing a rename gives the card its old id back, and every record naming it follows. Undoing an archive or an unarchive moves the record back to where it lay, and is refused while another record names it. A link the undone version held at a card's old id is read at the id that card holds now, so an undo never leaves a record pointing at an id that is gone, and an undo that would change nothing is refused.

`board-card search <text> [--kind epic]` prints the ids of the records whose content, everything below the front matter, holds the text, matched as a fixed string whatever its case. The board app uses it so its search reaches what a card says as well as its name.

`show --json` and `list --json` give each card two values worked out at read time and never stored, counting working time as 09:30 to 18:00 UTC on weekdays: `days_in_column`, the whole working days since it last reached its current column, which a column's date stamp alone cannot say because a stamp keeps its first arrival (0 in a column Notion never timed: `Backlog`, `Sprint Backlog`, `Daily Plan`, `Deprioritised`, `Done` and every by-AI column but `Ready for TR by AI`), and `overrunning`, true once its working minutes from `In Dev` to `Ready for CR` (or now) plus the time since it came back to `In Dev` when it is there again after `Ready for CR`, pass its `timebox_mins` when it is a timebox, or 102 for each point of complexity otherwise.

The app's Plan page draws one row per epic on a week or month timeline, grouped by project and within a project by track and then by the day it is scheduled to start, so the timeline reads as a cascade, with the epics done last and every epic in `rank` order once the grouping is turned off, and with the milestones across it. A row dragged onto another takes the `rank` just above or below that epic and moves to where that priority schedules it. Alt and an arrow key on a row's handle moves it past the open epic next above or below it in `rank` within its project, as the cascade's order on the page is the schedule's and not the priority's. The plan projects each open epic's end by scheduling the points left on its cards on its project's tracks, each track that frees going to the highest epic in `rank` order that is ready for it, at the project's TR complexity done a week over the last six weeks divided by how many of its epics it had in progress on average, falling back to the board's overall figure for a project with none, marked as a fallback on its heading, on each of its rows and on hovering its bars, then to the current sprint's speed and then to ten points a week. A project with no share of the tracks has none of its epics scheduled, and an epic whose project is not on the board is named in a notice above the timeline instead of drawn on it. The Epics board names the same epics in a notice above its columns, and the card board each card whose epic is not on the board.

An epic is moved to `Epic Done` from the Plan page's status or from the Epics board alike, and while it still has a card neither `Done` nor `Deprioritised` the app names those cards first and offers to deprioritise them with it in one move, to move it anyway, or to leave it where it is.

The Plan page shows the board's count of tracks with how many no project has been given, and steps it and each project's share up or down, a project's share stepping down to none; a share past the count or a count below the shares is refused there with what to change first, and a change to the count has no undo.

An epic's row spans the whole epic: its refinement, from its `start` to the day it reached `Tickets In Dev`, then its delivery, the points left on its cards. Refinement takes no track and runs beside other epics' delivery, but a project refines at most as many epics at once as its share of the tracks, so an epic in `Backlog` is forecast to start refinement when one of those slots frees, in `rank` order, and the plan warns when more than that are in refinement on the board. Refinement already done is drawn from the stamps, and refinement still to come is forecast at the average days past epics took from `start` to `Tickets In Dev`, or 14 days, labelled as a default, before any epic got there. An epic's delivery is scheduled no earlier than its refinement ends, and an epic counts as refined once it reached `Tickets In Dev` or is in progress. The span from its start to its target is fixed, the delivery already done is drawn behind today from the day it was refined and never moves, and only what is left is projected forward from today.

Priority wins over work in progress: an epic in progress, in `Tickets In Dev` or with a feature or bug card that reached `In Dev` or `Done` - a timebox never puts its epic in progress - that a higher epic leaves without a track is drawn paused where it stands until one frees, with a notice naming it and nothing on the board changed. An epic keeps the track it is given until its points are done, a pinned epic waits for its own track, and a pin past its project's tracks is warned about and ignored.

A card's points on the plan are its `complexity` when set and its `estimate` otherwise, and a card with neither is left out of every sum and date and counted on its epic as unsized, while a timebox counts in neither.

The average speed shows board-wide at the top of the Plan page, for each project and for each of its tracks on the project's heading, and for each sprint on the Sprints page as the complexity of the cards done within the sprint's dates, whatever sprint they were in, and that a week. The average speed counts only the `complexity` of the cards done in its window, and a done card with none, whatever its `estimate`, and a done timebox are counted beside it rather than in it.

An epic's TD estimate and TR complexity are each shown as a total over all its cards but the deprioritised ones and as what is left on its open cards, the second with how many open cards are sized, worked out wherever its side panel, its card on the Epics board or its full page shows them and never stored. A figure none of those cards has reads as `-`, never 0, and the plan schedules on what is left alone.

An epic's scheduled bar draws the length that rests on complexity solid and the length that rests on estimates hatched after it, then a `?` marker with no length while any open card is unsized, and an epic whose open cards are all unsized gets the marker alone.

An epic's row on the plan carries no figure of its own: its TD estimate, its TR complexity with how many tickets are sized, its unsized count and its points left show on hovering its bar or markers and in its side panel.

`board-card migrate` brings a board written before a change to its records' shape up to date, prints each record it changed or `nothing to migrate`, and changes nothing the second time it runs. It gives every epic a `rank` in the order the plan drew them, an old `plan_rank` first, then a rank dragged on the Epics board, then by target and number, and drops `plan_rank`. It gives each project with no share and an epic not in `Epic Done` a share of 1, sets the board's count of tracks to the shares added up when there is none, and removes the old `no-project-tracks` file. It gives an epic past `Backlog` with no `start` the day it was first stamped into a column past `Backlog`, else the day it was created. It names each card with no epic and each epic with no project, which only a person can give them.

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

`agents/claude/templates/raise-a-decision.md` owns all three parts: where the comment goes, what the session does once it is posted, and what the session that next reads the thread does with the person's answer. A branch names that template and its own default; it never restates the ask. A skill with no ticket to write on - the daily mail - names the gap in what it produces instead.

## The end of a dev turn

A commit is not the end of dev - several land while the tech steps are being built - so what carries the card to In CR by AI is the turn ending with one behind it. `remind-ticket-status.sh` records a commit that exited 0 as a `.dev-committed` sidecar. At the turn end `advance-after-dev.sh` takes that sidecar away and, while the recorded column still reads In Dev and the machine gates have not run, records a stop note that `replay-stop-notes.sh` prints when the person next writes.

The first turn end after a commit takes the sidecar whatever the column reads, so it costs one line per commit at most and never twice for the same one: a session with steps left says what is left, and the next commit arms it again.

## What the watcher announces

`ticket-watch-column` compares the live column against the one recorded for the session, and a mismatch counts only once it has held two polls - a hop the agent made itself is recorded by the time the second one asks. `Done` waits the same two polls before the watcher disarms, and a drag there is recorded for the status line like any other landing. A card no session registered has no record, so each new landing announces. `TICKET_WATCH_INTERVAL` sets the cadence a hand check runs at.

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
