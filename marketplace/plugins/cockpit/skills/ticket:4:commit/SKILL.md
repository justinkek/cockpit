---
name: ticket:4:commit
description: Commit the session's changes directly. Use when a logical unit of work is complete during development.
---

# commit

Commit changes in the working tree directly - no `[commit]` tag, no waiting for the user to run git commit.

Each commit is the smallest self-contained diff that builds/passes on its own. Don't accumulate a large diff and commit at the end - commit after each logical step completes. A single file change is a valid commit.

## When to invoke

1. **Commit-as-you-go (default)** - after each smallest self-contained change during development, commit it immediately. Don't wait for the user to ask.
2. **User says `/commit`** - commit all pending session changes. If they span multiple concerns, propose splitting into an ordered set of the smallest atomic commits. For a messy existing branch with many commits, use the `cockpit:ticket:4:cr:cleanup-commits` skill instead.

## Workflow

1. **Inspect the working tree.** Run `git status` (never `-uall`) and `git diff` (staged + unstaged) to see what changed. Run `git log` to see recent commit style.

2. **Check for secrets.** Scan file names and contents for `.env`, credentials, API keys, tokens, or other sensitive data. If found, exclude those files and warn the user.

3. **Scope to session changes.** Only commit files the agent created or edited in the current session. If the working tree contains pre-existing uncommitted changes (from before the session), flag them and ask the user before including them.

4. **Identify logical boundaries.** If the changes span multiple independent concerns, split into the smallest atomic commits and execute each in order. No confirmation needed - just split and commit.

   One root cause per commit. Two changes that fix different root causes are separate commits even if they produce the same user-facing symptom. Heuristic: if the commit message needs "and" or a semicolon to describe what it does, it should be split.

5. **Stage files.** Add relevant files by name - never `git add -A` or `git add .`. Exclude unrelated files, secrets, and large binaries.

6. **Commit.** Create the commit using a HEREDOC:

   ```sh
   git commit -m "$(cat <<'EOF'
   <type>(<scope>): <short description>

   Co-Authored-By: <model> <noreply@anthropic.com>
   EOF
   )"
   ```

   - Format: `<type>(<scope>): <short description>`
   - Types: feat, fix, perf, refactor, style, chore, docs, test, build, ci, revert
   - Imperative mood, under 72 characters, no trailing period
   - The `Co-Authored-By` name and email come from the system prompt's model identity (e.g. `Claude Opus 4.6 <noreply@anthropic.com>`)

7. **Verify.** Run `git status` after the commit to confirm success. If a pre-commit hook fails, fix the issue and create a NEW commit (never amend).

8. **Report.** State what was committed in one sentence. No `[commit]` tag.

## Branch guard

Before committing, check the current branch. If it is `main` or `master`, **block the commit** and ask the user to create a feature branch first.

No project opts out of this, and no section in a project's `./AGENTS.md` turns it off. A repo that used to carry one is still guarded.

## Guardrails

- Never amend a previous commit unless the user explicitly asks.
- Never force-push.
- Never skip hooks (`--no-verify`).
- Never commit files that likely contain secrets.
- If there are no changes to commit, say so and stop.
