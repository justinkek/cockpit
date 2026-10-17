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

printf "\nTest group: the average speed is the TR complexity done a week, or the sprint's speed, or a default\n"

DONE='[{"status":"Done","complexity":5,"dates":{"Done":"2026-10-12T10:00:00Z"}},{"status":"Done","complexity":3,"dates":{"Done":"2026-09-10T10:00:00Z"}},{"status":"Done","dates":{"Done":"2026-08-01T10:00:00Z"}},{"status":"In Dev","complexity":8,"dates":{"Done":"2026-10-13T10:00:00Z"}}]'
assert_eq "the average speed divides the points by the weeks something was finished in, never a week with nothing finished" \
  '{"perWeek":2.6666666666666665,"source":"measured","points":8,"weeks":3,"tickets":2,"uncounted":1,"timeboxes":0,"mondays":[20738,20703,20661]}' "$(evaluate "p.averageSpeedOf($DONE, [], $NOW)")"
assert_eq "a board with one week of finished cards divides by that one week" \
  '{"perWeek":8,"weeks":1}' \
  "$(evaluate 'pick(p.averageSpeedOf([{status:"Done",complexity:8,dates:{Done:"2026-09-30T12:00:00Z"}}], [], '"$NOW"'), "perWeek weeks")')"
WEEKLY='[7,14,21,28,35,42,49].map((back) => ({status:"Done",complexity:back,dates:{Done:new Date(Date.parse("2026-08-31T12:00:00Z") - back * 86400000).toISOString()}}))'
assert_eq "a break in the work reaches back past it for the last six weeks that finished something" \
  '{"perWeek":24.5,"points":147,"weeks":6}' \
  "$(evaluate "pick(p.averageSpeedOf($WEEKLY, [], $NOW), \"perWeek points weeks\")")"
assert_eq "a week counts once, however many cards it finished" '{"perWeek":4,"weeks":2}' \
  "$(evaluate 'pick(p.averageSpeedOf([{status:"Done",complexity:3,dates:{Done:"2026-10-12T12:00:00Z"}},{status:"Done",complexity:2,dates:{Done:"2026-10-13T12:00:00Z"}},{status:"Done",complexity:3,dates:{Done:"2026-06-03T12:00:00Z"}}], [], '"$NOW"'), "perWeek weeks")')"
assert_eq "a done card counts only its TR complexity, and one without it or a timebox is counted apart, whatever its estimate" '{"points":5,"tickets":1,"uncounted":2,"timeboxes":1}' \
  "$(evaluate 'pick(p.averageSpeedOf([{status:"Done",complexity:5,estimate:8,dates:{Done:"2026-10-01T12:00:00Z"}},{status:"Done",estimate:3,dates:{Done:"2026-10-01T12:00:00Z"}},{status:"Done",dates:{Done:"2026-10-02T12:00:00Z"}},{status:"Done",type:"Timebox",complexity:2,dates:{Done:"2026-10-03T12:00:00Z"}}], [], '"$NOW"'), "points tickets uncounted timeboxes")')"
assert_eq "a board done only without complexity has no measured speed" 'default' \
  "$(evaluate 'p.averageSpeedOf([{status:"Done",estimate:3,dates:{Done:"2026-10-01T12:00:00Z"}}], [], '"$NOW"').source')"
assert_eq "with nothing done, the current sprint's speed a day makes the average speed a week" \
  '{"perWeek":12.5,"source":"sprint","points":0,"weeks":0,"tickets":0,"uncounted":0,"timeboxes":0,"mondays":[]}' \
  "$(evaluate 'p.averageSpeedOf([], [{start:"2026-10-12",end:"2026-10-23",speed:2.5}], '"$NOW"')')"
assert_eq "with no sprint speed either, the average speed is the default" '{"perWeek":10,"source":"default","points":0,"weeks":0,"tickets":0,"uncounted":0,"timeboxes":0,"mondays":[]}' \
  "$(evaluate 'p.averageSpeedOf([], [{start:"2026-10-12",end:"2026-10-23",speed:0}], '"$NOW"')')"

printf "\nTest group: a break leaves its weeks out of the average speed\n"

assert_eq "breaks become day spans, the board's and the project's own, overlapping ones merged" '[[20730,20740],[20760,20760]]' \
  "$(evaluate 'p.daysOff([{from:"2026-10-04",to:"2026-10-10",project:null},{from:"2026-10-08",to:"2026-10-14",project:"PRJ-1"},{from:"2026-11-03",to:"2026-11-03",project:null},{from:"2026-10-20",to:"2026-10-30",project:"PRJ-2"}], "PRJ-1")')"
assert_eq "a project's break is never the board's" '[[20730,20736]]' \
  "$(evaluate 'p.daysOff([{from:"2026-10-04",to:"2026-10-10",project:null},{from:"2026-10-20",to:"2026-10-30",project:"PRJ-2"}], null)')"
BROKEN='[{status:"Done",complexity:5,dates:{Done:"2026-10-12T12:00:00Z"}},{status:"Done",complexity:3,dates:{Done:"2026-10-07T12:00:00Z"}},{status:"Done",complexity:4,dates:{Done:"2026-09-30T12:00:00Z"}}]'
assert_eq "a week whose working days all fall in a break never counts, though something was finished in it" '{"perWeek":4.5,"points":9,"weeks":2}' \
  "$(evaluate 'pick(p.averageSpeedOf('"$BROKEN"', [], '"$NOW"', p.daysOff([{from:"2026-10-05",to:"2026-10-09",project:null}], null)), "perWeek points weeks")')"
assert_eq "a break over part of a week leaves the week counted" '{"perWeek":4,"points":12,"weeks":3}' \
  "$(evaluate 'pick(p.averageSpeedOf('"$BROKEN"', [], '"$NOW"', p.daysOff([{from:"2026-10-05",to:"2026-10-07",project:null}], null)), "perWeek points weeks")')"
BREAK_EPICS='[{"id":"EPIC-1","status":"Tickets In Dev","project":"PRJ-1"},{"id":"EPIC-2","status":"Tickets In Dev","project":"PRJ-2"}]'
BREAK_CARDS='[{"epic":"EPIC-1","status":"Done","complexity":6,"dates":{"Done":"2026-10-12T12:00:00Z"}},{"epic":"EPIC-1","status":"Done","complexity":2,"dates":{"Done":"2026-10-07T12:00:00Z"}},{"epic":"EPIC-2","status":"Done","complexity":4,"dates":{"Done":"2026-10-07T12:00:00Z"}}]'
broken='p.trackSpeedsOf('"$BREAK_CARDS"', '"$BREAK_EPICS"', ["PRJ-1","PRJ-2"], [], '"$NOW"', [{from:"2026-10-05",to:"2026-10-09",project:"PRJ-1"}])'
assert_eq "a project's break leaves its weeks out of that project's speed alone" '6,4,12' \
  "$(evaluate "[$broken.teams[\"PRJ-1\"].speed.perWeek, $broken.teams[\"PRJ-2\"].speed.perWeek, $broken.overall.speed.points].join()")"

SPRINT='{start:"2026-09-28",end:"2026-10-11"}'
assert_eq "a sprint delivered the TR complexity of the cards done within its dates, a week, counting the rest beside it" \
  '{"points":8,"tickets":2,"uncounted":1,"timeboxes":1,"perWeek":4}' \
  "$(evaluate 'p.deliveredIn('"$SPRINT"', [{status:"Done",complexity:5,dates:{Done:"2026-09-28T09:00:00Z"}},{status:"Done",complexity:3,dates:{Done:"2026-10-11T17:00:00Z"}},{status:"Done",complexity:8,dates:{Done:"2026-10-12T09:00:00Z"}},{status:"Done",estimate:3,dates:{Done:"2026-10-01T09:00:00Z"}},{status:"Done",type:"Timebox",dates:{Done:"2026-10-01T09:00:00Z"}},{status:"In Dev",complexity:2,dates:{Done:"2026-10-01T09:00:00Z"}}])')"
assert_eq "a sprint with no dates has no speed" 'null' "$(evaluate 'String(p.deliveredIn({start:null,end:null}, []).perWeek)')"

printf "\nTest group: epics are scheduled one after another in plan order\n"

EPICS='[{"id":"EPIC-2","status":"In FD","rank":2,"target":"2026-10-31"},{"id":"EPIC-1","status":"Tickets In Dev","rank":1,"start":"2026-10-01","target":"2026-10-25","confidence":"On track"},{"id":"EPIC-3","status":"In FD"},{"id":"EPIC-4","status":"Epic Done","target":"2026-10-01","dates":{"Epic Done":"2026-10-05T10:00:00Z"}},{"id":"EPIC-5","status":"In TD","start":"2026-12-01","target":"2026-12-31","rank":3}]'
PLAN_CARDS='[{"epic":"EPIC-1","status":"In Dev","complexity":13},{"epic":"EPIC-1","status":"Done","complexity":8},{"epic":"EPIC-2","status":"Backlog","estimate":3},{"epic":"EPIC-5","status":"Backlog","complexity":5},{"epic":"EPIC-4","status":"Done","complexity":3}]'
rows="p.planOf($EPICS, $PLAN_CARDS, 7, $TODAY, $INSTANT)"
assert_eq "the plan order is the plan rank, then the target, then the id" 'EPIC-1,EPIC-2,EPIC-5,EPIC-4,EPIC-3' \
  "$(evaluate "p.planOrder($EPICS).map((e) => e.id).join()")"
assert_eq "the first epic runs from today for its points at the average speed, its last day of work its projected end, here past its target" '{"begin":20740,"projected":20752,"late":1}' \
  "$(evaluate "pick($rows[\"EPIC-1\"], \"begin projected late\")")"
assert_eq "the next one starts the day after the one ahead ends" '{"begin":20753,"projected":20755,"late":0}' \
  "$(evaluate "pick($rows[\"EPIC-2\"], \"begin projected late\")")"
assert_eq "an epic in refinement is not delivered before its refinement ends" '{"begin":20788,"projected":20792,"late":0}' \
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
  "$(evaluate 'p.planOf([{id:"EPIC-1",status:"In FD",target:"2026-10-15",confidence:"At risk - no plan"}], [{epic:"EPIC-1",status:"Backlog",complexity:5}], 7, '"$TODAY"', '"$INSTANT"')["EPIC-1"].atRisk')"
assert_eq "a target in the past needs more than any speed" 'true,1' \
  "$(evaluate 'Object.values(p.planOf([{id:"EPIC-1",status:"In FD",target:"2026-10-01"}], [{epic:"EPIC-1",status:"Backlog",complexity:5}], 7, '"$TODAY"', '"$INSTANT"')).map((r) => [r.needed === Infinity, r.late > 0 ? 1 : 0]).flat().join()')"
assert_eq "an epic whose cards are all done ends today and takes no time from the plan" '20740,20765' \
  "$(evaluate 'Object.values(p.planOf([{id:"EPIC-1",status:"In FD",rank:1},{id:"EPIC-2",status:"In FD",rank:2},{id:"EPIC-3",status:"In FD",rank:3}], [{epic:"EPIC-1",status:"In Dev",complexity:13},{epic:"EPIC-2",status:"Done",complexity:5},{epic:"EPIC-3",status:"Backlog",complexity:13}], 7, '"$TODAY"', '"$INSTANT"')).map((r) => r.projected).slice(1).join()')"
assert_eq "an epic whose open cards are all unsized has no projection, takes no time from the plan and counts them" '{"projected":null,"unsized":2,"next":20740}' \
  "$(evaluate 'Object.values(p.planOf([{id:"EPIC-1",status:"In FD",rank:1},{id:"EPIC-2",status:"In FD",rank:2}], [{epic:"EPIC-1",status:"Backlog"},{epic:"EPIC-1",status:"In BR"},{epic:"EPIC-2",status:"Backlog",complexity:5}], 7, '"$TODAY"', '"$INSTANT"')).reduce((all, r) => r.id === "EPIC-1" ? {...all, projected: r.projected, unsized: r.remaining.unsized} : {...all, next: r.begin}, {})')"
assert_eq "an unsized card leaves the date to the cards that are sized" '20744' \
  "$(evaluate 'p.planOf([{id:"EPIC-1",status:"In FD"}], [{epic:"EPIC-1",status:"Backlog",complexity:5},{epic:"EPIC-1",status:"Backlog"}], 7, '"$TODAY"', '"$INSTANT"')["EPIC-1"].projected')"
assert_eq "an epic with only a timebox open counts nothing unsized" '0' \
  "$(evaluate 'p.planOf([{id:"EPIC-1",status:"In FD"}], [{epic:"EPIC-1",status:"Backlog",type:"Timebox"}], 7, '"$TODAY"', '"$INSTANT"')["EPIC-1"].remaining.unsized')"
assert_eq "a start after the target is read as backwards" 'true' \
  "$(evaluate 'p.planOf([{id:"EPIC-1",status:"In FD",start:"2026-11-01",target:"2026-10-20"}], [], 7, '"$TODAY"', '"$INSTANT"')["EPIC-1"].backwards')"
assert_eq "an epic whose points fit exactly by its target ends on it, not a day late" '{"projected":20746,"late":0}' \
  "$(evaluate 'pick(p.planOf([{id:"EPIC-1",status:"In FD",target:"2026-10-20"}], [{epic:"EPIC-1",status:"Backlog",complexity:7}], 7, '"$TODAY"', '"$INSTANT"')["EPIC-1"], "projected late")')"
assert_eq "an average speed of zero is held above zero rather than dividing by it" 'true' \
  "$(evaluate 'Number.isFinite(p.planOf([{id:"EPIC-1",status:"In FD"}], [{epic:"EPIC-1",status:"Backlog",complexity:5}], 0, '"$TODAY"', '"$INSTANT"')["EPIC-1"].projected)')"

printf "\nTest group: each project runs its epics on its own tracks\n"

TEAMS='{"PRJ-1":{"tracks":2,"perWeek":7},"PRJ-2":{"tracks":1,"perWeek":7},"PRJ-3":{"tracks":0,"perWeek":7}}'
TRACKED='[{"id":"EPIC-1","status":"In FD","project":"PRJ-1","rank":1},{"id":"EPIC-2","status":"In FD","project":"PRJ-1","rank":2},{"id":"EPIC-3","status":"In FD","project":"PRJ-1","rank":3},{"id":"EPIC-4","status":"In FD","project":"PRJ-2","rank":4},{"id":"EPIC-5","status":"In FD","project":"PRJ-9","rank":5}]'
TRACKED_CARDS='[{"epic":"EPIC-1","status":"Backlog","complexity":5},{"epic":"EPIC-2","status":"Backlog","complexity":5},{"epic":"EPIC-3","status":"Backlog","complexity":5},{"epic":"EPIC-4","status":"Backlog","complexity":5},{"epic":"EPIC-5","status":"Backlog","complexity":5}]'
tracked="p.planOf($TRACKED, $TRACKED_CARDS, $TEAMS, $TODAY, $INSTANT)"
assert_eq "two tracks run the first two epics side by side from today, and the third takes the first track to free" '1@20740,2@20740,1@20745' \
  "$(evaluate "[\"EPIC-1\",\"EPIC-2\",\"EPIC-3\"].map((id) => $tracked[id].track + \"@\" + $tracked[id].begin).join()")"
assert_eq "another project never waits on the first one" '1@20740' \
  "$(evaluate "$tracked[\"EPIC-4\"].track + \"@\" + $tracked[\"EPIC-4\"].begin")"
assert_eq "an epic whose project is not on the board is left off the plan" 'undefined' \
  "$(evaluate "String($tracked[\"EPIC-5\"])")"
assert_eq "a project with no share of the tracks schedules none of its epics" '{"track":null,"begin":null,"projected":null}' \
  "$(evaluate 'pick(p.planOf([{id:"EPIC-1",status:"In FD",project:"PRJ-3"}], [{epic:"EPIC-1",status:"Backlog",complexity:5}], '"$TEAMS"', '"$TODAY"', '"$INSTANT"')["EPIC-1"], "track begin projected")')"
assert_eq "a number for the speed puts every epic on one track at it" '20740,20745' \
  "$(evaluate "[\"EPIC-1\",\"EPIC-2\"].map((id) => p.planOf($TRACKED, $TRACKED_CARDS, 7, $TODAY, $INSTANT)[id].begin).join()")"
assert_eq "the speed a target needs counts only the epics ahead of it on its own track" '5.8,5.8' \
  "$(evaluate "[\"EPIC-1\",\"EPIC-2\"].map((id) => p.planOf($TRACKED.map((e) => Object.assign({}, e, {target: \"2026-10-19\"})), $TRACKED_CARDS, $TEAMS, $TODAY, $INSTANT)[id].needed).join()")"

printf "\nTest group: priority wins over work in progress, and a displaced epic pauses where it stands\n"

STARTED='[{"id":"EPIC-1","status":"Tickets In Dev","project":"PRJ-1","rank":2},{"id":"EPIC-2","status":"In TD","project":"PRJ-1","rank":3},{"id":"EPIC-3","status":"In FD","project":"PRJ-1","rank":1}]'
STARTED_CARDS='[{"epic":"EPIC-1","status":"In Dev","complexity":5},{"epic":"EPIC-2","status":"In Dev","complexity":5,"dates":{"In Dev":"2026-10-12T10:00:00Z"}},{"epic":"EPIC-3","status":"Backlog","complexity":5}]'
one="p.planOf($STARTED, $STARTED_CARDS, {\"PRJ-1\":{\"tracks\":1,\"perWeek\":7}}, $TODAY, $INSTANT)"
two="p.planOf($STARTED, $STARTED_CARDS, {\"PRJ-1\":{\"tracks\":2,\"perWeek\":7}}, $TODAY, $INSTANT)"
assert_eq "an epic in Tickets In Dev, or with a card that reached In Dev, is in progress" 'true,true,false' \
  "$(evaluate "[\"EPIC-1\",\"EPIC-2\",\"EPIC-3\"].map((id) => $one[id].inProgress).join()")"
assert_eq "the highest epic takes the track though it has not started" '1@20740:null' \
  "$(evaluate "$one[\"EPIC-3\"].track + \"@\" + $one[\"EPIC-3\"].begin + \":\" + $one[\"EPIC-3\"].pausedUntil")"
assert_eq "and the epics in progress below it pause until the track frees, in priority order" '20745:20745,20750:20750' \
  "$(evaluate "[\"EPIC-1\",\"EPIC-2\"].map((id) => $one[id].begin + \":\" + $one[id].pausedUntil).join()")"
assert_eq "a second track lets the two highest run from today, and the third in progress pauses" '1@20740:null,2@20740:null,1@20745:20745' \
  "$(evaluate "[\"EPIC-3\",\"EPIC-1\",\"EPIC-2\"].map((id) => $two[id].track + \"@\" + $two[id].begin + \":\" + $two[id].pausedUntil).join()")"
assert_eq "an epic still in refinement leaves the free track to the next epic until its refinement ends" '1@20740,1@20745' \
  "$(evaluate 'Object.values(p.planOf([{id:"EPIC-1",status:"In FD",rank:1,start:"2026-10-19"},{id:"EPIC-2",status:"Tickets In Dev",rank:2}], [{epic:"EPIC-1",status:"Backlog",complexity:5},{epic:"EPIC-2",status:"In Dev",complexity:5}], 7, '"$TODAY"', '"$INSTANT"')).map((r) => r.track + "@" + r.begin).reverse().join()')"
assert_eq "an epic in progress that waits for its own start date is not paused" 'null' \
  "$(evaluate 'p.planOf([{id:"EPIC-1",status:"Tickets In Dev",start:"2026-10-20"}], [{epic:"EPIC-1",status:"In Dev",complexity:5}], 7, '"$TODAY"', '"$INSTANT"')["EPIC-1"].pausedUntil')"

assert_eq "a timebox in dev or done never puts its epic in progress" 'false,false' \
  "$(evaluate '[[{epic:"EPIC-1",type:"Timebox",status:"In Dev",dates:{"In Dev":"2026-10-12T10:00:00Z"}}],[{epic:"EPIC-1",type:"Timebox",status:"Done"}]].map((cards) => p.inProgressOf({status:"In FD"}, cards)).join()')"
assert_eq "while a feature or a bug that reached In Dev does" 'true,true' \
  "$(evaluate '[[{epic:"EPIC-1",type:"Feature",status:"In Dev",dates:{"In Dev":"2026-10-12T10:00:00Z"}}],[{epic:"EPIC-1",type:"Bug",status:"Done"}]].map((cards) => p.inProgressOf({status:"In FD"}, cards)).join()')"

printf "\nTest group: an epic is refined before it is delivered, and only its delivery takes a track\n"

PAST='[{"id":"EPIC-1","status":"Epic Done","start":"2026-08-01","dates":{"Tickets In Dev":"2026-08-11T10:00:00Z"}},{"id":"EPIC-2","status":"Tickets In Dev","start":"2026-09-01","dates":{"Tickets In Dev":"2026-09-21T10:00:00Z"}},{"id":"EPIC-3","status":"In FD","start":"2026-10-01"},{"id":"EPIC-4","status":"Backlog"}]'
assert_eq "the refinement average is the days from an epic's start to its Tickets In Dev, over the epics that reached it" '{"days":15,"source":"measured","epics":2}' \
  "$(evaluate "p.refinementOf($PAST)")"
assert_eq "with no epic refined yet it is a default, and says so" '{"days":2,"source":"default","epics":0}' \
  "$(evaluate 'p.refinementOf([{status:"In FD",start:"2026-10-01"}])')"
REFINE='{days:10,source:"measured",epics:3}'
STAGES='[{"id":"EPIC-1","status":"Tickets In Dev","project":"PRJ-1","rank":1,"start":"2026-09-20","dates":{"Tickets In Dev":"2026-10-02T10:00:00Z"}},{"id":"EPIC-2","status":"In TD","project":"PRJ-1","rank":2,"start":"2026-10-09"},{"id":"EPIC-3","status":"Backlog","project":"PRJ-1","rank":3},{"id":"EPIC-4","status":"Backlog","project":"PRJ-1","rank":4},{"id":"EPIC-5","status":"In FD","project":"PRJ-1","rank":5,"start":"2026-09-01"}]'
STAGE_CARDS='[{"epic":"EPIC-1","status":"In Dev","complexity":5},{"epic":"EPIC-2","status":"Backlog","complexity":5}]'
staged="p.planOf($STAGES, $STAGE_CARDS, {\"PRJ-1\":{\"tracks\":2,\"perWeek\":7}}, $TODAY, $REFINE)"
assert_eq "each epic is in backlog, refinement, delivery or done" 'delivery,refinement,backlog,backlog,refinement' \
  "$(evaluate "[1,2,3,4,5].map((n) => $staged[\"EPIC-\" + n].phase).join()")"
assert_eq "refinement already done is drawn from its stamps" '{"refineStart":20716,"refineEnd":20728,"refineForecast":false}' \
  "$(evaluate "pick($staged[\"EPIC-1\"], \"refineStart refineEnd refineForecast\")")"
assert_eq "refinement under way is forecast to end the average after its start" '{"refineStart":20735,"refineEnd":20745,"refineForecast":true}' \
  "$(evaluate "pick($staged[\"EPIC-2\"], \"refineStart refineEnd refineForecast\")")"
assert_eq "and one already past the average is forecast to end today" '20740' "$(evaluate "$staged[\"EPIC-5\"].refineEnd")"
assert_eq "its delivery begins no earlier than its refinement ends" '20745' "$(evaluate "$staged[\"EPIC-2\"].begin")"
assert_eq "every backlog epic starts refinement today, however many are in refinement already, as refinement has no limit" '20740:20750,20740:20750' \
  "$(evaluate "[3,4].map((n) => $staged[\"EPIC-\" + n].refineStart + \":\" + $staged[\"EPIC-\" + n].refineEnd).join()")"
assert_eq "refinement takes no track, so the epic in delivery runs from today beside it" '1@20740' \
  "$(evaluate "$staged[\"EPIC-1\"].track + \"@\" + $staged[\"EPIC-1\"].begin")"
assert_eq "a project with no tracks forecasts no refinement either" 'null' \
  "$(evaluate 'String(p.planOf([{id:"EPIC-1",status:"Backlog",project:"PRJ-1"}], [], {"PRJ-1":{tracks:0,perWeek:7}}, '"$TODAY"', '"$REFINE"')["EPIC-1"].refineStart)')"

printf "\nTest group: an epic pinned to a track waits for it\n"

PINNED='[{"id":"EPIC-1","status":"In FD","project":"PRJ-1","rank":1,"track":2},{"id":"EPIC-2","status":"In FD","project":"PRJ-1","rank":2,"track":2},{"id":"EPIC-3","status":"In FD","project":"PRJ-1","rank":3},{"id":"EPIC-4","status":"In FD","project":"PRJ-1","rank":4,"track":5}]'
PINNED_CARDS='[{"epic":"EPIC-1","status":"Backlog","complexity":5},{"epic":"EPIC-2","status":"Backlog","complexity":5},{"epic":"EPIC-3","status":"Backlog","complexity":5},{"epic":"EPIC-4","status":"Backlog","complexity":5}]'
pinned="p.planOf($PINNED, $PINNED_CARDS, {\"PRJ-1\":{\"tracks\":2,\"perWeek\":7}}, $TODAY, $INSTANT)"
assert_eq "a pinned epic waits for its track while another track is free" '2@20740,2@20745' \
  "$(evaluate "[\"EPIC-1\",\"EPIC-2\"].map((id) => $pinned[id].track + \"@\" + $pinned[id].begin).join()")"
assert_eq "and the next epic takes the free track" '1@20740' "$(evaluate "$pinned[\"EPIC-3\"].track + \"@\" + $pinned[\"EPIC-3\"].begin")"
assert_eq "a pin past the project's tracks is flagged and ignored" '{"pin":5,"pinIgnored":true,"track":1,"begin":20745}' \
  "$(evaluate "pick($pinned[\"EPIC-4\"], \"pin pinIgnored track begin\")")"

assert_eq "an epic the plan places leaves alone a track a pinned epic waits for" '2@20740,1@20740,1@20745' \
  "$(evaluate 'Object.values(p.planOf([{id:"EPIC-1",status:"Tickets In Dev",rank:1,project:"PRJ-1"},{id:"EPIC-2",status:"In FD",rank:2,project:"PRJ-1"},{id:"EPIC-3",status:"In FD",rank:3,track:1,project:"PRJ-1"}], [{epic:"EPIC-1",status:"In Dev",complexity:5},{epic:"EPIC-2",status:"Backlog",complexity:5},{epic:"EPIC-3",status:"Backlog",complexity:5}], {"PRJ-1":{tracks:2,perWeek:7}}, '"$TODAY"', '"$INSTANT"')).map((r) => r.track + "@" + r.begin).join()')"

printf "\nTest group: each project's speed a track comes from its own finished cards\n"

SPEED_EPICS='[{"id":"EPIC-1","status":"Tickets In Dev","project":"PRJ-1","dates":{"Tickets In Dev":"2026-08-01T10:00:00Z"}},{"id":"EPIC-2","status":"Tickets In Dev","project":"PRJ-1","dates":{"Tickets In Dev":"2026-08-01T10:00:00Z"}},{"id":"EPIC-3","status":"In FD","project":"PRJ-2"}]'
SPEED_CARDS='[{"epic":"EPIC-1","status":"Done","complexity":12,"dates":{"Done":"2026-10-10T10:00:00Z"}},{"epic":"EPIC-2","status":"Done","complexity":1,"dates":{"Done":"2026-08-05T10:00:00Z"}},{"status":"Done","complexity":6,"dates":{"Done":"2026-10-12T10:00:00Z"}}]'
speeds="p.trackSpeedsOf($SPEED_CARDS, $SPEED_EPICS, [\"PRJ-1\",\"PRJ-2\"], [], $NOW)"
assert_eq "a project's average speed is split across the epics it had in progress on average" '{"perWeek":3.25,"source":"measured","inProgress":2}' \
  "$(evaluate "pick($speeds.teams[\"PRJ-1\"], \"perWeek source inProgress\")")"
assert_eq "a project with no history takes the overall speed a track, and says so" '{"perWeek":3.1666666666666665,"source":"overall","inProgress":2}' \
  "$(evaluate "pick($speeds.teams[\"PRJ-2\"], \"perWeek source inProgress\")")"
assert_eq "a card with no epic and no project counts toward the overall speed alone" 'undefined,19' \
  "$(evaluate "[String($speeds.teams[\"\"]), $speeds.overall.speed.points].join()")"
assert_eq "an epic counts as in progress from its first card in dev until it is done" '0.5' \
  "$(evaluate 'p.epicsInProgressOver([{id:"EPIC-1",status:"Epic Done",dates:{"Epic Done":"2026-10-11T00:00:00Z"}}], [{epic:"EPIC-1",status:"Done",dates:{"In Dev":"2026-10-09T00:00:00Z","Done":"2026-10-10T00:00:00Z"}}], Date.parse("2026-10-07T00:00:00Z"), Date.parse("2026-10-11T00:00:00Z"))')"

printf "\nTest group: the forecast leaves a break's days empty\n"

ONE='[{id:"EPIC-1",status:"In FD",project:"PRJ-1",rank:1,target:"2026-10-27"}]'
ONE_CARDS='[{epic:"EPIC-1",status:"Backlog",complexity:7}]'
ONE_TEAM='{"PRJ-1":{tracks:1,perWeek:7},"PRJ-2":{tracks:1,perWeek:7}}'
assert_eq "the first open day, the end of a run of open days and the open days in a span all step over a break" '20744,7,0' \
  "$(evaluate '[p.openFrom(20740, [[20738,20743]]), p.afterOpen(20740, 4, [[20742,20744]]) - 20740, p.openDays(20740, 20746, [[20730,20750]])].join()')"
assert_eq "with no break an epic runs its days straight through" '{"begin":20740,"projected":20746}' \
  "$(evaluate 'pick(p.planOf('"$ONE"', '"$ONE_CARDS"', '"$ONE_TEAM"', '"$TODAY"', '"$INSTANT"')["EPIC-1"], "begin projected")')"
assert_eq "a board-wide break in its way stretches it by the break's days" '{"begin":20740,"projected":20749}' \
  "$(evaluate 'pick(p.planOf('"$ONE"', '"$ONE_CARDS"', '"$ONE_TEAM"', '"$TODAY"', '"$INSTANT"', [{from:"2026-10-16",to:"2026-10-18",project:null}])["EPIC-1"], "begin projected")')"
assert_eq "an epic due to start during a break begins the day after it" '{"begin":20742,"projected":20748}' \
  "$(evaluate 'pick(p.planOf('"$ONE"', '"$ONE_CARDS"', '"$ONE_TEAM"', '"$TODAY"', '"$INSTANT"', [{from:"2026-10-10",to:"2026-10-15",project:null}])["EPIC-1"], "begin projected")')"
assert_eq "an epic held up by a break is not paused, as no higher epic took its track" 'null' \
  "$(evaluate 'p.planOf([{id:"EPIC-1",status:"Tickets In Dev",project:"PRJ-1"}], [{epic:"EPIC-1",status:"In Dev",complexity:7}], '"$ONE_TEAM"', '"$TODAY"', '"$INSTANT"', [{from:"2026-10-10",to:"2026-10-15",project:null}])["EPIC-1"].pausedUntil')"
assert_eq "a project's break stretches its own epics and no other project's" '20749,20746' \
  "$(evaluate '(() => { const rows = p.planOf([...'"$ONE"', {id:"EPIC-2",status:"In FD",project:"PRJ-2",rank:2}], [...'"$ONE_CARDS"', {epic:"EPIC-2",status:"Backlog",complexity:7}], '"$ONE_TEAM"', '"$TODAY"', '"$INSTANT"', [{from:"2026-10-16",to:"2026-10-18",project:"PRJ-1"}]); return [rows["EPIC-1"].projected, rows["EPIC-2"].projected].join(); })()')"
assert_eq "the speed a target needs counts only the days a break leaves open" '3.5,4.9' \
  "$(evaluate '[[], [{from:"2026-10-16",to:"2026-10-19",project:null}]].map((breaks) => p.planOf('"$ONE"', '"$ONE_CARDS"', '"$ONE_TEAM"', '"$TODAY"', '"$INSTANT"', breaks)["EPIC-1"].needed).join()')"
assert_eq "refinement still to come waits out a break too" '20747:20757' \
  "$(evaluate '(() => { const row = p.planOf([{id:"EPIC-1",status:"Backlog",project:"PRJ-1"}], [], '"$ONE_TEAM"', '"$TODAY"', {days:10,source:"measured",epics:1}, [{from:"2026-10-14",to:"2026-10-20",project:null}])["EPIC-1"]; return row.refineStart + ":" + row.refineEnd; })()')"
assert_eq "and refinement under way ends the break's days later" '20748' \
  "$(evaluate 'p.planOf([{id:"EPIC-1",status:"In FD",project:"PRJ-1",start:"2026-10-09"}], [], '"$ONE_TEAM"', '"$TODAY"', {days:10,source:"measured",epics:1}, [{from:"2026-10-15",to:"2026-10-17",project:null}])["EPIC-1"].refineEnd')"

printf "\nTest group: the timeline spans what it shows, within its limits\n"

assert_eq "it opens on a Monday two weeks back and runs four weeks past the last date" \
  '{"first":20724,"last":20858,"clippedBefore":false,"clippedAfter":false}' "$(evaluate "p.spanOf([20830, null], $TODAY)")"
assert_eq "a plan running past five years is cut there and says so" 'true' \
  "$(evaluate "p.spanOf([$TODAY + 4000], $TODAY).clippedAfter")"
assert_eq "a date is the day it names" '2026-10-14' "$(evaluate "p.dayText($TODAY)")"
assert_eq "a late epic says how late in days" 'Delivered 1 day late,9 days late' \
  "$(evaluate '[p.lateText(1, true), p.lateText(9, false)].join()')"

finish
