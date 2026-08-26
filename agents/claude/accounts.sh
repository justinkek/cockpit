#!/usr/bin/env bash
#
# accounts.sh — single source of truth for the Claude account taxonomy.
#
# Sourced (not executed) by every concern's sync.*.sh — settings, plugins,
# claude-md, themes, skills — so the account list lives in exactly one place
# instead of being copy-pasted into each. Defines:
#   ACCOUNTS    — ordered, deterministic list of account names to sync.
#   acct_dir()  — maps an account name to its Claude config dir.

# Default list — overridden by accounts.local.sh if present.
ACCOUNTS=(cockpit)

# Naming convention: `claude` is the Claude Code DESKTOP app's account (it
# launches outside the claude-<name> wrappers, so it defaults to ~/.claude);
# every other account <name> maps to ~/.claude-<name>. With this convention an
# overlay usually only needs to set ACCOUNTS — acct_dir follows automatically.
acct_dir() {
  case "$1" in
    claude) printf '%s' "$HOME/.claude" ;;
    *)      printf '%s' "$HOME/.claude-$1" ;;
  esac
}

# Per-user overlay (untracked): may reassign ACCOUNTS and/or redefine acct_dir.
# Locating it needs BASH_SOURCE (bash-only). If this file is ever sourced from a
# non-bash shell, fail loudly rather than silently skip the overlay and run with
# the wrong (claude-only) account list.
if [ -z "${BASH_SOURCE:-}" ]; then
  echo "accounts.sh: must be sourced from bash (per-user overlay would be skipped)" >&2
  return 1 2>/dev/null || exit 1
fi
__accounts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$__accounts_dir/accounts.local.sh" ] && source "$__accounts_dir/accounts.local.sh"
unset __accounts_dir

for __account in "${ACCOUNTS[@]}"; do
  if [ "$__account" = "vanilla" ]; then
    echo "accounts.sh: 'vanilla' names the profile that runs with none of this repo's config, so it must never be synced" >&2
    return 1 2>/dev/null || exit 1
  fi
done
unset __account
