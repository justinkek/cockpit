#!/usr/bin/env bash

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$HOOKS/note-unflagged-question.sh"
RECORDER="$HOOKS/require-blocked-comment.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

STATE_DIR="$TMPDIR/.local/state/claude-ticket-sessions"
mkdir -p "$STATE_DIR"

SESSION="test-question-$$"
PAGE="3b68f3776f4f8123a2c7e6ec05d98cc4"
TRANSCRIPT="$TMPDIR/transcript.jsonl"

printf 'https://app.notion.com/p/%s\n' "$PAGE" > "$STATE_DIR/$SESSION.ticket"

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
  local page_id="$1" properties="$2"
  jq --null-input --compact-output --arg sid "$SESSION" --arg page "$page_id" --argjson properties "$properties" \
    '{hook_event_name:"PostToolUse",session_id:$sid,tool_input:{page_id:$page,properties:$properties}}' \
    | HOME="$TMPDIR" bash "$RECORDER" >/dev/null 2>&1
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

run_recorder "$PAGE" '{"Blocked":"Blocked"}'
assert_marker "setting the flag records it" present
assert_passes "the same question once the flag is set" "$(run_guard)"

run_recorder "$PAGE" '{"Status":"In Dev"}'
assert_marker "an unrelated property write leaves the flag alone" present

run_recorder "3b58f3776f4f81d4808ef39ef9033f10" '{"Blocked":null}'
assert_marker "clearing the flag on another ticket leaves this one alone" present

run_recorder "$PAGE" '{"Blocked":null}'
assert_marker "clearing the flag takes the record away" absent
assert_blocks "the question is refused again once unblocked" "$(run_guard)"

printf "\nTest group: a card that is finished has nothing left to block on\n"

reply_of '1. Q: Which board serves this checkout?'
printf 'In Dev\n' > "$STATE_DIR/$SESSION.column"
assert_blocks "a card still in the flow" "$(run_guard)"

printf 'Done\n' > "$STATE_DIR/$SESSION.column"
assert_passes "a card already at Done" "$(run_guard)"

rm -f "$STATE_DIR/$SESSION.column"

printf "\nTest group: the shapes a registered ticket url comes in\n"

for url in \
  "https://app.notion.com/p/$PAGE" \
  "https://app.notion.com/m33/A-reply-that-asks-a-question-$PAGE" \
  "https://app.notion.com/team/3928f3776f4f80909ee6d4cd230224de?v=3a58f3776f4f80c5a25e000cfd94acf8&p=$PAGE&pm=s" \
  "https://app.notion.com/p/3b68f377-6f4f-8123-a2c7-e6ec05d98cc4"; do
  printf '%s\n' "$url" > "$STATE_DIR/$SESSION.ticket"
  run_recorder "$PAGE" '{"Blocked":"Blocked"}'
  assert_marker "${url##*notion.com}" present
  run_recorder "$PAGE" '{"Blocked":null}'
done

printf 'https://app.notion.com/p/%s\n' "$PAGE" > "$STATE_DIR/$SESSION.ticket"

printf "\nTest group: the guards\n"

jq --null-input --compact-output --arg page "$PAGE" \
  '{hook_event_name:"PostToolUse",session_id:"no-such-session",tool_input:{page_id:$page,properties:{Blocked:"Blocked"}}}' \
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
