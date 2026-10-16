#!/usr/bin/env bash

repo_root_through_symlink() {
  cd "$(dirname "$0")" && cd "$(pwd -P)/../../.." && pwd
}

REPO="$(repo_root_through_symlink)"
BOARD="$REPO/board"

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

finish() {
  printf "\n%d passed, %d failed\n" "$pass" "$fail"
  [ "$fail" -eq 0 ]
  exit
}

if [ ! -d "$BOARD/node_modules/typescript" ]; then
  printf "  KO  the board's packages are installed — run npm ci in %s, or nothing below can be checked\n" "$BOARD"
  fail=1
  finish
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

node -e '
const fs = require("node:fs");
const [board, work] = process.argv.slice(1);
const ts = require(`${board}/node_modules/typescript`);
const options = { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } };
for (const name of ["shared", "metrics", "plan"]) {
	const source = fs.readFileSync(`${board}/lib/${name}.ts`, "utf8").replace(/from "\.\/(shared|metrics)"/g, "from \"./$1.mjs\"");
	fs.writeFileSync(`${work}/${name}.mjs`, ts.transpileModule(source, options).outputText);
}
' "$BOARD" "$WORK"

evaluate() {
  TZ=UTC node --input-type=module -e '
import * as plan from "'"$WORK"'/plan.mjs";
const pick = (record, keys) => Object.fromEntries(keys.split(" ").map((key) => [key, record[key]]));
const result = new Function("p", "pick", `return (${process.argv[1]});`)(plan, pick);
process.stdout.write(typeof result === "string" ? result : JSON.stringify(result));
' "$1"
}

NOW='new Date(Date.parse("2026-10-14T12:00:00Z"))'
TODAY='p.dayOf("2026-10-14")'

printf "Test group: a card left to do counts its complexity, else its estimate, else nothing\n"

CARDS='[{"status":"Done","complexity":3},{"status":"In Dev","complexity":5,"estimate":8},{"status":"Backlog","estimate":3},{"status":"Backlog"},{"status":"Deprioritised","complexity":8},{"status":"In TR","complexity":0,"estimate":5,"dependent_on":["FEAT-9"]},{"status":"In Dev","type":"Timebox","complexity":2}]'
assert_eq "a card's points are its complexity over its estimate" '5' "$(evaluate 'p.pointsOf({complexity:5,estimate:8})')"
assert_eq "an estimate stands in for a complexity not yet set" '3' "$(evaluate 'p.pointsOf({complexity:null,estimate:3})')"
assert_eq "a card with neither has no points rather than a guess" 'null' "$(evaluate 'String(p.pointsOf({}))')"
assert_eq "a timebox has no points whatever it holds" 'null' "$(evaluate 'String(p.pointsOf({type:"Timebox",complexity:2}))')"
assert_eq "the points left take complexity first, then estimates, and leave out an unsized card, a split parent and a timebox" \
  '{"points":8,"complexity":5,"fromEstimate":3,"estimate":11,"open":4,"tickets":3,"sized":1,"estimated":2,"unsized":1,"done":1,"dropped":1}' \
  "$(evaluate "p.remainingOf($CARDS)")"
assert_eq "an epic with no cards has nothing left" \
  '{"points":0,"complexity":0,"fromEstimate":0,"estimate":0,"open":0,"tickets":0,"sized":0,"estimated":0,"unsized":0,"done":0,"dropped":0}' \
  "$(evaluate 'p.remainingOf([])')"

printf "\nTest group: the average speed is the TR complexity done a week, or the sprint's speed, or a default\n"

DONE='[{"status":"Done","complexity":5,"dates":{"Done":"2026-10-12T10:00:00Z"}},{"status":"Done","complexity":3,"dates":{"Done":"2026-09-10T10:00:00Z"}},{"status":"Done","dates":{"Done":"2026-08-01T10:00:00Z"}},{"status":"In Dev","complexity":8,"dates":{"Done":"2026-10-13T10:00:00Z"}}]'
assert_eq "six weeks of done cards make the average speed, an older one counting only to start the window" \
  '{"perWeek":1.3333333333333333,"source":"measured","points":8,"weeks":6,"tickets":2,"uncounted":0,"timeboxes":0}' "$(evaluate "p.averageSpeedOf($DONE, [], $NOW)")"
assert_eq "a board done for under six weeks divides by the weeks it has" \
  '{"perWeek":4,"source":"measured","points":8,"weeks":2,"tickets":1,"uncounted":0,"timeboxes":0}' \
  "$(evaluate 'p.averageSpeedOf([{status:"Done",complexity:8,dates:{Done:"2026-09-30T12:00:00Z"}}], [], '"$NOW"')')"
assert_eq "a done card counts only its TR complexity, and one without it or a timebox is counted apart, whatever its estimate" '{"points":5,"tickets":1,"uncounted":2,"timeboxes":1}' \
  "$(evaluate 'pick(p.averageSpeedOf([{status:"Done",complexity:5,estimate:8,dates:{Done:"2026-10-01T12:00:00Z"}},{status:"Done",estimate:3,dates:{Done:"2026-10-01T12:00:00Z"}},{status:"Done",dates:{Done:"2026-10-02T12:00:00Z"}},{status:"Done",type:"Timebox",complexity:2,dates:{Done:"2026-10-03T12:00:00Z"}}], [], '"$NOW"'), "points tickets uncounted timeboxes")')"
assert_eq "a board done only without complexity has no measured speed" 'default' \
  "$(evaluate 'p.averageSpeedOf([{status:"Done",estimate:3,dates:{Done:"2026-10-01T12:00:00Z"}}], [], '"$NOW"').source')"
assert_eq "with nothing done, the current sprint's speed a day makes the average speed a week" \
  '{"perWeek":12.5,"source":"sprint","points":0,"weeks":0,"tickets":0,"uncounted":0,"timeboxes":0}' \
  "$(evaluate 'p.averageSpeedOf([], [{start:"2026-10-12",end:"2026-10-23",speed:2.5}], '"$NOW"')')"
assert_eq "with no sprint speed either, the average speed is the default" '{"perWeek":10,"source":"default","points":0,"weeks":0,"tickets":0,"uncounted":0,"timeboxes":0}' \
  "$(evaluate 'p.averageSpeedOf([], [{start:"2026-10-12",end:"2026-10-23",speed:0}], '"$NOW"')')"

printf "\nTest group: epics are scheduled one after another in plan order\n"

EPICS='[{"id":"EPIC-2","status":"In FD","rank":2,"target":"2026-10-31"},{"id":"EPIC-1","status":"Tickets In Dev","rank":1,"start":"2026-10-01","target":"2026-10-25","confidence":"On track"},{"id":"EPIC-3","status":"In FD"},{"id":"EPIC-4","status":"Epic Done","target":"2026-10-01","dates":{"Epic Done":"2026-10-05T10:00:00Z"}},{"id":"EPIC-5","status":"In TD","start":"2026-12-01","target":"2026-12-31","rank":3}]'
PLAN_CARDS='[{"epic":"EPIC-1","status":"In Dev","complexity":13},{"epic":"EPIC-1","status":"Done","complexity":8},{"epic":"EPIC-2","status":"Backlog","estimate":3},{"epic":"EPIC-5","status":"Backlog","complexity":5},{"epic":"EPIC-4","status":"Done","complexity":3}]'
rows="p.planOf($EPICS, $PLAN_CARDS, 7, $TODAY)"
assert_eq "the plan order is the plan rank, then the target, then the id" 'EPIC-1,EPIC-2,EPIC-5,EPIC-4,EPIC-3' \
  "$(evaluate "p.planOrder($EPICS).map((e) => e.id).join()")"
assert_eq "the first epic runs from today for its points at the average speed, its last day of work its projected end, here past its target" '{"begin":20740,"projected":20752,"late":1}' \
  "$(evaluate "pick($rows[\"EPIC-1\"], \"begin projected late\")")"
assert_eq "the next one starts the day after the one ahead ends" '{"begin":20753,"projected":20755,"late":0}' \
  "$(evaluate "pick($rows[\"EPIC-2\"], \"begin projected late\")")"
assert_eq "an epic waits for its own start date" '{"begin":20788,"projected":20792,"late":0}' \
  "$(evaluate "pick($rows[\"EPIC-5\"], \"begin projected late\")")"
assert_eq "the speed a target needs counts the points of every epic ahead of it" '6.2' "$(evaluate "$rows[\"EPIC-2\"].needed")"
assert_eq "an epic projected late with no worse confidence than on track is flagged at risk" 'true,false' \
  "$(evaluate "[$rows[\"EPIC-1\"].atRisk, $rows[\"EPIC-2\"].atRisk].join()")"
assert_eq "a done epic is delivered when it reached Epic Done, late by its days past the target" \
  '{"done":true,"doneDay":20731,"late":4,"projected":null}' \
  "$(evaluate "pick($rows[\"EPIC-4\"], \"done doneDay late projected\")")"
assert_eq "an epic with no cards has no projection and takes no time from the plan" 'null' \
  "$(evaluate "$rows[\"EPIC-3\"].projected")"
assert_eq "a worse confidence is not flagged again" 'false' \
  "$(evaluate 'p.planOf([{id:"EPIC-1",status:"In FD",target:"2026-10-15",confidence:"At risk - no plan"}], [{epic:"EPIC-1",status:"Backlog",complexity:5}], 7, '"$TODAY"')["EPIC-1"].atRisk')"
assert_eq "a target in the past needs more than any speed" 'true,1' \
  "$(evaluate 'Object.values(p.planOf([{id:"EPIC-1",status:"In FD",target:"2026-10-01"}], [{epic:"EPIC-1",status:"Backlog",complexity:5}], 7, '"$TODAY"')).map((r) => [r.needed === Infinity, r.late > 0 ? 1 : 0]).flat().join()')"
assert_eq "an epic whose cards are all done ends today and takes no time from the plan" '20740,20765' \
  "$(evaluate 'Object.values(p.planOf([{id:"EPIC-1",status:"In FD",rank:1},{id:"EPIC-2",status:"In FD",rank:2},{id:"EPIC-3",status:"In FD",rank:3}], [{epic:"EPIC-1",status:"In Dev",complexity:13},{epic:"EPIC-2",status:"Done",complexity:5},{epic:"EPIC-3",status:"Backlog",complexity:13}], 7, '"$TODAY"')).map((r) => r.projected).slice(1).join()')"
assert_eq "an epic whose open cards are all unsized has no projection, takes no time from the plan and counts them" '{"projected":null,"unsized":2,"next":20740}' \
  "$(evaluate 'Object.values(p.planOf([{id:"EPIC-1",status:"In FD",rank:1},{id:"EPIC-2",status:"In FD",rank:2}], [{epic:"EPIC-1",status:"Backlog"},{epic:"EPIC-1",status:"In BR"},{epic:"EPIC-2",status:"Backlog",complexity:5}], 7, '"$TODAY"')).reduce((all, r) => r.id === "EPIC-1" ? {...all, projected: r.projected, unsized: r.remaining.unsized} : {...all, next: r.begin}, {})')"
assert_eq "an unsized card leaves the date to the cards that are sized" '20744' \
  "$(evaluate 'p.planOf([{id:"EPIC-1",status:"In FD"}], [{epic:"EPIC-1",status:"Backlog",complexity:5},{epic:"EPIC-1",status:"Backlog"}], 7, '"$TODAY"')["EPIC-1"].projected')"
assert_eq "an epic with only a timebox open counts nothing unsized" '0' \
  "$(evaluate 'p.planOf([{id:"EPIC-1",status:"In FD"}], [{epic:"EPIC-1",status:"Backlog",type:"Timebox"}], 7, '"$TODAY"')["EPIC-1"].remaining.unsized')"
assert_eq "a start after the target is read as backwards" 'true' \
  "$(evaluate 'p.planOf([{id:"EPIC-1",status:"In FD",start:"2026-11-01",target:"2026-10-20"}], [], 7, '"$TODAY"')["EPIC-1"].backwards')"
assert_eq "an epic whose points fit exactly by its target ends on it, not a day late" '{"projected":20746,"late":0}' \
  "$(evaluate 'pick(p.planOf([{id:"EPIC-1",status:"In FD",target:"2026-10-20"}], [{epic:"EPIC-1",status:"Backlog",complexity:7}], 7, '"$TODAY"')["EPIC-1"], "projected late")')"
assert_eq "an average speed of zero is held above zero rather than dividing by it" 'true' \
  "$(evaluate 'Number.isFinite(p.planOf([{id:"EPIC-1",status:"In FD"}], [{epic:"EPIC-1",status:"Backlog",complexity:5}], 0, '"$TODAY"')["EPIC-1"].projected)')"

printf "\nTest group: each project runs its epics on its own tracks\n"

TEAMS='{"PRJ-1":{"tracks":2,"perWeek":7},"PRJ-2":{"tracks":1,"perWeek":7},"":{"tracks":1,"perWeek":7}}'
TRACKED='[{"id":"EPIC-1","status":"In FD","project":"PRJ-1","rank":1},{"id":"EPIC-2","status":"In FD","project":"PRJ-1","rank":2},{"id":"EPIC-3","status":"In FD","project":"PRJ-1","rank":3},{"id":"EPIC-4","status":"In FD","project":"PRJ-2","rank":4},{"id":"EPIC-5","status":"In FD","project":"PRJ-9","rank":5}]'
TRACKED_CARDS='[{"epic":"EPIC-1","status":"Backlog","complexity":5},{"epic":"EPIC-2","status":"Backlog","complexity":5},{"epic":"EPIC-3","status":"Backlog","complexity":5},{"epic":"EPIC-4","status":"Backlog","complexity":5},{"epic":"EPIC-5","status":"Backlog","complexity":5}]'
tracked="p.planOf($TRACKED, $TRACKED_CARDS, $TEAMS, $TODAY)"
assert_eq "two tracks run the first two epics side by side from today, and the third takes the first track to free" '1@20740,2@20740,1@20745' \
  "$(evaluate "[\"EPIC-1\",\"EPIC-2\",\"EPIC-3\"].map((id) => $tracked[id].track + \"@\" + $tracked[id].begin).join()")"
assert_eq "another project never waits on the first one" '1@20740' \
  "$(evaluate "$tracked[\"EPIC-4\"].track + \"@\" + $tracked[\"EPIC-4\"].begin")"
assert_eq "an epic whose project is not on the board runs with the epics with no project" '' \
  "$(evaluate "$tracked[\"EPIC-5\"].team")"
assert_eq "a number for the speed puts every epic on one track at it" '20740,20745' \
  "$(evaluate "[\"EPIC-1\",\"EPIC-2\"].map((id) => p.planOf($TRACKED, $TRACKED_CARDS, 7, $TODAY)[id].begin).join()")"
assert_eq "the speed a target needs counts only the epics ahead of it on its own track" '5.8,5.8' \
  "$(evaluate "[\"EPIC-1\",\"EPIC-2\"].map((id) => p.planOf($TRACKED.map((e) => Object.assign({}, e, {target: \"2026-10-19\"})), $TRACKED_CARDS, $TEAMS, $TODAY)[id].needed).join()")"

printf "\nTest group: an epic in progress keeps its track, and the lowest in the plan pauses when the tracks run out\n"

STARTED='[{"id":"EPIC-1","status":"Tickets In Dev","project":"PRJ-1","rank":2},{"id":"EPIC-2","status":"In TD","project":"PRJ-1","rank":3},{"id":"EPIC-3","status":"In FD","project":"PRJ-1","rank":1}]'
STARTED_CARDS='[{"epic":"EPIC-1","status":"In Dev","complexity":5},{"epic":"EPIC-2","status":"In Dev","complexity":5,"dates":{"In Dev":"2026-10-12T10:00:00Z"}},{"epic":"EPIC-3","status":"Backlog","complexity":5}]'
one="p.planOf($STARTED, $STARTED_CARDS, {\"PRJ-1\":{\"tracks\":1,\"perWeek\":7}}, $TODAY)"
two="p.planOf($STARTED, $STARTED_CARDS, {\"PRJ-1\":{\"tracks\":2,\"perWeek\":7}}, $TODAY)"
assert_eq "an epic in Tickets In Dev, or with a card that reached In Dev, is in progress" 'true,true,false' \
  "$(evaluate "[\"EPIC-1\",\"EPIC-2\",\"EPIC-3\"].map((id) => $one[id].inProgress).join()")"
assert_eq "with one track the lower epic in progress pauses until the higher one ends" '{"track":1,"begin":20745,"pausedUntil":20745}' \
  "$(evaluate "pick($one[\"EPIC-2\"], \"track begin pausedUntil\")")"
assert_eq "and an epic not yet started waits for both, whatever its place in the plan" '20750' "$(evaluate "$one[\"EPIC-3\"].begin")"
assert_eq "a second track lets both run from today with no pause" '1@20740:null,2@20740:null' \
  "$(evaluate "[\"EPIC-1\",\"EPIC-2\"].map((id) => $two[id].track + \"@\" + $two[id].begin + \":\" + $two[id].pausedUntil).join()")"
assert_eq "an epic in progress that waits for its own start date is not paused" 'null' \
  "$(evaluate 'p.planOf([{id:"EPIC-1",status:"Tickets In Dev",start:"2026-10-20"}], [{epic:"EPIC-1",status:"In Dev",complexity:5}], 7, '"$TODAY"')["EPIC-1"].pausedUntil')"

printf "\nTest group: an epic pinned to a track waits for it\n"

PINNED='[{"id":"EPIC-1","status":"In FD","project":"PRJ-1","rank":1,"track":2},{"id":"EPIC-2","status":"In FD","project":"PRJ-1","rank":2,"track":2},{"id":"EPIC-3","status":"In FD","project":"PRJ-1","rank":3},{"id":"EPIC-4","status":"In FD","project":"PRJ-1","rank":4,"track":5}]'
PINNED_CARDS='[{"epic":"EPIC-1","status":"Backlog","complexity":5},{"epic":"EPIC-2","status":"Backlog","complexity":5},{"epic":"EPIC-3","status":"Backlog","complexity":5},{"epic":"EPIC-4","status":"Backlog","complexity":5}]'
pinned="p.planOf($PINNED, $PINNED_CARDS, {\"PRJ-1\":{\"tracks\":2,\"perWeek\":7}}, $TODAY)"
assert_eq "a pinned epic waits for its track while another track is free" '2@20740,2@20745' \
  "$(evaluate "[\"EPIC-1\",\"EPIC-2\"].map((id) => $pinned[id].track + \"@\" + $pinned[id].begin).join()")"
assert_eq "and the next epic takes the free track" '1@20740' "$(evaluate "$pinned[\"EPIC-3\"].track + \"@\" + $pinned[\"EPIC-3\"].begin")"
assert_eq "a pin past the project's tracks is flagged and ignored" '{"pin":5,"pinIgnored":true,"track":1,"begin":20745}' \
  "$(evaluate "pick($pinned[\"EPIC-4\"], \"pin pinIgnored track begin\")")"

assert_eq "an epic in progress keeps the first track though an epic not yet started is pinned to it" '1@20740,2@20740,1@20745' \
  "$(evaluate 'Object.values(p.planOf([{id:"EPIC-1",status:"Tickets In Dev",rank:1},{id:"EPIC-2",status:"In FD",rank:2},{id:"EPIC-3",status:"In FD",rank:3,track:1}], [{epic:"EPIC-1",status:"In Dev",complexity:5},{epic:"EPIC-2",status:"Backlog",complexity:5},{epic:"EPIC-3",status:"Backlog",complexity:5}], {"":{tracks:2,perWeek:7}}, '"$TODAY"')).map((r) => r.track + "@" + r.begin).join()')"

printf "\nTest group: each project's speed a track comes from its own finished cards\n"

SPEED_EPICS='[{"id":"EPIC-1","status":"Tickets In Dev","project":"PRJ-1","dates":{"Tickets In Dev":"2026-08-01T10:00:00Z"}},{"id":"EPIC-2","status":"Tickets In Dev","project":"PRJ-1","dates":{"Tickets In Dev":"2026-08-01T10:00:00Z"}},{"id":"EPIC-3","status":"In FD","project":"PRJ-2"}]'
SPEED_CARDS='[{"epic":"EPIC-1","status":"Done","complexity":12,"dates":{"Done":"2026-10-10T10:00:00Z"}},{"epic":"EPIC-2","status":"Done","complexity":1,"dates":{"Done":"2026-08-05T10:00:00Z"}},{"status":"Done","complexity":6,"dates":{"Done":"2026-10-12T10:00:00Z"}}]'
speeds="p.trackSpeedsOf($SPEED_CARDS, $SPEED_EPICS, [\"PRJ-1\",\"PRJ-2\"], [], $NOW)"
assert_eq "a project's average speed is split across the epics it had in progress on average" '{"perWeek":1,"source":"measured","inProgress":2}' \
  "$(evaluate "pick($speeds.teams[\"PRJ-1\"], \"perWeek source inProgress\")")"
assert_eq "a project with no history takes the overall speed a track, and says so" '{"perWeek":1.5,"source":"overall","inProgress":2}' \
  "$(evaluate "pick($speeds.teams[\"PRJ-2\"], \"perWeek source inProgress\")")"
assert_eq "a card with no epic and no project counts toward the epics with no project" '{"perWeek":6,"source":"measured","inProgress":0}' \
  "$(evaluate "pick($speeds.teams[\"\"], \"perWeek source inProgress\")")"
assert_eq "an epic counts as in progress from its first card in dev until it is done" '0.5' \
  "$(evaluate 'p.epicsInProgressOver([{id:"EPIC-1",status:"Epic Done",dates:{"Epic Done":"2026-10-11T00:00:00Z"}}], [{epic:"EPIC-1",status:"Done",dates:{"In Dev":"2026-10-09T00:00:00Z","Done":"2026-10-10T00:00:00Z"}}], Date.parse("2026-10-07T00:00:00Z"), Date.parse("2026-10-11T00:00:00Z"))')"

printf "\nTest group: the timeline spans what it shows, within its limits\n"

assert_eq "it opens on a Monday two weeks back and runs four weeks past the last date" \
  '{"first":20724,"last":20858,"clippedBefore":false,"clippedAfter":false}' "$(evaluate "p.spanOf([20830, null], $TODAY)")"
assert_eq "a plan running past five years is cut there and says so" 'true' \
  "$(evaluate "p.spanOf([$TODAY + 4000], $TODAY).clippedAfter")"
assert_eq "a date is the day it names" '2026-10-14' "$(evaluate "p.dayText($TODAY)")"
assert_eq "a late epic says how late in days" 'Delivered 1 day late,9 days late' \
  "$(evaluate '[p.lateText(1, true), p.lateText(9, false)].join()')"

finish
