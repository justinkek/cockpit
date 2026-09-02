#!/usr/bin/env bash

input="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

[ "$(printf '%s' "$input" | jq --raw-output '.stop_hook_active // false')" = "true" ] && exit 0

session_id="$(printf '%s' "$input" | jq --raw-output '.session_id // empty')"
state_directory="$HOME/.local/state/claude-ticket-sessions"
[ -n "$session_id" ] && [ -f "$state_directory/$session_id.ticket" ] || exit 0

committed_marker="$state_directory/$session_id.dev-committed"
[ -f "$committed_marker" ] || exit 0

[ -f "$state_directory/$session_id.stage-cr" ] && exit 0
[ "$(cat "$state_directory/$session_id.column" 2>/dev/null)" = "In Dev" ] || exit 0

rm -f "$committed_marker"

. "${CLAUDE_SHARED_DIR:-$HOME/.claude-shared}/hooks/hook-stop-note-lib.sh"

stop_note_record "$session_id" "[ticket-status] A commit landed and the card is still In Dev. If the tech steps are built, walk it to In CR by AI now with the cockpit:ticket:x:status skill - landing there runs the machine gates. If dev is not finished, say what is left."
exit 0
