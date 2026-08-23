#!/usr/bin/env bash

HOOK="$(cd "$(dirname "$0")/.." && pwd)/remind-back-from-column.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

assert_fires() {
  local label="$1" output="$2"
  if printf '%s' "$output" | grep -qF "[back-from-column]"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected a nudge, got '%s'\n" "$label" "$output"
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

run_hook() {
  local session_id="$1" prompt="$2"
  jq -nc --arg sid "$session_id" --arg p "$prompt" \
    '{hook_event_name:"UserPromptSubmit",session_id:$sid,prompt:$p}' \
    | HOME="$TMPDIR" bash "$HOOK" 2>/dev/null
}

STATE_DIR="$TMPDIR/.local/state/claude-ticket-sessions"
mkdir -p "$STATE_DIR"

SESSION="test-bounce-$$"
printf 'https://app.notion.com/p/abc123\n' > "$STATE_DIR/$SESSION.ticket"
printf 'In Dev\n' > "$STATE_DIR/$SESSION.column"

printf "Test group: fires on a rejection at a counter column\n"

assert_fires "plain rejection" "$(run_hook "$SESSION" 'this is still broken')"
assert_fires "contraction with apostrophe" "$(run_hook "$SESSION" "the button doesn't work")"
assert_fires "contraction without apostrophe" "$(run_hook "$SESSION" 'the button doesnt work')"
assert_fires "case insensitive" "$(run_hook "$SESSION" 'You Missed the null case')"
assert_fires "names the column in the nudge" "$(run_hook "$SESSION" 'that is a regression')"

printf "\nTest group: silent when the prompt is not a rejection\n"

assert_silent "neutral instruction" "$(run_hook "$SESSION" 'add a comment explaining this')"
assert_silent "praise" "$(run_hook "$SESSION" 'nice, that looks right')"
assert_silent "empty prompt" "$(run_hook "$SESSION" '')"

printf "\nTest group: silent when the column has no counter\n"

for col in "In BR" "In TR" "Ready for CR" "Ready for Sprint"; do
  printf '%s\n' "$col" > "$STATE_DIR/$SESSION.column"
  assert_silent "column '$col' has no Back from counter" "$(run_hook "$SESSION" 'this is still broken')"
done

printf "\nTest group: fires at every column that does have a counter\n"

for col in "In Dev" "In CR" "In FR" "Ready for Validation"; do
  printf '%s\n' "$col" > "$STATE_DIR/$SESSION.column"
  assert_fires "column '$col' has a Back from counter" "$(run_hook "$SESSION" 'this is still broken')"
done

printf "\nTest group: silent without ticket registration\n"

printf 'In Dev\n' > "$STATE_DIR/$SESSION.column"
rm -f "$STATE_DIR/$SESSION.ticket"
assert_silent "no ticket marker" "$(run_hook "$SESSION" 'this is still broken')"

printf 'https://app.notion.com/p/abc123\n' > "$STATE_DIR/$SESSION.ticket"
rm -f "$STATE_DIR/$SESSION.column"
assert_silent "no column marker" "$(run_hook "$SESSION" 'this is still broken')"

assert_silent "no session id" "$(jq -nc '{prompt:"this is still broken"}' | HOME="$TMPDIR" bash "$HOOK" 2>/dev/null)"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
