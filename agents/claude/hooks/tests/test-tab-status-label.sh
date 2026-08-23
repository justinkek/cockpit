#!/usr/bin/env bash

HOOK="$(cd "$(dirname "$0")/.." && pwd)/tab-status.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

assert_contains() {
  local label="$1" expected="$2" output="$3"
  if printf '%s' "$output" | grep --quiet --fixed-strings "$expected"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s' in output '%s'\n" "$label" "$expected" "$output"
    fail=$((fail + 1))
  fi
}

assert_not_contains() {
  local label="$1" unexpected="$2" output="$3"
  if ! printf '%s' "$output" | grep --quiet --fixed-strings "$unexpected"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — did not expect '%s' in output '%s'\n" "$label" "$unexpected" "$output"
    fail=$((fail + 1))
  fi
}

SESSION_ID="test-tab-status-$$"
STATE_DIR="$TMPDIR/.local/state/claude-ticket-sessions"
TRANSCRIPT_DIR="$TMPDIR/transcripts/$SESSION_ID"
CWD_DIR="$TMPDIR/some-repo"
mkdir -p "$STATE_DIR" "$TRANSCRIPT_DIR" "$CWD_DIR"

TRANSCRIPT_PATH="$TRANSCRIPT_DIR/transcript.jsonl"

run_hook() {
  local state="$1"
  jq --null-input --compact-output \
    --arg transcript "$TRANSCRIPT_PATH" \
    --arg session "$SESSION_ID" \
    --arg directory "$CWD_DIR" \
    '{transcript_path:$transcript, session_id:$session, cwd:$directory}' \
    | HOME="$TMPDIR" bash "$HOOK" "$state" 2>/dev/null
}

printf "Test group: a named session titles the tab with everything after the bracket\n"

printf '{"type":"custom-title","customTitle":"[claude setup] warp tab is named after the session"}\n' > "$TRANSCRIPT_PATH"

output=$(run_hook working)

assert_contains "the whole description is the label" "warp tab is named after the session" "$output"
assert_not_contains "the bracketed epic is dropped" "claude setup" "$output"
assert_contains "the working glyph sits in front of it" "⏳ warp tab is named after the session" "$output"

printf "\nTest group: a one-word description comes through whole\n"

printf '{"type":"custom-title","customTitle":"[cve] scanning"}\n' > "$TRANSCRIPT_PATH"

assert_contains "a one-word description survives intact" "✅ scanning" "$(run_hook done)"

printf "\nTest group: the name recorded at registration is the fallback\n"

printf '' > "$TRANSCRIPT_PATH"
printf 'type=ticket\nname=[claude setup] registration name here\nticket_type=feature\n' > "$STATE_DIR/$SESSION_ID.type"

assert_contains "the type file answers when the transcript holds no rename" "🔔 registration name here" "$(run_hook needs)"

printf "\nTest group: an unnamed session still gets the directory basename\n"

rm -f "$STATE_DIR/$SESSION_ID.type"

assert_contains "the cwd basename is the floor" "⏳ some-repo" "$(run_hook working)"

printf "\nTest group: the glyph follows the state argument, never the name\n"

printf '{"type":"custom-title","customTitle":"[cve] scanning"}\n' > "$TRANSCRIPT_PATH"

assert_contains "working" "⏳ scanning" "$(run_hook working)"
assert_contains "done" "✅ scanning" "$(run_hook done)"
assert_contains "needs" "🔔 scanning" "$(run_hook needs)"
assert_contains "an unrecognised state" "• scanning" "$(run_hook something-else)"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
