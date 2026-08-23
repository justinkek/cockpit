#!/usr/bin/env bash
#
# sync.agents-md.sh — sync Codex's user-global AGENTS.md from the shared base
# (+ an optional Codex-specific override appended below the base).
#
#   final = base.AGENTS.md  [ + blank line + adapter.CODEX.md if non-empty ]
#
# Codex reads its user-global instructions from ~/.codex/AGENTS.md. This is the
# Codex twin of agents/claude/claude-md/sync.claude-md.sh (which writes
# ~/.claude*/CLAUDE.md): the canonical source is the same agent-agnostic
# base.AGENTS.md, mounted at ~/.agents-shared. There is a single
# global Codex config, so there is no per-account loop — just one target.
#
# The diff + prompt + timestamped backup are the safety net: any local edit to
# ~/.codex/AGENTS.md shows up in the diff and you can decline or recover. To
# make Codex-specific instructions stick, put them in adapter.CODEX.md.
#
# Usage: sync.agents-md.sh [--check|--apply] [--yes]
#   (default) --apply : interactive — show diff, prompt y/N, back up, write
#   --check           : report drift only; no writes; exit 1 if drift
#   --yes | -y        : apply without prompting. Implied when there is no
#                       terminal to prompt on.
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AGENTS_SHARED_DIR="${AGENTS_SHARED_DIR:-$HOME/.agents-shared}"
BASE="$AGENTS_SHARED_DIR/base.AGENTS.md"

OVR="$DIR/adapter.CODEX.md"                         # optional Codex-only additions
TARGET="${CODEX_HOME:-$HOME/.codex}/AGENTS.md"

# How many timestamped AGENTS.md.bak-* files to keep. Older ones are pruned
# lazily each time a new backup is written on apply.
KEEP_BACKUPS=5

MODE="apply"
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --check)   MODE="check" ;;
    --apply)   MODE="apply" ;;
    --yes|-y)  ASSUME_YES=1 ;;
    -h|--help) echo "usage: sync.agents-md.sh [--check|--apply] [--yes]"; exit 0 ;;
    *)         echo "error: unknown arg: $arg" >&2; exit 2 ;;
  esac
done

[ -f "$BASE" ] || { echo "error: missing base file: $BASE" >&2; exit 3; }

# Colors — only when stdout is a terminal (keeps pipes / hooks / CI clean).
if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_DIM=$'\033[2m'
else
  C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_DIM=''
fi

# Keep only the newest KEEP_BACKUPS backups; delete the rest. Backup names end
# in YYYYMMDD-HHMMSS, so a plain sort is chronological.
prune_backups() {
  local target="$1"
  local baks=() f
  while IFS= read -r f; do baks+=("$f"); done < <(printf '%s\n' "$target".bak-* | sort)
  [ -e "${baks[0]:-}" ] || return 0          # glob unmatched -> nothing to prune
  local remove=$(( ${#baks[@]} - KEEP_BACKUPS ))
  (( remove > 0 )) || return 0
  rm -f "${baks[@]:0:remove}"
}

# final = base, plus the override appended below a blank line (if non-empty).
# $(cat ...) strips trailing newlines, so comparison is newline-agnostic.
final="$(cat "$BASE")"
[ -s "$OVR" ] && final="$final"$'\n\n'"$(cat "$OVR")"

cur=''; [ -f "$TARGET" ] && cur="$(cat "$TARGET")"

if [ "$cur" = "$final" ]; then
  echo "${C_GREEN}✓ codex${C_RESET}  in sync  ${C_DIM}($TARGET)${C_RESET}"
  exit 0
fi

echo "${C_YELLOW}△ codex  DRIFT${C_RESET}  ${C_DIM}($TARGET)${C_RESET}"
echo "    ${C_DIM}--- diff: current (${C_RED}<${C_DIM}) → desired (${C_GREEN}>${C_DIM}) ---${C_RESET}"
diff <(printf '%s\n' "$cur") <(printf '%s\n' "$final") \
  | awk -v r="$C_RED" -v g="$C_GREEN" -v d="$C_DIM" -v x="$C_RESET" '
      /^</  { print "    " r $0 x; next }
      /^>/  { print "    " g $0 x; next }
      { print "    " d $0 x }
    ' || true

[ "$MODE" = "check" ] && exit 1

if ! confirm "    " "apply to codex?"; then
  echo "    skipped"; exit 0
fi

mkdir -p "$(dirname "$TARGET")"
if [ -f "$TARGET" ]; then
  ts="$(date +%Y%m%d-%H%M%S)"
  cp "$TARGET" "$TARGET.bak-$ts"
  echo "    backup: $TARGET.bak-$ts"
  prune_backups "$TARGET"
fi
printf '%s\n' "$final" > "$TARGET"
echo "    ✓ wrote $TARGET"
exit 0
