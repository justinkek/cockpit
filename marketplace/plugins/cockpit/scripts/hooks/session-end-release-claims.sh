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

release_board_claims() {
  "$here/../board-card" release-session "$session" >/dev/null 2>&1 || true
}

stop_session_watchers
release_local_locks
release_board_claims

exit 0
