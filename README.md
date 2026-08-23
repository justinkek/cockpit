<a href="https://www.tldraw.com/f/GzS-Hfkd2zkwaUg2epnp3?d=v-1680.-1036.4265.2474.page">
  <img width="14414" height="6190" alt="image" src="https://github.com/user-attachments/assets/91082d1d-392b-431c-99ee-8db966fe7527" />
</a>

## agents/

`agents/` is the agent-agnostic root. `agents/shared/` holds cross-agent files — the canonical `base.AGENTS.md` instruction source and `messages.json`. `agents/claude/` holds the Claude Code wiring (settings, hooks, skills, themes, plugins, sync scripts). `agents/claude/` installs to `~/.claude-shared` under its original name as a compat shim, so existing generated account configs keep resolving. `agents/codex/` is the Codex twin — it generates `~/.codex/AGENTS.md` from the same shared source (installs to `~/.codex-shared`). Cross-agent skills live in `agents/shared/skills/`; both agent syncs link them into their native user skill locations.

`agents/claude/` is the source of truth for Claude Code settings across the accounts you list in `agents/claude/accounts.local.sh`. `~/.claude-vanilla` is deliberately absent from that list: `claude-vanilla` runs Claude with none of this repo's settings, instructions, hooks or skills applied. A shared `base` + per-account `overrides` are merged into each account's real config by the sync scripts.

```sh
claude-sync            # interactive: per-account diff, prompt, backup, write
claude-sync --check    # report drift only, no writes
claude-sync --yes      # apply without prompting
```

`agents/codex/` mirrors this for the Codex agent — `codex-sync` runs every concern's sync script. It generates `~/.codex/AGENTS.md` from the same `agents/shared/base.AGENTS.md`, installs the enforced settings layer from `agents/codex/settings/`, and links shared skills into `~/.agents/skills/`:

```sh
codex-sync             # interactive: diff, prompt, backup, write
codex-sync --check     # report drift only, no writes
codex-sync --yes       # apply without prompting
```

The settings layer maps the Claude `settings.json` permissions onto Codex's native model, in two forms:

- `base.rules` → `~/.codex/rules/dotfiles.rules` — the execpolicy `prefix_rule` allowlist (twin of `permissions.allow`). A standalone file Codex owns whole, so it's a plain whole-file sync alongside any hand-authored rules.
- `base.config-profile.toml` → merged into `~/.codex/config.toml` — a permission profile that denies the agent read access to secret globs (twin of `permissions.deny`). Codex permission profiles gate the agent's own reader, not just shell commands. Because these keys live in the app-managed `config.toml`, `merge-config-profile` does a _targeted_ text edit (insert the top-level `default_permissions` line + a marked `[permissions.*]` block), leaving every app-owned key untouched — no re-serialization.

MCP/env and hooks are not synced yet. (A dead end worth recording: Codex's `requirements.toml` `deny_read` is not the mechanism — that file is only loaded from system/managed locations like `/etc/codex`, and its deny only ever governs sandboxed shell commands, never the agent's reader.)

Account `settings.json` / `CLAUDE.md` are **generated** from `base` + `overrides` — they are not tracked here. Workflow: edit the source → `claude-sync` to apply.
