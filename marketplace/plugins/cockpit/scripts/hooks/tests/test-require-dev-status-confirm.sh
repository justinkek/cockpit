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

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
