#!/usr/bin/env bash

SCRIPTS="$(cd "$(dirname "$0")/../.." && pwd)"
export CLAUDE_SHARED_DIR="$(cd "$SCRIPTS/../../../../agents/claude" && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

export COCKPIT_BOARD_DIR="$TMPDIR/board"
export TICKET_CLAIM_LOCK_DIR="$TMPDIR/claims"
export COCKPIT_COMMIT_DELAY=0
export TICKET_STATE_DIR="$TMPDIR/state"
export CLAUDE_SESSION_ID="session-one"
export COCKPIT_NOW="2026-10-17T10:00:00Z"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

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

stub() { bash "$SCRIPTS/board-card" "$@"; }
body() { stub show "$1" --json | jq --raw-output .body; }

base=$'# Goal\n\nShip the board.\n\n# Notes\n\nNothing yet.\n\n# Done when\n\nIt ships.'

stub init >/dev/null
stub create --kind project --name Cockpit >/dev/null
stub create --kind epic --project PRJ-1 --name Board >/dev/null
stub create --epic EPIC-1 --name Merged --body - <<<"$base" >/dev/null

printf "Test group: an edit made from an older body keeps what changed on the board since\n"

stub set FEAT-1 body "${base/Nothing yet./Written by an agent.}" >/dev/null
printf '%s' "$base" > "$TMPDIR/base"
output="$(stub set FEAT-1 body "${base/Ship the board./Ship the board this week.}" --base "$TMPDIR/base")"
assert_eq "the two edits to different lines both survive" \
  "${base/Nothing yet./Written by an agent.}" "$(body FEAT-1 | sed 's/Ship the board this week./Ship the board./')"
assert_eq "with the edit itself in place" "true" "$(body FEAT-1 | grep --quiet --fixed-strings 'Ship the board this week.' && echo true)"
assert_eq "and the agent's line kept" "true" "$(body FEAT-1 | grep --quiet --fixed-strings 'Written by an agent.' && echo true)"
assert_eq "saying it merged with no conflict" $'FEAT-1\tmerged the body' "$output"

printf "\nTest group: the base can arrive on stdin\n"

current="$(body FEAT-1)"
output="$(printf '%s' "$current" | stub set FEAT-1 body "${current/It ships./It ships and nobody notices.}" --base -)"
assert_eq "the edit lands" "true" "$(body FEAT-1 | grep --quiet --fixed-strings 'It ships and nobody notices.' && echo true)"
assert_eq "as a clean merge" $'FEAT-1\tmerged the body' "$output"

printf "\nTest group: the same line changed on both sides keeps both versions between conflict markers\n"

current="$(body FEAT-1)"
printf '%s' "$current" > "$TMPDIR/base"
stub set FEAT-1 body "${current/Written by an agent./Rewritten by the agent.}" >/dev/null
output="$(stub set FEAT-1 body "${current/Written by an agent./Rewritten in the app.}" --base "$TMPDIR/base")"
merged="$(body FEAT-1)"
assert_eq "the body holds both versions with markers naming each side" \
  $'<<<<<<< your edit\nRewritten in the app.\n=======\nRewritten by the agent.\n>>>>>>> on the board now' \
  "$(printf '%s\n' "$merged" | sed -n '/^<<<<<<< /,/^>>>>>>> /p')"
assert_eq "and the lines nobody fought over as they were" "true" "$(printf '%s' "$merged" | grep --quiet --fixed-strings 'Ship the board this week.' && echo true)"
assert_eq "saying how many conflicts it kept" \
  $'FEAT-1\tmerged the body with 1 conflict - both versions are kept between <<<<<<< and >>>>>>> lines' "$output"

printf "\nTest group: a body write without --base overwrites as before\n"

stub set FEAT-1 body "Only this." >/dev/null
assert_eq "the body is what was written" "Only this." "$(body FEAT-1)"
assert_eq "printing nothing about a merge" "" "$(stub set FEAT-1 body "Only this, again.")"

printf "\nTest group: --base is refused where it means nothing\n"

stub set FEAT-1 name Other --base "$TMPDIR/base" >/dev/null 2>&1
assert_eq "on a field other than the body" "2" "$?"
stub set FEAT-1 body Other --base "$TMPDIR/missing" >/dev/null 2>&1
assert_eq "naming a file that is not there" "2 Only this, again." "$? $(body FEAT-1)"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
