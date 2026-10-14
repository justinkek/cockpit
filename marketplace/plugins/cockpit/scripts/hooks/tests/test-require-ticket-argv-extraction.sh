#!/usr/bin/env bash

export CLAUDE_SHARED_DIR="$(cd "$(dirname "$0")/../../../../../../agents/claude" && pwd)"

TICKET_HOOK="$(cd "$(dirname "$0")/.." && pwd)/require-ticket.sh"
RENAME_HOOK="$(cd "$(dirname "$0")/.." && pwd)/require-rename.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

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

assert_contains() {
  local label="$1" needle="$2" path="$3"
  if grep -qF "$needle" "$path" 2>/dev/null; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — '%s' not found in %s\n" "$label" "$needle" "$path"
    fail=$((fail + 1))
  fi
}

run_ticket_hook() {
  local session_id="$1" cmd="$2"
  jq -nc --arg sid "$session_id" --arg cmd "$cmd" \
    '{tool_name:"Bash",session_id:$sid,tool_input:{command:$cmd}}' \
    | HOME="$TMPDIR" bash "$TICKET_HOOK" >/dev/null 2>&1
}

run_rename_hook() {
  local session_id="$1" cmd="$2" transcript="$3"
  jq -nc --arg sid "$session_id" --arg cmd "$cmd" --arg t "$transcript" \
    '{tool_name:"Bash",session_id:$sid,transcript_path:$t,tool_input:{command:$cmd}}' \
    | HOME="$TMPDIR" bash "$RENAME_HOOK" >/dev/null 2>&1
}

SESSION="test-argv-$$"
STATE_DIR="$TMPDIR/.local/state/claude-ticket-sessions"
mkdir -p "$STATE_DIR"
printf 'FEAT-31\n' > "$STATE_DIR/$SESSION.ticket"

printf "Test group: an unquoted argument is still read\n"

rm -f "$STATE_DIR/$SESSION.type"
run_ticket_hook "$SESSION" '"$HOME/.cockpit/scripts/ticket-register-type" ticket "a session name" feature'
assert_content "unquoted ticket type lands in the sidecar" "type=ticket
name=a session name
ticket_type=feature" "$STATE_DIR/$SESSION.type"

rm -f "$STATE_DIR/$SESSION.ticket"
run_ticket_hook "$SESSION" '"$HOME/.cockpit/scripts/ticket-register" FEAT-12'
assert_content "an unquoted card id is recorded" "FEAT-12" "$STATE_DIR/$SESSION.ticket"

printf "\nTest group: a session name echoing the script name does not hijack the match\n"

# The live failure: a ticket about ticket-register-type produces a session name
# containing "ticket-register-type", and the greedy anchor read its arguments
# from inside that quoted name instead of from the command.
rm -f "$STATE_DIR/$SESSION.type"
run_ticket_hook "$SESSION" '"$HOME/.cockpit/scripts/ticket-register-type" ticket "[x] ticket-register-type drops the ticket type when unquoted" bug'
assert_content "type sidecar written despite the self-referential name" "type=ticket
name=[x] ticket-register-type drops the ticket type when unquoted
ticket_type=bug" "$STATE_DIR/$SESSION.type"

rm -f "$STATE_DIR/$SESSION.column"
run_ticket_hook "$SESSION" '"$HOME/.cockpit/scripts/ticket-register-column" "In Dev on ticket-register-column"'
assert_content "column sidecar written despite the name containing the script name" "In Dev on ticket-register-column" "$STATE_DIR/$SESSION.column"

rm -f "$STATE_DIR/$SESSION.ticket"
run_ticket_hook "$SESSION" '"$HOME/.cockpit/scripts/ticket-register" "https://app.notion.com/p/ticket-register-lookalike"'
assert_content "ticket marker written despite the URL containing the script name" "https://app.notion.com/p/ticket-register-lookalike" "$STATE_DIR/$SESSION.ticket"

printf "\nTest group: a chained command's words are not this invocation's arguments\n"

rm -f "$STATE_DIR/$SESSION.type"
run_ticket_hook "$SESSION" '"$HOME/.cockpit/scripts/ticket-register-type" ticket "a session name" && echo feature'
assert_content "no ticket_type absorbed from the chained command" "type=ticket
name=a session name" "$STATE_DIR/$SESSION.type"

printf "\nTest group: the rename hook shares the fix\n"

TRANSCRIPT="$TMPDIR/transcript.jsonl"
: > "$TRANSCRIPT"
run_rename_hook "$SESSION-rename" '"$HOME/.cockpit/scripts/auto-rename" "[x] auto-rename swallows the name"' "$TRANSCRIPT"
assert_contains "custom-title carries the full name, not a fragment" '"customTitle":"[x] auto-rename swallows the name"' "$TRANSCRIPT"

fresh=0

assert_decision() {
  local label="$1" expected="$2" hook="$3" cmd="$4" actual
  fresh=$((fresh + 1))
  actual="$(jq -nc --arg sid "$SESSION-unregistered-unnamed-$fresh" --arg cmd "$cmd" \
    '{tool_name:"Bash",session_id:$sid,transcript_path:"",tool_input:{command:$cmd}}' \
    | HOME="$TMPDIR" bash "$hook" 2>/dev/null \
    | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  [ -n "$actual" ] || actual="none"
  if [ "$actual" = "$expected" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s', got '%s'\n" "$label" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

NEW_SKILL="$(cd "$(dirname "$0")/../../.." && pwd)/skills/ticket:0:new/SKILL.md"
NEW_CARD_CREATE="$(awk '
  /^### 3\. Create the card/ { step = 1 }
  open && /^```$/ { exit }
  open { print }
  step && /^```sh$/ { open = 1 }
' "$NEW_SKILL")"
NEW_CARD_CREATE="${NEW_CARD_CREATE//<title>/a new card}"
NEW_CARD_CREATE="${NEW_CARD_CREATE//<Type>/Feature}"
NEW_CARD_CREATE="${NEW_CARD_CREATE//<column>/Ready for BR by AI}"
NEW_CARD_CREATE="${NEW_CARD_CREATE//<EPIC-n>/EPIC-1}"
NEW_CARD_CREATE="${NEW_CARD_CREATE//<body>/$'## Context\n\n### Task\nA new card.'}"

printf "\nTest group: the heredoc create ticket:0:new prescribes runs before a ticket and a name exist\n"

case "$NEW_CARD_CREATE" in
  '"$HOME/.cockpit/scripts/board-card" create '*$'\n'*EOF)
    printf "  OK  step 3 of ticket:0:new still holds a multi-line board-card create\n"
    pass=$((pass + 1))
    ;;
  *)
    printf "  KO  step 3 of ticket:0:new no longer holds a multi-line board-card create — got '%s'\n" "$NEW_CARD_CREATE"
    fail=$((fail + 1))
    ;;
esac

assert_decision "the ticket gate lets the heredoc create through" none "$TICKET_HOOK" "$NEW_CARD_CREATE"
assert_decision "the rename gate lets the heredoc create through" none "$RENAME_HOOK" "$NEW_CARD_CREATE"

printf "\nTest group: only the first line names the command\n"

for hook in "$TICKET_HOOK" "$RENAME_HOOK"; do
  assert_decision "$(basename "$hook") denies a write whose later line runs ticket-claim-lock" deny "$hook" \
    "$(printf '%s\n%s' 'touch a-file' '"$HOME/.cockpit/scripts/ticket-claim-lock" FEAT-1')"
  assert_decision "$(basename "$hook") denies a write whose later line runs board-card show" deny "$hook" \
    "$(printf '%s\n%s' 'touch a-file' '"$HOME/.cockpit/scripts/board-card" show FEAT-1')"
done

printf "\nTest group: a line break keeps an intercepted script from approving another command\n"

assert_decision "ticket-register on its own line is still approved" allow "$TICKET_HOOK" \
  '"$HOME/.cockpit/scripts/ticket-register" FEAT-1'
assert_decision "ticket-register followed by another line is not approved" none "$TICKET_HOOK" \
  "$(printf '%s\n%s' '"$HOME/.cockpit/scripts/ticket-register" FEAT-1' 'touch a-file')"
assert_decision "ticket-register after another line is not approved" none "$TICKET_HOOK" \
  "$(printf '%s\n%s' 'touch a-file' '"$HOME/.cockpit/scripts/ticket-register" FEAT-1')"
assert_decision "auto-rename on its own line is still approved" allow "$RENAME_HOOK" \
  '"$HOME/.cockpit/scripts/auto-rename" "a name"'
assert_decision "auto-rename followed by another line is not approved" none "$RENAME_HOOK" \
  "$(printf '%s\n%s' '"$HOME/.cockpit/scripts/auto-rename" "a name"' 'touch a-file')"
assert_decision "auto-rename after another line is not approved" none "$RENAME_HOOK" \
  "$(printf '%s\n%s' 'touch a-file' '"$HOME/.cockpit/scripts/auto-rename" "a name"')"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
