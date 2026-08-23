#!/usr/bin/env bash

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

RUNS_BEFORE_A_TICKET_AND_A_NAME_EXIST="ticket-board-members
ticket-claim-lock
ticket-waiting-cards
cockpit-board-claim
cockpit-board-id
cockpit-cache-query"

pass=0
fail=0

assert_decision() {
  local label="$1" expected="$2" hook="$3" input="$4"
  local output decision
  output="$(printf '%s' "$input" | HOME="$TMPDIR" bash "$HOOKS/$hook" 2>/dev/null)"
  if [ -z "$output" ]; then
    decision="none"
  else
    decision="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null)"
  fi
  if [ "$decision" = "$expected" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s', got '%s'\n" "$label" "$expected" "$decision"
    fail=$((fail + 1))
  fi
}

bash_call() {
  jq --null-input --compact-output --arg command "$1" \
    '{session_id:"cross-allow-test",transcript_path:"",tool_name:"Bash",tool_input:{command:$command}}'
}

for hook in require-ticket.sh require-rename.sh; do
  printf "Test group: %s lets a pre-registration script through\n" "$hook"
  while IFS= read -r script; do
    assert_decision "$script" none "$hook" "$(bash_call "\"\$HOME/.claude-shared/$script\" some-argument")"
  done <<< "$RUNS_BEFORE_A_TICKET_AND_A_NAME_EXIST"
  assert_decision "and denies a script that is not one of them" \
    deny "$hook" "$(bash_call "\"\$HOME/.claude-shared/ticket-done-usage\" some-argument")"
  printf "\n"
done

printf "%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
