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
refused() {
  stub "$@" >/dev/null 2>&1
  echo "$?"
}
dues() { stub list --json | jq --raw-output 'map("\(.id)=\(.due // "-")@\(.due_from // "-")") | join(" ")'; }

stub init >/dev/null

printf "Test group: an epic carries the fields the plan reads\n"

stub create --kind epic --name Checkout >/dev/null
stub set EPIC-1 start 2026-10-05 >/dev/null
assert_eq "an epic takes a start date" "2026-10-05" "$(field EPIC-1 .start)"
stub set EPIC-1 target 2026-11-30 >/dev/null
assert_eq "an epic takes a target date" "2026-11-30" "$(field EPIC-1 .target)"
assert_eq "the target reads back by its property name" "Target	2026-11-30" "$(stub show EPIC-1 Target)"
assert_eq "a target before the start is refused" "2" "$(refused set EPIC-1 target 2026-10-01)"
assert_eq "a start after the target is refused" "2" "$(refused set EPIC-1 start 2026-12-01)"
assert_eq "and the refusal leaves the dates as they were" "2026-10-05 2026-11-30" "$(field EPIC-1 '"\(.start) \(.target)"')"
assert_eq "a target that is not a date is refused" "2" "$(refused set EPIC-1 target 2026-02-30)"
assert_eq "an epic has no end date - its target is that" "2" "$(refused set EPIC-1 end 2026-11-30)"
stub set EPIC-1 confidence "At risk - plan in place" >/dev/null
assert_eq "a confidence is one of the three" "At risk - plan in place" "$(field EPIC-1 .confidence)"
assert_eq "any other confidence is refused" "2" "$(refused set EPIC-1 confidence Fine)"
stub set EPIC-1 confidence "" >/dev/null
assert_eq "an empty confidence clears it" "null" "$(field EPIC-1 .confidence)"
stub set EPIC-1 learning "Involve QA from the design phase" >/dev/null
assert_eq "a learning is free text" "Learning	Involve QA from the design phase" "$(stub show EPIC-1 Learning)"
stub set EPIC-1 plan_rank -1.5 >/dev/null
assert_eq "a plan rank is a number" "-1.5" "$(field EPIC-1 .plan_rank)"
assert_eq "a plan rank that is not a number is refused" "2" "$(refused set EPIC-1 plan_rank first)"
stub create --name "A card" >/dev/null
assert_eq "a card has no target" "2" "$(refused set FEAT-1 target 2026-11-30)"
assert_eq "a card has no confidence" "2" "$(refused set FEAT-1 confidence "On track")"
assert_eq "a card has no place in the plan" "2" "$(refused set FEAT-1 plan_rank 1)"
assert_eq "a card has no start date" "2" "$(refused set FEAT-1 start 2026-10-05)"
assert_eq "an epic is created with its dates" "EPIC-2" "$(stub create --kind epic --name Search --start 2026-10-01 --target 2026-10-31)"
assert_eq "and keeps them" "2026-10-01 2026-10-31" "$(field EPIC-2 '"\(.start) \(.target)"')"
assert_eq "an epic created with its target before its start is refused" "2" \
  "$(refused create --kind epic --name Bad --start 2026-10-31 --target 2026-10-01)"

printf "\nTest group: a milestone is a dated marker of its own\n"

assert_eq "a milestone is numbered with MS" "MS-1" "$(stub create --kind milestone --name Launch --date 2026-12-01)"
assert_eq "it lies in the milestones folder" "true" "$([ -f "$COCKPIT_BOARD_DIR/milestones/MS-1.md" ] && echo true)"
assert_eq "it keeps its date" "2026-12-01" "$(field MS-1 .date)"
assert_eq "a milestone needs a date" "2" "$(refused create --kind milestone --name Undated)"
assert_eq "a milestone has no status" "2" "$(refused create --kind milestone --name Bad --date 2026-12-01 --status Done)"
assert_eq "its date cannot be cleared" "2" "$(refused set MS-1 date "")"
stub set MS-1 date 2026-12-08 >/dev/null
assert_eq "its date moves" "2026-12-08" "$(field MS-1 .date)"
assert_eq "an epic has no milestone date" "2" "$(refused set EPIC-1 date 2026-12-08)"
assert_eq "milestones are listed by kind" "MS-1	-	-	Launch" "$(stub list --kind milestone)"
stub archive MS-1 >/dev/null
assert_eq "archiving takes it off the plan" "" "$(stub list --kind milestone)"
stub undo MS-1 >/dev/null
assert_eq "and undo puts it back" "MS-1" "$(stub list --kind milestone --json | jq --raw-output '.[].id')"

printf "\nTest group: an epic's target holds its cards' due dates\n"

stub create --kind epic --name Payments >/dev/null
stub create --name "No due" --epic EPIC-3 >/dev/null
stub create --name "Due later" --epic EPIC-3 >/dev/null
stub create --name "Due earlier" --epic EPIC-3 >/dev/null
stub create --name "Already done" --epic EPIC-3 >/dev/null
stub create --name "Dropped" --epic EPIC-3 >/dev/null
stub set FEAT-3 due 2026-12-31 >/dev/null
stub set FEAT-4 due 2026-11-01 >/dev/null
stub walk FEAT-5 Done >/dev/null
stub move FEAT-6 Deprioritised >/dev/null
output="$(stub set EPIC-3 target 2026-11-20)"
assert_eq "setting the target names each card whose due date it changed" "FEAT-2	due 2026-11-20
FEAT-3	due 2026-11-20" "$(printf '%s\n' "$output" | grep due)"
assert_eq "an unset or later due date is pulled in to the target, and an earlier one is left" \
  "FEAT-2=2026-11-20@EPIC-3 FEAT-3=2026-11-20@EPIC-3 FEAT-4=2026-11-01@- FEAT-5=-@- FEAT-6=-@-" \
  "$(dues | sed 's/^.*FEAT-2/FEAT-2/')"
assert_eq "the epic and every card it held land in one commit" "set FEAT-2 FEAT-3 EPIC-3" \
  "$(git -C "$COCKPIT_BOARD_DIR" log -1 --format=%s)"
stub set EPIC-3 target 2026-12-10 >/dev/null
assert_eq "a later target carries the due dates it set, and leaves the card's own" \
  "FEAT-2=2026-12-10@EPIC-3 FEAT-3=2026-12-10@EPIC-3 FEAT-4=2026-11-01@-" "$(dues | sed 's/^.*FEAT-2/FEAT-2/; s/ FEAT-5.*//')"
stub set EPIC-3 target 2026-10-25 >/dev/null
assert_eq "an earlier target pulls in the card's own date too, and takes it over" \
  "FEAT-2=2026-10-25@EPIC-3 FEAT-3=2026-10-25@EPIC-3 FEAT-4=2026-10-25@EPIC-3" "$(dues | sed 's/^.*FEAT-2/FEAT-2/; s/ FEAT-5.*//')"
stub set FEAT-4 due 2026-10-20 >/dev/null
assert_eq "a due date set by hand is the card's own again" "2026-10-20@-" "$(field FEAT-4 '"\(.due)@\(.due_from // "-")"')"
stub set EPIC-3 target 2027-01-15 >/dev/null
assert_eq "a target moved past a card's own date gives the card its own date back" \
  "FEAT-2=2027-01-15@EPIC-3 FEAT-3=2026-12-31@- FEAT-4=2026-10-20@-" "$(dues | sed 's/^.*FEAT-2/FEAT-2/; s/ FEAT-5.*//')"
stub set EPIC-3 target 2026-12-10 >/dev/null
stub set EPIC-3 target "" >/dev/null
assert_eq "clearing the target clears the due dates it set, and gives back the ones it took over" \
  "FEAT-2=-@- FEAT-3=2026-12-31@- FEAT-4=2026-10-20@-" "$(dues | sed 's/^.*FEAT-2/FEAT-2/; s/ FEAT-5.*//')"
stub set FEAT-3 due "" >/dev/null

printf "\nTest group: a card moving between epics follows the target it lands under\n"

stub set EPIC-3 target 2026-11-20 >/dev/null
stub set EPIC-2 target 2026-11-05 >/dev/null
stub set FEAT-2 epic EPIC-2 >/dev/null
assert_eq "a card joining an epic is held to its target" "2026-11-05@EPIC-2" "$(field FEAT-2 '"\(.due)@\(.due_from // "-")"')"
stub set FEAT-2 epic "" >/dev/null
assert_eq "a card leaving every epic drops the due date the target set" "null@-" "$(field FEAT-2 '"\(.due)@\(.due_from // "-")"')"
stub create --name "Born held" --epic EPIC-3 >/dev/null
assert_eq "a card created in an epic with a target starts held to it" "2026-11-20@EPIC-3" "$(field FEAT-7 '"\(.due)@\(.due_from // "-")"')"
stub create --name "Own date" >/dev/null
stub set FEAT-8 due 2026-12-31 >/dev/null
stub set FEAT-8 epic EPIC-3 >/dev/null
assert_eq "a card joining an epic whose target is earlier than its own date is held to the target" "2026-11-20@EPIC-3" "$(field FEAT-8 '"\(.due)@\(.due_from // "-")"')"
stub set FEAT-8 epic "" >/dev/null
assert_eq "and leaving it gets its own date back" "2026-12-31@-" "$(field FEAT-8 '"\(.due)@\(.due_from // "-")"')"
stub set FEAT-3 epic EPIC-2 >/dev/null
assert_eq "a held card moving to another epic takes the new target" "2026-11-05@EPIC-2" "$(field FEAT-3 '"\(.due)@\(.due_from // "-")"')"
stub set EPIC-1 target "" >/dev/null
stub set FEAT-3 epic EPIC-1 >/dev/null
assert_eq "and to an epic with no target, drops the date the old one set" "null@-" "$(field FEAT-3 '"\(.due)@\(.due_from // "-")"')"

printf "\nTest group: undoing a target puts back the epic and, card by card, each due date it changed\n"

stub set EPIC-3 target 2026-11-02 >/dev/null
stub undo EPIC-3 >/dev/null
assert_eq "undo puts the epic's target back" "2026-11-20" "$(field EPIC-3 .target)"
assert_eq "and leaves the cards for their own undo" "2026-11-02" "$(field FEAT-7 .due)"
stub undo FEAT-7 >/dev/null
assert_eq "which puts the card's due date back" "2026-11-20" "$(field FEAT-7 .due)"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
