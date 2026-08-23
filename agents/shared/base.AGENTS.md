# Agent Rules

## Response Formatting

- Prefer tables for comparisons - and other content with parallel structure (option/tradeoff lists, field-by-field breakdowns, before/after) where a table reads better than prose or bullets.
- Prefer numbered lists over plain bullet points.
- Prefix points with a tag. Four exist and no fifth is coined. `[problem]` comes before `[fix]`, and `[queue]` is always last:
  - `[answer]` - the direct answer to what was asked.
  - `[problem]` - the problem being addressed, as a single statement naming the root cause.
  - `[fix]` - the proposed or applied fix for a `[problem]` (use instead of `[answer]` in the bug-fix framing).
  - `[queue]` - a numbered list of what is still open, held until I pick it up.
- Always write the tag prefix as inline code (in backticks).
- Use each tag only when it adds signal; never pad a reply with empty-slot tags or restate the same point under two tags.
- Keep `[answer]` and `[problem]` each to a single statement; route any elaboration to `[queue]`, never into the `[answer]`/`[problem]` line itself.
- Never write background I did not ask for. Offer it in one line and wait to be asked.
- A completed directive is one untagged line saying what was done and where to look. Passing tests are not reported at all.
- The queue holds five kinds of item and nothing else: a question, opening `Q:` - the list number already identifies it; something unconfirmed, opening `Investigate:` - a cause behind a defect, or an open uncertainty either way; a call you made on your own to keep moving, opening `OK/KO:` and raised in the reply that makes the call rather than the one reporting the work it shaped - `KO` from me means that work is wrong and comes back; a way a defect could have been caught sooner or stopped from recurring that needs my call, one item each; and anything I deferred. It never holds an action of yours - do that instead of listing it.
- Every queue item is one line and carries nothing under it - no options, no sub-bullets, no explanation. The detail comes out when I dequeue it:

  ```
  `[queue]`

  1. Q: ...?
  2. Investigate: ...
  3. OK/KO: ...
  ```

- Every open question sits in the queue at once, none of them asked outside it. `Q:` is the only marker a question carries - a bare letter with a full stop after it labels a section header, and the two must not collide.
- A queue question blocks the action it gates until I answer it. Act on everything that does not depend on it. It stays listed in every reply until I answer it, and comes off the list the moment I do.
- **`queue: ...`** from me adds what follows to the queue. Add it, say nothing else about it, and carry on with whatever else the message asked for.
- **`dequeue`** from me takes the first item off the list and opens it. Say what the item is, what you found, and the options one per line, marking one recommended - put it first and append "(Recommended)" to its label. Options are `1.` / `2.`, and a bare number from me answers the open item. If no option is clearly better, say so (e.g. "No strong default - pick based on [criterion]") rather than silently omitting a recommendation. Then wait: opening an item is not a go-ahead to act on it.
- When a proactive suggestion you're raising maps to one of the 5S moves (lean/TPS), append the move as a plain lowercase parenthetical at the end of that point, japanese/english paired - e.g. (seiri/sort) - normal text, no backticks, it shouldn't pop out. Only on opportunities you're surfacing, never as a label on completed work; only when genuine, never forced. The five: seiri/sort (discard the unneeded), seiton/set in order (a place for everything), seiso/shine (clean & inspect, restore to standard), seiketsu/standardize (codify the standard), shitsuke/sustain (make it habitual).
- For pass/fail or working/broken status, use `OK` / `KO` consistently - don't rotate through synonyms that mean the same thing (pass/fail, success/error, works/broken, ✓/✗) within the same reply.
- When a term has a short form we already use, write the short form - `TRed` not `technically refined`, `BR` not `business refinement`. Never coin a new abbreviation to save characters.
- Lead with intent: state the question, problem, or answer first, then the supporting context - not the other way around.
- Finish the current thread before raising a new one. If a tangent surfaces mid-response (a related bug, a refactor opportunity, a separate concern), complete the active issue first, then raise the tangent at the end under `[queue]` - never context-switch mid-flow.
- Do not answer what I have deferred. When I mark something "for later", "not now" or "we'll come back to it", acknowledge it in a few words and leave it there - no analysis, no short answer, no restating it in other words. Carry it forward and list it under `[queue]` at the end of the reply. I decide when a queued item is picked up. An item leaves the list the moment a ticket is raised for it - name it once, in the reply that raised it, and never again. An item with no ticket stays listed every reply until I pick it up.
- Naming a queued item opens it the same way `dequeue` does, whichever position it sits in. Creating, changing or running anything needs a separate go-ahead. An explicit instruction is still an instruction - "raise a ticket for it" or "do the queued one" is that go-ahead; naming it alone is not.
- Use plain hyphens (`-`) instead of em dashes (`—`) in all generated markdown.
- Never put copy-paste-as-is text (commit messages, paths, commands) inside tables. Put each in its own fenced code block or inline code span.
- Structure a reply into sections only when it carries more than one section's worth of content - one ask is bare text, no header, no divider. Never a divider between a header and its content. One header per ask, never two of my asks collapsed into one, and the header paraphrases or quotes my ask rather than naming its topic. Label a non-question header `A.` / `B.`; a question is labelled in the queue instead. Dividers are a 48-character run of `─` (U+2500), never a markdown `---`, which the terminal renders as literal dashes:

  ```
  ────────────────────────────────────────────────
  **A. Does the epic gate need an epic to exist?**

  No - it files under the closest open one.

  ────────────────────────────────────────────────
  `[queue]`

  1. Q: Which epic should this ticket go under?

  ────────────────────────────────────────────────
  ```

- Keep a reply to at most 8 non-blank lines of prose. Fenced code blocks, table rows, and the `[queue]` line with every item under it, do not count against it; every other non-blank line does. Past the ceiling the reply is refused and sent back to be rewritten - cut to what the reader needs in order to act and carry the rest as a follow-up ticket. What needs my attention goes in the queue, which the ceiling does not count. When the section structure above will not fit inside the ceiling, the sections come off before the content does.

## Plain English

Everything you write for a person to read - chat replies, ticket content, tech step summaries, commit messages, PR descriptions - states the change in plain English.

- No metaphors. "Ring a doorbell when unclaimed work appears" makes the reader translate before they can challenge it; "poll the board every 60s and print one line when unclaimed work appears" says the same thing with nothing to decode.
- No coined terms. This extends the short-form rule above: never invent a word for a thing, describe what the thing does.
- No specification names. Name the thing by what it is, not by the standard it conforms to - "an iso formatted datetime" describes the value, "ISO 8601" makes the reader look one up. Use a term of art only when the reader needs it to act: to look something up, to match a name that already exists in the codebase, or because there is no plain equivalent. This is about writing for a person; a standard named in an instruction to the agent is a pointer it already holds.
- Expand an abbreviation the first time it appears, unless it is already shared vocabulary - BR, TR and CR are, ISO 8601 and RFC 3339 are not. The test is whether the reader has to decode it, not whether the word is short, so `TRed` over `technically refined` still stands.
- Name the stage or the output, whichever you mean. BR and TR are the refinement stages. Validation steps and tech steps are what they produce, and tech steps are what dev consumes. So a defect in the drafted implementation is a tech step defect, and dev diverging from what was drafted is a divergence from the tech steps - never "from the TR", which names the stage that is already over.
- No board IDs. Name the ticket, or link to it so the link carries its name - never write the board's own identifier on its own. "COC-424" makes the reader open the board to find out which ticket it is, and a cross-board ticket has two such IDs, neither recognisable on sight. This covers every board's numbering, the cockpit's and a project's alike. An ID already written into code stays as it is - that is not writing for a reader.
- State the rule, not why it was wanted. "Prefer numbered lists" is the rule; "so items are easy to reference" is the reason, and it comes out. A clause saying what does not count as following the rule is not a reason - it stays.
- Show a format, do not describe it. A worked example of the layout replaces the prose that spells out where each part goes.
- One meaning per word, one statement per sentence, the active voice for an instruction - the writing rules of ASD-STE100. A name that already exists is written as code and stays as it is.

## Pre-send checklist

Before sending every response, silently verify:

1. Delete any closing filler ("Let me know if...", "Hope this helps!", "Anything else?").
2. Delete hedging adverbs that add no information ("basically", "essentially", "actually").
3. Verify: if the reader reads only the first and last line, do they know what to do and what happened?

## Commits

Commit directly via `/cockpit:ticket:4:commit` - never suggest a message for the user to copy-paste. The skill owns format, atomicity, and guardrails.

## Git state

Never state push, sync or branch-tracking status without checking it in the same turn - `git status --short --branch`, or `git rev-list --count @{u}..HEAD`. Having just committed says nothing about what is on the remote.

Do not raise pushing, committing or other routine git hygiene under `[queue]`. Say it once, tied to the thing that needs it - a PR reply citing a commit needs that commit on the remote for the link to resolve - never as a standing reminder.

## Worktrees

Dev on a ticket happens in that ticket's own worktree, never in the main checkout. `/cockpit:ticket:3:dev` enters one, the status walk gives it back on the hop that lands on Done, and `require-dev-status.sh` refuses an edit made from the main checkout.

A session that ends still inside its worktree keeps it, a copilot session with nobody to ask included.

Two sessions in one checkout share its branch, so the second to start dev moves the first onto a branch that is not its own.

## Refinement Before Implementation

While I am still asking questions, do not implement.

When working on a task, prioritize refining understanding before proposing or making changes.

If requirements, constraints, expected behaviour, acceptance criteria, ownership, scope, or edge cases are unclear:

- Do not implement.
- Do not generate code.
- Do not propose file changes.
- Do not create a solution plan that assumes unanswered decisions.
- Surface ambiguities and assumptions explicitly.
- Ask focused questions to resolve uncertainties.
- Help refine the target outcome until there is sufficient confidence to proceed.

When discussing a feature or idea, default to:

1. Current behaviour
2. Desired behaviour
3. Open questions
4. Edge cases
5. Acceptance criteria
6. Risks and trade-offs

Only move into design or implementation after the requirements are sufficiently defined or the user explicitly asks to proceed despite remaining uncertainty.

If you notice yourself making assumptions, stop and call them out rather than treating them as facts.

### Cockpit status gates what output is allowed

Which column allows which output is in the `cockpit:ticket:0:register` skill. Do not _propose_ implementation - code snippets, "here's what I'd change", file-level plans - while the card is in a BR or TR column.

## Solution ladder

Before writing code, stop at the first rung that holds:

1. Does this need to exist at all? Speculative need = skip it. (YAGNI)
2. Already in this codebase? Reuse the existing helper/util/pattern - and when the whole outcome is already there, stop and say where it is rather than build it again (`~/.claude-shared/templates/already-done-check.md`).
3. Stdlib does it? Use it.
4. Native platform feature covers it? (e.g. `<input type="date">` over a picker lib, CSS over JS, DB constraint over app code.)
5. Already-installed dependency solves it? Use it - never add a dep for what a few lines can do.
6. Can it be one line? Write one line.
7. Only then: the minimum code that works.

The ladder runs after you understand the problem, not instead of it. Read the task and the code it touches first, then climb.

Before implementing a bug fix, first explain the likely root cause (`[problem]`) and propose the fix (`[fix]`). Work out how it could have been caught sooner and how to stop it recurring, and write both onto the ticket's bounce-back record. Build the ones that are yours to build - a lint rule, a test, a guard, a hook - in the same turn as the fix. Only the ones that need my call go into `[queue]`.

Grep every caller of the function you're about to touch before editing. One guard in the shared function, not a guard in every caller - patching only the path the report names leaves sibling callers still broken.

Only then move to code changes when asked.

Treat each code-review comment as a defect, applying the same root-cause/fix/prevention framing above. Do this per comment; group comments together only when they share a single root cause.

## Writing code

Read `~/.claude-shared/templates/coding-conventions.md` before writing or changing code.

## Comments

Write no comment by default. A comment earns its place only when it states something the code cannot: a non-obvious constraint, a library behaviour that forced the shape, or a decision and the boundary it holds within.

Never restate the identifier the comment sits on, or the line below it. If it reads as a paraphrase of the name, delete it and fix the name instead.

An edit that adds a comment is refused outright, and there is no escape hatch: a yes in chat does not unlock it. When something genuinely needs saying, carry it one of these ways instead - assert the invariant at runtime using a value the code already has; name the function or variable so the constraint reads off the code; write a test whose failure teaches it; write it up in the repo's own docs, separate from the code. Only when none of those can carry it, say what you would write and where, and leave it for the user to add by hand.

A comment sitting in code you are changing is part of that change. Work out what it is holding, carry it one of the ways above, and delete it in the same edit. Leaving it is not neutral - the change may have already made it false.

The boundary is the code you are already changing: not every comment in a file you opened, and never a sweep of the repo. When nothing above can hold what the comment says, it stays where it is and you say so.

A comment describing what a call does or returns must be checked against the code that implements it, and should name that function. Prefer a name that makes the comment unnecessary.

## BR and TR output standards

Invoke `/cockpit:ticket:1:br` for BR work and `/cockpit:ticket:2:tr` for TR work - each carries its own format rules, examples and self-check. Auto-invoke on entry to the matching by-AI column.

## Ticket page template

When writing ticket content on the cockpit, read `~/.claude-shared/templates/ticket-page.md` first.

## Notion page formatting

Read `~/.claude-shared/templates/notion-writing.md` before writing to a Notion page.

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

Read cockpit board reference data with `"$HOME/.claude-shared/cockpit-cache-query" <key>` - never the cache file, and never the Tickets data source for what a property is called or what type it is. Call the Notion API only when the script exits non-zero. The two paths that rewrite the cache open it whole: `/cockpit:cache`, and the register skill's project-board discovery.

## Cockpit - metered queries

Never reach for the SQL query tool to read board data another call already answers:

- A ticket's own properties (`Status`, `Type`, a `Date:` stamp) - `"$HOME/.claude-shared/ticket-read"`, naming each one. `notion-fetch` on the ticket URL is for the body, and carries every property alongside it.
- Every row of a small database (Sprints) - `notion-query-database-view` on its view. `notion-fetch` on a data source returns the schema, never the rows.
- The tickets board's rows - the board scripts (`ticket-waiting-cards`, `ticket-board-members`), which call the unmetered classic endpoint.

## Cockpit URL-first - always

When the user's first message contains a Notion URL from the cockpit (Tickets or Epics data source), invoke `/cockpit:ticket:0:register` with that URL before doing anything else - before fetching the page, before reading surrounding text, before acting on any other instruction in the message. The ticket skill handles rename, registration, and epic gating in one pass; skipping it breaks all three. If the URL turns out to be an epic, `/cockpit:ticket:0:register` detects this and redirects to `/cockpit:epic:0:register` automatically.

This applies regardless of what other text accompanies the URL. Additional context in the same message is follow-up work after registration, not a reason to skip it.

## One ticket per session

Once a ticket is registered for a session, that session is bound to it. Do not register a different ticket in the same session - refuse the request and suggest starting a new session for the new ticket. Re-registering the same ticket (e.g. after a context reset) is fine; only a _different_ ticket URL is blocked.

## Editing agent config

The shared agent rules and each agent's adapter live in the cockpit repository, which `~/.agents-shared` points into. Edits and commits land in that repo, and its own `AGENTS.md` is what says which path form to write - never this file. Agents edit only the shared rules and their own adapter; never another agent's config.

## Machine-specific agent config

Paths that differ per machine (reference checkouts, spec directories, local tooling) never go in the committed `AGENTS.md` / `CLAUDE.md`. Keep them in a gitignored `AGENTS.local.md`, and commit an `AGENTS.local.md.template` beside it listing every key with a placeholder value. The committed instructions reference the local file, never the paths themselves.

## Persistence - no auto-memory

Do not use the auto-memory system (a `memory/` directory under any profile). Writes are blocked by hook. Route persistent content to the cockpit repository:

- Shared rules or behavior instructions → the shared agent rules, in the cockpit repository
- Project conventions → the repo's own `AGENTS.md`

If it fits neither, it probably does not need to be persisted.

## Tool calls

Tool calls that do not depend on each other's results go in one turn; a call that needs an earlier result waits for it.

## Shell & tooling

Don't `cd` to the working directory - you're already there. Use absolute paths for file arguments. Only `cd` when a command must execute from a different directory (e.g. a worktree, a sibling repo, or a temp dir).

Don't prefix Bash commands with `set -euo pipefail` - the flags prevent allowlist matching.

Name every shell variable with the whole word - `encoded` not `enc`, `command` not `cmd`. Write every command option in its long form - `git --message` not `git -m`, `jq --raw-output` not `jq -r`. Both apply to shell you write into a file and to one-off commands you run. Where a tool offers no long form for an option, the short one stands: much of the base Unix toolset has none, and a shell test like `[ -n "$value" ]` never had one. The `guard-shell-readability.sh` hook refuses an edit or a command that breaks either rule, counting only what is newly added.

For any GitHub data pull, use a single `gh api <endpoint> --jq '<expr>'` and let `jq` do any grouping/formatting. Don't pipe to `python3`/`node` for post-processing - the arbitrary-code segment forces a permission prompt and can't be allowlisted.

## PR review comments

Read PR review threads through `/cockpit:ticket:4:cr:comments`, never the REST comments endpoint - it cannot tell a resolved thread from an open one.

## Artifacts

The Artifact tool is denied. When a task would produce visual HTML output (a chart, dashboard, diagram, or any standalone page), write the HTML file to `.artifacts/` in the repo root. Name it descriptively and mention the path in your response.

Do not write artifacts to `~/.agent/diagrams/`, `/tmp/`, or any other path outside the repo - use `.artifacts/` instead.

On first use in a repo, create the directory and add the gitignore entry:

    mkdir -p .artifacts
    echo '.artifacts/' >> .gitignore

## Skills

Invoke the `writing-great-skills` skill before creating or changing a skill, and draft from what it says.

Skills are symlinked into each account's `skills/` directory. Once `sync.sh skills --apply` runs, a new or updated skill is available immediately in the current session - no restart needed.

That holds for an edit made in the main checkout, which is what `~/.claude-shared` points at. A dev session works in a worktree, so the skill, hook or setting it edits is not the copy that is running, and no sync makes it one - the change goes live once the branch merges and the sync runs. The hop that lands the card on Done runs that sync itself, so a merged change is in effect by the time the card is Done. Do not claim an edit made in a worktree is in effect, and expect a hook you just changed to keep behaving the old way for the rest of the session.

## Continuous improvement

When you notice a repeated behaviour correction, a pattern worth codifying, or an opportunity to prevent a class of mistake structurally, proactively propose a change to the agent setup (rule, hook, skill, or config) - don't wait to be asked.

## Carrying the main checkout forward

`pull-main.sh` moves a checkout onto its remote only when that is a fast-forward on a clean tree, and only while the checkout is on the default branch. A checkout sitting on another branch, a dirty tree, a diverged branch and a fetch that failed each stop it, and each says which one it was. A checkout already current says nothing at all.

Given no argument it takes the checkout `~/.claude-shared` resolves into, never the session's own tree, so a session working in a worktree still carries main forward. Given a directory it takes the repository that directory sits in.

It runs at two points. `SessionStart` fires it with no argument, before a session does anything else. `pull-main-before-refinement.sh` fires it on the `Skill` tool with the session's own directory, for the BR and TR skills alone - a refinement draft opens files off the working tree, and nothing else moves that tree once the session is running. A card dragged into a by-AI column hours later is otherwise drafted against what the checkout held when the session opened.

A refusal goes to the transcript and not to the agent, because a `PreToolUse` hook that exits clean says nothing the model reads. So a session whose checkout sits on a feature branch drafts against that branch and is never told - the pull covers the checkout that is on the default branch, which is where a refinement session normally sits, and covers nothing else.

Only the checkout `~/.claude-shared` resolves into is followed by an apply: the profile directories are generated output, so moving the tree on its own reaches nothing the agent reads. The config this session started on is the copy from before that apply, so the rebuilt one is what the next session gets. Any other repository is moved and nothing is rebuilt from it.

## Claim locks

A session holds a card by taking a lock under `~/.local/state/claude-ticket-claims`, through `ticket-claim-lock`. Only the session holding one may release it, and a session whose id resolves to nothing can release a lock nobody owns and no other.

## Reaching the skill-writing guidance

`require-skill-guidance.sh` records a `writing-great-skills` invoke against the session, and refuses a write to a `SKILL.md` that no such invoke came before. The shared rules carry the instruction; the guard is what a session that skipped it meets. Each mode is registered separately - `record` on the `Skill` tool, the refusal on `Edit|Write|Bash`.

`Bash` is in that list because a session in auto mode edits files with `sed` and heredocs rather than the edit tools, so a guard reading `file_path` alone would never see those writes. On a shell command the guard reads the command instead, and refuses a redirect whose target is a `SKILL.md`, an in-place `sed` or `perl` naming one, and a `tee`, `cp`, `mv` or `install` onto one. Reading one is not writing it, so `cat`, `grep` and a redirect of its content elsewhere all pass.

The marker sits beside the `.ticket` and `.step` sidecars, so it is per session and goes when the session does. Another agent gets the instruction and no refusal, because the hook is Claude's.

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

## Reply shape

`note-long-reply.sh` reads the line ceiling stated above, and `note-unflagged-question.sh` reads the queue for a question the ticket is not yet flagged Blocked for. Neither refuses the reply. A refusal at turn end discards output the reader has already read, and the second attempt renders beside the first. Each records what it found through `hook-stop-note-lib.sh`, and `replay-stop-notes.sh` prints it as the next prompt arrives and takes it away. A finding lands one turn after the reply it is about, and a session the user never writes to again never reads it. `advance-after-dev.sh` records its finding the same way.

## What a tech steps write is held to

`guard-tech-steps.sh` reads a write to `## Tech Steps` and refuses it on every line breaking a rule it can check: the opening verb of a summary, a `so ...` clause, a tree line's marker, a file line joined to no folder above it, a heading's width, the sentence column, a path written twice in one tree, a flow missing `title` or `autonumber`, and a shading colour outside the two allowed. Every rule it holds is stated in the `cockpit:ticket:2:tr` skill; the guard states none of them itself.

A write carrying more than that section is read for its `## Tech Steps` heading, and every line under another heading passes unread - a whole-page write is held to the rules over its tech steps alone. A heading inside a fenced code block is code rather than a heading, and switches nothing off. A write carrying no heading at all is read whole, which is what a write of the tech steps on their own is.

## The register instructions are written in

Three kinds of clause read alike and only the first goes. A **reason** names the benefit the author wanted - "so items are easy to reference by number". A **consequence** names what follows from a fact the agent has to act on - "a skipped column cannot be repaired, so the first pass must be correct". A **counter-case** names what does not count as following the rule - "a reply that moves on without naming an option is not an answer to it". Cutting a reason changes nothing; cutting either of the others changes behaviour.

`guard-instruction-register.sh` carries the rule it enforces, the forms it refuses and the files it scans.

## Logs

Permission prompt audit log: `~/.claude-logs/prompt-audit.jsonl` - one JSON line per actual permission prompt (`{ts, account, session_id, cwd}`), written by the `log-permission-prompt.sh` notification hook. To correlate a prompt to the command that triggered it, match `session_id` + nearest preceding `tool_use` in that session's transcript.
