#!/usr/bin/env bash

export CLAUDE_SHARED_DIR="$(cd "$(dirname "$0")/../../../../../../agents/claude" && pwd)"

HOOK="$(cd "$(dirname "$0")/.." && pwd)/require-ticket.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

assert_file_exists() {
  local label="$1" path="$2"
  if [ -f "$path" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — file not found: %s\n" "$label" "$path"
    fail=$((fail + 1))
  fi
}

assert_file_absent() {
  local label="$1" path="$2"
  if [ ! -f "$path" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — file should not exist: %s\n" "$label" "$path"
    fail=$((fail + 1))
  fi
}

assert_content() {
  local label="$1" expected="$2" path="$3"
  actual="$(cat "$path" 2>/dev/null)"
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

SESSION="test-sidecar-$$"
STATE_DIR="$TMPDIR/.local/state/claude-ticket-sessions"
mkdir -p "$STATE_DIR"
printf 'https://app.notion.com/p/abc123\n' > "$STATE_DIR/$SESSION.ticket"

printf "Test group: ticket-register-type writes to correct path\n"

run_hook "$SESSION" '"$HOME/.cockpit/scripts/ticket-register-type" ticket "test session name"'
assert_file_exists "type file at \$session_id.type" "$STATE_DIR/$SESSION.type"
assert_file_absent "no type file at \$session_id.ticket.type" "$STATE_DIR/$SESSION.ticket.type"
assert_content "type file contains correct data" "type=ticket
name=test session name" "$STATE_DIR/$SESSION.type"

printf "\nTest group: ticket-register-column writes to correct path\n"

run_hook "$SESSION" '"$HOME/.cockpit/scripts/ticket-register-column" "In Dev"'
assert_file_exists "column file at \$session_id.column" "$STATE_DIR/$SESSION.column"
assert_file_absent "no column file at \$session_id.ticket.column" "$STATE_DIR/$SESSION.ticket.column"
assert_content "column file contains correct data" "In Dev" "$STATE_DIR/$SESSION.column"

printf "\nTest group: ticket-register-source-ticket writes to correct path\n"

run_hook "$SESSION" '"$HOME/.cockpit/scripts/ticket-register-source-ticket" "https://app.notion.com/p/source123"'
assert_file_exists "source-ticket file at \$session_id.source-ticket" "$STATE_DIR/$SESSION.source-ticket"
assert_file_absent "no source-ticket file at \$session_id.ticket.source-ticket" "$STATE_DIR/$SESSION.ticket.source-ticket"
assert_content "source-ticket file contains correct URL" "https://app.notion.com/p/source123" "$STATE_DIR/$SESSION.source-ticket"

printf "\nTest group: compound commands still record state\n"

# The defect this covers: the hook used to write sidecars only inside the
# safe-shape branch, so a chained invocation printed success and wrote nothing.
rm -f "$STATE_DIR/$SESSION.column" "$STATE_DIR/$SESSION.type" "$STATE_DIR/$SESSION.source-ticket"

run_hook "$SESSION" '"$HOME/.cockpit/scripts/ticket-register-column" "In Dev" && "$HOME/.cockpit/scripts/ticket-status-confirm" dev'
assert_file_exists "column file written from a chained command" "$STATE_DIR/$SESSION.column"
assert_content "chained column has the requested value, not the command line" "In Dev" "$STATE_DIR/$SESSION.column"

run_hook "$SESSION" '"$HOME/.cockpit/scripts/ticket-register-type" ticket "chained session name" "bug" && echo done'
assert_content "chained type has the requested values" "type=ticket
name=chained session name
ticket_type=bug" "$STATE_DIR/$SESSION.type"

run_hook "$SESSION" '"$HOME/.cockpit/scripts/ticket-register-source-ticket" "https://app.notion.com/p/chained123"; echo done'
assert_content "chained source-ticket has the requested URL" "https://app.notion.com/p/chained123" "$STATE_DIR/$SESSION.source-ticket"

printf "\nTest group: missing arguments write nothing\n"

# An absent argument must leave the sidecar alone rather than record whatever
# the command line happened to contain.
rm -f "$STATE_DIR/$SESSION.column"
run_hook "$SESSION" '"$HOME/.cockpit/scripts/ticket-register-column"'
assert_file_absent "no column file when the argument is missing" "$STATE_DIR/$SESSION.column"

# Quoting is not load-bearing: an unquoted argument is one shell word and is
# recorded as given. (It used to be dropped, which is the defect this suite's
# argv sibling covers.)
run_hook "$SESSION" '"$HOME/.cockpit/scripts/ticket-register-column" InDevUnquoted'
assert_content "unquoted column argument is recorded" "InDevUnquoted" "$STATE_DIR/$SESSION.column"

printf "\nTest group: chained registration still defers to the prompt\n"

# State is recorded, but auto-approval is not granted for a chained shape.
decision="$(jq -nc --arg sid "$SESSION" --arg cmd '"$HOME/.cockpit/scripts/ticket-register-column" "In CR" && rm -rf /' \
  '{tool_name:"Bash",session_id:$sid,tool_input:{command:$cmd}}' \
  | HOME="$TMPDIR" bash "$HOOK" 2>/dev/null)"
if [ -z "$decision" ]; then
  printf "  OK  chained command is not auto-approved\n"
  pass=$((pass + 1))
else
  printf "  KO  chained command was auto-approved — %s\n" "$decision"
  fail=$((fail + 1))
fi
assert_content "chained command still recorded its column" "In CR" "$STATE_DIR/$SESSION.column"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
