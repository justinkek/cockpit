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

printf "\nTest group: the average speed is the points done a week, or the sprint's speed, or a default\n"

DONE='[{"status":"Done","complexity":5,"dates":{"Done":"2026-10-12T10:00:00Z"}},{"status":"Done","complexity":3,"dates":{"Done":"2026-09-10T10:00:00Z"}},{"status":"Done","dates":{"Done":"2026-08-01T10:00:00Z"}},{"status":"In Dev","complexity":8,"dates":{"Done":"2026-10-13T10:00:00Z"}}]'
assert_eq "six weeks of done cards make the average speed, an older one counting only to start the window" \
  '{"perWeek":1.3333333333333333,"source":"measured","points":8,"weeks":6}' "$(evaluate "p.averageSpeedOf($DONE, [], $NOW)")"
assert_eq "a board done for under six weeks divides by the weeks it has" \
  '{"perWeek":4,"source":"measured","points":8,"weeks":2}' \
  "$(evaluate 'p.averageSpeedOf([{status:"Done",complexity:8,dates:{Done:"2026-09-30T12:00:00Z"}}], [], '"$NOW"')')"
assert_eq "a done card counts its estimate when it has no complexity, and nothing when it has neither" '3' \
  "$(evaluate 'p.averageSpeedOf([{status:"Done",estimate:3,dates:{Done:"2026-10-01T12:00:00Z"}},{status:"Done",dates:{Done:"2026-10-02T12:00:00Z"}}], [], '"$NOW"').points')"
assert_eq "with nothing done, the current sprint's speed a day makes the average speed a week" \
  '{"perWeek":12.5,"source":"sprint","points":0,"weeks":0}' \
  "$(evaluate 'p.averageSpeedOf([], [{start:"2026-10-12",end:"2026-10-23",speed:2.5}], '"$NOW"')')"
assert_eq "with no sprint speed either, the average speed is the default" '{"perWeek":10,"source":"default","points":0,"weeks":0}' \
  "$(evaluate 'p.averageSpeedOf([], [{start:"2026-10-12",end:"2026-10-23",speed:0}], '"$NOW"')')"

printf "\nTest group: epics are scheduled one after another in plan order\n"

EPICS='[{"id":"EPIC-2","status":"In FD","plan_rank":2,"target":"2026-10-31"},{"id":"EPIC-1","status":"Tickets In Dev","plan_rank":1,"start":"2026-10-01","target":"2026-10-25","confidence":"On track"},{"id":"EPIC-3","status":"In FD"},{"id":"EPIC-4","status":"Epic Done","target":"2026-10-01","dates":{"Epic Done":"2026-10-05T10:00:00Z"}},{"id":"EPIC-5","status":"In TD","start":"2026-12-01","target":"2026-12-31","plan_rank":3}]'
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
  "$(evaluate 'Object.values(p.planOf([{id:"EPIC-1",status:"In FD",plan_rank:1},{id:"EPIC-2",status:"In FD",plan_rank:2},{id:"EPIC-3",status:"In FD",plan_rank:3}], [{epic:"EPIC-1",status:"In Dev",complexity:13},{epic:"EPIC-2",status:"Done",complexity:5},{epic:"EPIC-3",status:"Backlog",complexity:13}], 7, '"$TODAY"')).map((r) => r.projected).slice(1).join()')"
assert_eq "an epic whose open cards are all unsized has no projection, takes no time from the plan and counts them" '{"projected":null,"unsized":2,"next":20740}' \
  "$(evaluate 'Object.values(p.planOf([{id:"EPIC-1",status:"In FD",plan_rank:1},{id:"EPIC-2",status:"In FD",plan_rank:2}], [{epic:"EPIC-1",status:"Backlog"},{epic:"EPIC-1",status:"In BR"},{epic:"EPIC-2",status:"Backlog",complexity:5}], 7, '"$TODAY"')).reduce((all, r) => r.id === "EPIC-1" ? {...all, projected: r.projected, unsized: r.remaining.unsized} : {...all, next: r.begin}, {})')"
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

printf "\nTest group: the timeline spans what it shows, within its limits\n"

assert_eq "it opens on a Monday two weeks back and runs four weeks past the last date" \
  '{"first":20724,"last":20858,"clippedBefore":false,"clippedAfter":false}' "$(evaluate "p.spanOf([20830, null], $TODAY)")"
assert_eq "a plan running past five years is cut there and says so" 'true' \
  "$(evaluate "p.spanOf([$TODAY + 4000], $TODAY).clippedAfter")"
assert_eq "a date is the day it names" '2026-10-14' "$(evaluate "p.dayText($TODAY)")"
assert_eq "a late epic says how late in days" 'Delivered 1 day late,9 days late' \
  "$(evaluate '[p.lateText(1, true), p.lateText(9, false)].join()')"

finish
