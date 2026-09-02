#!/usr/bin/env bash

export CLAUDE_SHARED_DIR="$(cd "$(dirname "$0")/../../../../../../agents/claude" && pwd)"

HOOK="$(cd "$(dirname "$0")/.." && pwd)/require-ticket.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

assert_marker() {
  local label="$1" expected="$2" marker="$3"
  actual="$(cat "$marker" 2>/dev/null)"
  if [ "$actual" = "$expected" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s', got '%s'\n" "$label" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

run_hook() {
  local session_id="$1" cmd="$2"
  jq -nc --arg sid "$session_id" --arg cmd "$cmd" \
    '{tool_name:"Bash",session_id:$sid,tool_input:{command:$cmd}}' \
    | HOME="$TMPDIR" bash "$HOOK" >/dev/null 2>&1
}

SESSION="test-session-$$"
STATE_DIR="$TMPDIR/.local/state/claude-ticket-sessions"
mkdir -p "$STATE_DIR"
VALID_URL="https://app.notion.com/p/abc123"
printf '%s\n' "$VALID_URL" > "$STATE_DIR/$SESSION.ticket"

printf "Test group: piped commands must not corrupt existing marker\n"

run_hook "$SESSION" 'find . -name "ticket-register" | head -30'
assert_marker "find ... | head -30" "$VALID_URL" "$STATE_DIR/$SESSION.ticket"

run_hook "$SESSION" 'grep "ticket-register" file.sh | wc -l'
assert_marker "grep ... | wc -l" "$VALID_URL" "$STATE_DIR/$SESSION.ticket"

run_hook "$SESSION" 'cat marketplace/plugins/cockpit/scripts/ticket-register | grep url'
assert_marker "cat ... | grep url" "$VALID_URL" "$STATE_DIR/$SESSION.ticket"

run_hook "$SESSION" 'grep -rn "ticket-register" hooks/ | head -20'
assert_marker "grep -rn ... | head -20" "$VALID_URL" "$STATE_DIR/$SESSION.ticket"

printf "\nTest group: non-piped non-registration commands must not corrupt marker\n"

run_hook "$SESSION" 'cat marketplace/plugins/cockpit/scripts/ticket-register'
assert_marker "cat ticket-register (no pipe)" "$VALID_URL" "$STATE_DIR/$SESSION.ticket"

run_hook "$SESSION" 'grep -c ticket-register hooks/require-ticket.sh'
assert_marker "grep -c (no pipe)" "$VALID_URL" "$STATE_DIR/$SESSION.ticket"

printf "\nTest group: genuine registration must still write the marker\n"

NEW_URL="https://app.notion.com/p/def456"
run_hook "$SESSION" '"$HOME/.cockpit/scripts/ticket-register" "'"$NEW_URL"'"'
assert_marker "genuine ticket-register" "$NEW_URL" "$STATE_DIR/$SESSION.ticket"

printf "\nTest group: chained registration records the URL it was given\n"

# This used to assert the marker was left alone: extraction was awk '{print
# $NF}', so a trailing `; echo done` yielded "done" and writing was unsafe.
# Extraction now anchors on the script name and captures the https argument,
# so a chained registration is recorded rather than dropped.
CHAINED_URL="https://app.notion.com/p/ghi789"
run_hook "$SESSION" '"$HOME/.cockpit/scripts/ticket-register" "'"$CHAINED_URL"'" ; echo done'
assert_marker "ticket-register with a trailing semicolon" "$CHAINED_URL" "$STATE_DIR/$SESSION.ticket"

printf "\nTest group: registration with no URL must not overwrite\n"

run_hook "$SESSION" '"$HOME/.cockpit/scripts/ticket-register" ; echo done'
assert_marker "ticket-register with no argument" "$CHAINED_URL" "$STATE_DIR/$SESSION.ticket"

run_hook "$SESSION" '"$HOME/.cockpit/scripts/ticket-register" not-a-url'
assert_marker "ticket-register with a non-URL argument" "$CHAINED_URL" "$STATE_DIR/$SESSION.ticket"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
