## Editing config (AGENTS.md, settings & plugins)

Before adding or changing memory, a setting, or a plugin, ask who it's for — unless already explicit — and route by scope. Same pattern for all; only the file differs:

- **The team, on this repo** → committed in-repo:
  - memory → `./AGENTS.md` (and parent dirs)
  - settings → `.claude/settings.json`
- **Just me, on this repo** → settings only → `.claude/settings.local.json` (gitignored). No per-project personal memory exists; `CLAUDE.local.md` is deprecated.
- **Just me, everywhere** → edit that role's source file in the dotfiles repo, then run `"$HOME/.claude-shared/sync.sh" --apply` (don't edit the live `~/.claude*/` files — the sync regenerates them):
  - memory → the shared agent rules
  - settings → the base settings file
  - plugins → the base plugins file (then `sync.sh plugins --apply` installs across all accounts). Never edit live `installed_plugins.json` files directly.
  - The repo is the one `~/.claude-shared` points into, and its own `CLAUDE.md` maps each role to a path and says which form to write. (See also "Editing agent config" in base.AGENTS.md.)

(Precedence, highest first: memory is Managed > Project > User; settings is Managed > CLI > Local > Project > User. CLI = launch flags; Managed = the enterprise policy file — both rarely edited.)

## Claude directories

`~/.claude` is created and used by Claude Desktop too — verified by experiment (deleting `~/.claude` and launching Claude Desktop recreates it). Never describe it as CLI-only, and never park runtime state there (Desktop and `sync.sh` both touch it). Layout: each `~/.claude-*` is a Claude Code profile, and the active one is whichever the session was launched under; `~/.claude-shared` = the symlink into the dotfiles repo that is the source of truth (edit there, then `sync.sh --apply`); runtime state belongs in `~/.local/state/`.

Never read from `~/.claude/` - it is the default profile, not the active one. Read from the active profile directory - whichever `~/.claude-*` the session was launched under - or the source of truth (`~/.claude-shared/`). The sync script regenerates `~/.claude/` and profile directories from `~/.claude-shared/`, so edits to `~/.claude/` are overwritten.

## MCP plugin tool permissions (workaround)

MCP plugin tools bypass the settings.json permission prompt when not in the deny list ([claude-code#80135](https://github.com/anthropics/claude-code/issues/80135)). The three-state model (allow / deny / ask-first) collapses to two: deny or auto-allow. Until fixed upstream, compensate with behavioral rules:

- The deny list still works - denied tools are hidden from the model entirely.
- `permissions.allow` entries for MCP plugin tools are currently redundant (all non-denied plugin tools auto-allow) but keep them for when the bug is fixed.

## Code review fixes

When applying fixes during `/code-review`, commit each fix individually via the `/commit` skill before moving to the next finding. One commit per finding, never batch multiple fixes into a single commit. Each commit message should reference the finding (e.g. `fix(scope): address review finding #N`).
