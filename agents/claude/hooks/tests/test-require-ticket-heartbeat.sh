#!/usr/bin/env bash

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s', got '%s'\n" "$label" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

FAKE_HOME="$TMPDIR/home"
STATE_DIR="$FAKE_HOME/.local/state/claude-ticket-sessions"
mkdir -p "$STATE_DIR"

SESSION="test-heartbeat-$$"
BEAT="$STATE_DIR/$SESSION.alive"

# Run the hook against one tool call. $1 is the JSON payload; the hook's own
# decision is discarded — the heartbeat is what is under test.
run_hook() {
  rm -f "$BEAT"
  printf '%s' "$1" | HOME="$FAKE_HOME" bash "$HOOK_DIR/require-ticket.sh" >/dev/null 2>&1
}

beat_written() {
  [ -f "$BEAT" ] && printf 'yes' || printf 'no'
}

printf "Test group: the heartbeat lands on a gated call\n"

run_hook "$(printf '{"session_id":"%s","tool_name":"Edit","tool_input":{}}' "$SESSION")"
assert_eq "an edit with no ticket registered still beats" "yes" "$(beat_written)"

run_hook "$(printf '{"session_id":"%s","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}' "$SESSION")"
assert_eq "a mutating shell command beats" "yes" "$(beat_written)"

printf '%s\n' "https://app.notion.com/p/abc" > "$STATE_DIR/$SESSION.ticket"
run_hook "$(printf '{"session_id":"%s","tool_name":"Edit","tool_input":{}}' "$SESSION")"
assert_eq "an edit the gate allows beats too" "yes" "$(beat_written)"
rm -f "$STATE_DIR/$SESSION.ticket"

printf "\nTest group: the heartbeat lands on the calls that never reach the gate\n"

run_hook "$(printf '{"session_id":"%s","tool_name":"Bash","tool_input":{"command":"ls -la"}}' "$SESSION")"
assert_eq "a read-only command beats" "yes" "$(beat_written)"

run_hook "$(printf '{"session_id":"%s","tool_name":"Bash","tool_input":{"command":"/Users/x/.claude-shared/ticket-claim-lock take abc"}}' "$SESSION")"
assert_eq "a cross-allowed command beats" "yes" "$(beat_written)"

printf "\nTest group: no session id, no heartbeat\n"

rm -f "$BEAT"
printf '{"tool_name":"Edit","tool_input":{}}' \
  | HOME="$FAKE_HOME" bash "$HOOK_DIR/require-ticket.sh" >/dev/null 2>&1
assert_eq "nothing is written without a session to name it" "0" \
  "$(find "$STATE_DIR" -name '*.alive' | wc -l | tr -d ' ')"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
