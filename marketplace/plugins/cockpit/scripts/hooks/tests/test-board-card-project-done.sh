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
field() { stub show "$1" --json | jq --raw-output "$2"; }
last_commit() { git -C "$COCKPIT_BOARD_DIR" log -1 --format="$1"; }

stub init >/dev/null
stub create --kind project --name Cockpit --key COC >/dev/null
stub create --kind project --name Home --key HOM >/dev/null
stub create --kind epic --project PRJ-1 --name Board >/dev/null
stub create --kind epic --project PRJ-1 --name Plan >/dev/null
stub create --kind epic --project PRJ-1 --name Shipped >/dev/null
stub create --kind epic --project PRJ-2 --name Garden >/dev/null
stub move EPIC-3 "Epic Done" >/dev/null
stub create --epic EPIC-1 --name Open >/dev/null
stub create --epic EPIC-1 --name Started >/dev/null
stub move COC-2 "In Dev" >/dev/null
stub create --epic EPIC-2 --name Finished >/dev/null
stub move COC-3 Done >/dev/null
stub create --epic EPIC-2 --name Dropped >/dev/null
stub move COC-4 Deprioritised >/dev/null
stub create --epic EPIC-4 --name Elsewhere >/dev/null

printf "Test group: a project with open work is marked Done on its own, leaving that work open\n"

stub set PRJ-1 status Done >/dev/null
assert_eq "plain set marks it Done" "0 Done" "$? $(field PRJ-1 .status)"
assert_eq "and leaves its tickets and epics where they were" "Backlog In Dev Backlog Backlog" "$(field COC-1 .status) $(field COC-2 .status) $(field EPIC-1 .status) $(field EPIC-2 .status)"
stub undo PRJ-1 >/dev/null
assert_eq "undo puts it back" "Not started" "$(field PRJ-1 .status)"
stub set PRJ-1 priority 1 --close >/dev/null 2>&1
assert_eq "--close is refused on anything but marking a project Done" "2" "$?"

printf "\nTest group: --close closes everything open in the project and marks it Done in one commit\n"

before="$(git -C "$COCKPIT_BOARD_DIR" rev-list --count HEAD)"
output="$(stub set PRJ-1 status Done --close)"
assert_eq "the project is Done" "Done" "$(field PRJ-1 .status)"
assert_eq "its open tickets are deprioritised" "Deprioritised Deprioritised" "$(field COC-1 .status) $(field COC-2 .status)"
assert_eq "its open epics move to Epic Done" "Epic Done Epic Done" "$(field EPIC-1 .status) $(field EPIC-2 .status)"
assert_eq "a done ticket stays done" "Done" "$(field COC-3 .status)"
assert_eq "and another project's work is left alone" "Backlog Backlog" "$(field EPIC-4 .status) $(field HOM-1 .status)"
assert_eq "all in one commit" "1" "$(($(git -C "$COCKPIT_BOARD_DIR" rev-list --count HEAD) - before))"
assert_eq "printing each record it moved" "COC-1 COC-2 EPIC-1 EPIC-2" "$(printf '%s\n' "$output" | grep -- ' -> ' | cut -f1 | paste -sd ' ' -)"
stub undo EPIC-1 >/dev/null
assert_eq "each closed record can be undone on its own" "Backlog Done" "$(field EPIC-1 .status) $(field PRJ-1 .status)"

printf "\nTest group: a project with nothing open is marked Done as before\n"

stub set PRJ-2 status "In progress" >/dev/null
stub move HOM-1 Done >/dev/null
stub move EPIC-4 "Epic Done" >/dev/null
stub set PRJ-2 status Done >/dev/null
assert_eq "with no --close" "Done" "$(field PRJ-2 .status)"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
