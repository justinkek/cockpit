#!/usr/bin/env bash

input="$(cat)"

if command -v jq >/dev/null 2>&1; then
  session="$(printf '%s' "$input" | jq -r '.session_id // empty')"
else
  session="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi
[ -n "$session" ] || exit 0

here="$(dirname "$0")"

owning_claude() {
  local pid="$1" depth=0
  while [ -n "$pid" ] && [ "$pid" -gt 1 ] && [ "$depth" -lt 8 ]; do
    case "$(ps -o comm= -p "$pid" 2>/dev/null)" in
      *claude) printf '%s\n' "$pid"; return 0 ;;
    esac
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    depth=$((depth + 1))
  done
  return 1
}

stop_session_watchers() {
  local claude_pid watcher
  claude_pid="$(owning_claude "$$" || true)"
  [ -n "$claude_pid" ] || return 0
  for watcher in $(pgrep -f 'ticket-watch-(column|board)' 2>/dev/null); do
    [ "$(owning_claude "$watcher" || true)" = "$claude_pid" ] && kill "$watcher" 2>/dev/null
  done
  return 0
}

release_local_locks() {
  CLAUDE_SESSION_ID="$session" "$here/../ticket-claim-lock" release-all >/dev/null 2>&1 || true
}

release_notion_claims() {
  local token cards body
  command -v jq >/dev/null 2>&1 || return 0
  token="$(security find-generic-password -a "$USER" -s cockpit-notion-token -w 2>/dev/null || true)"
  [ -n "$token" ] || return 0

  cards="$("$here/../ticket-waiting-cards" --claimed-by "$session" 2>/dev/null || true)"
  [ -n "$cards" ] || return 0

  body="$(mktemp -t session-end-release)"
  trap 'rm -f "$body"' EXIT
  printf '{"properties":{"Agent: Session Id":{"rich_text":[]}}}' > "$body"

  printf '%s\n' "$cards" \
    | awk -F'\t' -v session="$session" \
        '{ page = $2; claim = $4 } claim ~ ("^" session) { print page }' \
    | while read -r page; do
    [ -n "$page" ] || continue
    printf '%s\n' \
      "header = \"Authorization: Bearer $token\"" \
      'header = "Notion-Version: 2022-06-28"' \
      'header = "Content-Type: application/json"' \
      "url = \"https://api.notion.com/v1/pages/$page\"" \
      'request = "PATCH"' \
      "data = \"@$body\"" \
      'silent' \
      | curl --config - >/dev/null 2>&1 || true
  done
}

stop_session_watchers
release_local_locks
release_notion_claims

exit 0
