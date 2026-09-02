#!/usr/bin/env bash

export CLAUDE_SHARED_DIR="$(cd "$(dirname "$0")/../../../../../../agents/claude" && pwd)"
export COCKPIT_PLUGIN_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

export TICKET_STATE_DIR="$TMPDIR/state"
mkdir -p "$TICKET_STATE_DIR"

pass=0
fail=0

assert_equals() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s', got '%s'\n" "$label" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

run_column() {
  local variable="$1" value="$2" column="$3"
  (
    unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID
    [ -z "$variable" ] || export "$variable=$value"
    bash "$SCRIPT_DIR/ticket-register-column" "$column" >/dev/null 2>&1
  )
  echo $?
}

printf "Test group: the file a state script writes and confirms\n"

assert_equals "confirms the file the session's own id names" 0 \
  "$(run_column CLAUDE_SESSION_ID session-a "In Dev")"
assert_equals "and that file holds what was asked for" "In Dev" \
  "$(cat "$TICKET_STATE_DIR/session-a.column")"

assert_equals "resolves the harness id when the other is unset" 0 \
  "$(run_column CLAUDE_CODE_SESSION_ID session-b "In CR")"
assert_equals "and writes under the harness id" "In CR" \
  "$(cat "$TICKET_STATE_DIR/session-b.column")"

printf "\nTest group: another session's file never stands in\n"

printf 'Ready for CR\n' > "$TICKET_STATE_DIR/session-c.column"
assert_equals "refuses when only another session's file holds the value" 1 \
  "$(
    unset CLAUDE_CODE_SESSION_ID
    export CLAUDE_SESSION_ID=session-d
    printf 'In Dev\n' > "$TICKET_STATE_DIR/session-d.column"
    source "$SCRIPT_DIR/ticket-state-lib.sh"
    ticket_state_confirm .column "Ready for CR" "Column stored" >/dev/null 2>&1
    echo $?
  )"

printf "\nTest group: no id resolves at all\n"

printf 'Ready for FR\n' > "$TICKET_STATE_DIR/session-e.column"
assert_equals "falls back to the sidecar the hook just wrote" 0 \
  "$(run_column "" "" "Ready for FR")"

printf "\nTest group: the settings scope file in its own directory\n"

assert_equals "confirms the scope it just wrote" 0 \
  "$(
    unset CLAUDE_SESSION_ID
    export CLAUDE_CODE_SESSION_ID=session-f
    export HOME="$TMPDIR/home"
    bash "$CLAUDE_SHARED_DIR/settings-scope-confirm" global >/dev/null 2>&1
    echo $?
  )"
assert_equals "and writes the scope under that id" "global" \
  "$(cat "$TMPDIR/home/.local/state/claude-settings-scope/session-f")"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
