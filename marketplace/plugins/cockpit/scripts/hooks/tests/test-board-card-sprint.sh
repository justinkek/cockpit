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
stub create --kind epic --project PRJ-1 --name Board >/dev/null
stub create --kind sprint --name "Sprint 1" --start 2026-09-28 --end 2026-10-09 >/dev/null
stub create --kind sprint --name "Sprint 2" --start 2026-10-12 --end 2026-10-23 >/dev/null

printf "Test group: a card reaching Done takes the sprint whose dates hold that day\n"

walked="$(stub create --epic EPIC-1 --name Walked)"
stub set "$walked" sprint SPR-2 >/dev/null
stub walk "$walked" Done --skip "Sprint Backlog" >/dev/null
assert_eq "a walk to Done sets the sprint of the day it lands" "SPR-1" "$(field "$walked" .sprint)"
assert_eq "in the walk's own commit" "walk $walked" "$(last_commit %s)"
moved="$(stub create --epic EPIC-1 --name Moved)"
COCKPIT_NOW=2026-10-23T23:30:00Z stub move "$moved" Done >/dev/null
assert_eq "a move to Done on a sprint's last day takes that sprint, by the UTC date" "SPR-2" "$(field "$moved" .sprint)"
gap="$(stub create --epic EPIC-1 --name Gap)"
stub set "$gap" sprint SPR-1 >/dev/null
COCKPIT_NOW=2026-10-10T10:00:00Z stub move "$gap" Done >/dev/null
assert_eq "a day no sprint covers leaves the sprint as it was" "SPR-1" "$(field "$gap" .sprint)"
unplanned="$(stub create --epic EPIC-1 --name Unplanned)"
COCKPIT_NOW=2026-11-02T10:00:00Z stub move "$unplanned" Done >/dev/null
assert_eq "and leaves a card with no sprint without one" "null" "$(field "$unplanned" .sprint)"
open="$(stub create --epic EPIC-1 --name Open)"
stub move "$open" "In Dev" >/dev/null
assert_eq "a move to any other column leaves the sprint alone" "null" "$(field "$open" .sprint)"

printf "\nTest group: migrate gives every Done card the sprint its Done stamp falls in\n"

stale="$(stub create --epic EPIC-1 --name Stale)"
COCKPIT_NOW=2026-10-14T10:00:00Z stub move "$stale" Done >/dev/null
stub set "$stale" sprint SPR-1 >/dev/null
output="$(stub migrate)"
assert_eq "migrate names each card whose sprint it changed and the sprint it had" "$stale	sprint SPR-1 -> SPR-2" "$(printf '%s\n' "$output" | grep 'sprint')"
assert_eq "and sets it" "SPR-2" "$(field "$stale" .sprint)"
assert_eq "leaving a Done card whose day no sprint covers as it was" "SPR-1 null" "$(field "$gap" .sprint) $(field "$unplanned" .sprint)"
assert_eq "in migrate's commit" "migrate" "$(git -C "$COCKPIT_BOARD_DIR" log -1 --format=%s -- "cards/$stale.md" | cut -d' ' -f1)"
assert_eq "a second migrate changes no sprint" "0" "$(stub migrate | grep --count 'sprint')"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
