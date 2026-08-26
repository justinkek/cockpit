<a href="https://www.tldraw.com/f/GzS-Hfkd2zkwaUg2epnp3?d=v-1680.-1036.4265.2474.page">
  <img width="14414" height="6190" alt="image" src="https://github.com/user-attachments/assets/91082d1d-392b-431c-99ee-8db966fe7527" />
</a>

## Install

Needs `bash`, `git` and `jq`.

    git clone https://github.com/justinkek/cockpit.git ~/cockpit
    ~/cockpit/install.sh --apply
    ~/.claude-shared/sync.sh --yes

`install.sh` symlinks the three agent trees into `$HOME`, links the `cockpit` command into `~/.local/bin`, and scaffolds `accounts.local.sh`. It writes no profile, which is why the sync is a step of its own. The sync writes to `~/.claude-cockpit` and to no other profile.

If `cockpit` still comes back `command not found`, `~/.local/bin` is not on your PATH. Add this to your shell config:

    export PATH="$HOME/.local/bin:$PATH"

## Run it

    cockpit

Every argument goes to `claude` unchanged, so `cockpit --resume` and the rest behave as they do without it.

It refuses to start outside a git repository: Claude runs with broad read and write permissions, and the repository is what keeps its edits reviewable and revertible. To start anyway, run `CLAUDE_ALLOW_NONREPO=1 cockpit`.

The profile runs on `base.settings.json` alone. To choose a model or a permission mode, write your own `agents/claude/settings/overrides/cockpit.settings.json` and run the sync again. That directory is untracked, so nobody else's choices arrive with the clone and yours never leave it.

## agents/

`agents/` is the agent-agnostic root. `agents/shared/` holds cross-agent files — the canonical `base.AGENTS.md` instruction source and `messages.json`. `agents/claude/` holds the Claude Code wiring (settings, hooks, skills, themes, plugins, sync scripts). `agents/claude/` installs to `~/.claude-shared` under its original name as a compat shim, so existing generated account configs keep resolving. `agents/codex/` is the Codex twin — it generates `~/.codex/AGENTS.md` from the same shared source (installs to `~/.codex-shared`). Cross-agent skills live in `agents/shared/skills/`; both agent syncs link them into their native user skill locations.

`agents/claude/` is the source of truth for Claude Code settings across the accounts you list in `agents/claude/accounts.local.sh`. `~/.claude-vanilla` is deliberately absent from that list: `claude-vanilla` runs Claude with none of this repo's settings, instructions, hooks or skills applied. A shared `base` + per-account `overrides` are merged into each account's real config by the sync scripts.

```sh
~/.claude-shared/sync.sh          # interactive: per-account diff, prompt, backup, write
~/.claude-shared/sync.sh --check  # report drift only, no writes
~/.claude-shared/sync.sh --yes    # apply without prompting
```

`agents/codex/` mirrors this for the Codex agent — `codex-sync` runs every concern's sync script. It generates `~/.codex/AGENTS.md` from the same `agents/shared/base.AGENTS.md`, installs the enforced settings layer from `agents/codex/settings/`, and links shared skills into `~/.agents/skills/`:

```sh
~/.codex-shared/sync.sh          # interactive: diff, prompt, backup, write
~/.codex-shared/sync.sh --check  # report drift only, no writes
~/.codex-shared/sync.sh --yes    # apply without prompting
```

The settings layer maps the Claude `settings.json` permissions onto Codex's native model, in two forms:

- `base.rules` → `~/.codex/rules/dotfiles.rules` — the execpolicy `prefix_rule` allowlist (twin of `permissions.allow`). A standalone file Codex owns whole, so it's a plain whole-file sync alongside any hand-authored rules.
- `base.config-profile.toml` → merged into `~/.codex/config.toml` — a permission profile that denies the agent read access to secret globs (twin of `permissions.deny`). Codex permission profiles gate the agent's own reader, not just shell commands. Because these keys live in the app-managed `config.toml`, `merge-config-profile` does a _targeted_ text edit (insert the top-level `default_permissions` line + a marked `[permissions.*]` block), leaving every app-owned key untouched — no re-serialization.

MCP/env and hooks are not synced yet. (A dead end worth recording: Codex's `requirements.toml` `deny_read` is not the mechanism — that file is only loaded from system/managed locations like `/etc/codex`, and its deny only ever governs sandboxed shell commands, never the agent's reader.)

Account `settings.json` / `CLAUDE.md` are **generated** from `base` + `overrides` — they are not tracked here. Workflow: edit the source → `~/.claude-shared/sync.sh` to apply.

## Send a change back

1. Fork the repository and branch off `main`.
2. Edit the files in the checkout, never in `~/.claude-cockpit` - the next sync overwrites that copy.
3. Run `./scripts/run-tests` and check every line reads OK.
4. Open a pull request saying what changed and what it is for.

## Rehearse the install

    cockpit-fresh

It clones this repository into a throwaway home, installs and syncs into it, then starts that install's own `cockpit` for you. Quit it to come back; the directory is deleted on the way out.

What it clones depends on where you run it:

| Run it from       | It installs                           |
| ----------------- | ------------------------------------- |
| a worktree        | that worktree, on the branch it is on |
| the main checkout | that checkout, on the branch it is on |
| anywhere else     | `main` from the remote                |

Cloning takes committed state, so uncommitted changes do not travel - it says so before it starts when the tree is dirty. `cockpit-fresh --print-source` prints what it would clone and stops. `COCKPIT_FRESH_REMOTE` overrides the choice with a path or a URL.
