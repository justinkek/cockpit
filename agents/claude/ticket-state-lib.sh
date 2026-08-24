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

# The boards the agent reads for refinement work. Four scripts need this list
# and none of them may disagree with the others, so it is parsed here once
# rather than in each of them.
COCKPIT_BOARDS_FILE="${COCKPIT_BOARDS_FILE:-$HOME/.local/state/cockpit/boards.json}"

cockpit_main_checkout() {
  if [ -n "${COCKPIT_REPO:-}" ]; then
    printf '%s\n' "$COCKPIT_REPO"
    return 0
  fi

  local common_git_directory
  if common_git_directory="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
    dirname "$common_git_directory"
  else
    pwd -P
  fi
}

# One tab-separated line per board: name, database id, view id. The view id is
# empty when the board has no view — see boards.json for what that means
# to a caller.
#
# When no board claims the checkout this returns nothing and exits 3, which the
# copilot skill turns into a question. There is deliberately no default board:
# answering silently is how a session ends up offered another project's cards,
# and the one thing nobody can guess is which project this checkout belongs to.
#
# Exit codes, so a caller can say which of the three happened:
#   3  no board claims this checkout — ask
#   4  COCKPIT_BOARD names a board the file does not have
#   5  the file configures no boards at all
no_boards_recorded_yet() { [ ! -f "$COCKPIT_BOARDS_FILE" ]; }

cockpit_boards() {
  local out
  if no_boards_recorded_yet; then
    echo "[boards] no boards configured — check $COCKPIT_BOARDS_FILE" >&2
    return 5
  fi
  out="$(jq -r --arg checkout "$(cockpit_main_checkout)" --arg home "$HOME" --arg named "${COCKPIT_BOARD:-}" '
    [ .boards[] | .checkouts = ((.checkouts // .repos // []) | map(sub("^~"; $home))) ] as $all
    | (if $named == "" then [ $all[] | select(.checkouts | index($checkout)) ]
       else [ $all[] | select(.name == $named) ] end)
    | .[] | [.name, (.ids["tickets-database"] // error("[boards] \(.name) has no tickets-database id: cockpit-board-id set tickets-database <value> \(.name)")), (.view_id // "")] | @tsv
  ' "$COCKPIT_BOARDS_FILE")" || return 1

  if [ -z "$out" ]; then
    if [ "$(jq -r '.boards | length' "$COCKPIT_BOARDS_FILE" 2>/dev/null || echo 0)" -eq 0 ]; then
      echo "[boards] no boards configured — check $COCKPIT_BOARDS_FILE" >&2
      return 5
    fi
    if [ -n "${COCKPIT_BOARD:-}" ]; then
      echo "[boards] no board named '$COCKPIT_BOARD' in $COCKPIT_BOARDS_FILE" >&2
      return 4
    fi
    return 3
  fi

  printf '%s\n' "$out"
}

# The line a caller prints when cockpit_boards came back empty. Shared so the
# three scripts cannot drift into three different ways of saying the same thing.
cockpit_boards_explain() {
  local status="$1" tag="$2"
  [ "$status" -eq 3 ] || return 0
  echo "[$tag] no board claims $(cockpit_main_checkout) — run /copilot to pick one" >&2
}

# Seconds since a file was last modified, on both BSD (macOS) and GNU stat.
_ticket_state_age() {
  local f="$1" mtime
  mtime="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null)"
  [ -n "$mtime" ] || return 1
  echo $(( $(date +%s) - mtime ))
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
