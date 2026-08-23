---
name: launchpad:react-native
description: Add React Native coding standards to the current project's AGENTS.md. Use when setting up a React Native project or when the user says /launchpad:react-native.
---

# launchpad:react-native

Write the shared React Native coding standards into the current project's `./AGENTS.md` so they load in every session for this repo - and only this repo.

## Source of truth

The canonical React Native rules live at `~/.agents-shared/includes/react-native.md`. Always read this file first - never hardcode the rules in this skill.

## Workflow

1. **Read the source** - read `~/.agents-shared/includes/react-native.md` to get the latest React Native rules.

2. **Check the project's `./AGENTS.md`:**
   - If `./AGENTS.md` does not exist, create it with the React Native rules as its only content, and write `./CLAUDE.md` as one line naming it.
   - If `./AGENTS.md` exists but has no `## React Native` section, append the React Native rules at the end of the file (after a blank line).
   - If `./AGENTS.md` already has a `## React Native` section, replace everything from `## React Native` up to (but not including) the next `## ` heading or end of file with the contents of the source file.

3. **Report** what was done: created, appended, or replaced.
