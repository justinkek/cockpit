#!/usr/bin/env bash

export CLAUDE_SHARED_DIR="$(cd "$(dirname "$0")/../../../../../../agents/claude" && pwd)"

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

# Feed one hook a PreToolUse Bash payload and print its decision, or "none"
# when the hook stays silent (exit 0 = no opinion; the normal allowlist or
# permission prompt decides). jq builds the payload so a command carrying its
# own quotes or newlines stays valid JSON.
decision() {
  local hook="$1" cmd="$2" out
  out="$(jq -nc --arg s "readonly-$$-$RANDOM" --arg c "$cmd" \
    '{tool_name:"Bash",session_id:$s,transcript_path:"",tool_input:{command:$c}}' \
    | HOME="$TMPDIR" bash "$HOOKS/$hook" 2>/dev/null)"
  if [ -z "$out" ]; then
    printf 'none\n'
  else
    printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null
  fi
}

assert_decision() {
  local label="$1" expected="$2" hook="$3" cmd="$4" got
  got="$(decision "$hook" "$cmd")"
  if [ "$got" = "$expected" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected '%s', got '%s'\n" "$label" "$expected" "$got"
    fail=$((fail + 1))
  fi
}

ls_bare='ls'
ls_flags='ls -la /tmp'
grep_flags='grep -rn foo .'
absolute='/bin/ls'
board_members='"$HOME/.cockpit/scripts/ticket-board-members"'
# Every script the copilot skill runs before the session has a name or a ticket.
# One of them missing from a gate's cross-allow list is a deadlock the skill
# cannot work around — its own rules forbid naming the session to get past it —
# and that is exactly how cockpit-board-claim shipped broken.
copilot_scripts=(
  '"$HOME/.cockpit/scripts/ticket-waiting-cards"'
  '"$HOME/.cockpit/scripts/ticket-board-members"'
  '"$HOME/.cockpit/scripts/cockpit-board-claim" ProjectBoard'
  '"$HOME/.cockpit/scripts/ticket-claim-lock" take abc123'
)

redirect='cat a > b'
chain='ls && rm -rf /tmp/scratch'
subshell='cat $(rm -rf /tmp/scratch)'
backtick='cat `rm -rf /tmp/scratch`'
pipe='ls | xargs rm'
twolines=$'cat a\nrm -rf /tmp/scratch'
outside='rm -rf /tmp/scratch'
find_cmd='find . -name x -delete'

for hook in require-ticket.sh require-rename.sh; do
  printf "Test group: %s\n" "$hook"
  assert_decision "lets a bare read through"             none "$hook" "$ls_bare"
  assert_decision "lets a read with flags through"       none "$hook" "$ls_flags"
  assert_decision "lets a grep with flags through"       none "$hook" "$grep_flags"
  assert_decision "matches on the basename, not the path" none "$hook" "$absolute"
  assert_decision "still cross-allows the repo script"   none "$hook" "$board_members"
  for script in "${copilot_scripts[@]}"; do
    assert_decision "cross-allows $(printf '%s' "$script" | awk '{print $1}' | sed 's|.*/||' | tr -d '"')" \
      none "$hook" "$script"
  done
  assert_decision "denies a redirection"                 deny "$hook" "$redirect"
  assert_decision "denies a chain onto a read"           deny "$hook" "$chain"
  assert_decision "denies a substitution"                deny "$hook" "$subshell"
  assert_decision "denies a backtick substitution"       deny "$hook" "$backtick"
  assert_decision "denies a pipe into a write"           deny "$hook" "$pipe"
  assert_decision "denies a second line"                 deny "$hook" "$twolines"
  assert_decision "denies a command outside the set"     deny "$hook" "$outside"
  assert_decision "denies find, which can delete"        deny "$hook" "$find_cmd"
  printf "\n"
done

printf "%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
