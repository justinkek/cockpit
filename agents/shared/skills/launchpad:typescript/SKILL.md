---
name: launchpad:typescript
description: Add TypeScript coding standards to the current project's AGENTS.md. Use when setting up a TypeScript project or when the user says /launchpad:typescript.
---

# launchpad:typescript

Write the shared TypeScript coding standards into the current project's `./AGENTS.md` so they load in every session for this repo - and only this repo.

## Source of truth

The canonical TypeScript rules live at `~/.agents-shared/includes/typescript.md`. Always read this file first - never hardcode the rules in this skill.

## Workflow

1. **Read the source** - read `~/.agents-shared/includes/typescript.md` to get the latest TypeScript rules.

2. **Check the project's `./AGENTS.md`:**
   - If `./AGENTS.md` does not exist, create it with the TypeScript rules as its only content, and write `./CLAUDE.md` as one line naming it.
   - If `./AGENTS.md` exists but has no `## TypeScript` section, append the TypeScript rules at the end of the file (after a blank line).
   - If `./AGENTS.md` already has a `## TypeScript` section, replace everything from `## TypeScript` up to (but not including) the next `## ` heading or end of file with the contents of the source file.

3. **Report** what was done: created, appended, or replaced.
