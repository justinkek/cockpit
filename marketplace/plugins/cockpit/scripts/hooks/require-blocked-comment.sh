#!/usr/bin/env bash

input="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

. "${CLAUDE_SHARED_DIR:-$HOME/.claude-shared}/hooks/hook-argv-lib.sh"

[ "$(printf '%s' "$input" | jq --raw-output '.tool_name // "Bash"')" = "Bash" ] || exit 0
cmd="$(printf '%s' "$input" | jq --raw-output '.tool_input.command // empty')"
printf '%s' "$cmd" | grep --quiet 'board-card' || exit 0

exit_code="$(printf '%s' "$input" | jq --raw-output '.tool_response.exitCode // .tool_result.exitCode // 0')"
[ "$exit_code" = "0" ] || exit 0

words="$(hook_argv_after "$cmd" board-card)"
[ "$(printf '%s\n' "$words" | sed -n 1p)" = "set" ] || exit 0
[ "$(printf '%s\n' "$words" | sed -n 3p)" = "blocked" ] || exit 0
[ "$(printf '%s\n' "$words" | wc -l | tr -d ' ')" -ge 3 ] || exit 0

card="$(printf '%s\n' "$words" | sed -n 2p | tr '[:lower:]' '[:upper:]')"
reason="$(printf '%s\n' "$words" | sed -n 4p)"
[ -n "$card" ] || exit 0

session_id="$(printf '%s' "$input" | jq --raw-output '.session_id // empty')"
state_directory="$HOME/.local/state/claude-ticket-sessions"
registered_card="$(tr '[:lower:]' '[:upper:]' < "$state_directory/$session_id.ticket" 2>/dev/null | tr -d '[:space:]')"

if [ -n "$session_id" ] && [ -n "$registered_card" ] && [ "$registered_card" = "$card" ]; then
  if [ -n "$reason" ]; then
    touch "$state_directory/$session_id.blocked"
  else
    rm -f "$state_directory/$session_id.blocked"
  fi
fi

[ -n "$reason" ] || exit 0

echo "[blocked-comment] You just set Blocked on ${card}. You MUST now comment the reason on that card: \$HOME/.cockpit/scripts/board-card comment ${card} with the text on stdin, in the format: 🤖 🚧 **Blocked** - <reason>. The robot marker is what tells a reader an agent wrote it. State the specific reason this ticket is blocked. Do not skip this step. Follow ~/.claude-shared/templates/blocked-flag.md."
exit 0
