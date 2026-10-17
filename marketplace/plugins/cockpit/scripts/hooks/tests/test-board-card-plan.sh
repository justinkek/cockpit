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
stub create --kind project --name Home >/dev/null

printf "Test group: an epic carries the fields the plan reads\n"

stub create --kind epic --project PRJ-1 --name Checkout >/dev/null
assert_eq "an epic's start is never set by hand" "2" "$(refused set EPIC-1 start 2026-10-05)"
COCKPIT_NOW=2026-10-05T09:00:00Z stub move EPIC-1 "Ready for FD by AI" >/dev/null
assert_eq "it is stamped the day the epic leaves Backlog" "2026-10-05" "$(field EPIC-1 .start)"
stub set EPIC-1 target 2026-11-30 >/dev/null
assert_eq "an epic takes a target date" "2026-11-30" "$(field EPIC-1 .target)"
assert_eq "the target reads back by its property name" "Target	2026-11-30" "$(stub show EPIC-1 Target)"
assert_eq "a target before the start is refused" "2" "$(refused set EPIC-1 target 2026-10-01)"
assert_eq "nor cleared by hand" "2" "$(refused set EPIC-1 start '')"
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
assert_eq "a new epic is ranked below every other" "1" "$(field EPIC-1 .rank)"
stub set EPIC-1 rank -1.5 >/dev/null
assert_eq "an epic's place in the plan is its rank" "Rank	-1.5" "$(stub show EPIC-1 Rank)"
assert_eq "a plan rank of its own is refused, pointing at the rank" "2" "$(refused set EPIC-1 plan_rank 1)"
stub create --epic EPIC-1 --name "A card" >/dev/null
assert_eq "a card has no target" "2" "$(refused set FEAT-1 target 2026-11-30)"
assert_eq "a card has no confidence" "2" "$(refused set FEAT-1 confidence "On track")"
assert_eq "a card has no start date" "2" "$(refused set FEAT-1 start 2026-10-05)"
assert_eq "an epic is never created with a start of its own" "2" \
  "$(refused create --kind epic --project PRJ-1 --name Bad --start 2026-10-01 --target 2026-10-31)"
assert_eq "an epic is created with its target" "EPIC-2" "$(stub create --kind epic --project PRJ-1 --name Search --target 2026-10-31)"
assert_eq "and keeps it, with no start while it waits in Backlog" "null 2026-10-31" "$(field EPIC-2 '"\(.start) \(.target)"')"

assert_eq "the next epic created is ranked below the lowest" "-1" "$(field EPIC-2 .rank)"
stub set EPIC-2 body "rank: 99" >/dev/null
assert_eq "a line in an epic's content that reads like a rank is never taken for one" "0" "$(field "$(stub create --kind epic --name "After the content" --project PRJ-1)" .rank)"

printf "\nTest group: migrate gives every epic one rank, the plan's order first\n"

migrated="$TMPDIR/migrated"
mkdir -p "$migrated"
COCKPIT_BOARD_DIR="$migrated" stub init >/dev/null
COCKPIT_BOARD_DIR="$migrated" stub create --kind project --name Home >/dev/null
for name in Placed Dragged Dated Plain; do COCKPIT_BOARD_DIR="$migrated" stub create --kind epic --project PRJ-1 --name "$name" >/dev/null; done
for epic in 1 2 3 4; do perl -ni -e 'print unless /^rank: /' "$migrated/epics/EPIC-$epic.md"; done
perl -pi -e 's/^(name: .*)$/$1\nplan_rank: 5/' "$migrated/epics/EPIC-1.md"
perl -pi -e 's/^(name: .*)$/$1\nrank: -8/' "$migrated/epics/EPIC-2.md"
perl -pi -e 's/^(name: .*)$/$1\ntarget: "2026-11-01"/' "$migrated/epics/EPIC-3.md"
git -C "$migrated" add --all >/dev/null && git -C "$migrated" -c user.name=t -c user.email=t@t commit --quiet -m seed
output="$(COCKPIT_BOARD_DIR="$migrated" stub migrate)"
ranks() { COCKPIT_BOARD_DIR="$migrated" stub list --kind epic --json | jq --raw-output 'map("\(.id)=\(.rank)\(if has("plan_rank") then "+plan" else "" end)") | join(" ")'; }
assert_eq "an epic placed in the plan comes first, then one dragged on the board, then by target and number" \
  "EPIC-1=1 EPIC-2=2 EPIC-3=3 EPIC-4=4" "$(ranks)"
assert_eq "and migrate names each epic it ranked" "4" "$(printf '%s\n' "$output" | grep --count rank)"
assert_eq "the whole migration is one commit" "migrate EPIC-1 EPIC-2 EPIC-3 EPIC-4 PRJ-1" "$(git -C "$migrated" log -1 --format=%s)"
assert_eq "a second migrate finds nothing to do" "nothing to migrate" "$(COCKPIT_BOARD_DIR="$migrated" stub migrate)"
assert_eq "and changes nothing" "EPIC-1=1 EPIC-2=2 EPIC-3=3 EPIC-4=4" "$(ranks)"

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

stub create --kind epic --project PRJ-1 --name Payments >/dev/null
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
stub set EPIC-1 target "" >/dev/null
stub set FEAT-2 epic EPIC-1 >/dev/null
assert_eq "a card moving to an epic with no target drops the due date the old one set" "null@-" "$(field FEAT-2 '"\(.due)@\(.due_from // "-")"')"
stub create --name "Born held" --epic EPIC-3 >/dev/null
assert_eq "a card created in an epic with a target starts held to it" "2026-11-20@EPIC-3" "$(field FEAT-7 '"\(.due)@\(.due_from // "-")"')"
stub create --epic EPIC-1 --name "Own date" >/dev/null
stub set FEAT-8 due 2026-12-31 >/dev/null
stub set FEAT-8 epic EPIC-3 >/dev/null
assert_eq "a card joining an epic whose target is earlier than its own date is held to the target" "2026-11-20@EPIC-3" "$(field FEAT-8 '"\(.due)@\(.due_from // "-")"')"
stub set FEAT-8 epic EPIC-1 >/dev/null
assert_eq "and leaving it for one with no target gets its own date back" "2026-12-31@-" "$(field FEAT-8 '"\(.due)@\(.due_from // "-")"')"
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

printf "\nTest group: a card carries a high-level estimate apart from its complexity\n"

estimated="$(stub create --epic EPIC-1 --name "Estimated")"
assert_eq "a new card has no estimate" "null" "$(field "$estimated" .estimate)"
stub set "$estimated" estimate 5 >/dev/null
assert_eq "a Fibonacci estimate is kept" "5" "$(field "$estimated" .estimate)"
assert_eq "and reads back by its property name" "Estimate	5" "$(stub show "$estimated" Estimate)"
assert_eq "and leaves the complexity unset" "null" "$(field "$estimated" .complexity)"
assert_eq "an estimate off the Fibonacci list is refused" "2" "$(refused set "$estimated" estimate 4)"
assert_eq "an estimate of 0 is refused, unknown being no estimate at all" "2" "$(refused set "$estimated" estimate 0)"
assert_eq "an epic has no estimate of its own" "2" "$(refused set EPIC-1 estimate 8)"
assert_eq "a copy carries the estimate" "5" "$(field "$(stub duplicate "$estimated")" .estimate)"
stub set "$estimated" estimate "" >/dev/null
assert_eq "an empty estimate clears it" "null" "$(field "$estimated" .estimate)"
timebox="$(stub create --epic EPIC-1 --name "Spike" --type Timebox)"
assert_eq "a timebox carries no estimate" "2" "$(refused set "$timebox" estimate 3)"
stub set "$estimated" estimate 3 >/dev/null
estimated="$(stub set "$estimated" type Timebox >/dev/null; stub list --json | jq --raw-output 'map(select(.name == "Estimated")) | .[0].id')"
assert_eq "a card turned into a timebox drops its estimate" "null" "$(field "$estimated" .estimate)"

printf "\nTest group: a project runs on tracks, and an epic can be pinned to one\n"

tracked="$(stub create --kind project --name Tracked)"
assert_eq "a new project has no share of the tracks" "null" "$(field "$tracked" .tracks)"
stub set "$tracked" tracks 3 >/dev/null
assert_eq "a project takes a whole number of tracks as its share" "3" "$(field "$tracked" .tracks)"
assert_eq "and reads it back by its property name" "Tracks	3" "$(stub show "$tracked" Tracks)"
assert_eq "no tracks at all is refused" "2" "$(refused set "$tracked" tracks 0)"
assert_eq "part of a track is refused" "2" "$(refused set "$tracked" tracks 1.5)"
assert_eq "an epic has no share of its own" "2" "$(refused set EPIC-1 tracks 2)"
stub set EPIC-1 track 2 >/dev/null
assert_eq "an epic is pinned to a track by its number" "Track	2" "$(stub show EPIC-1 Track)"
stub set EPIC-1 track 9 >/dev/null
assert_eq "a pin past its project's tracks is kept, for the plan to warn about" "9" "$(field EPIC-1 .track)"
assert_eq "a card is never pinned to a track" "2" "$(refused set "$estimated" track 1)"
assert_eq "a project is never pinned to a track" "2" "$(refused set "$tracked" track 1)"
stub set EPIC-1 track "" >/dev/null
assert_eq "an empty pin lets the plan place the epic again" "null" "$(field EPIC-1 .track)"

printf "\nTest group: the board has one count of tracks, which the projects' shares add up to at most\n"

other="$(stub create --kind project --name Other)"
stub set "$other" tracks 1 >/dev/null
assert_eq "until it is set, the board's count reads as the shares added up" "4" "$(stub tracks)"
assert_eq "and no share is refused" "Tracks	2" "$(stub set "$other" tracks 2)"
assert_eq "a count below the shares is refused" "2" "$(refused tracks 4)"
assert_eq "a count the shares fit in is kept" "6" "$(stub tracks 6)"
assert_eq "at the board's root" "6" "$(cat "$COCKPIT_BOARD_DIR/tracks")"
assert_eq "and committed there" "" "$(git -C "$COCKPIT_BOARD_DIR" status --porcelain tracks)"
assert_eq "a share that takes the total over the count is refused" "2" "$(refused set "$other" tracks 4)"
assert_eq "and leaves the share as it was" "2" "$(field "$other" .tracks)"
stub set "$other" tracks 3 >/dev/null
assert_eq "a share that fits exactly is kept" "3" "$(field "$other" .tracks)"
stub set "$tracked" tracks "" >/dev/null
assert_eq "an empty share clears it, giving that project none" "null" "$(field "$tracked" .tracks)"
assert_eq "no tracks at all is refused for the board too" "2" "$(refused tracks 0)"
assert_eq "an empty count reads as the shares again" "3" "$(stub tracks "")"
stub set "$tracked" body "tracks: 9" >/dev/null
assert_eq "a line in a project's content that reads like a share is never counted as one" "3" "$(stub tracks)"
assert_eq "the epics with no project have no count of their own any more" "2" "$(refused no-project-tracks 2)"

printf "\nTest group: a finished project's share stops counting, and comes back when it reopens\n"

finished="$(stub create --kind project --name Finished)"
stub set "$finished" tracks 2 >/dev/null
stub tracks 5 >/dev/null
stub set "$finished" status Done >/dev/null
assert_eq "a done project keeps its share on the record" "2" "$(field "$finished" .tracks)"
assert_eq "but leaves it out of the shares the count is checked against" "3" "$(stub tracks "" >/dev/null; stub tracks)"
stub tracks 3 >/dev/null
assert_eq "so the count can drop to the open projects' shares alone" "3" "$(stub tracks)"
assert_eq "a done project's share can change without counting either" "Tracks	4" "$(stub set "$finished" tracks 4)"
assert_eq "reopening a project whose share would take the total over the count is refused" "2" "$(refused set "$finished" status "In progress")"
assert_eq "naming the overshoot" "[board-card] reopening $finished brings back its share of 4, taking the projects' shares to 7, 4 over the board's 3 tracks - lower another project's share first, or raise the board's count with: board-card tracks <n>" "$(stub set "$finished" status "In progress" 2>&1 >/dev/null)"
assert_eq "and leaves it done" "Done" "$(field "$finished" .status)"
stub tracks 7 >/dev/null
stub set "$finished" status "In progress" >/dev/null
assert_eq "a reopened project whose share fits counts it again" "In progress" "$(field "$finished" .status)"
assert_eq "towards the count" "2" "$(refused tracks 6)"
stub set "$finished" status Done >/dev/null
stub set "$finished" tracks "" >/dev/null
stub set "$finished" status "Not started" >/dev/null
assert_eq "a done project with no share reopens whatever the count" "Not started" "$(field "$finished" .status)"

printf "\nTest group: a break is a span of days off for the whole board, kept at the board's root\n"

assert_eq "a board with no breaks lists none" "" "$(stub breaks)"
assert_eq "and gives an empty list as JSON" "[]" "$(stub breaks --json | jq --compact-output .)"
assert_eq "a break added gets an id" "b1" "$(stub breaks add 2026-12-21 2027-01-02 --name 'Christmas')"
assert_eq "and is committed under its verb" "breaks" "$(git -C "$COCKPIT_BOARD_DIR" log -1 --format=%s)"
assert_eq "a break with no name has none" "b2" "$(stub breaks add 2026-11-02 2026-11-06)"
assert_eq "the list runs in the order the breaks start" \
  "b2	2026-11-02	2026-11-06	|b1	2026-12-21	2027-01-02	Christmas" "$(stub breaks | paste -sd '|' -)"
assert_eq "the file at the root is JSON, naming no project" "b2,b1|false" "$(jq --raw-output '(map(.id) | join(",")) + "|" + (any(.[]; has("project")) | tostring)' "$COCKPIT_BOARD_DIR/breaks")"
assert_eq "a break for one project is refused, as a break is the whole board's" "2" "$(refused breaks add 2026-11-02 2026-11-06 --project PRJ-1)"
assert_eq "a break that ends before it starts is refused" "2" "$(refused breaks add 2026-11-10 2026-11-09)"
assert_eq "a one-day break is kept" "b3" "$(stub breaks add 2026-11-10 2026-11-10)"
assert_eq "a date that is not one is refused" "2" "$(refused breaks add 2026-02-30 2026-03-02)"
assert_eq "a date in another shape is refused" "2" "$(refused breaks add 1/11/2026 2026-11-02)"
assert_eq "an option breaks does not take is refused" "2" "$(refused breaks add 2026-11-02 2026-11-06 --track 1)"
assert_eq "a refused break writes nothing" "3" "$(stub breaks --json | jq length)"
assert_eq "a break is removed by its place in the list" "b2" "$(stub breaks remove 1)"
assert_eq "or by its id" "b3" "$(stub breaks remove B3)"
assert_eq "and the others stay" "b1" "$(stub breaks --json | jq --raw-output 'map(.id) | join(",")')"
assert_eq "a break the list does not have is refused" "3" "$(refused breaks remove b9)"
assert_eq "a place past the list is refused" "3" "$(refused breaks remove 5)"
assert_eq "a removed break comes back under its own id, to undo its removal" "b3	2026-11-10	2026-11-10	Away" \
  "$(stub breaks add 2026-11-10 2026-11-10 --name Away --id B3 >/dev/null; stub breaks | grep '^b3')"
assert_eq "and is committed under the same verb" "breaks" "$(git -C "$COCKPIT_BOARD_DIR" log -1 --format=%s)"
assert_eq "an id another break has is refused" "2" "$(refused breaks add 2026-11-11 2026-11-11 --id b1)"
assert_eq "an id that is not b and a number is refused" "2" "$(refused breaks add 2026-11-11 2026-11-11 --id x1)"
assert_eq "a new break after one brought back takes the next id past the highest" "b4" "$(stub breaks add 2026-11-12 2026-11-12)"
stub breaks remove b3 >/dev/null
stub breaks remove b4 >/dev/null
stub breaks remove b1 >/dev/null
assert_eq "the file goes with the last break" "false" "$([ -f "$COCKPIT_BOARD_DIR/breaks" ] && echo true || echo false)"
assert_eq "and its going is committed too" "" "$(git -C "$COCKPIT_BOARD_DIR" status --porcelain)"

printf "\nTest group: migrate gives each project with open epics a share and sets the board's count\n"

shared="$TMPDIR/shared"
mkdir -p "$shared"
on_shared() { COCKPIT_BOARD_DIR="$shared" stub "$@"; }
on_shared init >/dev/null
open_project="$(on_shared create --kind project --name Open)"
done_project="$(on_shared create --kind project --name Finished)"
given_project="$(on_shared create --kind project --name Given)"
idle_project="$(on_shared create --kind project --name Idle)"
on_shared set "$given_project" tracks 2 >/dev/null
for project in "$open_project" "$done_project" "$given_project"; do
  epic="$(on_shared create --kind epic --project "$project" --name "Of $project")"
  [ "$project" != "$open_project" ] || on_shared create --epic "$epic" --name "Of the open project" >/dev/null
  [ "$project" != "$done_project" ] || on_shared move "$epic" "Epic Done" >/dev/null
done
printf '3\n' > "$shared/no-project-tracks"
output="$(on_shared migrate)"
assert_eq "a project with an open epic and no share gets one track, and one with a share keeps it" \
  "1 null 2 null" "$(for project in "$open_project" "$done_project" "$given_project" "$idle_project"; do COCKPIT_BOARD_DIR="$shared" field "$project" .tracks; done | paste -sd ' ' -)"
assert_eq "the board's count becomes the shares added up" "3" "$(cat "$shared/tracks")"
assert_eq "the count the epics with no project had is dropped" "false" "$([ -f "$shared/no-project-tracks" ] && echo true || echo false)"
assert_eq "and migrate names each change" "$open_project	tracks 1|no-project-tracks	removed|tracks	3" \
  "$(printf '%s\n' "$output" | grep --invert-match rank | sort | paste -sd '|' -)"
assert_eq "a second migrate finds nothing to do" "nothing to migrate" "$(on_shared migrate)"
perl -pi -e 's/^epic: .*/epic: null/' "$shared/cards/FEAT-1.md"
perl -pi -e 's/^project: .*/project: null/' "$shared/epics/EPIC-1.md"
assert_eq "migrate names a card with no epic and an epic with no project, which only a person can give them" \
  "FEAT-1	needs an epic|EPIC-1	needs a project" "$(on_shared migrate | paste -sd '|' -)"

printf "\nTest group: migrate drops a break kept for one project, as a break is the whole board's\n"

projected="$TMPDIR/projected"
mkdir -p "$projected"
COCKPIT_BOARD_DIR="$projected" stub init >/dev/null
COCKPIT_BOARD_DIR="$projected" stub create --kind project --name Home >/dev/null
printf '%s\n' '[{"id":"b1","from":"2026-11-02","to":"2026-11-06","project":"PRJ-1","name":null},{"id":"b2","from":"2026-12-21","to":"2027-01-02","project":null,"name":"Christmas"}]' > "$projected/breaks"
git -C "$projected" add --all >/dev/null && git -C "$projected" -c user.name=t -c user.email=t@t commit --quiet --message seed
assert_eq "migrate names the project break it drops" "b1	break 2026-11-02 to 2026-11-06 for PRJ-1 removed, as a break is the whole board's|breaks	no break names a project" \
  "$(COCKPIT_BOARD_DIR="$projected" stub migrate | grep --extended-regexp '^(b[0-9]|breaks)' | paste -sd '|' -)"
assert_eq "and keeps the board's own, with no project field" '[{"id":"b2","from":"2026-12-21","to":"2027-01-02","name":"Christmas"}]' "$(jq --compact-output . "$projected/breaks")"
assert_eq "and commits it" "" "$(git -C "$projected" status --porcelain)"
assert_eq "a break file with only project breaks goes altogether" "false" \
  "$(printf '%s\n' '[{"id":"b1","from":"2026-11-02","to":"2026-11-06","project":"PRJ-1","name":null}]' > "$projected/breaks"; COCKPIT_BOARD_DIR="$projected" stub migrate >/dev/null; [ -f "$projected/breaks" ] && echo true || echo false)"

printf "\nTest group: migrate gives an epic past Backlog with no start the day it first left Backlog\n"

started="$TMPDIR/started"
mkdir -p "$started"
on_started() { COCKPIT_BOARD_DIR="$started" stub "$@"; }
on_started init >/dev/null
on_started create --kind project --name Home >/dev/null
COCKPIT_NOW=2026-09-01T10:00:00Z on_started create --kind epic --project PRJ-1 --name Moved >/dev/null
COCKPIT_NOW=2026-09-03T10:00:00Z on_started move EPIC-1 "In FD" >/dev/null
COCKPIT_NOW=2026-09-05T10:00:00Z on_started move EPIC-1 "In TD" >/dev/null
COCKPIT_NOW=2026-09-02T10:00:00Z on_started create --kind epic --project PRJ-1 --name Unstamped --status "In FD" >/dev/null
on_started create --kind epic --project PRJ-1 --name Waiting >/dev/null
perl -ni -e 'print unless /^start: /' "$started/epics/EPIC-1.md" "$started/epics/EPIC-2.md"
perl -0pi -e 's/dates:\n(  .*\n)*//' "$started/epics/EPIC-2.md"
git -C "$started" add --all >/dev/null && git -C "$started" -c user.name=t -c user.email=t@t commit --quiet -m seed
output="$(on_started migrate)"
assert_eq "it takes the earliest column it was stamped into past Backlog, else the day it was created" "2026-09-03 2026-09-02 null" \
  "$(for epic in 1 2 3; do COCKPIT_BOARD_DIR="$started" field "EPIC-$epic" .start; done | paste -sd ' ' -)"
assert_eq "and migrate names each start it gave" "EPIC-1	start 2026-09-03|EPIC-2	start 2026-09-02" "$(printf '%s\n' "$output" | grep start | paste -sd '|' -)"
assert_eq "a second migrate finds nothing to do" "nothing to migrate" "$(on_started migrate)"

printf "\nTest group: an epic moved back to Backlog loses its start, and leaving Backlog again stamps it afresh\n"

COCKPIT_NOW=2026-10-01T10:00:00Z on_started move EPIC-3 "In FD" >/dev/null
assert_eq "it is stamped the day it first leaves Backlog" "2026-10-01" "$(COCKPIT_BOARD_DIR="$started" field EPIC-3 .start)"
COCKPIT_NOW=2026-10-08T10:00:00Z on_started move EPIC-3 Backlog >/dev/null
assert_eq "moving it back to Backlog clears its start" "null false" "$(COCKPIT_BOARD_DIR="$started" field EPIC-3 '"\(.start) \(has("start"))"')"
assert_eq "in the move's own commit" "move EPIC-3" "$(git -C "$started" log -1 --format=%s)"
on_started undo EPIC-3 >/dev/null
assert_eq "undoing the move puts the old start back with the column" "2026-10-01 In FD" "$(COCKPIT_BOARD_DIR="$started" field EPIC-3 '"\(.start) \(.status)"')"
COCKPIT_NOW=2026-10-08T10:00:00Z on_started move EPIC-3 Backlog >/dev/null
COCKPIT_NOW=2026-10-12T10:00:00Z on_started move EPIC-3 "In FD" >/dev/null
assert_eq "leaving Backlog again stamps the day it leaves" "2026-10-12" "$(COCKPIT_BOARD_DIR="$started" field EPIC-3 .start)"
COCKPIT_NOW=2026-10-13T10:00:00Z on_started move EPIC-3 "In TD" >/dev/null
assert_eq "a move between later columns keeps it" "2026-10-12" "$(COCKPIT_BOARD_DIR="$started" field EPIC-3 .start)"

printf "\n%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
