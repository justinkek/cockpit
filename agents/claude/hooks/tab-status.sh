#!/usr/bin/env bash

state="$1"
input="$(cat)"

. "$(dirname "$0")/../session-name-lib.sh"

case "$state" in
  working) glyph="⏳" ;;
  done)    glyph="✅" ;;
  needs)   glyph="🔔" ;;
  *)       glyph="•" ;;
esac

cwd=""
transcript=""
session_id=""
if command -v jq >/dev/null 2>&1; then
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
  transcript="$(printf '%s' "$input" | jq --raw-output '.transcript_path // empty')"
  session_id="$(printf '%s' "$input" | jq --raw-output '.session_id // empty')"
fi
[ -n "$cwd" ] || cwd="$PWD"
label="$(session_name_tab_label "$(session_name_read "$transcript" "$HOME/.local/state/claude-ticket-sessions/$session_id.type")")"
[ -n "$label" ] || label="${cwd##*/}"
[ -n "$label" ] || label="claude"

# Actual ESC (\033) and BEL (\007) bytes; jq JSON-encodes them safely.
seq="$(printf '\033]0;%s %s\007' "$glyph" "$label")"

if command -v jq >/dev/null 2>&1; then
  jq -nc --arg seq "$seq" '{terminalSequence:$seq}'
else
  # jq is expected to be present; minimal fallback for the label path only.
  printf '{"terminalSequence":"\\u001b]0;%s %s\\u0007"}\n' "$glyph" "$label"
fi

exit 0
