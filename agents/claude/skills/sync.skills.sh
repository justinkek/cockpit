#!/usr/bin/env bash
#
# sync.skills.sh — make shared and Claude-specific user-level skills available
# in every Claude account by symlinking each managed skill into skills/.
#
#   <account>/skills/<shared-skill> -> ~/.agents-shared/skills/<shared-skill>
#   <account>/skills/<claude-skill> -> ~/.claude-shared/skills/<claude-skill>
#
# Managed skills come from both roots. Duplicate names are rejected instead of
# choosing an ambiguous source. Each skill is linked individually so accounts
# remain free to add their own skill directories alongside managed links.
#
# A skill is "in sync" for an account when <account>/skills/<skill> is a
# symlink pointing at the canonical shared source. Drift = missing, a real
# dir/file of the same name (an account's own copy), or a symlink elsewhere.
# On apply, an existing real dir/file is backed up before being replaced.
#
# Usage: sync.skills.sh [--check|--apply] [--yes]
#   (default) --apply : interactive — show per-account drift, prompt y/N,
#                       back up any clobbered path, then (re)create symlinks.
#   --check           : report drift only; no writes; exit 1 if any drift.
#                       (use this from a SessionStart hook / CI)
#   --yes | -y        : apply without prompting (unattended). Implied when
#                       there is no terminal to prompt on.
#
set -euo pipefail

SHARED_DIR="${CLAUDE_SHARED_DIR:-$HOME/.claude-shared}"
CLAUDE_SKILLS_DIR="$SHARED_DIR/skills"
AGENTS_SHARED_DIR="${AGENTS_SHARED_DIR:-$HOME/.agents-shared}"
SHARED_SKILLS_DIR="$AGENTS_SHARED_DIR/skills"

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
    -h|--help) echo "usage: sync.skills.sh [--check|--apply] [--yes]"; exit 0 ;;
    *)         echo "error: unknown arg: $arg" >&2; exit 2 ;;
  esac
done

[ -d "$CLAUDE_SKILLS_DIR" ] || { echo "error: missing Claude skills dir: $CLAUDE_SKILLS_DIR" >&2; exit 3; }
[ -d "$SHARED_SKILLS_DIR" ] || { echo "error: missing shared skills dir: $SHARED_SKILLS_DIR" >&2; exit 3; }

# Colors — only when stdout is a terminal (keeps pipes / hooks / CI clean).
if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'; C_DIM=$'\033[2m'
else
  C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''; C_DIM=''
fi

# Managed skills: shared first, then Claude-specific. Keep parallel arrays for
# macOS's Bash 3.2 compatibility (no associative arrays).
managed=()
sources=()
shopt -s nullglob
for root in "$SHARED_SKILLS_DIR" "$CLAUDE_SKILLS_DIR"; do
  for d in "$root"/*/; do
    [ -f "$d/SKILL.md" ] || continue
    skill="$(basename "$d")"
    if [ "${#managed[@]}" -gt 0 ]; then
      for existing in "${managed[@]}"; do
        if [ "$existing" = "$skill" ]; then
          echo "error: duplicate managed skill '$skill' in shared and Claude roots" >&2
          exit 3
        fi
      done
    fi
    managed+=("$skill")
    sources+=("$root/$skill")
  done
done
shopt -u nullglob

if [ "${#managed[@]}" -eq 0 ]; then
  echo "${C_YELLOW}no managed skills (no */SKILL.md)${C_RESET}"
  exit 0
fi

drift=0
first=1

for acct in "${ACCOUNTS[@]}"; do
  [ "$first" -eq 1 ] && first=0 || echo
  dir="$(acct_dir "$acct")"
  skills="$dir/skills"
  echo "${C_DIM}$acct  ($skills)${C_RESET}"

  for i in "${!managed[@]}"; do
    skill="${managed[$i]}"
    src="${sources[$i]}"
    link="$skills/$skill"

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
      reason="real $( [ -d "$link" ] && echo dir || echo file ) (account's own copy)"
    fi
    echo "    ${C_YELLOW}△ $skill${C_RESET}  $reason"

    [ "$MODE" = "check" ] && continue

    if ! confirm "      " "link $skill for $acct?"; then
      echo "      skipped"; continue
    fi

    mkdir -p "$skills"
    # Back up anything real (or a wrong symlink) before replacing it.
    if [ -e "$link" ] || [ -L "$link" ]; then
      ts="$(date +%Y%m%d-%H%M%S)"
      mv "$link" "$link.bak-$ts"
      echo "      backup: $link.bak-$ts"
    fi
    ln -s "$src" "$link"
    echo "      ${C_GREEN}✓ linked${C_RESET} $link → $src"
  done

  # A renamed or deleted skill leaves its old link behind, pointing at a source
  # that no longer exists. Nothing above touches it — the loop only visits names
  # that are still managed — so it would sit there broken until someone noticed.
  # Only links into a managed root are swept: an account's own link elsewhere is
  # its own business, and a real dir/file of the same name is never touched.
  shopt -s nullglob
  for link in "$skills"/*; do
    [ -L "$link" ] || continue
    [ -e "$link" ] && continue
    target="$(readlink "$link")"
    case "$target" in
      "$SHARED_SKILLS_DIR"/*|"$CLAUDE_SKILLS_DIR"/*) ;;
      *) continue ;;
    esac

    drift=1
    echo "    ${C_YELLOW}△ $(basename "$link")${C_RESET}  stale symlink → $target (source is gone)"
    [ "$MODE" = "check" ] && continue
    if ! confirm "      " "remove stale link $(basename "$link") for $acct?"; then
      echo "      skipped"; continue
    fi
    rm "$link"
    echo "      ${C_GREEN}✓ removed${C_RESET} $link"
  done
  shopt -u nullglob
done

if [ "$MODE" = "check" ] && [ "$drift" -eq 1 ]; then
  exit 1
fi
exit 0
