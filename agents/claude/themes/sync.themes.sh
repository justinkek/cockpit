#!/usr/bin/env bash
#
# sync.themes.sh — make shared Claude Code themes available in every account by
# symlinking each managed theme JSON into the account's themes/ dir.
#
#   <account>/themes/<theme>.json  ->  ~/.claude-shared/themes/<theme>.json
#
# Managed themes = every *.json file in this concern folder. Each is symlinked
#                  (per-file, NOT the whole themes/ dir) into each account, so an
#                  account stays free to add its own real theme files alongside.
#
# A theme is "in sync" for an account when <account>/themes/<theme>.json is a
# symlink pointing at the canonical shared source. Drift = missing, a real file
# of the same name (an account's own copy), or a symlink elsewhere. On apply,
# an existing real file is backed up before being replaced.
#
# Activate a synced theme by setting "theme": "custom:<theme>" in
# settings/base.settings.json (the filename slug, sans .json).
#
# Usage: sync.themes.sh [--check|--apply] [--yes]
#   (default) --apply : interactive — show per-account drift, prompt y/N,
#                       back up any clobbered path, then (re)create symlinks.
#   --check           : report drift only; no writes; exit 1 if any drift.
#   --yes | -y        : apply without prompting (unattended). Implied when
#                       there is no terminal to prompt on.
#
set -euo pipefail

SHARED_DIR="${CLAUDE_SHARED_DIR:-$HOME/.claude-shared}"
THEMES_DIR="$SHARED_DIR/themes"
AGENTS_SHARED_DIR="${AGENTS_SHARED_DIR:-$HOME/.agents-shared}"

# Account taxonomy (ACCOUNTS + acct_dir) is centralized in accounts.sh, shared
# by every concern's sync script.
source "$SHARED_DIR/accounts.sh"

MODE="apply"
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --check)   MODE="check" ;;
    --apply)   MODE="apply" ;;
    --yes|-y)  ASSUME_YES=1 ;;
    -h|--help) echo "usage: sync.themes.sh [--check|--apply] [--yes]"; exit 0 ;;
    *)         echo "error: unknown arg: $arg" >&2; exit 2 ;;
  esac
done

[ -d "$THEMES_DIR" ] || { echo "error: missing themes dir: $THEMES_DIR" >&2; exit 3; }

# Colors — only when stdout is a terminal (keeps pipes / hooks / CI clean).
if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'; C_DIM=$'\033[2m'
else
  C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''; C_DIM=''
fi

# Managed themes: *.json files in THEMES_DIR.
managed=()
shopt -s nullglob
for f in "$THEMES_DIR"/*.json; do
  managed+=("$(basename "$f")")
done
shopt -u nullglob

if [ "${#managed[@]}" -eq 0 ]; then
  echo "${C_YELLOW}no managed themes (no *.json) in $THEMES_DIR${C_RESET}"
  exit 0
fi

drift=0
first=1

for acct in "${ACCOUNTS[@]}"; do
  [ "$first" -eq 1 ] && first=0 || echo
  dir="$(acct_dir "$acct")"
  themes="$dir/themes"
  echo "${C_DIM}$acct  ($themes)${C_RESET}"

  for theme in "${managed[@]}"; do
    src="$THEMES_DIR/$theme"
    link="$themes/$theme"

    if [ -L "$link" ] && [ "$(readlink "$link")" = "$src" ]; then
      echo "    ${C_GREEN}✓ $theme${C_RESET}  linked"
      continue
    fi

    drift=1
    if [ ! -e "$link" ] && [ ! -L "$link" ]; then
      reason="missing"
    elif [ -L "$link" ]; then
      reason="symlink → $(readlink "$link")"
    else
      reason="real file (account's own copy)"
    fi
    echo "    ${C_YELLOW}△ $theme${C_RESET}  $reason"

    [ "$MODE" = "check" ] && continue

    if ! confirm "      " "link $theme for $acct?"; then
      echo "      skipped"; continue
    fi

    mkdir -p "$themes"
    # Back up anything real (or a wrong symlink) before replacing it.
    if [ -e "$link" ] || [ -L "$link" ]; then
      ts="$(date +%Y%m%d-%H%M%S)"
      mv "$link" "$link.bak-$ts"
      echo "      backup: $link.bak-$ts"
    fi
    ln -s "$src" "$link"
    echo "      ${C_GREEN}✓ linked${C_RESET} $link → $src"
  done
done

if [ "$MODE" = "check" ] && [ "$drift" -eq 1 ]; then
  exit 1
fi
exit 0
