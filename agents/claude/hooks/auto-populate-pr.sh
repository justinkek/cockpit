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

# --- Bash: gh pr create ---
if [ "$tool" = "Bash" ]; then
  if command -v jq >/dev/null 2>&1; then
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
    exit_code="$(printf '%s' "$input" | jq --raw-output '.tool_response.exitCode // .tool_result.exitCode // 0')"
  else
    cmd="$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    exit_code="0"
  fi
  printf '%s' "$cmd" | grep -q 'gh pr create' || exit 0
  [ "$exit_code" = "0" ] || exit 0

  echo "[auto-populate-pr] A PR was just created. Update the cockpit ticket's PRs property: run \`gh pr view --json url -q .url\` to get the PR URL, fetch the ticket's current PRs value, append the URL on a new line (preserve existing entries, skip if already listed), and update via notion-update-page (update_properties, set PRs)."
  exit 0
fi

# --- notion-update-page: Status set to a CR column ---
if [ "$tool" = "mcp__plugin_Notion_notion__notion-update-page" ]; then
  command -v jq >/dev/null 2>&1 || exit 0
  status="$(printf '%s' "$input" | jq -r '.tool_input.properties.Status // empty')"
  case "$status" in
    *CR*) ;;
    *) exit 0 ;;
  esac

  echo "[auto-populate-pr] Ticket moving to ${status}. Check if the current branch has a PR: run \`gh pr view --json url -q .url 2>/dev/null\`. If a PR URL is returned, update the cockpit ticket's PRs property - fetch the current value, append the URL on a new line (preserve existing entries, skip if already listed), and update via notion-update-page (update_properties, set PRs). If no PR exists, skip silently."
  exit 0
fi

exit 0
