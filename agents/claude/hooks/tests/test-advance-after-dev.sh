#!/usr/bin/env bash

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$HOOKS/advance-after-dev.sh"
RECORDER="$HOOKS/remind-ticket-status.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

STATE_DIR="$TMPDIR/.local/state/claude-ticket-sessions"
mkdir -p "$STATE_DIR"

SESSION="test-advance-after-dev-$$"
PAGE="3b68f3776f4f8115ac0fd6bbfbea6973"

printf 'https://app.notion.com/p/%s\n' "$PAGE" > "$STATE_DIR/$SESSION.ticket"

run_guard() {
  local session_id="${1:-$SESSION}" active="${2:-false}" sent notes_file
  notes_file="$STATE_DIR/$session_id.stop-notes"
  rm -f "$notes_file"
  sent="$(jq --null-input --compact-output \
    --arg sid "$session_id" --argjson active "$active" \
    '{hook_event_name:"Stop",session_id:$sid,stop_hook_active:$active}' \
    | HOME="$TMPDIR" bash "$GUARD" 2>/dev/null)"
  if [ -n "$sent" ]; then
    printf 'THE REPLY WAS DISCARDED: %s' "$sent"
    return 0
  fi
  [ -f "$notes_file" ] && cat "$notes_file"
  return 0
}

run_recorder() {
  local command="$1" exit_code="${2:-0}" session_id="${3:-$SESSION}" field="${4:-tool_response}"
  jq --null-input --compact-output \
    --arg sid "$session_id" --arg command "$command" --argjson code "$exit_code" --arg field "$field" \
    '{hook_event_name:"PostToolUse",tool_name:"Bash",session_id:$sid,tool_input:{command:$command}}
     | .[$field] = {exitCode:$code}' \
    | HOME="$TMPDIR" bash "$RECORDER" >/dev/null 2>&1
}

at_column() {
  printf '%s\n' "$1" > "$STATE_DIR/$SESSION.column"
}

assert_blocks() {
  local label="$1" note="$2"
  if [ -n "$note" ] && [ "${note#THE REPLY WAS DISCARDED}" = "$note" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected a recorded note, got '%s'\n" "$label" "$note"
    fail=$((fail + 1))
  fi
}

assert_passes() {
  local label="$1" note="$2"
  if [ -z "$note" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected nothing recorded, got '%s'\n" "$label" "$note"
    fail=$((fail + 1))
  fi
}

assert_marker() {
  local label="$1" expected="$2"
  local actual=absent
  [ -f "$STATE_DIR/$SESSION.dev-committed" ] && actual=present
  if [ "$actual" = "$expected" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected the marker %s, found it %s\n" "$label" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

printf "Test group: what records a commit\n"

at_column "In Dev"
assert_marker "no commit yet" absent

run_recorder "git commit --message 'a change'"
assert_marker "a commit that succeeded" present

rm -f "$STATE_DIR/$SESSION.dev-committed"
run_recorder "git commit --message 'nothing staged'" 1
assert_marker "a commit that failed" absent

run_recorder "git status --short"
assert_marker "a command that is not a commit" absent

run_recorder "git commit --message 'nothing staged'" 1 "$SESSION" tool_result
assert_marker "a failed commit reported under the older field name" absent

run_recorder "git commit --message 'a change'" 0 "$SESSION" tool_result
assert_marker "a commit reported under the older field name" present
rm -f "$STATE_DIR/$SESSION.dev-committed"

printf "\nTest group: the turn that ends with a commit behind it\n"

run_recorder "git commit --message 'a change'"
assert_blocks "a commit landed, the card still In Dev" "$(run_guard)"
assert_marker "the block consumes the commit" absent
assert_passes "the turn after the hook already fired" "$(run_guard)"

printf "\nTest group: where the hook stays quiet\n"

run_recorder "git commit --message 'a change'"
at_column "In CR by AI"
assert_passes "the card already past In Dev" "$(run_guard)"

at_column "In Dev"
: > "$STATE_DIR/$SESSION.stage-cr"
assert_passes "the post-dev stage already confirmed" "$(run_guard)"
rm -f "$STATE_DIR/$SESSION.stage-cr"

rm -f "$STATE_DIR/$SESSION.column"
assert_passes "no column recorded for the session" "$(run_guard)"

at_column "In Dev"
assert_blocks "the column back in place" "$(run_guard)"

printf "\nTest group: the guards\n"

run_recorder "git commit --message 'a change'"
assert_passes "the second pass, so a block cannot loop" "$(run_guard "$SESSION" true)"

run_recorder "git commit --message 'a change'" 0 "no-such-session"
assert_passes "a session with no registered ticket" "$(run_guard "no-such-session")"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
