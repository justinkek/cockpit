#!/usr/bin/env bash

mode="$1"
input="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

session_id="$(printf '%s' "$input" | jq --raw-output '.session_id // empty')"
[ -n "$session_id" ] || exit 0

STATE_DIR="${TICKET_STATE_DIR:-$HOME/.local/state/claude-ticket-sessions}"
marker="$STATE_DIR/$session_id.step"

if [ "$mode" = "clear" ]; then
  [ -f "$marker" ] && rm "$marker"
  exit 0
fi

skill="$(printf '%s' "$input" | jq --raw-output '.tool_input.skill // empty')"
[ -n "$skill" ] || exit 0

mkdir -p "$STATE_DIR"
printf '%s\n' "${skill##*:}" > "$marker"
exit 0
