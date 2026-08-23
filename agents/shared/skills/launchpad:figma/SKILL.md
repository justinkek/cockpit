---
name: launchpad:figma
description: Add Figma workflow standards to the current project's AGENTS.md. Use when setting up a project with Figma designs or when the user says /launchpad:figma.
---

# launchpad:figma

Write the shared Figma workflow standards into the current project's `./AGENTS.md` so they load in every session for this repo - and only this repo.

## Source of truth

The canonical Figma rules live at `~/.agents-shared/includes/figma.md`. Always read this file first - never hardcode the rules in this skill.

## Workflow

1. **Read the source** - read `~/.agents-shared/includes/figma.md` to get the latest Figma rules.

2. **Check the project's `./AGENTS.md`:**
   - If `./AGENTS.md` does not exist, create it with the Figma rules as its only content, and write `./CLAUDE.md` as one line naming it.
   - If `./AGENTS.md` exists but has no `## Figma source of truth` section, append the Figma rules at the end of the file (after a blank line).
   - If `./AGENTS.md` already has a `## Figma source of truth` section, replace everything from `## Figma source of truth` up to (but not including) the next `## ` heading or end of file with the contents of the source file.

3. **Report** what was done: created, appended, or replaced.
