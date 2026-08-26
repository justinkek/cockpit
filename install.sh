#!/usr/bin/env bash
#
# install.sh — symlink this repo's agent setup into $HOME.
#
# Default is a DRY RUN: it reports what it would do and changes nothing.
# Re-run with --apply to actually create the symlinks. Existing real files
# and symlinks pointing elsewhere are backed up to <target>.bak-<ts> first —
# never deleted.
#
# Usage: install.sh [--apply]
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APPLY=0
for arg in "$@"; do
  case "$arg" in
    --apply)   APPLY=1 ;;
    -h|--help) echo "usage: install.sh [--apply]"; exit 0 ;;
    *)         echo "error: unknown arg: $arg" >&2; exit 2 ;;
  esac
done

if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'; C_DIM=$'\033[2m'
else
  C_RESET=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_DIM=''
fi

# repo-relative source  ->  target in $HOME
MAP=(
  "agents/claude:$HOME/.claude-shared"
  "agents/shared:$HOME/.agents-shared"
  "agents/codex:$HOME/.codex-shared"
  "agents/claude/bin/cockpit:$HOME/.local/bin/cockpit"
  "agents/claude/bin/cockpit-fresh:$HOME/.local/bin/cockpit-fresh"
)

# repo-relative example  ->  per-user target, COPIED from the example ONCE and
# only when the target is absent. These hold per-user values (git identity, the
# account list) that the user then edits; an existing target is never touched.
SCAFFOLD=(
  "agents/claude/accounts.local.sh.example:$DIR/agents/claude/accounts.local.sh"
  "agents/claude/settings/base.settings.local.json.example:$DIR/agents/claude/settings/base.settings.local.json"
)

ts="$(date +%Y%m%d-%H%M%S)"
changes=0

for entry in "${MAP[@]}"; do
  src="$DIR/${entry%%:*}"
  dst="${entry#*:}"

  if [ ! -e "$src" ]; then
    echo "${C_RED}✗ ${entry%%:*}${C_RESET}  missing in repo ($src) — skipping"
    continue
  fi

  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    echo "${C_GREEN}✓ $dst${C_RESET}  already linked"
    continue
  fi

  changes=1

  if [ -L "$dst" ]; then
    echo "${C_YELLOW}△ $dst${C_RESET}  is a symlink → $(readlink "$dst")  ${C_DIM}(not this repo)${C_RESET}"
    action="back up to $dst.bak-$ts, then relink"
  elif [ -e "$dst" ]; then
    kind="$( [ -d "$dst" ] && echo dir || echo file )"
    echo "${C_YELLOW}△ $dst${C_RESET}  is a real $kind"
    action="back up to $dst.bak-$ts, then link"
  else
    echo "${C_DIM}· $dst${C_RESET}  does not exist"
    action="create link"
  fi

  if [ "$APPLY" -eq 0 ]; then
    echo "    would: $action  →  $src"
    continue
  fi

  if [ -e "$dst" ] || [ -L "$dst" ]; then
    mv "$dst" "$dst.bak-$ts"
    echo "    backup: $dst.bak-$ts"
  fi
  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst"
  echo "    ${C_GREEN}linked${C_RESET} $dst → $src"
done

for entry in "${SCAFFOLD[@]}"; do
  src="$DIR/${entry%%:*}"
  dst="${entry#*:}"

  if [ ! -e "$src" ]; then
    echo "${C_RED}✗ ${entry%%:*}${C_RESET}  missing in repo ($src) — skipping"
    continue
  fi

  if [ -e "$dst" ]; then
    echo "${C_GREEN}✓ $dst${C_RESET}  already present  ${C_DIM}(left untouched)${C_RESET}"
    continue
  fi

  changes=1
  echo "${C_DIM}· $dst${C_RESET}  does not exist"

  if [ "$APPLY" -eq 0 ]; then
    echo "    would: scaffold from $src"
    continue
  fi

  cp "$src" "$dst"
  echo "    ${C_GREEN}scaffolded${C_RESET} $dst ← $src  ${C_DIM}(edit in your per-user values)${C_RESET}"
done

if [ "$APPLY" -eq 0 ]; then
  echo
  if [ "$changes" -eq 1 ]; then
    echo "${C_DIM}dry-run — re-run with --apply to make these changes${C_RESET}"
  else
    echo "${C_GREEN}all linked — nothing to do${C_RESET}"
  fi
fi
