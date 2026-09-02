#!/usr/bin/env bash

input="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

blocked="$(printf '%s' "$input" | jq -r '.tool_input.properties.Blocked // empty')"
blocked_was_written="$(printf '%s' "$input" | jq -r '.tool_input.properties | has("Blocked")')"

page_id="$(printf '%s' "$input" | jq -r '.tool_input.page_id // empty')"
[ -n "$page_id" ] || exit 0

. "$(dirname "$0")/hook-notion-page-lib.sh"

session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
state_directory="$HOME/.local/state/claude-ticket-sessions"
registered_page="$(notion_page_id_of "$(cat "$state_directory/$session_id.ticket" 2>/dev/null)")"
this_page="$(notion_page_id_of "$page_id")"

if [ "$blocked_was_written" = "true" ] && [ -n "$registered_page" ] && [ "$registered_page" = "$this_page" ]; then
  if [ "$blocked" = "Blocked" ]; then
    touch "$state_directory/$session_id.blocked"
  else
    rm -f "$state_directory/$session_id.blocked"
  fi
fi

[ "$blocked" = "Blocked" ] || exit 0

echo "[blocked-comment] You just set Blocked on page ${page_id}. You MUST now call notion-create-comment on that page with a comment in the format: 🤖 🚧 **Blocked** - <reason>. The robot marker is what tells a reader an agent wrote it. State the specific reason this ticket is blocked. Do not skip this step. Follow ~/.claude-shared/templates/blocked-flag.md."
exit 0
