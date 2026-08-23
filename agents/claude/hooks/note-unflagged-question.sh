#!/usr/bin/env bash

input="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

[ "$(printf '%s' "$input" | jq --raw-output '.stop_hook_active // false')" = "true" ] && exit 0

transcript="$(printf '%s' "$input" | jq --raw-output '.transcript_path // empty')"
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

session_id="$(printf '%s' "$input" | jq --raw-output '.session_id // empty')"
state_directory="$HOME/.local/state/claude-ticket-sessions"
registered_ticket="$state_directory/$session_id.ticket"
flag_already_set="$state_directory/$session_id.blocked"

[ -n "$session_id" ] && [ -f "$registered_ticket" ] || exit 0
[ -f "$flag_already_set" ] && exit 0

landed_column="$(cat "$state_directory/$session_id.column" 2>/dev/null)"
[ "$landed_column" = "Done" ] && exit 0

. "$(dirname "$0")/hook-transcript-lib.sh"
. "$(dirname "$0")/hook-stop-note-lib.sh"

last="$(hook_last_reply "$transcript")"
[ -n "$last" ] || exit 0

fence="$(printf '\140\140\140')"
outside_code_blocks="$(printf '%s\n' "$last" | awk -v fence="$fence" '
  { probe = $0; sub(/^[[:space:]]+/, "", probe) }
  index(probe, fence) == 1 { fenced = !fenced; next }
  fenced { next }
  { print }')"

QUESTION_LABELLED_IN_QUEUE='^[[:space:]]*([-*+][[:space:]]+|[0-9]+\.[[:space:]]+)?[`*_]*Q:'
printf '%s\n' "$outside_code_blocks" | grep --quiet --extended-regexp "$QUESTION_LABELLED_IN_QUEUE" || exit 0

stop_note_record "$session_id" "[reply-shape] The last reply asked the user a question the next step waits on, and the ticket is not flagged Blocked. Set the flag and comment the question on it now, following ~/.claude-shared/templates/blocked-flag.md."
exit 0
