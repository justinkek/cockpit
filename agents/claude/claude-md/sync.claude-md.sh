#!/usr/bin/env bash
#
# sync.claude-md.sh — sync each Claude account's user-level CLAUDE.md.
#
# Only ONE account (the base account, ~/.claude) carries the full rules:
#
#   ~/.claude/CLAUDE.md = base.AGENTS.md [ + adapter.CLAUDE.md ] [ + overrides/claude.CLAUDE.md ]
#
# Every other account (~/.claude-<name>) gets a one-line POINTER STUB instead
# of the full base, plus its own override if any:
#
#   ~/.claude-<name>/CLAUDE.md = <pointer stub> [ + overrides/<account>.CLAUDE.md ]
#
# Why: Claude Code always reads the hardcoded ~/.claude/CLAUDE.md as global
# memory IN ADDITION to $CLAUDE_CONFIG_DIR/CLAUDE.md. Since the CLI wrappers
# redirect CLAUDE_CONFIG_DIR to ~/.claude-<name>, duplicating the full base in
# both dirs injected the same ~2.7k-token block twice per turn. Keeping the
# base only in ~/.claude (shared with Claude Desktop, which also reads it) and
# stubbing the profiles removes that duplicate — the profiles pick the base up
# via the hardcoded read. Trade-off: profiles now DEPEND on that read, which is
# Claude Code implementation behaviour, not a documented Anthropic contract; if
# a future version drops it, profiles lose their base rules (silently). The
# stub text documents the dependency in-context so the failure is diagnosable.
# Note: the profile override then loads BEFORE the base (config-dir read
# precedes the hardcoded read), so profile overrides refine, they don't cleanly
# override the base. Overrides are empty today; revisit if that changes.
#
# CLAUDE.md is a whole markdown file (not key/value), so unlike settings.json
# there are no "unmanaged keys" to preserve. The diff + per-account prompt +
# timestamped backup are the safety net: any local edit (e.g. via the `#`
# quick-add-memory shortcut) shows up in the diff and you can decline or
# recover. To make account-specific memory stick, put it in the override file.
#
# Usage: sync.claude-md.sh [--check|--apply] [--yes]
#   (default) --apply : interactive — show per-account diff, prompt y/N, back up, write
#   --check           : report drift only; no writes; exit 1 if any drift
#   --yes | -y        : apply without prompting. Implied when there is no
#                       terminal to prompt on.
#
set -euo pipefail

SHARED_DIR="${CLAUDE_SHARED_DIR:-$HOME/.claude-shared}"
CM_DIR="$SHARED_DIR/claude-md"
# The canonical base is the agent-agnostic shared instruction file
# (base.AGENTS.md), mounted at ~/.agents-shared. Per-account overrides stay
# Claude-specific under agents/claude/claude-md/overrides.
AGENTS_SHARED_DIR="${AGENTS_SHARED_DIR:-$HOME/.agents-shared}"
BASE="$AGENTS_SHARED_DIR/base.AGENTS.md"
OVR_DIR="$CM_DIR/overrides"
# The Claude adapter: Claude-specific sections split out of the agnostic base,
# appended for the base account (between the base and its override).
ADAPTER="$CM_DIR/adapter.CLAUDE.md"

# The base account owns the full rules; ~/.claude is the hardcoded global memory
# path Claude Code always reads (and Claude Desktop reads too).
BASE_ACCOUNT="claude"

# Pointer stub written to every non-base profile in place of the full base. One
# HTML comment (inert in markdown), ~25 tokens, documenting where the real rules
# live so an "empty-looking" profile CLAUDE.md is self-explanatory.
PROFILE_POINTER='<!-- Base agent rules load from ~/.claude/CLAUDE.md (Claude Code'"'"'s hardcoded global memory), shared with Claude Desktop and picked up in this profile via that read. Intentionally not duplicated per-profile — maintained by agents/claude/claude-md/sync.claude-md.sh. -->'

# How many timestamped CLAUDE.md.bak-* files to keep per account dir.
# Older ones are pruned lazily, each time a new backup is written on apply.
KEEP_BACKUPS=5

# Account taxonomy (ACCOUNTS + acct_dir) is centralized in accounts.sh, shared
# by every concern's sync script.
source "$SHARED_DIR/accounts.sh"

# Keep only the newest KEEP_BACKUPS backups for a target file; delete the
# rest. Backup names end in YYYYMMDD-HHMMSS, so a plain sort is chronological.
prune_backups() {
  local target="$1"
  local baks=() f
  while IFS= read -r f; do baks+=("$f"); done < <(printf '%s\n' "$target".bak-* | sort)
  [ -e "${baks[0]:-}" ] || return 0          # glob unmatched -> nothing to prune
  local remove=$(( ${#baks[@]} - KEEP_BACKUPS ))
  (( remove > 0 )) || return 0
  rm -f "${baks[@]:0:remove}"
}

MODE="apply"
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --check)   MODE="check" ;;
    --apply)   MODE="apply" ;;
    --yes|-y)  ASSUME_YES=1 ;;
    -h|--help) echo "usage: sync.claude-md.sh [--check|--apply] [--yes]"; exit 0 ;;
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

drift=0
first=1

for acct in "${ACCOUNTS[@]}"; do
  [ "$first" -eq 1 ] && first=0 || echo
  dir="$(acct_dir "$acct")"
  target="$dir/CLAUDE.md"
  ovr="$OVR_DIR/$acct.CLAUDE.md"

  # Base account carries the full rules (base + adapter); every other profile
  # gets the pointer stub instead. Both then append their override (if any)
  # below a blank line. $(cat ...) strips trailing newlines, so comparison is
  # newline-agnostic.
  if [ "$acct" = "$BASE_ACCOUNT" ]; then
    final="$(cat "$BASE")"
    [ -s "$ADAPTER" ] && final="$final"$'\n\n'"$(cat "$ADAPTER")"
  else
    final="$PROFILE_POINTER"
  fi
  [ -s "$ovr" ] && final="$final"$'\n\n'"$(cat "$ovr")"

  cur=''; [ -f "$target" ] && cur="$(cat "$target")"

  if [ "$cur" = "$final" ]; then
    echo "${C_GREEN}✓ $acct${C_RESET}  in sync  ${C_DIM}($target)${C_RESET}"
    continue
  fi

  drift=1
  echo "${C_YELLOW}△ $acct  DRIFT${C_RESET}  ${C_DIM}($target)${C_RESET}"
  echo "    ${C_DIM}--- diff: current (${C_RED}<${C_DIM}) → desired (${C_GREEN}>${C_DIM}) ---${C_RESET}"
  diff <(printf '%s\n' "$cur") <(printf '%s\n' "$final") \
    | awk -v r="$C_RED" -v g="$C_GREEN" -v d="$C_DIM" -v x="$C_RESET" '
        /^</  { print "    " r $0 x; next }
        /^>/  { print "    " g $0 x; next }
        { print "    " d $0 x }
      ' || true

  [ "$MODE" = "check" ] && continue

  if ! confirm "    " "apply to $acct?"; then
    echo "    skipped"; continue
  fi

  mkdir -p "$dir"
  if [ -f "$target" ]; then
    ts="$(date +%Y%m%d-%H%M%S)"
    cp "$target" "$target.bak-$ts"
    echo "    backup: $target.bak-$ts"
    prune_backups "$target"
  fi
  printf '%s\n' "$final" > "$target"
  echo "    ✓ wrote $target"
done

if [ "$MODE" = "check" ] && [ "$drift" -eq 1 ]; then
  exit 1
fi
exit 0
