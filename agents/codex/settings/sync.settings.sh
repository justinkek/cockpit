#!/usr/bin/env bash
#
# sync.settings.sh — sync Codex's user-level settings from this folder into
# $CODEX_HOME. Three concerns, three mechanisms:
#
#   base.rules            -> $CODEX_HOME/rules/dotfiles.rules   (whole-file)
#   base.config-profile.toml -> merged into $CODEX_HOME/config.toml (targeted)
#   base.tui-profile.toml -> merged into $CODEX_HOME/config.toml (targeted)
#
# 1. rules — the execpolicy allowlist (twin of settings.json permissions.allow).
#    Codex owns rules/*.rules wholesale, so it's a plain whole-file sync
#    (diff+backup+prompt, like sync.agents-md.sh). dotfiles.rules layers
#    alongside any hand-authored rules; we never touch the rest of rules/.
#
# 2. config-profile — a permission profile (twin of settings.json
#    permissions.deny) that denies the agent read access to secret globs. Codex
#    profiles gate the agent's own reader, not just shell — verified. These keys
#    live in config.toml, which the Desktop app also writes, so we DON'T
#    whole-file sync it: merge-config-profile does a targeted text edit (insert
#    the top-level default_permissions line + a marked [permissions.*] block),
#    leaving every app-owned key untouched. See that script's header.
#
# 3. tui-profile — the closest native equivalent of Claude's status line. The
#    targeted merger owns only tui.status_line and preserves every other [tui]
#    and app-owned config.toml key.
#
# NOT synced (deferred): MCP servers, env.
#
# Single target: one global Codex home, so no per-account loop yet (add a
# codex/accounts.sh twin when you run more than one CODEX_HOME).
#
# Usage: sync.settings.sh [--check|--apply] [--yes]
#   (default) --apply : interactive — show diff, prompt y/N, back up, write
#   --check           : report drift only; no writes; exit 1 if any drift
#   --yes | -y        : apply without prompting. Implied when there is no
#                       terminal to prompt on.
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
AGENTS_SHARED_DIR="${AGENTS_SHARED_DIR:-$HOME/.agents-shared}"
source "$DIR/../homes.sh"
TMPDIR_SYNC="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_SYNC"' EXIT

# Whole-file source:target pairs (target relative to CODEX_HOME).
PAIRS=(
  "base.rules:rules/dotfiles.rules"
)

# How many timestamped <target>.bak-* files to keep per target.
KEEP_BACKUPS=5

MODE="apply"
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --check)   MODE="check" ;;
    --apply)   MODE="apply" ;;
    --yes|-y)  ASSUME_YES=1 ;;
    -h|--help) echo "usage: sync.settings.sh [--check|--apply] [--yes]"; exit 0 ;;
    *)         echo "error: unknown arg: $arg" >&2; exit 2 ;;
  esac
done

command -v python3 >/dev/null || { echo "error: python3 is required" >&2; exit 3; }

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
  [ -e "${baks[0]:-}" ] || return 0
  local remove=$(( ${#baks[@]} - KEEP_BACKUPS ))
  (( remove > 0 )) || return 0
  rm -f "${baks[@]:0:remove}"
}

# Colorize a unified diff on stdin.
color_diff() {
  awk -v r="$C_RED" -v g="$C_GREEN" -v d="$C_DIM" -v x="$C_RESET" '
      /^-/ { print "    " r $0 x; next }
      /^\+/ { print "    " g $0 x; next }
      { print "    " d $0 x }'
}

# Back up + write a target, honoring MODE/ASSUME_YES. $2 is a writer command run
# only on confirmation (it performs the actual write to $1).
confirm_and_write() {
  local target="$1"; shift
  [ "$MODE" = "check" ] && return 0
  if ! confirm "    " "apply $(basename "$target")?"; then
    echo "    skipped"; return 1
  fi
  mkdir -p "$(dirname "$target")"
  if [ -f "$target" ]; then
    local ts; ts="$(date +%Y%m%d-%H%M%S)"
    cp "$target" "$target.bak-$ts"
    echo "    backup: $target.bak-$ts"
    prune_backups "$target"
  fi
  "$@"
}

# Whole-file sync of one source:target pair. Sets global `drift=1` on difference.
sync_pair() {
  local src="$DIR/$1" target="$CODEX_HOME/$2" label="$2"
  [ -f "$src" ] || { echo "error: missing source: $src" >&2; exit 3; }

  local final cur=''
  final="$(cat "$src")"
  [ -f "$target" ] && cur="$(cat "$target")"

  if [ "$cur" = "$final" ]; then
    echo "${C_GREEN}✓ $label${C_RESET}  in sync  ${C_DIM}($target)${C_RESET}"
    return 0
  fi
  drift=1
  echo "${C_YELLOW}△ $label  DRIFT${C_RESET}  ${C_DIM}($target)${C_RESET}"
  echo "    ${C_DIM}--- current (${C_RED}-${C_DIM}) → desired (${C_GREEN}+${C_DIM}) ---${C_RESET}"
  diff <(printf '%s\n' "$cur") <(printf '%s\n' "$final") \
    | sed -e 's/^</-/' -e 's/^>/+/' | color_diff || true
  confirm_and_write "$target" cp "$src" "$target" && [ "$MODE" != "check" ] \
    && echo "    ✓ wrote $target" || true
}

# Merge the permission profile into config.toml via the targeted helper.
sync_config_profile() {
  local src="$DIR/base.config-profile.toml" target="$CODEX_HOME/config.toml"
  local helper="$DIR/merge-config-profile"
  [ -f "$src" ] || { echo "error: missing source: $src" >&2; exit 3; }

  # NB: capture via `if` so the helper's intentional exit-1 (drift) doesn't trip
  # `set -e` on the assignment.
  local diff_out rc
  if diff_out="$(python3 "$helper" --source "$src" --target "$target" --check 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  case "$rc" in
    0) echo "${C_GREEN}✓ config.toml${C_RESET}  permission profile in sync  ${C_DIM}($target)${C_RESET}"; return 0 ;;
    1) : ;;  # drift
    *) echo "error: merge-config-profile failed:" >&2; printf '%s\n' "$diff_out" >&2; exit 3 ;;
  esac

  drift=1
  echo "${C_YELLOW}△ config.toml  DRIFT (permission profile)${C_RESET}  ${C_DIM}($target)${C_RESET}"
  echo "    ${C_DIM}--- current (${C_RED}-${C_DIM}) → desired (${C_GREEN}+${C_DIM}) ---${C_RESET}"
  printf '%s\n' "$diff_out" | color_diff || true
  confirm_and_write "$target" python3 "$helper" --source "$src" --target "$target" --apply >/dev/null \
    && [ "$MODE" != "check" ] && echo "    ✓ merged profile into $target" || true
}

# Merge the hooks profile into config.toml via the targeted helper.
compose_hooks_profile() {
  local composed="$1" base="$DIR/base.hooks-profile.toml" board="$DIR/board.hooks-profile.toml"
  if codex_home_works_the_ticket_board "${CODEX_HOME_NAME:-codex}"; then
    awk -v board="$board" '
      /^# <<< dotfiles-codex-hooks <<</ { while ((getline line < board) > 0) print line; print "" }
      { print }
    ' "$base" > "$composed"
  else
    cp "$base" "$composed"
  fi
}

sync_hooks_profile() {
  local target="$CODEX_HOME/config.toml"
  local helper="$DIR/merge-hooks-profile"
  local src="$TMPDIR_SYNC/composed.hooks-profile.toml"
  local base="$DIR/base.hooks-profile.toml" board="$DIR/board.hooks-profile.toml"
  [ -f "$base" ] || { echo "error: missing source: $base" >&2; exit 3; }
  [ -f "$board" ] || { echo "error: missing source: $board" >&2; exit 3; }
  compose_hooks_profile "$src"

  local diff_out rc
  if diff_out="$(python3 "$helper" --source "$src" --target "$target" --check 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  case "$rc" in
    0) echo "${C_GREEN}✓ config.toml${C_RESET}  hooks profile in sync  ${C_DIM}($target)${C_RESET}"; return 0 ;;
    1) : ;;  # drift
    *) echo "error: merge-hooks-profile failed:" >&2; printf '%s\n' "$diff_out" >&2; exit 3 ;;
  esac

  drift=1
  echo "${C_YELLOW}△ config.toml  DRIFT (hooks profile)${C_RESET}  ${C_DIM}($target)${C_RESET}"
  echo "    ${C_DIM}--- current (${C_RED}-${C_DIM}) → desired (${C_GREEN}+${C_DIM}) ---${C_RESET}"
  printf '%s\n' "$diff_out" | color_diff || true
  confirm_and_write "$target" python3 "$helper" --source "$src" --target "$target" --apply >/dev/null \
    && [ "$MODE" != "check" ] && echo "    ✓ merged hooks into $target" || true
}

# Merge the managed native status-line key into config.toml.
sync_tui_profile() {
  local src="$DIR/base.tui-profile.toml" target="$CODEX_HOME/config.toml"
  local helper="$DIR/merge-tui-profile"
  [ -f "$src" ] || { echo "error: missing source: $src" >&2; exit 3; }

  local diff_out rc
  if diff_out="$("$helper" --source "$src" --target "$target" --check 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  case "$rc" in
    0) echo "${C_GREEN}✓ config.toml${C_RESET}  status line in sync  ${C_DIM}($target)${C_RESET}"; return 0 ;;
    1) : ;;  # drift
    *) echo "error: merge-tui-profile failed:" >&2; printf '%s\n' "$diff_out" >&2; exit 3 ;;
  esac

  drift=1
  echo "${C_YELLOW}△ config.toml  status line DRIFT${C_RESET}  ${C_DIM}($target)${C_RESET}"
  echo "    ${C_DIM}--- current (${C_RED}-${C_DIM}) → desired (${C_GREEN}+${C_DIM}) ---${C_RESET}"
  printf '%s\n' "$diff_out" | color_diff || true
  confirm_and_write "$target" "$helper" --source "$src" --target "$target" --apply >/dev/null \
    && [ "$MODE" != "check" ] && echo "    ✓ merged status line into $target" || true
}

drift=0
first=1
for pair in "${PAIRS[@]}"; do
  [ "$first" -eq 1 ] && first=0 || echo
  sync_pair "${pair%%:*}" "${pair#*:}"
done
echo
sync_config_profile
echo
sync_hooks_profile
echo
sync_tui_profile

if [ "$MODE" = "check" ] && [ "$drift" -eq 1 ]; then
  exit 1
fi
exit 0
