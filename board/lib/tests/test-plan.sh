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
INSTANT='{days:0,source:"default",epics:0}'

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

assert_eq "an epic's estimates total every ticket but a deprioritised one, a split parent and a timebox, beside what is left" \
  '{"tickets":4,"estimate":11,"estimated":2,"complexity":8,"sized":2}|8' \
  "$(evaluate "(() => { const e = p.estimatesOf($CARDS); return JSON.stringify(e.total) + '|' + e.left.points; })()")"
assert_eq "an epic with no tickets has no totals, which read as none rather than zero" '0,0' \
  "$(evaluate '(() => { const e = p.estimatesOf([]); return [e.total.estimated, e.total.sized].join(); })()')"

printf "\nTest group: the average speed is the TR complexity finished a working day over the last 30 working days, or since the first card was finished when that is fewer, or the sprint's speed, or a default\n"

DONE='[{"status":"Done","complexity":5,"dates":{"Done":"2026-10-12T10:00:00Z"}},{"status":"Done","complexity":3,"dates":{"Done":"2026-09-10T10:00:00Z"}},{"status":"Done","dates":{"Done":"2026-08-01T10:00:00Z"}},{"status":"In Dev","complexity":8,"dates":{"Done":"2026-10-13T10:00:00Z"}}]'
assert_eq "the average speed divides the points finished on the last 30 working days by those days, shown as a week of five, and a card finished before them is left out" \
  '{"perWeek":1.3333333333333333,"perDay":0.26666666666666666,"source":"measured","points":8,"days":30,"tickets":2,"uncounted":0,"timeboxes":0}' \
  "$(evaluate "pick(p.averageSpeedOf($DONE, [], $NOW), \"perWeek perDay source points days tickets uncounted timeboxes\")")"
assert_eq "the window runs back from today over weekdays alone" '30,2026-10-14,2026-09-03' \
  "$(evaluate '((days) => [days.length, p.dayText(days[0]), p.dayText(days.at(-1))].join())(p.averageSpeedOf('"$DONE"', [], '"$NOW"').workingDays)')"
assert_eq "a working day that finished nothing still counts" '{"perWeek":1.3333333333333333,"days":30}' \
  "$(evaluate 'pick(p.averageSpeedOf([{status:"Done",complexity:8,dates:{Done:"2026-09-30T12:00:00Z"}},{status:"Done",dates:{Done:"2026-08-03T12:00:00Z"}}], [], '"$NOW"'), "perWeek days")')"
assert_eq "a board whose first card was finished fewer than 30 working days ago divides by the working days since, that day and today among them" '{"perWeek":3.6363636363636367,"days":11}|2026-09-30' \
  "$(evaluate '((speed) => JSON.stringify(pick(speed, "perWeek days")) + "|" + p.dayText(speed.workingDays.at(-1)))(p.averageSpeedOf([{status:"Done",complexity:8,dates:{Done:"2026-09-30T12:00:00Z"}}], [], '"$NOW"'))')"
assert_eq "the first card finished counts its day even when it was done without a complexity" '{"days":13}' \
  "$(evaluate 'pick(p.averageSpeedOf([{status:"Done",complexity:8,dates:{Done:"2026-10-07T12:00:00Z"}},{status:"Done",estimate:3,dates:{Done:"2026-09-28T12:00:00Z"}}], [], '"$NOW"'), "days")')"
assert_eq "a board that finished its first card today divides by that one day" '{"perWeek":25,"days":1}' \
  "$(evaluate 'pick(p.averageSpeedOf([{status:"Done",complexity:5,dates:{Done:"2026-10-14T09:00:00Z"}}], [], '"$NOW"'), "perWeek days")')"
assert_eq "a card finished at a weekend is left out" '3' \
  "$(evaluate 'p.averageSpeedOf([{status:"Done",complexity:5,dates:{Done:"2026-10-10T12:00:00Z"}},{status:"Done",complexity:3,dates:{Done:"2026-10-12T12:00:00Z"}}], [], '"$NOW"').points')"
assert_eq "a done card counts only its TR complexity, and one without it or a timebox is counted apart, whatever its estimate" '{"points":5,"tickets":1,"uncounted":2,"timeboxes":1}' \
  "$(evaluate 'pick(p.averageSpeedOf([{status:"Done",complexity:5,estimate:8,dates:{Done:"2026-10-01T12:00:00Z"}},{status:"Done",estimate:3,dates:{Done:"2026-10-01T12:00:00Z"}},{status:"Done",dates:{Done:"2026-10-02T12:00:00Z"}},{status:"Done",type:"Timebox",complexity:2,dates:{Done:"2026-10-05T12:00:00Z"}}], [], '"$NOW"'), "points tickets uncounted timeboxes")')"
assert_eq "a board done only without complexity has no measured speed" 'default' \
  "$(evaluate 'p.averageSpeedOf([{status:"Done",estimate:3,dates:{Done:"2026-10-01T12:00:00Z"}}], [], '"$NOW"').source')"
assert_eq "with nothing done, the current sprint's speed a day times five makes the average speed a week" \
  '{"perWeek":12.5,"perDay":2.5,"source":"sprint","points":0,"days":0,"tickets":0,"uncounted":0,"timeboxes":0,"workingDays":[]}' \
  "$(evaluate 'p.averageSpeedOf([], [{start:"2026-10-12",end:"2026-10-23",speed:2.5}], '"$NOW"')')"
assert_eq "with no sprint speed either, the average speed is the default" '{"perWeek":10,"perDay":2,"source":"default","points":0,"days":0,"tickets":0,"uncounted":0,"timeboxes":0,"workingDays":[]}' \
  "$(evaluate 'p.averageSpeedOf([], [{start:"2026-10-12",end:"2026-10-23",speed:0}], '"$NOW"')')"

printf "\nTest group: a break's days are not working days, so the speed leaves them out\n"

assert_eq "breaks become day spans, overlapping ones merged" '[[20730,20740],[20760,20760]]' \
  "$(evaluate 'p.daysOff([{from:"2026-10-04",to:"2026-10-10"},{from:"2026-10-08",to:"2026-10-14"},{from:"2026-11-03",to:"2026-11-03"}])')"
assert_eq "a working day is a weekday outside a break" 'true,false,false,false' \
  "$(evaluate '[20740, 20743, 20744, 20741].map((day) => p.isWorkingDay(day, [[20741,20741]])).join()')"
FIRST_BROKEN='[{status:"Done",complexity:5,dates:{Done:"2026-10-12T12:00:00Z"}},{status:"Done",complexity:3,dates:{Done:"2026-10-07T12:00:00Z"}},{status:"Done",complexity:4,dates:{Done:"2026-09-30T12:00:00Z"}}]'
assert_eq "the working days since the first card was finished leave a break out" '{"perWeek":7.5,"points":9,"days":6}|2026-09-30' \
  "$(evaluate '((speed) => JSON.stringify(pick(speed, "perWeek points days")) + "|" + p.dayText(speed.workingDays.at(-1)))(p.averageSpeedOf('"$FIRST_BROKEN"', [], '"$NOW"', p.daysOff([{from:"2026-10-05",to:"2026-10-09"}])))')"
BROKEN='[{status:"Done",complexity:5,dates:{Done:"2026-10-12T12:00:00Z"}},{status:"Done",complexity:3,dates:{Done:"2026-10-07T12:00:00Z"}},{status:"Done",complexity:4,dates:{Done:"2026-09-30T12:00:00Z"}},{status:"Done",dates:{Done:"2026-08-03T12:00:00Z"}}]'
assert_eq "a card finished in a break is left out, and the window reaches back past the break for its 30 working days" '{"perWeek":1.5,"points":9,"days":30}|2026-08-27' \
  "$(evaluate '((speed) => JSON.stringify(pick(speed, "perWeek points days")) + "|" + p.dayText(speed.workingDays.at(-1)))(p.averageSpeedOf('"$BROKEN"', [], '"$NOW"', p.daysOff([{from:"2026-10-05",to:"2026-10-09"}])))')"
assert_eq "a card finished on a working day beside a break still counts" '{"perWeek":2,"points":12}' \
  "$(evaluate 'pick(p.averageSpeedOf('"$BROKEN"', [], '"$NOW"', p.daysOff([{from:"2026-10-05",to:"2026-10-06"}])), "perWeek points")')"
BREAK_EPICS='[{"id":"EPIC-1","status":"Tickets In Dev","project":"PRJ-1"},{"id":"EPIC-2","status":"Tickets In Dev","project":"PRJ-2"}]'
BREAK_CARDS='[{"epic":"EPIC-1","status":"Done","dates":{"Done":"2026-08-03T12:00:00Z"}},{"epic":"EPIC-1","status":"Done","complexity":6,"dates":{"Done":"2026-10-12T12:00:00Z"}},{"epic":"EPIC-1","status":"Done","complexity":2,"dates":{"Done":"2026-10-07T12:00:00Z"}},{"epic":"EPIC-2","status":"Done","complexity":4,"dates":{"Done":"2026-10-07T12:00:00Z"}}]'
broken='p.trackSpeedsOf('"$BREAK_CARDS"', '"$BREAK_EPICS"', ["PRJ-1","PRJ-2"], [], '"$NOW"', [{from:"2026-10-05",to:"2026-10-09"}])'
assert_eq "a break leaves its days out of every project's speed, so a project with nothing else finished takes the board's" '1,1,6' \
  "$(evaluate "[$broken.teams[\"PRJ-1\"].speed.perWeek, $broken.teams[\"PRJ-2\"].speed.perWeek, $broken.overall.speed.points].join()")"

SPRINT='{id:"SPR-1",start:"2026-09-28",end:"2026-10-11"}'
assert_eq "a sprint delivered the TR complexity of the done cards whose sprint it is, a week, counting the rest beside it" \
  '{"points":16,"tickets":2,"uncounted":1,"timeboxes":1,"workingDays":10,"perWeek":8}' \
  "$(evaluate 'p.deliveredIn('"$SPRINT"', [{status:"Done",sprint:"SPR-1",complexity:5,dates:{Done:"2026-09-28T09:00:00Z"}},{status:"Done",sprint:"SPR-2",complexity:3,dates:{Done:"2026-10-11T17:00:00Z"}},{status:"Done",sprint:"SPR-1",complexity:11,dates:{Done:"2026-10-12T09:00:00Z"}},{status:"Done",sprint:"SPR-1",estimate:3,dates:{Done:"2026-10-01T09:00:00Z"}},{status:"Done",sprint:"SPR-1",type:"Timebox",dates:{Done:"2026-10-01T09:00:00Z"}},{status:"In Dev",sprint:"SPR-1",complexity:2,dates:{Done:"2026-10-01T09:00:00Z"}}])')"
assert_eq "a sprint with no dates has no speed" 'null' "$(evaluate 'String(p.deliveredIn({id:"SPR-1",start:null,end:null}, []).perWeek)')"
assert_eq "a sprint's speed is its points over its working days, a weekend and a break left out, as a week of five" '{"workingDays":5,"perWeek":16}' \
  "$(evaluate 'pick(p.deliveredIn('"$SPRINT"', [{status:"Done",sprint:"SPR-1",complexity:16,dates:{Done:"2026-09-28T09:00:00Z"}}], p.daysOff([{from:"2026-10-05",to:"2026-10-09"}])), "workingDays perWeek")')"
assert_eq "a sprint that falls on no working day has no speed" '{"workingDays":0,"perWeek":null}' \
  "$(evaluate 'pick(p.deliveredIn({id:"SPR-1",start:"2026-10-10",end:"2026-10-11"}, []), "workingDays perWeek")')"

printf "\nTest group: epics are scheduled one after another in plan order\n"

EPICS='[{"id":"EPIC-2","status":"In FD","rank":2,"target":"2026-11-06"},{"id":"EPIC-1","status":"Tickets In Dev","rank":1,"start":"2026-10-01","target":"2026-10-25","confidence":"On track"},{"id":"EPIC-3","status":"In FD"},{"id":"EPIC-4","status":"Epic Done","target":"2026-10-01","dates":{"Epic Done":"2026-10-05T10:00:00Z"}},{"id":"EPIC-5","status":"In TD","start":"2026-12-01","target":"2026-12-31","rank":3}]'
PLAN_CARDS='[{"epic":"EPIC-1","status":"In Dev","complexity":13},{"epic":"EPIC-1","status":"Done","complexity":8},{"epic":"EPIC-2","status":"Backlog","estimate":3},{"epic":"EPIC-5","status":"Backlog","complexity":5},{"epic":"EPIC-4","status":"Done","complexity":3}]'
rows="p.planOf($EPICS, $PLAN_CARDS, 5, $TODAY, $INSTANT)"
assert_eq "the plan order is the plan rank, then the target, then the id" 'EPIC-1,EPIC-2,EPIC-5,EPIC-4,EPIC-3' \
  "$(evaluate "p.planOrder($EPICS).map((e) => e.id).join()")"
assert_eq "the first epic runs from today for its points at the average speed, its last day of work its projected end, here past its target" '{"begin":20740,"projected":20756,"late":5}' \
  "$(evaluate "pick($rows[\"EPIC-1\"], \"begin projected late\")")"
assert_eq "the next one starts on the first working day after the one ahead ends" '{"begin":20759,"projected":20761,"late":0}' \
  "$(evaluate "pick($rows[\"EPIC-2\"], \"begin projected late\")")"
assert_eq "an epic in refinement is not delivered before its refinement ends" '{"begin":20788,"projected":20794,"late":0}' \
  "$(evaluate "pick($rows[\"EPIC-5\"], \"begin projected late\")")"
assert_eq "the speed a target needs counts the points of every epic ahead of it over the working days before it" '4.4' "$(evaluate "$rows[\"EPIC-2\"].needed")"
assert_eq "an epic projected late with no worse confidence than on track is flagged at risk" 'true,false' \
  "$(evaluate "[$rows[\"EPIC-1\"].atRisk, $rows[\"EPIC-2\"].atRisk].join()")"
assert_eq "a done epic is delivered when it reached Epic Done, late by its days past the target" \
  '{"done":true,"doneDay":20731,"late":4,"projected":null}' \
  "$(evaluate "pick($rows[\"EPIC-4\"], \"done doneDay late projected\")")"
assert_eq "an epic with no cards has no projection and takes no time from the plan" 'null' \
  "$(evaluate "$rows[\"EPIC-3\"].projected")"
assert_eq "a worse confidence is not flagged again" 'false' \
  "$(evaluate 'p.planOf([{id:"EPIC-1",status:"In FD",target:"2026-10-15",confidence:"At risk - no plan"}], [{epic:"EPIC-1",status:"Backlog",complexity:5}], 5, '"$TODAY"', '"$INSTANT"')["EPIC-1"].atRisk')"
assert_eq "a target in the past needs more than any speed" 'true,1' \
  "$(evaluate 'Object.values(p.planOf([{id:"EPIC-1",status:"In FD",target:"2026-10-01"}], [{epic:"EPIC-1",status:"Backlog",complexity:5}], 5, '"$TODAY"', '"$INSTANT"')).map((r) => [r.needed === Infinity, r.late > 0 ? 1 : 0]).flat().join()')"
assert_eq "an epic whose cards are all done ends today and takes no time from the plan" '20740,20775' \
  "$(evaluate 'Object.values(p.planOf([{id:"EPIC-1",status:"In FD",rank:1},{id:"EPIC-2",status:"In FD",rank:2},{id:"EPIC-3",status:"In FD",rank:3}], [{epic:"EPIC-1",status:"In Dev",complexity:13},{epic:"EPIC-2",status:"Done",complexity:5},{epic:"EPIC-3",status:"Backlog",complexity:13}], 5, '"$TODAY"', '"$INSTANT"')).map((r) => r.projected).slice(1).join()')"
assert_eq "an epic whose open cards are all unsized has no projection, takes no time from the plan and counts them" '{"projected":null,"unsized":2,"next":20740}' \
  "$(evaluate 'Object.values(p.planOf([{id:"EPIC-1",status:"In FD",rank:1},{id:"EPIC-2",status:"In FD",rank:2}], [{epic:"EPIC-1",status:"Backlog"},{epic:"EPIC-1",status:"In BR"},{epic:"EPIC-2",status:"Backlog",complexity:5}], 5, '"$TODAY"', '"$INSTANT"')).reduce((all, r) => r.id === "EPIC-1" ? {...all, projected: r.projected, unsized: r.remaining.unsized} : {...all, next: r.begin}, {})')"
assert_eq "an unsized card leaves the date to the cards that are sized" '20746' \
  "$(evaluate 'p.planOf([{id:"EPIC-1",status:"In FD"}], [{epic:"EPIC-1",status:"Backlog",complexity:5},{epic:"EPIC-1",status:"Backlog"}], 5, '"$TODAY"', '"$INSTANT"')["EPIC-1"].projected')"
assert_eq "an epic with only a timebox open counts nothing unsized" '0' \
  "$(evaluate 'p.planOf([{id:"EPIC-1",status:"In FD"}], [{epic:"EPIC-1",status:"Backlog",type:"Timebox"}], 5, '"$TODAY"', '"$INSTANT"')["EPIC-1"].remaining.unsized')"
assert_eq "a start after the target is read as backwards" 'true' \
  "$(evaluate 'p.planOf([{id:"EPIC-1",status:"In FD",start:"2026-11-01",target:"2026-10-20"}], [], 5, '"$TODAY"', '"$INSTANT"')["EPIC-1"].backwards')"
assert_eq "an epic whose points fit exactly by its target ends on it, not a day late, its days stepping over the weekend" '{"projected":20748,"late":0}' \
  "$(evaluate 'pick(p.planOf([{id:"EPIC-1",status:"In FD",target:"2026-10-22"}], [{epic:"EPIC-1",status:"Backlog",complexity:7}], 5, '"$TODAY"', '"$INSTANT"')["EPIC-1"], "projected late")')"
assert_eq "an average speed of zero is held above zero rather than dividing by it" 'true' \
  "$(evaluate 'Number.isFinite(p.planOf([{id:"EPIC-1",status:"In FD"}], [{epic:"EPIC-1",status:"Backlog",complexity:5}], 0, '"$TODAY"', '"$INSTANT"')["EPIC-1"].projected)')"

printf "\nTest group: each project runs its epics on its own tracks\n"

TEAMS='{"PRJ-1":{"tracks":2,"perWeek":5},"PRJ-2":{"tracks":1,"perWeek":5},"PRJ-3":{"tracks":0,"perWeek":5}}'
TRACKED='[{"id":"EPIC-1","status":"In FD","project":"PRJ-1","rank":1},{"id":"EPIC-2","status":"In FD","project":"PRJ-1","rank":2},{"id":"EPIC-3","status":"In FD","project":"PRJ-1","rank":3},{"id":"EPIC-4","status":"In FD","project":"PRJ-2","rank":4},{"id":"EPIC-5","status":"In FD","project":"PRJ-9","rank":5}]'
TRACKED_CARDS='[{"epic":"EPIC-1","status":"Backlog","complexity":5},{"epic":"EPIC-2","status":"Backlog","complexity":5},{"epic":"EPIC-3","status":"Backlog","complexity":5},{"epic":"EPIC-4","status":"Backlog","complexity":5},{"epic":"EPIC-5","status":"Backlog","complexity":5}]'
tracked="p.planOf($TRACKED, $TRACKED_CARDS, $TEAMS, $TODAY, $INSTANT)"
assert_eq "two tracks run the first two epics side by side from today, and the third takes the first track to free" '1@20740,2@20740,1@20747' \
  "$(evaluate "[\"EPIC-1\",\"EPIC-2\",\"EPIC-3\"].map((id) => $tracked[id].track + \"@\" + $tracked[id].begin).join()")"
assert_eq "another project never waits on the first one" '1@20740' \
  "$(evaluate "$tracked[\"EPIC-4\"].track + \"@\" + $tracked[\"EPIC-4\"].begin")"
assert_eq "an epic whose project is not on the board is left off the plan" 'undefined' \
  "$(evaluate "String($tracked[\"EPIC-5\"])")"
assert_eq "a project with no share of the tracks schedules none of its epics" '{"track":null,"begin":null,"projected":null}' \
  "$(evaluate 'pick(p.planOf([{id:"EPIC-1",status:"In FD",project:"PRJ-3"}], [{epic:"EPIC-1",status:"Backlog",complexity:5}], '"$TEAMS"', '"$TODAY"', '"$INSTANT"')["EPIC-1"], "track begin projected")')"
assert_eq "a number for the speed puts every epic on one track at it" '20740,20747' \
  "$(evaluate "[\"EPIC-1\",\"EPIC-2\"].map((id) => p.planOf($TRACKED, $TRACKED_CARDS, 5, $TODAY, $INSTANT)[id].begin).join()")"
assert_eq "the speed a target needs counts only the epics ahead of it on its own track" '6.3,6.3' \
  "$(evaluate "[\"EPIC-1\",\"EPIC-2\"].map((id) => p.planOf($TRACKED.map((e) => Object.assign({}, e, {target: \"2026-10-19\"})), $TRACKED_CARDS, $TEAMS, $TODAY, $INSTANT)[id].needed).join()")"

printf "\nTest group: priority wins over work in progress, and a displaced epic pauses where it stands\n"

STARTED='[{"id":"EPIC-1","status":"Tickets In Dev","project":"PRJ-1","rank":2},{"id":"EPIC-2","status":"In TD","project":"PRJ-1","rank":3},{"id":"EPIC-3","status":"In FD","project":"PRJ-1","rank":1}]'
STARTED_CARDS='[{"epic":"EPIC-1","status":"In Dev","complexity":5},{"epic":"EPIC-2","status":"In Dev","complexity":5,"dates":{"In Dev":"2026-10-12T10:00:00Z"}},{"epic":"EPIC-3","status":"Backlog","complexity":5}]'
one="p.planOf($STARTED, $STARTED_CARDS, {\"PRJ-1\":{\"tracks\":1,\"perWeek\":5}}, $TODAY, $INSTANT)"
two="p.planOf($STARTED, $STARTED_CARDS, {\"PRJ-1\":{\"tracks\":2,\"perWeek\":5}}, $TODAY, $INSTANT)"
assert_eq "an epic in Tickets In Dev, or with a card that reached In Dev, is in progress" 'true,true,false' \
  "$(evaluate "[\"EPIC-1\",\"EPIC-2\",\"EPIC-3\"].map((id) => $one[id].inProgress).join()")"
assert_eq "the highest epic takes the track though it has not started" '1@20740:null' \
  "$(evaluate "$one[\"EPIC-3\"].track + \"@\" + $one[\"EPIC-3\"].begin + \":\" + $one[\"EPIC-3\"].pausedUntil")"
assert_eq "and the epics in progress below it pause until the track frees, in priority order" '20747:20747,20754:20754' \
  "$(evaluate "[\"EPIC-1\",\"EPIC-2\"].map((id) => $one[id].begin + \":\" + $one[id].pausedUntil).join()")"
assert_eq "a second track lets the two highest run from today, and the third in progress pauses" '1@20740:null,2@20740:null,1@20747:20747' \
  "$(evaluate "[\"EPIC-3\",\"EPIC-1\",\"EPIC-2\"].map((id) => $two[id].track + \"@\" + $two[id].begin + \":\" + $two[id].pausedUntil).join()")"
assert_eq "an epic still in refinement leaves the free track to the next epic until its refinement ends" '1@20740,1@20747' \
  "$(evaluate 'Object.values(p.planOf([{id:"EPIC-1",status:"In FD",rank:1,start:"2026-10-19"},{id:"EPIC-2",status:"Tickets In Dev",rank:2}], [{epic:"EPIC-1",status:"Backlog",complexity:5},{epic:"EPIC-2",status:"In Dev",complexity:5}], 5, '"$TODAY"', '"$INSTANT"')).map((r) => r.track + "@" + r.begin).reverse().join()')"
assert_eq "an epic in progress that waits for its own start date is not paused" 'null' \
  "$(evaluate 'p.planOf([{id:"EPIC-1",status:"Tickets In Dev",start:"2026-10-20"}], [{epic:"EPIC-1",status:"In Dev",complexity:5}], 5, '"$TODAY"', '"$INSTANT"')["EPIC-1"].pausedUntil')"

assert_eq "a timebox in dev or done never puts its epic in progress" 'false,false' \
  "$(evaluate '[[{epic:"EPIC-1",type:"Timebox",status:"In Dev",dates:{"In Dev":"2026-10-12T10:00:00Z"}}],[{epic:"EPIC-1",type:"Timebox",status:"Done"}]].map((cards) => p.inProgressOf({status:"In FD"}, cards)).join()')"
assert_eq "while a feature or a bug that reached In Dev does" 'true,true' \
  "$(evaluate '[[{epic:"EPIC-1",type:"Feature",status:"In Dev",dates:{"In Dev":"2026-10-12T10:00:00Z"}}],[{epic:"EPIC-1",type:"Bug",status:"Done"}]].map((cards) => p.inProgressOf({status:"In FD"}, cards)).join()')"

printf "\nTest group: an epic is refined before it is delivered, and only its delivery takes a track\n"

PAST='[{"id":"EPIC-1","status":"Epic Done","start":"2026-08-01","dates":{"Tickets In Dev":"2026-08-11T10:00:00Z"}},{"id":"EPIC-2","status":"Tickets In Dev","start":"2026-09-01","dates":{"Tickets In Dev":"2026-09-21T10:00:00Z"}},{"id":"EPIC-3","status":"In FD","start":"2026-10-01"},{"id":"EPIC-4","status":"Backlog"}]'
assert_eq "the refinement average is the working days from an epic's start to its Tickets In Dev when it never had a Ready for Dev, over the epics that reached it" '{"days":10,"source":"measured","epics":2}' \
  "$(evaluate "p.refinementOf($PAST)")"
READY='[{"id":"EPIC-1","status":"Tickets In Dev","start":"2026-09-01","dates":{"Ready for Dev":"2026-09-05T10:00:00Z","Tickets In Dev":"2026-09-21T10:00:00Z"}},{"id":"EPIC-2","status":"Ready for Dev","start":"2026-09-01","dates":{"Ready for Dev":"2026-09-09T10:00:00Z"}}]'
assert_eq "an epic that reached Ready for Dev is measured to that stamp rather than to Tickets In Dev" '{"days":5,"source":"measured","epics":2}' \
  "$(evaluate "p.refinementOf($READY)")"
assert_eq "an epic in Ready for Dev counts as refined, its refinement ending that day" 'delivery,2026-09-09' \
  "$(evaluate '((row) => [row.phase, p.dayText(row.refineEnd)].join())(p.planOf([{id:"EPIC-1",status:"Ready for Dev",start:"2026-09-01",dates:{"Ready for Dev":"2026-09-09T10:00:00Z"}}], [{epic:"EPIC-1",status:"Backlog",complexity:5}], 5, '"$TODAY"', '"$INSTANT"')["EPIC-1"])')"
assert_eq "with no epic refined yet it is a default, and says so" '{"days":2,"source":"default","epics":0}' \
  "$(evaluate 'p.refinementOf([{status:"In FD",start:"2026-10-01"}])')"
REFINE='{days:10,source:"measured",epics:3}'
STAGES='[{"id":"EPIC-1","status":"Tickets In Dev","project":"PRJ-1","rank":1,"start":"2026-09-20","dates":{"Tickets In Dev":"2026-10-02T10:00:00Z"}},{"id":"EPIC-2","status":"In TD","project":"PRJ-1","rank":2,"start":"2026-10-09"},{"id":"EPIC-3","status":"Backlog","project":"PRJ-1","rank":3},{"id":"EPIC-4","status":"Backlog","project":"PRJ-1","rank":4},{"id":"EPIC-5","status":"In FD","project":"PRJ-1","rank":5,"start":"2026-09-01"}]'
STAGE_CARDS='[{"epic":"EPIC-1","status":"In Dev","complexity":5},{"epic":"EPIC-2","status":"Backlog","complexity":5}]'
staged="p.planOf($STAGES, $STAGE_CARDS, {\"PRJ-1\":{\"tracks\":2,\"perWeek\":5}}, $TODAY, $REFINE)"
assert_eq "each epic is in backlog, refinement, delivery or done" 'delivery,refinement,backlog,backlog,refinement' \
  "$(evaluate "[1,2,3,4,5].map((n) => $staged[\"EPIC-\" + n].phase).join()")"
assert_eq "refinement already done is drawn from its stamps" '{"refineStart":20716,"refineEnd":20728,"refineForecast":false}' \
  "$(evaluate "pick($staged[\"EPIC-1\"], \"refineStart refineEnd refineForecast\")")"
assert_eq "refinement under way is forecast to end the average in working days after its start" '{"refineStart":20735,"refineEnd":20749,"refineForecast":true}' \
  "$(evaluate "pick($staged[\"EPIC-2\"], \"refineStart refineEnd refineForecast\")")"
assert_eq "and one already past the average is forecast to end today" '20740' "$(evaluate "$staged[\"EPIC-5\"].refineEnd")"
assert_eq "its delivery begins no earlier than its refinement ends" '20749' "$(evaluate "$staged[\"EPIC-2\"].begin")"
assert_eq "every backlog epic starts refinement today, however many are in refinement already, as refinement has no limit" '20740:20754,20740:20754' \
  "$(evaluate "[3,4].map((n) => $staged[\"EPIC-\" + n].refineStart + \":\" + $staged[\"EPIC-\" + n].refineEnd).join()")"
assert_eq "refinement takes no track, so the epic in delivery runs from today beside it" '1@20740' \
  "$(evaluate "$staged[\"EPIC-1\"].track + \"@\" + $staged[\"EPIC-1\"].begin")"
assert_eq "a project with no tracks forecasts no refinement either" 'null' \
  "$(evaluate 'String(p.planOf([{id:"EPIC-1",status:"Backlog",project:"PRJ-1"}], [], {"PRJ-1":{tracks:0,perWeek:5}}, '"$TODAY"', '"$REFINE"')["EPIC-1"].refineStart)')"

printf "\nTest group: a blocked epic gives up its track to the next epic in priority\n"

BLOCKED='[{"id":"EPIC-1","status":"Tickets In Dev","project":"PRJ-1","rank":1,"start":"2026-09-20","blocked":"Waiting on the vendor","dates":{"Tickets In Dev":"2026-10-02T10:00:00Z"}},{"id":"EPIC-2","status":"In FD","project":"PRJ-1","rank":2},{"id":"EPIC-3","status":"Tickets In Dev","project":"PRJ-1","rank":3}]'
BLOCKED_CARDS='[{"epic":"EPIC-1","status":"In Dev","complexity":5},{"epic":"EPIC-2","status":"Backlog","complexity":5},{"epic":"EPIC-3","status":"In Dev","complexity":5,"blocked":"Needs a key"},{"epic":"EPIC-3","status":"Backlog","complexity":3,"blocked":"Needs a key too"},{"epic":"EPIC-3","status":"Done","complexity":2},{"epic":"EPIC-3","status":"In Dev","type":"Timebox"}]'
blocked="p.planOf($BLOCKED, $BLOCKED_CARDS, {\"PRJ-1\":{\"tracks\":1,\"perWeek\":5}}, $TODAY, $INSTANT)"
assert_eq "an epic is blocked by its own flag, or once every open feature or bug card on it is" 'epic,null,cards' \
  "$(evaluate "[1,2,3].map((n) => String($blocked[\"EPIC-\" + n].blocked)).join()")"
assert_eq "a blocked epic gives up its track, so the next epic in priority takes it from today" '1@20740' \
  "$(evaluate "$blocked[\"EPIC-2\"].track + \"@\" + $blocked[\"EPIC-2\"].begin")"
assert_eq "and is queued for the next track that frees after it, forecast as though unblocked by then, and not drawn paused" '{"track":1,"begin":20747,"projected":20753,"pausedUntil":null}' \
  "$(evaluate "pick($blocked[\"EPIC-1\"], \"track begin projected pausedUntil\")")"
assert_eq "blocked epics queue in priority order behind every unblocked one" '1@20754' \
  "$(evaluate "$blocked[\"EPIC-3\"].track + \"@\" + $blocked[\"EPIC-3\"].begin")"
assert_eq "the delivery a blocked epic already did is still drawn from the day it was refined" '{"phase":"delivery","refineEnd":20728,"refineForecast":false}' \
  "$(evaluate "pick($blocked[\"EPIC-1\"], \"phase refineEnd refineForecast\")")"
assert_eq "one open card left unblocked keeps the epic unblocked" 'null' \
  "$(evaluate 'String(p.blockedOf({status:"Tickets In Dev"}, [{status:"In Dev",blocked:"Needs a key"},{status:"Backlog"}]))')"
assert_eq "an epic with no open feature or bug card is never blocked by its cards" 'null,null' \
  "$(evaluate '[[], [{status:"In Dev",type:"Timebox",blocked:"Waiting"}]].map((cards) => String(p.blockedOf({status:"In FD"}, cards))).join()')"
assert_eq "a done epic is never blocked" 'null' \
  "$(evaluate 'String(p.blockedOf({status:"Epic Done",blocked:"Waiting"}, []))')"
assert_eq "a blocked epic in Backlog is still forecast to refine from today, as refinement takes no track" '{"refineStart":20740,"refineEnd":20740,"refineForecast":true}' \
  "$(evaluate 'pick(p.planOf([{id:"EPIC-1",status:"Backlog",project:"PRJ-1",blocked:"Waiting"}], [], {"PRJ-1":{tracks:1,perWeek:5}}, '"$TODAY"', '"$INSTANT"')["EPIC-1"], "refineStart refineEnd refineForecast")')"

SPANS_EPIC='{blocked_spans:[{from:"2026-10-01",to:"2026-10-03"},{from:"2026-10-12"}]}'
SPANS_CARDS='[{type:"Feature",blocked_spans:[{from:"2026-10-03",to:"2026-10-05"}]},{type:"Timebox",blocked_spans:[{from:"2026-09-01",to:"2026-09-02"}]},{type:"Bug",blocked_spans:[{from:"2026-10-07",to:"2026-10-08"}]}]'
assert_eq "an epic's blocked spells are its own and its feature and bug cards', merged where they meet, an open one running to today" \
  '2026-10-01..2026-10-05 2026-10-07..2026-10-08 2026-10-12..2026-10-14 open' \
  "$(evaluate 'p.blockedSpansOf('"$SPANS_EPIC"', '"$SPANS_CARDS"', '"$TODAY"').map((span) => p.dayText(span.from) + ".." + p.dayText(span.to) + (span.open ? " open" : "")).join(" ")')"
assert_eq "a card done while still flagged blocked stops its spell on the day it was done" '2026-10-01..2026-10-04' \
  "$(evaluate 'p.blockedSpansOf({}, [{type:"Feature",status:"Done",dates:{Done:"2026-10-04T10:00:00Z"},blocked_spans:[{from:"2026-10-01"}]}], '"$TODAY"').map((span) => p.dayText(span.from) + ".." + p.dayText(span.to) + (span.open ? " open" : "")).join(" ")')"
assert_eq "an epic never blocked has none" '0' "$(evaluate 'String(p.blockedSpansOf({}, [], '"$TODAY"').length)')"

printf "\nTest group: an epic's delivery waits for the epics it depends on\n"

DEPENDS='[{"id":"EPIC-1","status":"Tickets In Dev","project":"PRJ-1","rank":1,"dependent_on":["EPIC-2"]},{"id":"EPIC-2","status":"Tickets In Dev","project":"PRJ-1","rank":2},{"id":"EPIC-3","status":"Tickets In Dev","project":"PRJ-2","rank":3,"dependent_on":["EPIC-2","EPIC-9"]},{"id":"EPIC-9","status":"Epic Done","project":"PRJ-2"}]'
DEPENDS_CARDS='[{"epic":"EPIC-1","status":"Backlog","complexity":5},{"epic":"EPIC-2","status":"Backlog","complexity":3},{"epic":"EPIC-3","status":"Backlog","complexity":2}]'
depends="p.planOf($DEPENDS, $DEPENDS_CARDS, {\"PRJ-1\":{\"tracks\":2,\"perWeek\":5},\"PRJ-2\":{\"tracks\":1,\"perWeek\":5}}, $TODAY, $INSTANT)"
assert_eq "the epic it depends on starts today, though it is lower in priority" '{"track":1,"begin":20740,"projected":20742}' \
  "$(evaluate "pick($depends[\"EPIC-2\"], \"track begin projected\")")"
assert_eq "and the epic that depends on it starts on the next working day after it ends" '{"track":1,"begin":20745,"dependsOn":["EPIC-2"],"waitingOn":null,"pausedUntil":null}' \
  "$(evaluate "pick($depends[\"EPIC-1\"], \"track begin dependsOn waitingOn pausedUntil\")")"
assert_eq "an epic of another project waits for it too, and one in Epic Done holds nothing up" '{"begin":20745,"dependsOn":["EPIC-2"]}' \
  "$(evaluate "pick($depends[\"EPIC-3\"], \"begin dependsOn\")")"

WAITING='[{"id":"EPIC-1","status":"Tickets In Dev","project":"PRJ-1","rank":1,"blocked":"Waiting on the vendor"},{"id":"EPIC-2","status":"Tickets In Dev","project":"PRJ-1","rank":2,"dependent_on":["EPIC-1"]},{"id":"EPIC-3","status":"Tickets In Dev","project":"PRJ-1","rank":3},{"id":"EPIC-4","status":"Tickets In Dev","project":"PRJ-1","rank":4,"dependent_on":["EPIC-2"]}]'
WAITING_CARDS='[{"epic":"EPIC-1","status":"Backlog","complexity":2},{"epic":"EPIC-2","status":"Backlog","complexity":2},{"epic":"EPIC-3","status":"Backlog","complexity":2},{"epic":"EPIC-4","status":"Backlog","complexity":2}]'
waiting="p.planOf($WAITING, $WAITING_CARDS, {\"PRJ-1\":{\"tracks\":1,\"perWeek\":5}}, $TODAY, $INSTANT)"
assert_eq "an epic that depends on a blocked one waits on it, as does one further down the chain" 'EPIC-1,EPIC-1,null' \
  "$(evaluate "[2,4,3].map((n) => String($waiting[\"EPIC-\" + n].waitingOn)).join()")"
assert_eq "so the unblocked epic below them takes the track first" '20740' "$(evaluate "String($waiting[\"EPIC-3\"].begin)")"
assert_eq "and the blocked epic goes next, then each epic waiting on it after the one it depends on" '20742<20746<20748' \
  "$(evaluate "[1,2,4].map((n) => $waiting[\"EPIC-\" + n].begin).join(\"<\")")"

printf "\nTest group: an epic is late once its target passes with work open, or once its last card was done after it\n"

LATE_TEAM='{"PRJ-1":{tracks:1,perWeek:5},"PRJ-2":{tracks:0,perWeek:5}}'
assert_eq "a blocked epic with work open is late by how far past its target its forecast end falls" '10' \
  "$(evaluate 'p.planOf([{id:"EPIC-1",status:"Tickets In Dev",project:"PRJ-1",target:"2026-10-10",blocked:"Waiting"}], [{epic:"EPIC-1",status:"In Dev",complexity:5}], '"$LATE_TEAM"', '"$TODAY"', '"$INSTANT"')["EPIC-1"].late')"
assert_eq "and so is an unsized one, and one whose project has no tracks" '4,4' \
  "$(evaluate '[["PRJ-1",{}],["PRJ-2",{complexity:5}]].map(([project, size]) => p.planOf([{id:"EPIC-1",status:"In FD",project,target:"2026-10-10"}], [{epic:"EPIC-1",status:"Backlog",...size}], '"$LATE_TEAM"', '"$TODAY"', '"$INSTANT"')["EPIC-1"].late).join()')"
assert_eq "an epic whose cards are all done is late by the days its last card was done past its target, before it reaches Epic Done" '3,0' \
  "$(evaluate '["2026-10-08","2026-10-12"].map((target) => p.planOf([{id:"EPIC-1",status:"Tickets In Dev",project:"PRJ-1",target}], [{epic:"EPIC-1",status:"Done",complexity:3,dates:{Done:"2026-10-05T10:00:00Z"}},{epic:"EPIC-1",status:"Done",complexity:3,dates:{Done:"2026-10-11T10:00:00Z"}}], '"$LATE_TEAM"', '"$TODAY"', '"$INSTANT"')["EPIC-1"].late).join()')"
assert_eq "a target today is not passed yet" '0' \
  "$(evaluate 'p.lateOf(p.dayOf("2026-10-14"), {open:1,done:0}, [], '"$TODAY"')')"
assert_eq "an epic with no cards is never late, whatever its target" '0' \
  "$(evaluate 'p.lateOf(p.dayOf("2026-10-01"), {open:0,done:0}, [], '"$TODAY"')')"

printf "\nTest group: an epic pinned to a track waits for it\n"

PINNED='[{"id":"EPIC-1","status":"In FD","project":"PRJ-1","rank":1,"track":2},{"id":"EPIC-2","status":"In FD","project":"PRJ-1","rank":2,"track":2},{"id":"EPIC-3","status":"In FD","project":"PRJ-1","rank":3},{"id":"EPIC-4","status":"In FD","project":"PRJ-1","rank":4,"track":5}]'
PINNED_CARDS='[{"epic":"EPIC-1","status":"Backlog","complexity":5},{"epic":"EPIC-2","status":"Backlog","complexity":5},{"epic":"EPIC-3","status":"Backlog","complexity":5},{"epic":"EPIC-4","status":"Backlog","complexity":5}]'
pinned="p.planOf($PINNED, $PINNED_CARDS, {\"PRJ-1\":{\"tracks\":2,\"perWeek\":5}}, $TODAY, $INSTANT)"
assert_eq "a pinned epic waits for its track while another track is free" '2@20740,2@20747' \
  "$(evaluate "[\"EPIC-1\",\"EPIC-2\"].map((id) => $pinned[id].track + \"@\" + $pinned[id].begin).join()")"
assert_eq "and the next epic takes the free track" '1@20740' "$(evaluate "$pinned[\"EPIC-3\"].track + \"@\" + $pinned[\"EPIC-3\"].begin")"
assert_eq "a pin past the project's tracks is flagged and ignored" '{"pin":5,"pinIgnored":true,"track":1,"begin":20747}' \
  "$(evaluate "pick($pinned[\"EPIC-4\"], \"pin pinIgnored track begin\")")"

assert_eq "an epic the plan places leaves alone a track a pinned epic waits for" '2@20740,1@20740,1@20747' \
  "$(evaluate 'Object.values(p.planOf([{id:"EPIC-1",status:"Tickets In Dev",rank:1,project:"PRJ-1"},{id:"EPIC-2",status:"In FD",rank:2,project:"PRJ-1"},{id:"EPIC-3",status:"In FD",rank:3,track:1,project:"PRJ-1"}], [{epic:"EPIC-1",status:"In Dev",complexity:5},{epic:"EPIC-2",status:"Backlog",complexity:5},{epic:"EPIC-3",status:"Backlog",complexity:5}], {"PRJ-1":{tracks:2,perWeek:5}}, '"$TODAY"', '"$INSTANT"')).map((r) => r.track + "@" + r.begin).join()')"

printf "\nTest group: each project's speed a track comes from its own finished cards\n"

SPEED_EPICS='[{"id":"EPIC-1","status":"Tickets In Dev","project":"PRJ-1","dates":{"Tickets In Dev":"2026-08-01T10:00:00Z"}},{"id":"EPIC-2","status":"Tickets In Dev","project":"PRJ-1","dates":{"Tickets In Dev":"2026-08-01T10:00:00Z"}},{"id":"EPIC-3","status":"In FD","project":"PRJ-2"}]'
SPEED_CARDS='[{"epic":"EPIC-1","status":"Done","dates":{"Done":"2026-08-03T10:00:00Z"}},{"epic":"EPIC-1","status":"Done","complexity":12,"dates":{"Done":"2026-10-09T10:00:00Z"}},{"epic":"EPIC-2","status":"Done","complexity":1,"dates":{"Done":"2026-09-10T10:00:00Z"}},{"status":"Done","complexity":6,"dates":{"Done":"2026-10-12T10:00:00Z"}}]'
speeds="p.trackSpeedsOf($SPEED_CARDS, $SPEED_EPICS, [\"PRJ-1\",\"PRJ-2\"], [], $NOW)"
assert_eq "a project's average speed is split across the epics it had in progress on average" '{"perWeek":1.0833333333333335,"source":"measured","inProgress":2}' \
  "$(evaluate "pick($speeds.teams[\"PRJ-1\"], \"perWeek source inProgress\")")"
assert_eq "a project with no history takes the overall speed a track, and says so" '{"perWeek":1.5833333333333333,"source":"overall","inProgress":2}' \
  "$(evaluate "pick($speeds.teams[\"PRJ-2\"], \"perWeek source inProgress\")")"
assert_eq "a project's speed divides by the working days since its own first finished card, while the board's runs from the board's" '6,30' \
  "$(evaluate '((speeds) => [speeds.teams["PRJ-2"].speed.days, speeds.overall.speed.days].join())(p.trackSpeedsOf([{epic:"EPIC-1",status:"Done",complexity:2,dates:{Done:"2026-08-03T10:00:00Z"}},{epic:"EPIC-3",status:"Done",complexity:3,dates:{Done:"2026-10-07T10:00:00Z"}}], '"$SPEED_EPICS"', ["PRJ-1","PRJ-2"], [], '"$NOW"'))')"
assert_eq "a card with no epic and no project counts toward the overall speed alone" 'undefined,19' \
  "$(evaluate "[String($speeds.teams[\"\"]), $speeds.overall.speed.points].join()")"
assert_eq "an epic counts as in progress from its first card in dev until it is done" '0.5' \
  "$(evaluate 'p.epicsInProgressOver([{id:"EPIC-1",status:"Epic Done",dates:{"Epic Done":"2026-10-11T00:00:00Z"}}], [{epic:"EPIC-1",status:"Done",dates:{"In Dev":"2026-10-09T00:00:00Z","Done":"2026-10-10T00:00:00Z"}}], Date.parse("2026-10-07T00:00:00Z"), Date.parse("2026-10-11T00:00:00Z"))')"

printf "\nTest group: the forecast moves on working days alone, leaving a weekend and a break empty\n"

ONE='[{id:"EPIC-1",status:"In FD",project:"PRJ-1",rank:1,target:"2026-10-27"}]'
ONE_CARDS='[{epic:"EPIC-1",status:"Backlog",complexity:7}]'
ONE_TEAM='{"PRJ-1":{tracks:1,perWeek:5},"PRJ-2":{tracks:1,perWeek:5}}'
assert_eq "the first open day, the end of a run of open days and the open days in a span all step over a break and a weekend" '20745,7,0' \
  "$(evaluate '[p.openFrom(20740, [[20738,20743]]), p.afterOpen(20740, 4, [[20742,20744]]) - 20740, p.openDays(20740, 20746, [[20730,20750]])].join()')"
assert_eq "a forecast made at a weekend begins on the Monday, and two working days from a Friday end before the Tuesday" '20745,20746' \
  "$(evaluate '[p.planOf('"$ONE"', '"$ONE_CARDS"', '"$ONE_TEAM"', 20743, '"$INSTANT"')["EPIC-1"].begin, p.afterOpen(20742, 2, [])].join()')"
assert_eq "with no break an epic runs its working days straight through, over the weekend" '{"begin":20740,"projected":20748}' \
  "$(evaluate 'pick(p.planOf('"$ONE"', '"$ONE_CARDS"', '"$ONE_TEAM"', '"$TODAY"', '"$INSTANT"')["EPIC-1"], "begin projected")')"
assert_eq "a break in its way stretches it by the working days the break takes" '{"begin":20740,"projected":20749}' \
  "$(evaluate 'pick(p.planOf('"$ONE"', '"$ONE_CARDS"', '"$ONE_TEAM"', '"$TODAY"', '"$INSTANT"', [{from:"2026-10-16",to:"2026-10-18"}])["EPIC-1"], "begin projected")')"
assert_eq "an epic due to start during a break begins on the first working day after it" '{"begin":20742,"projected":20752}' \
  "$(evaluate 'pick(p.planOf('"$ONE"', '"$ONE_CARDS"', '"$ONE_TEAM"', '"$TODAY"', '"$INSTANT"', [{from:"2026-10-10",to:"2026-10-15"}])["EPIC-1"], "begin projected")')"
assert_eq "an epic held up by a break is not paused, as no higher epic took its track" 'null' \
  "$(evaluate 'p.planOf([{id:"EPIC-1",status:"Tickets In Dev",project:"PRJ-1"}], [{epic:"EPIC-1",status:"In Dev",complexity:7}], '"$ONE_TEAM"', '"$TODAY"', '"$INSTANT"', [{from:"2026-10-10",to:"2026-10-15"}])["EPIC-1"].pausedUntil')"
assert_eq "the speed a target needs counts only the working days a break leaves open" '3.5,4.4' \
  "$(evaluate '[[], [{from:"2026-10-16",to:"2026-10-19"}]].map((breaks) => p.planOf('"$ONE"', '"$ONE_CARDS"', '"$ONE_TEAM"', '"$TODAY"', '"$INSTANT"', breaks)["EPIC-1"].needed).join()')"
assert_eq "refinement still to come waits out a break too" '20747:20761' \
  "$(evaluate '(() => { const row = p.planOf([{id:"EPIC-1",status:"Backlog",project:"PRJ-1"}], [], '"$ONE_TEAM"', '"$TODAY"', {days:10,source:"measured",epics:1}, [{from:"2026-10-14",to:"2026-10-20"}])["EPIC-1"]; return row.refineStart + ":" + row.refineEnd; })()')"
assert_eq "and refinement under way ends the break's working days later" '20753' \
  "$(evaluate 'p.planOf([{id:"EPIC-1",status:"In FD",project:"PRJ-1",start:"2026-10-09"}], [], '"$ONE_TEAM"', '"$TODAY"', {days:10,source:"measured",epics:1}, [{from:"2026-10-15",to:"2026-10-17"}])["EPIC-1"].refineEnd')"

printf "\nTest group: the timeline spans what it shows, within its limits\n"

assert_eq "it opens on a Monday two weeks back and runs four weeks past the last date" \
  '{"first":20724,"last":20858,"clippedBefore":false,"clippedAfter":false}' "$(evaluate "p.spanOf([20830, null], $TODAY)")"
assert_eq "a plan running past five years is cut there and says so" 'true' \
  "$(evaluate "p.spanOf([$TODAY + 4000], $TODAY).clippedAfter")"
assert_eq "a date is the day it names" '2026-10-14' "$(evaluate "p.dayText($TODAY)")"
assert_eq "a late epic says how late in days" 'Delivered 1 day late,9 days late' \
  "$(evaluate '[p.lateText(1, true), p.lateText(9, false)].join()')"

finish
