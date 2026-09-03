#!/usr/bin/env bash
#
# sync.settings.sh — sync each Claude account's settings.json from a shared
# base + a per-account override.
#
#   final = (current settings.json's UNMANAGED keys) + (base * override)
#
# Managed keys  = the top-level keys present in base.settings.json or in the
#                 account's override. The script is authoritative for these
#                 (replaced, not deep-merged — so removing a plugin from base
#                 actually removes it).
# Unmanaged keys = anything else already in the account's settings.json. These
#                 are preserved untouched and reported, so settings you (or
#                 Claude) add locally are never silently dropped.
#
# Usage: sync.settings.sh [--check|--apply] [--yes]
#   (default) --apply : interactive — show per-account diff, prompt y/N,
#                       back up the old file, then write.
#   --check           : report drift only; no writes; exit 1 if any drift.
#                       (use this from a SessionStart hook / CI)
#   --yes | -y        : apply without prompting (unattended). Implied when
#                       there is no terminal to prompt on.
#
set -euo pipefail

SHARED_DIR="${CLAUDE_SHARED_DIR:-$HOME/.claude-shared}"
SETTINGS_DIR="$SHARED_DIR/settings"
BASE="$SETTINGS_DIR/base.settings.json"
BASE_LOCAL="$SETTINGS_DIR/base.settings.local.json"
OVR_DIR="$SETTINGS_DIR/overrides"

# How many timestamped settings.json.bak-* files to keep per account dir.
# Older ones are pruned lazily, each time a new backup is written on apply.
KEEP_BACKUPS=5

# Account taxonomy (ACCOUNTS + acct_dir) is centralized in accounts.sh, shared
# by every concern's sync script.
source "$SHARED_DIR/accounts.sh"
source "$SHARED_DIR/board-accounts.sh"

# Keep only the newest KEEP_BACKUPS backups for a settings file; delete the
# rest. Backup names end in YYYYMMDD-HHMMSS, so a plain sort is chronological.
prune_backups() {
  local settings="$1"
  local baks=() f
  while IFS= read -r f; do baks+=("$f"); done < <(printf '%s\n' "$settings".bak-* | sort)
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
    -h|--help) echo "usage: sync.settings.sh [--check|--apply] [--yes]"; exit 0 ;;
    *)         echo "error: unknown arg: $arg" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 3; }
[ -f "$BASE" ]          || { echo "error: missing base file: $BASE" >&2; exit 3; }

# Colors — only when stdout is a terminal (keeps pipes / hooks / CI clean).
if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'; C_DIM=$'\033[2m'
else
  C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''; C_DIM=''
fi

read_entries_for_every_account() {
  local entries=() name directory below_home
  for name in "${ACCOUNTS[@]}"; do
    directory="$(acct_dir "$name")"
    case "$directory" in
      "$HOME"/*)
        below_home="${directory#"$HOME"/}"
        entries+=("Read(~/$below_home/**)" "Read(\$HOME/$below_home/**)")
        ;;
      *) entries+=("Read($directory/**)") ;;
    esac
  done
  printf '%s\n' "${entries[@]}" |
    jq --raw-input --slurp 'split("\n") | map(select(length > 0))'
}

account_read_entries="$(read_entries_for_every_account)"

drift=0
first=1

for acct in "${ACCOUNTS[@]}"; do
  [ "$first" -eq 1 ] && first=0 || echo
  dir="$(acct_dir "$acct")"
  settings="$dir/settings.json"
  ovr="$OVR_DIR/$acct.settings.json"

  committed_base_json="$(cat "$BASE")"
  base_local_json='{}'; [ -f "$BASE_LOCAL" ] && base_local_json="$(cat "$BASE_LOCAL")"
  ovr_json='{}'; [ -f "$ovr" ]      && ovr_json="$(cat "$ovr")"
  if ! account_works_the_ticket_board "$acct"; then
    ovr_json="$(printf '%s' "$ovr_json" | jq '.enabledPlugins["cockpit@cockpit"] = false')"
  fi
  cur_json='{}'; [ -f "$settings" ] && cur_json="$(cat "$settings")"

  base_json="$(jq -n \
    --argjson committed "$committed_base_json" \
    --argjson local "$base_local_json" \
    --argjson accounts "$account_read_entries" '
      reduce ("allow", "deny") as $list ($committed * $local;
        (($committed.permissions[$list] // [])
          + ($local.permissions[$list] // [])
          + (if $list == "allow" then $accounts else [] end)) as $joined
        | if ($joined | length) > 0 then .permissions[$list] = $joined else . end)
    ')"

  # desired managed state (base recursively merged with override),
  # then graft the current file's unmanaged keys back on top.
  #
  # WARNING: jq '*' deep-merges objects but REPLACES arrays. So if both base
  # and an account override define the same hooks event (e.g. hooks.PreToolUse),
  # the override's array wins entirely — base's entries are NOT appended. Today
  # only base defines hooks, so this is harmless. If you ever add per-account
  # hooks on an event base already uses, either restate base's entries in the
  # override or replace '*' with a deep-merge that concatenates arrays.
  final="$(jq -n \
    --argjson base "$base_json" \
    --argjson ovr  "$ovr_json" \
    --argjson cur  "$cur_json" \
    --arg home "$HOME" '
      ($base * $ovr) as $desired
      | (($base | keys) + ($ovr | keys) | unique) as $managed
      | ($cur | with_entries(select(.key as $k | $managed | index($k) | not))) as $unmanaged
      | ($unmanaged * $desired)
      | (.permissions.allow?, .permissions.deny?) |= (
          if . == null then . else
            map(. as $entry
              | ($entry | gsub("\\$HOME"; $home)) as $expanded
              | if $expanded == $entry then [$entry] else [$entry, $expanded] end)
            | flatten
          end)
    ')"

  cur_sorted="$(printf '%s' "$cur_json" | jq -S .)"
  final_sorted="$(printf '%s' "$final"  | jq -S .)"

  unmanaged_keys="$(jq -rn \
    --argjson base "$base_json" --argjson ovr "$ovr_json" --argjson cur "$cur_json" '
      (($base | keys) + ($ovr | keys) | unique) as $m
      | [ $cur | keys[] | select(. as $k | $m | index($k) | not) ] | join(", ")')"

  if [ "$cur_sorted" = "$final_sorted" ]; then
    echo "${C_GREEN}✓ $acct${C_RESET}  in sync  ${C_DIM}($settings)${C_RESET}"
    [ -n "$unmanaged_keys" ] && echo "    ${C_CYAN}unmanaged (preserved): $unmanaged_keys${C_RESET}"
    continue
  fi

  drift=1
  echo "${C_YELLOW}△ $acct  DRIFT${C_RESET}  ${C_DIM}($settings)${C_RESET}"
  [ -n "$unmanaged_keys" ] && echo "    ${C_CYAN}unmanaged (preserved): $unmanaged_keys${C_RESET}"
  echo "    ${C_DIM}--- diff: current (${C_RED}<${C_DIM}) → desired (${C_GREEN}>${C_DIM}) ---${C_RESET}"
  diff <(printf '%s\n' "$cur_sorted") <(printf '%s\n' "$final_sorted") \
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
  if [ -f "$settings" ]; then
    ts="$(date +%Y%m%d-%H%M%S)"
    cp "$settings" "$settings.bak-$ts"
    echo "    backup: $settings.bak-$ts"
    prune_backups "$settings"
  fi
  printf '%s\n' "$final" | jq . > "$settings"
  echo "    ✓ wrote $settings"
done

if [ "$MODE" = "check" ] && [ "$drift" -eq 1 ]; then
  exit 1
fi
exit 0
