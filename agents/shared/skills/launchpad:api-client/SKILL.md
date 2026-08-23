---
name: launchpad:api-client
description: Add API client file conventions to the current project's AGENTS.md. Use when setting up a project's API layer or when the user says /launchpad:api-client.
---

# launchpad:api-client

Write the shared API client file conventions into the current project's `./AGENTS.md` so they load in every session for this repo - and only this repo.

## Source of truth

The canonical API client rules live at `~/.agents-shared/includes/api-client.md`. Always read this file first - never hardcode the rules in this skill.

## Workflow

1. **Read the source** - read `~/.agents-shared/includes/api-client.md` to get the latest API client rules.

2. **Check the project's `./AGENTS.md`:**
   - If `./AGENTS.md` does not exist, create it with the API client rules as its only content, and write `./CLAUDE.md` as one line naming it.
   - If `./AGENTS.md` exists but has no `## API client` section, append the API client rules at the end of the file (after a blank line).
   - If `./AGENTS.md` already has a `## API client` section, replace everything from `## API client` up to (but not including) the next `## ` heading or end of file with the contents of the source file.

3. **Report** what was done: created, appended, or replaced.
