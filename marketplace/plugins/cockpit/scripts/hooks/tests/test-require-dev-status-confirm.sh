#!/usr/bin/env bash

here="$(cd "$(dirname "$0")" && pwd -P)"
HOOK="$here/../require-dev-status.sh"

[ -x "$HOOK" ] || { printf "KO  hook not found at %s\n" "$HOOK"; exit 1; }

pass=0
fail=0

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

export HOME="$sandbox/home"
state_directory="$HOME/.local/state/claude-ticket-sessions"
mkdir -p "$state_directory"

session="test-session"
printf 'https://example.invalid/ticket\n' > "$state_directory/$session.ticket"
stage_marker="$state_directory/$session.stage-dev"

verdict() {
  printf '{"tool_name":"Bash","session_id":"%s","cwd":"%s","tool_input":{"command":"%s"}}' \
    "$session" "$sandbox" "$1" | "$HOOK"
}

assert_marker_written() {
  local label="$1" command="$2"
  rm -f "$stage_marker"
  verdict "$command" > /dev/null
  if [ -f "$stage_marker" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected the stage marker to be written\n" "$label"
    fail=$((fail + 1))
  fi
}

assert_marker_withheld() {
  local label="$1" command="$2"
  rm -f "$stage_marker"
  verdict "$command" > /dev/null
  if [ -f "$stage_marker" ]; then
    printf "  KO  %s — the stage marker was written, unlocking file edits\n" "$label"
    fail=$((fail + 1))
  else
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  fi
}

printf "Test group: only the confirm script itself unlocks file edits\n"

assert_marker_written "the confirm script, quoted home form" \
  "\\\"\$HOME/.cockpit/scripts/ticket-status-confirm\\\" dev"
assert_marker_written "the confirm script, expanded path" \
  "$HOME/.cockpit/scripts/ticket-status-confirm dev"

printf "\nTest group: a command that merely names the confirm script does not\n"

assert_marker_withheld "a grep for the script's name" \
  "grep --recursive ticket-status-confirm ."
assert_marker_withheld "an echo of the script's name" \
  "echo ticket-status-confirm"
assert_marker_withheld "the script's name inside another script's path" \
  "\\\"\$HOME/.cockpit/scripts/ticket-status-confirm-wrapper\\\" dev"
assert_marker_withheld "the script piped into another command" \
  "\\\"\$HOME/.cockpit/scripts/ticket-status-confirm\\\" dev | tee log"
assert_marker_withheld "the script chained after another command" \
  "true; \\\"\$HOME/.cockpit/scripts/ticket-status-confirm\\\" dev"

column_file="$state_directory/$session.column"

edit_verdict() {
  printf '{"tool_name":"%s","session_id":"%s","cwd":"%s","tool_input":{"file_path":"%s/edited.txt"}}' \
    "$1" "$session" "$sandbox" "$sandbox" | "$HOOK"
}

assert_edit_denied() {
  local label="$1" tool="$2" want="$3" out
  out="$(edit_verdict "$tool")"
  case "$out" in
    *'"permissionDecision":"deny"'*"$want"*)
      printf "  OK  %s\n" "$label"
      pass=$((pass + 1)) ;;
    *)
      printf "  KO  %s — expected a deny naming '%s', got '%s'\n" "$label" "$want" "$out"
      fail=$((fail + 1)) ;;
  esac
}

assert_edit_allowed() {
  local label="$1" tool="$2" out
  out="$(edit_verdict "$tool")"
  if [ -z "$out" ]; then
    printf "  OK  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  KO  %s — expected the edit to pass, got '%s'\n" "$label" "$out"
    fail=$((fail + 1))
  fi
}

printf "\nTest group: a card on Done keeps file edits shut although dev once confirmed\n"

: > "$stage_marker"

printf 'In Dev\n' > "$column_file"
assert_edit_allowed "an edit while the card is In Dev" Edit

printf 'Done\n' > "$column_file"
assert_edit_denied "an edit once the card is Done" Edit "card this session is bound to is Done"
assert_edit_denied "a write once the card is Done" Write "new work needs its own ticket and its own session"

verdict "\\\"\$HOME/.cockpit/scripts/ticket-status-confirm\\\" dev" > /dev/null
assert_edit_denied "an edit after the confirm script runs again on a Done card" Edit "Done gate"

rm -f "$stage_marker"
assert_edit_denied "an edit on a Done card with no stage marker names Done, not In Dev" Edit "Done gate"

printf 'Ready for CR\n' > "$column_file"
: > "$stage_marker"
assert_edit_allowed "an edit once the card has moved on from In Dev but not to Done" Edit
rm -f "$column_file"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
