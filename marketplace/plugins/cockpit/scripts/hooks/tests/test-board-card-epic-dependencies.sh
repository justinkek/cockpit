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
export COCKPIT_NOW="2026-10-07T10:00:00Z"
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
stub create --kind epic --project PRJ-1 --name Foundations >/dev/null
stub create --kind epic --project PRJ-1 --name Walls >/dev/null
stub create --kind epic --project PRJ-1 --name Roof >/dev/null
stub create --epic EPIC-1 --name Ticket >/dev/null

printf "Test group: an epic depends on another epic\n"

assert_eq "link prints what the epic depends on" "Dependent on	EPIC-1" "$(stub link EPIC-2 EPIC-1)"
assert_eq "the dependency it needs names the epic that needs it" '["EPIC-2"]' "$(field EPIC-1 '.dependency_for | tojson')"
assert_eq "an epic takes no complexity from a link" "null" "$(field EPIC-2 .complexity)"
assert_eq "in one commit under link, naming both" "link EPIC-1 EPIC-2" "$(last_commit %s)"
stub link EPIC-3 EPIC-2 >/dev/null
assert_eq "an epic depends on several in a chain" '["EPIC-2"]' "$(field EPIC-3 '.dependent_on | tojson')"

printf "\nTest group: a dependency never makes a cycle\n"

message="$(stub link EPIC-1 EPIC-3 2>&1 >/dev/null)"
assert_eq "linking back along the chain is refused, naming the chain" \
  "2|[board-card] EPIC-3 already depends on EPIC-1 (EPIC-3 -> EPIC-2 -> EPIC-1), so EPIC-1 depending on EPIC-3 would make a cycle" \
  "$(stub link EPIC-1 EPIC-3 >/dev/null 2>&1; echo "$?")|$message"
assert_eq "writing nothing" "[]" "$(field EPIC-1 '.dependent_on // [] | tojson')"
stub link EPIC-1 EPIC-2 >/dev/null 2>&1
assert_eq "and so is a direct one" "2" "$?"
stub link EPIC-1 EPIC-1 >/dev/null 2>&1
assert_eq "an epic never depends on itself" "2" "$?"
stub link EPIC-1 COC-1 >/dev/null 2>&1
assert_eq "an epic never depends on a ticket" "2" "$?"
stub link COC-1 EPIC-1 >/dev/null 2>&1
assert_eq "nor a ticket on an epic" "2" "$?"

printf "\nTest group: unlink takes a dependency off, and undo puts it back\n"

assert_eq "unlink leaves the epic depending on nothing" "" "$(stub unlink EPIC-3 EPIC-2)"
assert_eq "and takes the other side off too" "[]" "$(field EPIC-2 '.dependency_for | tojson')"
stub undo EPIC-3 >/dev/null
assert_eq "undo of the unlink puts both sides back" '["EPIC-2"]|["EPIC-3"]' "$(field EPIC-3 '.dependent_on | tojson')|$(field EPIC-2 '.dependency_for | tojson')"
assert_eq "still with no complexity" "null" "$(field EPIC-2 .complexity)"
stub link EPIC-1 EPIC-3 >/dev/null 2>&1
assert_eq "and the cycle it closes is refused again" "2" "$?"
stub archive EPIC-1 >/dev/null 2>&1
assert_eq "an epic another depends on is not archived" "2" "$?"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
