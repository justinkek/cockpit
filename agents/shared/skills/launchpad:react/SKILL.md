---
name: launchpad:react
description: Add React coding standards to the current project's AGENTS.md. Use when setting up a React project or when the user says /launchpad:react.
---

# launchpad:react

Write the shared React coding standards into the current project's `./AGENTS.md` so they load in every session for this repo - and only this repo.

## Source of truth

The canonical React rules live at `~/.agents-shared/includes/react.md`. Always read this file first - never hardcode the rules in this skill.

## Workflow

1. **Read the source** - read `~/.agents-shared/includes/react.md` to get the latest React rules.

2. **Check the project's `./AGENTS.md`:**
   - If `./AGENTS.md` does not exist, create it with the React rules as its only content, and write `./CLAUDE.md` as one line naming it.
   - If `./AGENTS.md` exists but has no `## React` section, append the React rules at the end of the file (after a blank line).
   - If `./AGENTS.md` already has a `## React` section, replace everything from `## React` up to (but not including) the next `## ` heading or end of file with the contents of the source file.

3. **Report** what was done: created, appended, or replaced.
