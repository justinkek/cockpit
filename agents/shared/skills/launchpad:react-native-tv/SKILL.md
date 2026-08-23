---
name: launchpad:react-native-tv
description: Add React Native TV coding standards to the current project's AGENTS.md. Use when setting up a TV app or when the user says /launchpad:react-native-tv.
---

# launchpad:react-native-tv

Write the shared React Native TV coding standards into the current project's `./AGENTS.md` so they load in every session for this repo - and only this repo.

## Source of truth

The canonical React Native TV rules live at `~/.agents-shared/includes/react-native-tv.md`. Always read this file first - never hardcode the rules in this skill.

## Workflow

1. **Read the source** - read `~/.agents-shared/includes/react-native-tv.md` to get the latest React Native TV rules.

2. **Check the project's `./AGENTS.md`:**
   - If `./AGENTS.md` does not exist, create it with the React Native TV rules as its only content, and write `./CLAUDE.md` as one line naming it.
   - If `./AGENTS.md` exists but has no `## React Native TV` section, append the React Native TV rules at the end of the file (after a blank line).
   - If `./AGENTS.md` already has a `## React Native TV` section, replace everything from `## React Native TV` up to (but not including) the next `## ` heading or end of file with the contents of the source file.

3. **Report** what was done: created, appended, or replaced.
