---
name: launchpad:vpn-vegaos
description: Add VPN on VegaOS gotchas to the current project's AGENTS.md. Use when setting up a VegaOS VPN project or when the user says /launchpad:vpn-vegaos.
---

# launchpad:vpn-vegaos

Write the VPN on VegaOS constraints and workarounds into the current project's `./AGENTS.md` so they load in every session for this repo - and only this repo.

## Source of truth

The canonical VPN on VegaOS rules live at `~/.agents-shared/includes/vpn-vegaos.md`. Always read this file first - never hardcode the rules in this skill.

## Workflow

1. **Read the source** - read `~/.agents-shared/includes/vpn-vegaos.md` to get the latest VPN on VegaOS rules.

2. **Check the project's `./AGENTS.md`:**
   - If `./AGENTS.md` does not exist, create it with the VPN on VegaOS rules as its only content, and write `./CLAUDE.md` as one line naming it.
   - If `./AGENTS.md` exists but has no `## VPN on VegaOS` section, append the VPN on VegaOS rules at the end of the file (after a blank line).
   - If `./AGENTS.md` already has a `## VPN on VegaOS` section, replace everything from `## VPN on VegaOS` up to (but not including) the next `## ` heading or end of file with the contents of the source file.

3. **Report** what was done: created, appended, or replaced.
