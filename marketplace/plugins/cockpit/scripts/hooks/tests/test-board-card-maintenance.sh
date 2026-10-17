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
stub create --kind project --name Cockpit >/dev/null
stub create --kind project --name Home >/dev/null
stub create --kind epic --project PRJ-1 --name Board >/dev/null

printf "Test group: a project's maintenance epic is made the first time the month needs it\n"

assert_eq "the first call for a month makes the epic and prints its id" "EPIC-2" "$(stub maintenance PRJ-1)"
assert_eq "it is named after the project, the short month and the year" "Cockpit maintenance - Oct 2026" "$(field EPIC-2 .name)"
assert_eq "it starts in Tickets In Dev, with no design stages" "Tickets In Dev" "$(field EPIC-2 .status)"
assert_eq "it belongs to the project" "PRJ-1" "$(field EPIC-2 .project)"
assert_eq "it carries the maintenance label" "maintenance" "$(field EPIC-2 '.labels | join(",")')"
assert_eq "it keeps its month in its front matter" "2026-10" "$(field EPIC-2 .maintenance)"
assert_eq "it is ranked below every other epic" "2" "$(field EPIC-2 .rank)"
assert_eq "it starts the day it is first needed" "2026-10-17" "$(field EPIC-2 .start)"
assert_eq "the creation is committed under maintenance" "maintenance EPIC-2" "$(last_commit %s)"

printf "\nTest group: the month's epic is found again rather than made twice\n"

assert_eq "a second call that month prints the same epic" "EPIC-2" "$(stub maintenance PRJ-1 --date 2026-10-30)"
stub set EPIC-2 name "Board upkeep" >/dev/null
assert_eq "it is found by its month and label, so a rename keeps it" "EPIC-2" "$(stub maintenance PRJ-1)"
assert_eq "and nothing new was written" "maintenance EPIC-2" "$(git -C "$COCKPIT_BOARD_DIR" log --format=%s --grep '^maintenance' -1)"
assert_eq "another project gets an epic of its own" "EPIC-3" "$(stub maintenance PRJ-2)"
assert_eq "named after that project" "Home maintenance - Oct 2026" "$(field EPIC-3 .name)"
stub set EPIC-2 labels "" >/dev/null
assert_eq "an epic whose label was taken off is no longer the month's" "EPIC-4" "$(stub maintenance PRJ-1)"
stub set EPIC-2 labels maintenance >/dev/null

printf "\nTest group: --date names the month across its boundary\n"

assert_eq "the last day of a month is that month" "EPIC-5" "$(stub maintenance PRJ-1 --date 2026-11-30)"
assert_eq "named for it" "Cockpit maintenance - Nov 2026" "$(field EPIC-5 .name)"
assert_eq "the first day of the next is the next" "EPIC-6" "$(stub maintenance PRJ-1 --date 2026-12-01)"
assert_eq "named for that one" "Cockpit maintenance - Dec 2026" "$(field EPIC-6 .name)"
assert_eq "and its month is kept" "2026-12" "$(field EPIC-6 .maintenance)"
assert_eq "January rolls the year" "Cockpit maintenance - Jan 2027" "$(field "$(stub maintenance PRJ-1 --date 2027-01-01)" .name)"

printf "\nTest group: a maintenance epic closes once its month is over and its cards are done\n"

stub create --epic EPIC-2 --name "Fix the drag" --type Bug >/dev/null
stub create --epic EPIC-2 --name "Look into the lag" --type Timebox >/dev/null
COCKPIT_NOW=2026-11-02T09:00:00Z stub maintenance --close >/dev/null
assert_eq "a month that is over with cards still open stays open" "Tickets In Dev" "$(field EPIC-2 .status)"
assert_eq "an empty epic of a month that is over closes" "Epic Done" "$(field EPIC-4 .status)"
assert_eq "and so does another project's" "Epic Done" "$(field EPIC-3 .status)"
assert_eq "the month that is not over stays open" "Tickets In Dev" "$(field EPIC-5 .status)"
assert_eq "a plain epic is never swept" "Backlog" "$(field EPIC-1 .status)"
assert_eq "the sweep is committed under maintenance" "maintenance EPIC-3 EPIC-4" "$(last_commit %s)"

stub move BUG-1 Done >/dev/null
assert_eq "a card done in the month leaves its epic open" "Tickets In Dev" "$(field EPIC-2 .status)"
COCKPIT_NOW=2026-11-02T09:00:00Z stub move TIME-2 Deprioritised >/dev/null
assert_eq "the last card leaving after the month closes it" "Epic Done" "$(field EPIC-2 .status)"
assert_eq "in the same commit as the move" "move TIME-2 EPIC-2" "$(last_commit %s)"

stub create --epic EPIC-5 --name "Tidy the plan" >/dev/null
COCKPIT_NOW=2026-12-03T09:00:00Z stub walk FEAT-3 Done >/dev/null
assert_eq "a walk that lands a card on Done after the month closes its epic" "Epic Done" "$(field EPIC-5 .status)"
assert_eq "in the walk's own commit" "walk FEAT-3 EPIC-5" "$(last_commit %s)"
assert_eq "while a month not over yet stays open through the walk's sweep" "Tickets In Dev" "$(field EPIC-6 .status)"

COCKPIT_NOW=2027-01-05T09:00:00Z stub maintenance PRJ-1 2>/dev/null >/dev/null
assert_eq "asking for a month's epic sweeps the ones that are over" "Epic Done" "$(field EPIC-6 .status)"
assert_eq "asking for a month that is over gives its open epic" "EPIC-7" "$(COCKPIT_NOW=2027-03-01T00:00:00Z stub maintenance PRJ-1 --date 2027-01-20 2>/dev/null)"
assert_eq "rather than closing it under the card about to be filed there" "Tickets In Dev" "$(field EPIC-7 .status)"
COCKPIT_NOW=2027-03-01T00:00:00Z stub maintenance --close >/dev/null
assert_eq "the next sweep closes it" "Epic Done" "$(field EPIC-7 .status)"

printf "\nTest group: maintenance refuses what it cannot file under\n"

stub maintenance PRJ-9 >/dev/null 2>&1
assert_eq "a project the board does not have" "3" "$?"
stub maintenance EPIC-1 >/dev/null 2>&1
assert_eq "an id that is not a project" "2" "$?"
stub maintenance PRJ-1 --date 2026-02-30 >/dev/null 2>&1
assert_eq "a day that is not a date" "2" "$?"
stub maintenance >/dev/null 2>&1
assert_eq "no project at all" "2" "$?"
stub maintenance --close PRJ-1 >/dev/null 2>&1
assert_eq "--close with anything after it" "2" "$?"
stub set PRJ-2 status Done >/dev/null
stub maintenance PRJ-2 >/dev/null 2>&1
assert_eq "a project that is Done" "2" "$?"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
