#!/usr/bin/env bash

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
export CLAUDE_SHARED_DIR="$(cd "$HOOKS/.." && pwd)"
GUARD="$HOOKS/note-unflagged-question.sh"
RECORDER="$(cd "$HOOKS/../../../marketplace/plugins/cockpit/scripts/hooks" && pwd)/require-blocked-comment.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

STATE_DIR="$TMPDIR/.local/state/claude-ticket-sessions"
mkdir -p "$STATE_DIR"

SESSION="test-question-$$"
CARD="FEAT-42"
TRANSCRIPT="$TMPDIR/transcript.jsonl"

printf '%s\n' "$CARD" > "$STATE_DIR/$SESSION.ticket"

reply_of() {
  jq --null-input --compact-output --arg t "$1" \
    '{type:"assistant",message:{content:[{type:"text",text:$t}]}}' > "$TRANSCRIPT"
}

run_payload() {
  local session_id="$1" sent notes_file="$STATE_DIR/$1.stop-notes"
  rm -f "$notes_file"
  sent="$(printf '%s' "$2" | HOME="$TMPDIR" bash "$GUARD" 2>/dev/null)"
  if [ -n "$sent" ]; then
    printf 'THE REPLY WAS DISCARDED: %s' "$sent"
    return 0
  fi
  [ -f "$notes_file" ] && cat "$notes_file"
  return 0
}

run_guard() {
  local session_id="${1:-$SESSION}" active="${2:-false}" payload
  payload="$(jq --null-input --compact-output \
    --arg sid "$session_id" --arg path "$TRANSCRIPT" --argjson active "$active" \
    '{hook_event_name:"Stop",session_id:$sid,transcript_path:$path,stop_hook_active:$active}')"
  run_payload "$session_id" "$payload"
}

run_recorder() {
  local command="$1" exit_code="${2:-0}"
  jq --null-input --compact-output --arg sid "$SESSION" --arg command "$command" --argjson code "$exit_code" \
    '{hook_event_name:"PostToolUse",session_id:$sid,tool_name:"Bash",tool_input:{command:$command},tool_response:{exitCode:$code}}' \
    | HOME="$TMPDIR" bash "$RECORDER" >/dev/null 2>&1
}

board_card='"$HOME/.cockpit/scripts/board-card"'

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
  [ -f "$STATE_DIR/$SESSION.blocked" ] && actual=present
  if [ "$actual" = "$expected" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected the marker %s, found it %s\n" "$label" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

printf "Test group: a question the next step waits on\n"

reply_of '`[queue]`

1. Q: Which of the two boards serves this checkout?
2. Investigate: whether the walk skips a date stamp under load.'
assert_blocks "a labelled question inside the queue" "$(run_guard)"

reply_of '**Q: Which board serves this checkout?**'
assert_blocks "the marker in bold at the start of a line" "$(run_guard)"

reply_of '`[queue]`

1. Q1. Which board serves this checkout?'
assert_passes "the retired numbered label is not the marker" "$(run_guard)"

reply_of '`[answer]` Tech steps redrafted, complexity 3 to 2.'
assert_passes "a reply that answers without asking" "$(run_guard)"

reply_of '`[queue]`

1. Whether this card splits.'
assert_passes "a queue item that asks nothing" "$(run_guard)"

reply_of 'The hook reads the queue for a Q: marker in header position.'
assert_passes "a reply that only describes the convention" "$(run_guard)"

reply_of "$(printf 'The rule writes a queue like this:\n\n```\n1. Q: Should the ADR reference specific CVE examples, or link to the folder?\n```\n\nThat is the whole shape.\n')"
assert_passes "the convention quoted inside a code block" "$(run_guard)"

reply_of "$(printf '```\n1. Q: a quoted example\n```\n\n1. Q: And one actually asked below it.\n')"
assert_blocks "a real question below a quoted one" "$(run_guard)"

printf "\nTest group: the flag is what clears the refusal\n"

reply_of '1. Q: Which board serves this checkout?'
assert_blocks "unflagged" "$(run_guard)"

run_recorder "$board_card set $CARD blocked 'waiting on the venue'" 1
assert_marker "a set that failed records nothing" absent

run_recorder "$board_card set $CARD blocked 'waiting on the venue'"
assert_marker "setting the flag records it" present
assert_passes "the same question once the flag is set" "$(run_guard)"

run_recorder "$board_card set $CARD prs https://github.com/owner/name/pull/1"
assert_marker "an unrelated field write leaves the flag alone" present

run_recorder "$board_card set FEAT-7 blocked ''"
assert_marker "clearing the flag on another card leaves this one alone" present

run_recorder "$board_card set $CARD blocked ''"
assert_marker "clearing the flag takes the record away" absent
assert_blocks "the question is refused again once unblocked" "$(run_guard)"

run_recorder "$board_card set feat-42 blocked 'lower case id'"
assert_marker "a card id typed in lower case is the same card" present
run_recorder "$board_card set $CARD blocked \"\""
assert_marker "and a double-quoted empty value clears it" absent

printf "\nTest group: a card that is finished has nothing left to block on\n"

reply_of '1. Q: Which board serves this checkout?'
printf 'In Dev\n' > "$STATE_DIR/$SESSION.column"
assert_blocks "a card still in the flow" "$(run_guard)"

printf 'Done\n' > "$STATE_DIR/$SESSION.column"
assert_passes "a card already at Done" "$(run_guard)"

rm -f "$STATE_DIR/$SESSION.column"

printf "\nTest group: the guards\n"

jq --null-input --compact-output --arg command "board-card set $CARD blocked reason" \
  '{hook_event_name:"PostToolUse",session_id:"no-such-session",tool_name:"Bash",tool_input:{command:$command}}' \
  | HOME="$TMPDIR" bash "$RECORDER" >/dev/null 2>&1
if [ -f "$STATE_DIR/no-such-session.blocked" ]; then
  printf "  KO  a session with no registered ticket records no flag — the marker was written\n"
  fail=$((fail + 1))
else
  printf "  OK  a session with no registered ticket records no flag\n"
  pass=$((pass + 1))
fi

assert_passes "a session with no registered ticket" "$(run_guard "no-such-session")"
assert_passes "the second pass, so a block cannot loop" "$(run_guard "$SESSION" true)"
assert_passes "no transcript on disk" \
  "$(run_payload "$SESSION" "$(jq --null-input --compact-output --arg sid "$SESSION" \
      '{hook_event_name:"Stop",session_id:$sid,transcript_path:"/nowhere/at/all.jsonl"}')")"

reply_of '1. Q: Which board serves this checkout?'
discarded="$(printf '%s' "$(run_guard)" | grep --count 'THE REPLY WAS DISCARDED')"
if [ "$discarded" = "0" ]; then
  printf "  OK  the hook sends nothing back on an unflagged question\n"
  pass=$((pass + 1))
else
  printf "  KO  the hook still discards the reply on an unflagged question\n"
  fail=$((fail + 1))
fi

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
