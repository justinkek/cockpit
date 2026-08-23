---
name: launchpad:vegaos
description: Add VegaOS platform gotchas to the current project's AGENTS.md. Use when setting up a VegaOS project or when the user says /launchpad:vegaos.
---

# launchpad:vegaos

Write the VegaOS constraints and workarounds into the current project's `./AGENTS.md` so they load in every session for this repo - and only this repo.

A VPN app on VegaOS needs `/launchpad:vpn-vegaos` as well, which carries what a VPN adds on top of these.

## Source of truth

The canonical VegaOS rules live at `~/.agents-shared/includes/vegaos.md`. Read it on every run; this skill never restates a rule.

## Workflow

1. **Read the source** - read `~/.agents-shared/includes/vegaos.md` to get the latest VegaOS rules.

2. **Check the project's `./AGENTS.md`:**
   - If `./AGENTS.md` does not exist, create it with the VegaOS rules as its only content, and write `./CLAUDE.md` as one line naming it.
   - If `./AGENTS.md` exists but has no `## VegaOS` section, append the VegaOS rules at the end of the file (after a blank line).
   - If `./AGENTS.md` already has a `## VegaOS` section, replace everything from `## VegaOS` up to (but not including) the next `## ` heading or end of file with the contents of the source file.

3. **Report** what was done: created, appended, or replaced.
