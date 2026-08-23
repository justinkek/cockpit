#!/bin/sh
# Claude Code status line.
# Shows (three lines):
#   line 1: session name (if set)
#   line 2: type · column (lowercase)
#   line 3: profile · model · effort · cost · tokens · prompts/day · 5h usage
# Repo/branch/dir are intentionally omitted — Warp's own badges show those.
# Source of truth — synced to ~/.claude*/ by ~/.claude-shared/sync.sh.
# Do not edit the synced copies directly; edit this file and re-sync.

input=$(cat)

. "$(dirname "$0")/session-name-lib.sh"

session_name=$(printf '%s' "$input" | jq -r '.session_name // empty')
tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty')

_item_type=""
_ticket_type=""
_ctx_sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
if [ -z "$_ctx_sid" ] && [ -n "$tp" ]; then
  _ctx_sid=$(basename "$(dirname "$tp")")
fi
_type_file="$HOME/.local/state/claude-ticket-sessions/$_ctx_sid.type"
[ -n "$session_name" ] || session_name=$(session_name_read "$tp" "$_type_file")
if [ -n "$_ctx_sid" ] && [ -f "$_type_file" ]; then
  while IFS='=' read -r _tk _tv; do
    case "$_tk" in
      type) _item_type="$_tv" ;;
      ticket_type) _ticket_type="$_tv" ;;
    esac
  done < "$_type_file"
fi
# Check for board column (.column file written at ticket status changes).
_column=""
_col_file="$HOME/.local/state/claude-ticket-sessions/$_ctx_sid.column"
if [ -n "$_ctx_sid" ] && [ -f "$_col_file" ]; then
  _column=$(cat "$_col_file")
fi
_step=""
_step_file="$HOME/.local/state/claude-ticket-sessions/$_ctx_sid.step"
if [ -n "$_ctx_sid" ] && [ -f "$_step_file" ]; then
  _step=$(cat "$_step_file")
fi

model=$(printf '%s' "$input" | jq -r '.model.display_name // "unknown"')
effort=$(printf '%s' "$input" | jq -r '.effort.level // empty')
cost=$(printf '%s' "$input" | jq -r '.cost.total_cost_usd // empty')

# 5-hour plan-limit usage, 0-100. Only emitted for Claude.ai Pro/Max
# subscribers after the first API response — absent on API-key and Bedrock
# profiles, where `// empty` drops the segment entirely.
limit5h=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')

# Current context occupancy in tokens, rendered as a rounded "k" count.
# current_usage is an OBJECT — the window is filled by the input side
# (fresh input + cache creation + cache reads), so sum those.
tok=$(printf '%s' "$input" | jq -r '
  (.context_window.current_usage // {}) as $u
  | ( ($u.input_tokens // 0)
    + ($u.cache_creation_input_tokens // 0)
    + ($u.cache_read_input_tokens // 0) ) as $t
  | if $t > 0 then (($t / 1000) | round | tostring) else empty end')

_audit="$HOME/.claude-logs/prompt-audit.jsonl"
if [ -f "$_audit" ]; then
  _today=$(date -u +%Y-%m-%d)
  _yesterday=$(date -u -v-1d +%Y-%m-%d)
  prompts=$(grep -c "\"ts\":\"\\($_today\\|$_yesterday\\)" "$_audit" 2>/dev/null)
  [ "$prompts" -gt 0 ] 2>/dev/null || prompts=""
fi

# Persist cost/tokens to a sidecar file so ticket-done-usage can sum them at Done.
# Cost: monotonic (never regress — last good value survives null/0 at shutdown).
# Tokens: delta-accumulation (track context window growth, survive compaction).
_sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
if [ -z "$_sid" ] && [ -n "$tp" ]; then
  _sid=$(basename "$(dirname "$tp")")
fi
STATE_DIR="$HOME/.local/state/claude-ticket-sessions"
if [ -n "$_sid" ] && [ -f "$STATE_DIR/$_sid.ticket" ]; then
  _uf="$STATE_DIR/$_sid.usage"
  _prev_cost=""; _prev_tok=0; _prev_cumul=0
  if [ -f "$_uf" ]; then
    while IFS='=' read -r _k _v; do
      case "$_k" in
        cost_usd)       _prev_cost="$_v" ;;
        tokens_k_prev)  _prev_tok="${_v:-0}" ;;
        tokens_k_cumul) _prev_cumul="${_v:-0}" ;;
        tokens_k)       [ "$_prev_cumul" = "0" ] && _prev_cumul="${_v:-0}" ;;
      esac
    done < "$_uf"
  fi
  _new_cost="$cost"
  if [ -n "$_new_cost" ] && [ -n "$_prev_cost" ]; then
    _write_cost=$(awk -v a="$_prev_cost" -v b="$_new_cost" 'BEGIN{print (b+0 > a+0) ? b : a}')
  elif [ -n "$_new_cost" ]; then
    _write_cost="$_new_cost"
  else
    _write_cost="$_prev_cost"
  fi
  _curr_tok="${tok:-0}"
  _delta=$(awk -v c="$_curr_tok" -v p="$_prev_tok" 'BEGIN{d=c-p; print (d>0) ? d : 0}')
  _write_cumul=$(awk -v cum="$_prev_cumul" -v d="$_delta" 'BEGIN{print cum+d}')
  printf 'cost_usd=%s\ntokens_k_prev=%s\ntokens_k_cumul=%s\n' \
    "$_write_cost" "$_curr_tok" "$_write_cumul" > "$_uf"
fi

profile="${CLAUDE_CONFIG_DIR##*/}"
profile="${profile#.claude-}"

# Colored to match the theme's muted "inactive" blue (#7fa3c7) — the same
# soft blue the "manual mode on" mode line uses — via a truecolor escape.
# NOTE: this is a hardcoded hex from the Pi theme; it won't auto-track a theme
# switch (see the status-line ticket for the robustness trade-off discussion).
printf '\033[38;2;127;163;199m'
if [ -n "$session_name" ]; then
  printf '%s\n' "$session_name"
  if [ -n "$_item_type" ] || [ -n "$_ticket_type" ] || [ -n "$_column" ] || [ -n "$_step" ]; then
    _sep=""
    if [ -n "$_item_type" ]; then
      printf '%s' "$_item_type"
      _sep=1
    fi
    if [ -n "$_ticket_type" ]; then
      [ -n "$_sep" ] && printf ' \302\267 '
      printf '%s' "$_ticket_type"
      _sep=1
    fi
    if [ -n "$_column" ]; then
      [ -n "$_sep" ] && printf ' \302\267 '
      printf '%s' "$_column" | tr '[:upper:]' '[:lower:]'
      _sep=1
    fi
    if [ -n "$_step" ]; then
      [ -n "$_sep" ] && printf ' \302\267 '
      printf '/%s' "$_step"
    fi
    printf '\n'
  fi
fi
[ -n "$profile" ] && printf '%s \302\267 ' "$profile"
printf '%s' "$model"
[ -n "$effort" ] && printf ' \302\267 %s' "$effort"
[ -n "$cost" ]   && printf ' \302\267 $%.2f' "$cost"
[ -n "$tok" ]    && printf ' \302\267 %sk' "$tok"
[ -n "$limit5h" ] && printf ' \302\267 5h %.0f%%' "$limit5h"
[ -n "$prompts" ] && printf ' \302\267 %s perms' "$prompts"
printf '\033[0m'
