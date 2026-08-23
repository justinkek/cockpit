#!/usr/bin/env bash
#
# sync.skills.sh — expose shared user-level skills to Codex.
#
#   ~/.agents/skills/<skill> -> ~/.agents-shared/skills/<skill>
#
# Codex discovers user-global skills under ~/.agents/skills and follows
# symlinked skill directories. Managed skills are every shared subdirectory
# containing SKILL.md. Existing real paths or wrong symlinks are backed up
# before replacement.
#
# Usage: sync.skills.sh [--check|--apply] [--yes]
#
set -euo pipefail

AGENTS_SHARED_DIR="${AGENTS_SHARED_DIR:-$HOME/.agents-shared}"
AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
SKILLS_DIR="$AGENTS_SHARED_DIR/skills"
TARGET_DIR="$AGENTS_HOME/skills"

MODE="apply"
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --check)   MODE="check" ;;
    --apply)   MODE="apply" ;;
    --yes|-y)  ASSUME_YES=1 ;;
    -h|--help) echo "usage: sync.skills.sh [--check|--apply] [--yes]"; exit 0 ;;
    *)         echo "error: unknown arg: $arg" >&2; exit 2 ;;
  esac
done

[ -d "$SKILLS_DIR" ] || { echo "error: missing shared skills dir: $SKILLS_DIR" >&2; exit 3; }

if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_DIM=$'\033[2m'
else
  C_RESET=''; C_GREEN=''; C_YELLOW=''; C_DIM=''
fi

managed=()
shopt -s nullglob
for dir in "$SKILLS_DIR"/*/; do
  [ -f "$dir/SKILL.md" ] || continue
  managed+=("$(basename "$dir")")
done
shopt -u nullglob

if [ "${#managed[@]}" -eq 0 ]; then
  echo "${C_YELLOW}no managed shared skills (no */SKILL.md) in $SKILLS_DIR${C_RESET}"
  exit 0
fi

drift=0
echo "${C_DIM}codex  ($TARGET_DIR)${C_RESET}"
for skill in "${managed[@]}"; do
  src="$SKILLS_DIR/$skill"
  link="$TARGET_DIR/$skill"

  if [ -L "$link" ] && [ "$(readlink "$link")" = "$src" ]; then
    echo "    ${C_GREEN}✓ $skill${C_RESET}  linked"
    continue
  fi

  drift=1
  if [ ! -e "$link" ] && [ ! -L "$link" ]; then
    reason="missing"
  elif [ -L "$link" ]; then
    reason="symlink → $(readlink "$link")"
  else
    reason="real $( [ -d "$link" ] && echo dir || echo file )"
  fi
  echo "    ${C_YELLOW}△ $skill${C_RESET}  $reason"

  [ "$MODE" = "check" ] && continue

  if ! confirm "      " "link $skill for Codex?"; then
    echo "      skipped"; continue
  fi

  mkdir -p "$TARGET_DIR"
  if [ -e "$link" ] || [ -L "$link" ]; then
    ts="$(date +%Y%m%d-%H%M%S)"
    mv "$link" "$link.bak-$ts"
    echo "      backup: $link.bak-$ts"
  fi
  ln -s "$src" "$link"
  echo "      ${C_GREEN}✓ linked${C_RESET} $link → $src"
done

if [ "$MODE" = "check" ] && [ "$drift" -eq 1 ]; then
  exit 1
fi
exit 0
