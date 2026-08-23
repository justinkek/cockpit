#!/usr/bin/env bash

HOOK="$(cd "$(dirname "$0")/.." && pwd)/remind-response-length.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

assert_fires() {
  local label="$1" output="$2"
  if printf '%s' "$output" | grep -qF "[response-length]"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected the ceiling, got '%s'\n" "$label" "$output"
    fail=$((fail + 1))
  fi
}

run_hook() {
  local session_id="$1" prompt="$2"
  jq -nc --arg sid "$session_id" --arg p "$prompt" \
    '{hook_event_name:"UserPromptSubmit",session_id:$sid,prompt:$p}' \
    | HOME="$TMPDIR" bash "$HOOK" 2>/dev/null
}

STATE_DIR="$TMPDIR/.local/state/claude-ticket-sessions"
mkdir -p "$STATE_DIR"

SESSION="test-length-$$"

printf "Test group: fires regardless of prompt shape\n"

assert_fires "plain directive" "$(run_hook "$SESSION" 'add a rule')"
assert_fires "question" "$(run_hook "$SESSION" 'why does the hook not fire?')"
assert_fires "long prompt" "$(run_hook "$SESSION" "$(head -c 4000 /dev/zero | tr '\0' 'x')")"
assert_fires "empty prompt" "$(run_hook "$SESSION" '')"

printf "\nTest group: carries the clauses the always-loaded rules no longer state\n"

assert_carries() {
  local label="$1" clause="$2"
  if run_hook "$SESSION" 'add a rule' | grep --quiet --fixed-strings -- "$clause"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — the reminder does not state '%s'\n" "$label" "$clause"
    fail=$((fail + 1))
  fi
}

assert_carries "the rule reaches past the chat reply" \
  "a ticket comment and a reply to a review comment alike"
assert_carries "a directive is answered in one line" \
  "A completed directive is a one-line confirmation, not a write-up."

printf "\nTest group: fires regardless of session state\n"

assert_fires "no ticket registered" "$(run_hook "$SESSION" 'add a rule')"

printf 'https://app.notion.com/p/abc123\n' > "$STATE_DIR/$SESSION.ticket"
assert_fires "ticket registered, no column" "$(run_hook "$SESSION" 'add a rule')"

for col in "In BR" "In TR" "In Dev" "In CR" "Done"; do
  printf '%s\n' "$col" > "$STATE_DIR/$SESSION.column"
  assert_fires "column '$col'" "$(run_hook "$SESSION" 'add a rule')"
done

assert_fires "no session id" "$(jq -nc '{prompt:"add a rule"}' | HOME="$TMPDIR" bash "$HOOK" 2>/dev/null)"

printf "\nTest group: emits exactly one line\n"

lines="$(run_hook "$SESSION" 'add a rule' | wc -l | tr -d ' ')"
if [ "$lines" = "1" ]; then
  printf "  OK  single line of output\n"
  pass=$((pass + 1))
else
  printf "  KO  single line of output — got %s lines\n" "$lines"
  fail=$((fail + 1))
fi

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
