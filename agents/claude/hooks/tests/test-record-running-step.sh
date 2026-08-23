#!/usr/bin/env bash

HOOK="$(cd "$(dirname "$0")/.." && pwd)/record-running-step.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

export TICKET_STATE_DIR="$TMPDIR/state"

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

assert_absent() {
  local label="$1" path="$2"
  if [ ! -e "$path" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — %s still exists holding '%s'\n" "$label" "$path" "$(cat "$path")"
    fail=$((fail + 1))
  fi
}

marker="$TICKET_STATE_DIR/s1.step"

printf "Test group: record writes the step the agent entered\n"

printf '{"session_id":"s1","tool_input":{"skill":"cockpit:ticket:4:ready-for-cr"}}' \
  | bash "$HOOK" record
assert_equals "namespace stripped off the skill name" "ready-for-cr" "$(cat "$marker" 2>/dev/null)"

printf '{"session_id":"s1","tool_input":{"skill":"code-review"}}' \
  | bash "$HOOK" record
assert_equals "an unnamespaced skill is written whole" "code-review" "$(cat "$marker" 2>/dev/null)"

printf "\nTest group: clear takes it away, and says nothing when there is nothing there\n"

printf '{"session_id":"s1"}' | bash "$HOOK" clear
assert_absent "clear removes the marker" "$marker"

printf '{"session_id":"s1"}' | bash "$HOOK" clear
assert_equals "clear on a missing marker exits 0" "0" "$?"

printf "\nTest group: nothing is written without the two values the marker needs\n"

printf '{"tool_input":{"skill":"cockpit:ticket:3:dev"}}' | bash "$HOOK" record
assert_absent "no session id, no marker" "$marker"

printf '{"session_id":"s1","tool_input":{"file_path":"/tmp/x"}}' | bash "$HOOK" record
assert_absent "a tool that is not Skill leaves no marker" "$marker"

printf "\nTest group: one session's step is not another's\n"

printf '{"session_id":"s1","tool_input":{"skill":"cockpit:ticket:3:dev"}}' | bash "$HOOK" record
printf '{"session_id":"s2","tool_input":{"skill":"cockpit:ticket:1:br"}}' | bash "$HOOK" record
printf '{"session_id":"s2"}' | bash "$HOOK" clear
assert_equals "clearing s2 leaves s1 alone" "dev" "$(cat "$marker" 2>/dev/null)"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
