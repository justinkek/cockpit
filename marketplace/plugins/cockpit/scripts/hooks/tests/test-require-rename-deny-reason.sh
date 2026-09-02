#!/usr/bin/env bash

export CLAUDE_SHARED_DIR="$(cd "$(dirname "$0")/../../../../../../agents/claude" && pwd)"

HOOK="$(cd "$(dirname "$0")/.." && pwd)/require-rename.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s', got '%s'\n" "$label" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

assert_contains() {
  local label="$1" expected="$2" output="$3"
  if printf '%s' "$output" | grep -qF "$expected"; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s' in output '%s'\n" "$label" "$expected" "$output"
    fail=$((fail + 1))
  fi
}

assert_absent() {
  local label="$1" unwanted="$2" output="$3"
  if printf '%s' "$output" | grep -qF "$unwanted"; then
    printf "  KO  %s — found '%s' in output '%s'\n" "$label" "$unwanted" "$output"
    fail=$((fail + 1))
  else
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  fi
}

TRANSCRIPT="$TMPDIR/transcript.jsonl"
: > "$TRANSCRIPT"

# Feed the hook one PreToolUse payload. $1 is a session id, $2 a Bash command.
# jq builds the payload so a command carrying its own quotes stays valid JSON.
run_hook() {
  jq -nc --arg s "$1" --arg t "$TRANSCRIPT" --arg c "$2" \
    '{tool_name:"Bash",session_id:$s,transcript_path:$t,tool_input:{command:$c}}' \
    | HOME="$TMPDIR" bash "$HOOK"
}

field() { printf '%s' "$2" | jq -r ".hookSpecificOutput.$1"; }

printf "Test group: the deny reason directs the agent to self-serve\n"

# `ls` now reads as looking around and is let through, so the deny case has to
# be a command that changes something — otherwise this test pins the old
# behaviour and the change lands red.
denied="$(run_hook "unnamed-$$" "rm -rf $TMPDIR/scratch")"
reason="$(field permissionDecisionReason "$denied")"

assert_eq "an unnamed session is denied" "deny" "$(field permissionDecision "$denied")"
assert_contains "names the self-serve script" "auto-rename" "$reason"
assert_contains "names where the convention is stated" "templates/session-name.md" "$reason"
assert_absent "carries no convention of its own" "[area]" "$reason"
assert_absent "never hands the rename back as /rename" "/rename" "$reason"
assert_absent "never tells the agent to ask the user" "tell the user" "$reason"

printf "\nTest group: the reason survives the no-jq fallback branch\n"

# The fallback branch builds its JSON with printf and no escaping, so a double
# quote anywhere in the reason would emit an unparseable payload.
assert_absent "carries no double quote" '"' "$reason"

printf "\nTest group: the intercept the reason points at still self-serves\n"

allowed="$(run_hook "intercept-$$" "\"\$HOME/.cockpit/scripts/auto-rename\" \"[test] a name\"")"

assert_eq "auto-rename is allowed, not denied" "allow" "$(field permissionDecision "$allowed")"
assert_eq "the session is named without the user" "1" \
  "$(grep -c '"type":"custom-title"' "$TRANSCRIPT" | tr -d ' ')"

printf "\nTest group: refinement renaming the ticket renames the session again\n"

renamed="$(run_hook "intercept-$$" "\"\$HOME/.cockpit/scripts/auto-rename\" \"[test] a newer name\"")"

assert_eq "the second rename of the same session is allowed" "allow" "$(field permissionDecision "$renamed")"
assert_eq "the newer name is recorded too" "2" \
  "$(grep -c '"type":"custom-title"' "$TRANSCRIPT" | tr -d ' ')"
assert_contains "the newer name is the one recorded last" '"customTitle":"[test] a newer name"' \
  "$(tail -n 1 "$TRANSCRIPT")"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
