#!/usr/bin/env bash

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
REPLAY="$HOOKS/replay-stop-notes.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

STATE_DIR="$TMPDIR/.local/state/claude-ticket-sessions"
mkdir -p "$STATE_DIR"

SESSION="test-replay-$$"
NOTES_FILE="$STATE_DIR/$SESSION.stop-notes"

record() {
  printf '%s\n' "$1" >> "$NOTES_FILE"
}

run_replay() {
  local session_id="${1:-$SESSION}"
  jq --null-input --compact-output --arg sid "$session_id" \
    '{hook_event_name:"UserPromptSubmit",session_id:$sid,prompt:"carry on"}' \
    | HOME="$TMPDIR" bash "$REPLAY" 2>/dev/null
}

assert_prints() {
  local label="$1" output="$2" expected="$3"
  if printf '%s' "$output" | grep --quiet --fixed-strings "$expected"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s', got '%s'\n" "$label" "$expected" "$output"
    fail=$((fail + 1))
  fi
}

assert_silent() {
  local label="$1" output="$2"
  if [ -z "$output" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected silence, got '%s'\n" "$label" "$output"
    fail=$((fail + 1))
  fi
}

assert_file() {
  local label="$1" expected="$2"
  local actual=absent
  [ -f "$NOTES_FILE" ] && actual=present
  if [ "$actual" = "$expected" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected the note file %s, found it %s\n" "$label" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

printf "Test group: a note the last turn left\n"

assert_silent "no note to replay" "$(run_replay)"

record '[reply-shape] The last reply ran 40 lines of prose against a ceiling of 8.'
assert_prints "the note reaches the next prompt" "$(run_replay)" "ran 40 lines of prose"

printf "\nTest group: a note fires once\n"

record '[reply-shape] The last reply ran 40 lines of prose against a ceiling of 8.'
run_replay >/dev/null
assert_file "the replay takes the note away" absent
assert_silent "the prompt after it" "$(run_replay)"

printf "\nTest group: two findings from one turn\n"

record '[reply-shape] The last reply ran 40 lines of prose against a ceiling of 8.'
record '[ticket-status] A commit landed and the card is still In Dev.'
replayed="$(run_replay)"
assert_prints "the first one" "$replayed" "ran 40 lines of prose"
assert_prints "the second one" "$replayed" "still In Dev"
assert_file "both go together" absent

printf "\nTest group: the guards\n"

record '[reply-shape] The last reply ran 40 lines of prose against a ceiling of 8.'
assert_silent "another session's prompt reads nothing" "$(run_replay "some-other-session")"
assert_file "and leaves this session's note in place" present

assert_silent "no session id" \
  "$(jq --null-input --compact-output '{hook_event_name:"UserPromptSubmit",prompt:"carry on"}' \
    | HOME="$TMPDIR" bash "$REPLAY" 2>/dev/null)"
assert_file "still in place with no session id" present

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
