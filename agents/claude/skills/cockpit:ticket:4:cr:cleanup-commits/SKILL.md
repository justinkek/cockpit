---
name: cockpit:ticket:4:cr:cleanup-commits
description: Analyse branch changes and produce an ordered atomic commit plan for CR
---

# code-review-cleanup-commits

Analyse all changes on the current branch vs `origin/main` and produce an ordered list of atomic commits suitable for code review.

## Usage

```
/code-review-cleanup-commits
```

## Behavior

1. Run `git diff --stat origin/main..HEAD` and `git diff origin/main..HEAD` to understand every changed file and what changed in it.
2. Group changes into atomic commits where each commit is a single coherent unit of work (one feature, one fix, one refactor).
3. Order commits by dependency — implementations before consumers (e.g. a new endpoint before the CI step that polls it, a new Docker service before the CI step that starts it).
4. For files with changes belonging to multiple commits, identify the exact line ranges and produce `git add -p` instructions noting which hunks to accept or skip.
5. Produce the exact staging commands for each commit — `git add <file>` for whole files and `git add -p <file>` (noting which hunks to accept) for partial files — not just file names.
6. Flag any changes that are temporary/debug scaffolding (prefixed `temp:`, `debug:`) and recommend dropping them entirely.

Do NOT touch git. Do NOT reset, amend, or commit anything. Output only the plan.

## Output format

For each commit, output a block: the commit message, a bullet list of its files (with line ranges for partial files), a **Stage with:** subsection of the exact shell commands to run, and a one-line rationale. Use `git add <path>` for whole files and `git add -p <path>` for partial ones, noting which hunks to accept (`y`) and skip (`n`).

Example:

`chore(build): add Gradle tasks to index Axon modules`

- `build.gradle` (lines 334–411 only — Axon tasks; skip the lfrSchemaTest removal hunk)
- `buildSrc/src/main/groovy/AxonIndexerTask.groovy`

**Stage with:**

```sh
git add buildSrc/src/main/groovy/AxonIndexerTask.groovy
git add -p build.gradle   # accept: Axon task hunks; skip: lfrSchemaTest removal hunk
```

Why these belong together: ...

After the full list, note any ambiguities or open questions that require the user's input before committing.

## Conventions

- Use conventional commit format: `type(scope): description` — the types are the ones the `cockpit:ticket:4:commit` skill lists
- Keep descriptions under 72 characters, imperative mood, no trailing period
- Scope should reflect the area changed: `ci`, `be`, `e2e`, `db`, `dev`, `deps`, `agents`
- Prefer many small commits over few large ones — a reviewer should be able to understand each commit in isolation
- Use `generate` (not `add`) in commit messages for machine-generated output files (e.g. `docs(user-stories): generate execution trees for all modules`)
- When a skill/tool produces generated output, commit them as a pair: the skill first, then its output
- Before writing a commit message that names specific modules or files (e.g. "for swaps module"), verify which modules actually contain the relevant output — don't assume from the skill description alone; run `find` or `ls` to confirm

## Staging large untracked file sets

When a commit covers many untracked files matching a pattern, use `git ls-files` piped to `xargs` — never `$(git ls-files ...)` which hits shell argument limits with thousands of files:

```sh
# Good — handles thousands of files
git ls-files --others --exclude-standard <dir> | grep "<pattern>" | xargs git add

# Bad — breaks with "Argument list too long" on large sets
git add $(git ls-files --others --exclude-standard <dir> | grep "<pattern>")
```

Use `--others --exclude-standard` to list only untracked files (respects `.gitignore`). For already-tracked modified files, use `git diff --name-only | xargs git add` instead.

## Execution workflow

Clean up the commits first with a soft reset, then rebase once at the end — NOT interactive rebase (`git rebase -i`).

1. Back up the cumulative branch diff first, so you can prove the cleanup changed only commit boundaries — not a single line of content:

   ```sh
   git diff $(git merge-base origin/main HEAD)..HEAD > /tmp/atomic-before.diff
   ```

2. Soft-reset to the merge base — NOT `origin/main`, which is ahead by however many commits main has moved since the branch diverged. This lands every change unstaged in the working tree while leaving the files themselves untouched:

   ```sh
   git reset --soft $(git merge-base origin/main HEAD)
   ```

3. Work through the commits in plan order. For each one, run its **Stage with:** commands (`git add <path>` for whole files, `git add -p <path>` for partial ones), then commit:

   ```sh
   git commit -m "<conventional commit message>"
   ```

4. Verify the recomposed commits reproduce the exact same changes — diff against the backup BEFORE rebasing (so moved-main changes don't muddy the comparison). The output must be empty:

   ```sh
   git diff $(git merge-base origin/main HEAD)..HEAD > /tmp/atomic-after.diff
   diff /tmp/atomic-before.diff /tmp/atomic-after.diff
   ```

   If it isn't empty, the cleanup dropped or altered content — fix it before continuing.

5. Once the branch is a clean set of commits, rebase onto `origin/main`. Rebasing ~10 clean commits instead of ~100 messy ones minimises the conflict surface:

   ```sh
   git rebase origin/main
   ```

6. Force-push the rebased branch:

   ```sh
   git push --force-with-lease
   ```
