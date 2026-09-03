# Agent Rules

## Git state

Never state push, sync or branch-tracking status without checking it in the same turn - `git status --short --branch`, or `git rev-list --count @{u}..HEAD`. Having just committed says nothing about what is on the remote.

Do not raise pushing, committing or other routine git hygiene under `[queue]`. Say it once, tied to the thing that needs it - a PR reply citing a commit needs that commit on the remote for the link to resolve - never as a standing reminder.

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

## Notion page formatting

Read `~/.claude-shared/templates/notion-writing.md` before writing to a Notion page.

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

## Reaching the skill-writing guidance

`require-skill-guidance.sh` records a `writing-great-skills` invoke against the session, and refuses a write to a `SKILL.md` that no such invoke came before. The shared rules carry the instruction; the guard is what a session that skipped it meets. Each mode is registered separately - `record` on the `Skill` tool, the refusal on `Edit|Write|Bash`.

`Bash` is in that list because a session in auto mode edits files with `sed` and heredocs rather than the edit tools, so a guard reading `file_path` alone would never see those writes. On a shell command the guard reads the command instead, and refuses a redirect whose target is a `SKILL.md`, an in-place `sed` or `perl` naming one, and a `tee`, `cp`, `mv` or `install` onto one. Reading one is not writing it, so `cat`, `grep` and a redirect of its content elsewhere all pass.

The marker sits beside the `.ticket` and `.step` sidecars, so it is per session and goes when the session does. Another agent gets the instruction and no refusal, because the hook is Claude's.

## The register instructions are written in

Three kinds of clause read alike and only the first goes. A **reason** names the benefit the author wanted - "so items are easy to reference by number". A **consequence** names what follows from a fact the agent has to act on - "a skipped column cannot be repaired, so the first pass must be correct". A **counter-case** names what does not count as following the rule - "a reply that moves on without naming an option is not an answer to it". Cutting a reason changes nothing; cutting either of the others changes behaviour.

`guard-instruction-register.sh` carries the rule it enforces, the forms it refuses and the files it scans.

## Logs

Permission prompt audit log: `~/.claude-logs/prompt-audit.jsonl` - one JSON line per actual permission prompt (`{ts, account, session_id, cwd}`), written by the `log-permission-prompt.sh` notification hook. To correlate a prompt to the command that triggered it, match `session_id` + nearest preceding `tool_use` in that session's transcript.
