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

printf "\nTest group: at month end a maintenance epic's unfinished cards move to the new month's epic and it closes\n"

stub create --epic EPIC-2 --name "Fix the drag" --type Bug >/dev/null
stub create --epic EPIC-2 --name "Look into the lag" --type Timebox >/dev/null
stub create --epic EPIC-2 --name "Shipped already" >/dev/null
stub create --epic EPIC-2 --name "Dropped" >/dev/null
stub move COC-3 Done >/dev/null
stub move COC-4 Deprioritised >/dev/null
assert_eq "a move within the month leaves the month's epic open" "Tickets In Dev" "$(field EPIC-2 .status)"
COCKPIT_NOW=2026-11-02T09:00:00Z stub maintenance --close >/dev/null
assert_eq "once the month is over its epic closes, cards still open and all" "Epic Done" "$(field EPIC-2 .status)"
assert_eq "its unfinished cards move to the same project's epic for the new month" "EPIC-5 EPIC-5" "$(field COC-1 .epic) $(field COC-2 .epic)"
assert_eq "a done card and a deprioritised one stay where they were done" "EPIC-2 EPIC-2" "$(field COC-3 .epic) $(field COC-4 .epic)"
assert_eq "an empty epic of a month that is over closes" "Epic Done" "$(field EPIC-4 .status)"
assert_eq "and so does another project's" "Epic Done" "$(field EPIC-3 .status)"
assert_eq "the month that is not over stays open" "Tickets In Dev" "$(field EPIC-5 .status)"
assert_eq "a plain epic is never swept" "Backlog" "$(field EPIC-1 .status)"
assert_eq "the cards and the epics they left go in one commit" "maintenance COC-1 COC-2 EPIC-2 EPIC-3 EPIC-4" "$(last_commit %s)"

COCKPIT_NOW=2026-12-03T09:00:00Z stub walk COC-1 Done >/dev/null
assert_eq "a walk after the month rolls the epic over" "Epic Done" "$(field EPIC-5 .status)"
assert_eq "taking the card still open to December's" "EPIC-6" "$(field COC-2 .epic)"
assert_eq "and leaving the card it walked to Done behind" "EPIC-5" "$(field COC-1 .epic)"
assert_eq "in the walk's own commit" "walk COC-1 COC-2 EPIC-5" "$(last_commit %s)"
assert_eq "while a month not over yet stays open through the walk's sweep" "Tickets In Dev" "$(field EPIC-6 .status)"

COCKPIT_NOW=2027-01-05T09:00:00Z stub move EPIC-1 "Ready for FD by AI" >/dev/null
assert_eq "a move of any record sweeps, so nobody has to ask" "Epic Done EPIC-7" "$(field EPIC-6 .status) $(field COC-2 .epic)"
assert_eq "in the move's own commit" "move COC-2 EPIC-1 EPIC-6" "$(last_commit %s)"

output="$(COCKPIT_NOW=2027-02-02T09:00:00Z stub migrate)"
assert_eq "migrate sweeps too, making the new month's epic when there is none" "EPIC-8" "$(field COC-2 .epic)"
assert_eq "named for the new month" "Cockpit maintenance - Feb 2027" "$(field EPIC-8 .name)"
assert_eq "starting the day of the sweep, in Tickets In Dev" "2027-02-02 Tickets In Dev 2027-02" "$(field EPIC-8 '"\(.start) \(.status) \(.maintenance)"')"
assert_eq "and migrate names each card it moved and each epic it closed" \
  "COC-2	epic EPIC-7 -> EPIC-8|EPIC-7	Tickets In Dev -> Epic Done" "$(printf '%s\n' "$output" | grep 'EPIC-7' | paste -sd '|' -)"

COCKPIT_NOW=2027-03-01T00:00:00Z stub maintenance PRJ-1 --date 2027-03-01 2>/dev/null >/dev/null
assert_eq "asking for the new month's epic across the boundary rolls the old one into it" "EPIC-9 Epic Done" "$(field COC-2 .epic) $(field EPIC-8 .status)"
assert_eq "which is the epic the call printed" "EPIC-9" "$(COCKPIT_NOW=2027-03-01T00:00:00Z stub maintenance PRJ-1 --date 2027-03-01 2>/dev/null)"

printf "\nTest group: asking for a month that is over gives the current month's epic\n"

assert_eq "a past month's --date prints this month's epic" "EPIC-9" "$(COCKPIT_NOW=2027-03-05T09:00:00Z stub maintenance PRJ-1 --date 2027-01-20 2>/dev/null)"
assert_eq "and makes no epic for the month that is over" "9" "$(stub list --kind epic --json | jq length)"
assert_eq "a month that is over with no epic of its own is never given one" "EPIC-10 Cockpit maintenance - Apr 2027" \
  "$(id="$(COCKPIT_NOW=2027-04-02T09:00:00Z stub maintenance PRJ-1 --date 2026-12-15 2>/dev/null)"; printf '%s %s' "$id" "$(field "$id" .name)")"
assert_eq "after the sweep has rolled March's cards into it" "EPIC-10 Epic Done" "$(field COC-2 .epic) $(field EPIC-9 .status)"
assert_eq "a month still to come is that month" "Cockpit maintenance - May 2027" \
  "$(field "$(COCKPIT_NOW=2027-04-02T09:00:00Z stub maintenance PRJ-1 --date 2027-05-03 2>/dev/null)" .name)"

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
