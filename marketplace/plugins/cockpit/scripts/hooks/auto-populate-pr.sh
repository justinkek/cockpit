#!/usr/bin/env bash

input="$(cat)"

if command -v jq >/dev/null 2>&1; then
  tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
  session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
else
  tool="$(printf '%s' "$input" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  session_id="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi

[ -n "$session_id" ] || exit 0

STATE_DIR="$HOME/.local/state/claude-ticket-sessions"
marker="$STATE_DIR/${session_id}.ticket"
[ -f "$marker" ] || exit 0

[ "$tool" = "Bash" ] || exit 0

if command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
  exit_code="$(printf '%s' "$input" | jq --raw-output '.tool_response.exitCode // .tool_result.exitCode // 0')"
else
  cmd="$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  exit_code="0"
fi
printf '%s' "$cmd" | grep -q 'gh pr create' || exit 0
[ "$exit_code" = "0" ] || exit 0

card="$(tr -d '[:space:]' < "$marker")"

echo "[auto-populate-pr] A PR was just created. Record it on the cockpit ticket ${card}: run \`gh pr view --json url -q .url\` for the PR URL, read the current list with \`\$HOME/.cockpit/scripts/board-card show ${card} PRs\`, append the URL on a new line (keep existing entries, skip it if already listed), and write the result with \`\$HOME/.cockpit/scripts/board-card set ${card} prs \"<urls>\"\`."
exit 0
