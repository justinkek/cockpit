#!/usr/bin/env bash
#
# ticket-state-lib.sh — shared confirmation for the ticket state scripts.
#
#   source "$(dirname "$0")/ticket-state-lib.sh"
#   ticket_state_confirm <suffix> <expected_content> <label> [display]
#
# On success it prints "<label>: <display>" — callers pass the full sentence
# they used to echo, so their output is unchanged. On failure it prints which
# sidecar was not written and exits non-zero.

TICKET_STATE_DIR="${TICKET_STATE_DIR:-$HOME/.local/state/claude-ticket-sessions}"
TICKET_STATE_MAX_AGE=10

session_id() {
  printf '%s\n' "${CLAUDE_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"
}

# Seconds since a file was last modified, on both BSD (macOS) and GNU stat.
_ticket_state_age() {
  local f="$1" mtime
  mtime="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null)"
  [ -n "$mtime" ] || return 1
  echo $(( $(date +%s) - mtime ))
}

# Seconds a session may go without a heartbeat before its claim is expirable,
# and the floor under every claim regardless. Both have to be exceeded: the
# heartbeat is written on this machine only, so the floor is what stops a claim
# held by a session elsewhere being taken over on sight.
TICKET_CLAIM_BEAT_WINDOW=1800
TICKET_CLAIM_FLOOR=3600

# Epoch seconds for an iso formatted datetime, read as UTC because that is how a
# claim is written. Prints nothing when it cannot be parsed.
ticket_claim_epoch() {
  local ts="${1%%.*}"
  ts="${ts%Z}"
  ts="${ts%%+*}"
  TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$ts" +%s 2>/dev/null \
    || date -u -d "$1" +%s 2>/dev/null
}

ticket_claim_is_stale() {
  local sid="$1" claimed="$2" age
  if [ -f "$TICKET_STATE_DIR/$sid.alive" ]; then
    age="$(_ticket_state_age "$TICKET_STATE_DIR/$sid.alive" 2>/dev/null || true)"
    [ -n "$age" ] && [ "$age" -le "$TICKET_CLAIM_BEAT_WINDOW" ] && return 1
  fi
  [ -n "$claimed" ] && [ "$(( $(date +%s) - claimed ))" -ge "$TICKET_CLAIM_FLOOR" ]
}

_ticket_state_matches() {
  local f="$1" expected="$2" age
  [ -f "$f" ] || return 1
  age="$(_ticket_state_age "$f")" || return 1
  [ "$age" -le "$TICKET_STATE_MAX_AGE" ] || return 1
  # An empty expectation means the marker carries no content (stage markers) —
  # existence and freshness are the whole signal.
  [ -z "$expected" ] || [ "$(cat "$f")" = "$expected" ]
}

ticket_state_confirm() {
  local suffix="$1" expected="$2" label="$3" display="${4:-$2}" f session
  session="$(session_id)"

  if [ -n "$session" ]; then
    f="$TICKET_STATE_DIR/$session$suffix"
    if [ -f "$f" ] && { [ -z "$expected" ] || [ "$(cat "$f")" = "$expected" ]; }; then
      printf '%s: %s\n' "$label" "$display"
      return 0
    fi
  else
    for f in "$TICKET_STATE_DIR"/*"$suffix"; do
      if _ticket_state_matches "$f" "$expected"; then
        printf '%s: %s\n' "$label" "$display"
        return 0
      fi
    done
  fi

  printf 'FAILED to record %s=%s — the hook did not intercept this command, so nothing was written.\n' "$suffix" "$display" >&2
  printf 'The hook is the only writer, and it either did not fire or could not read the arguments. Check the command is standalone (no &&, ;, or pipe on the same line) and that its arguments are plain shell words.\n' >&2
  return 1
}
