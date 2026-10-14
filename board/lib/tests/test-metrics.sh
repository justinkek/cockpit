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
for (const [name, file] of [["shared", "lib/shared.ts"], ["metrics", "lib/metrics.ts"]]) {
	const source = fs.readFileSync(`${board}/${file}`, "utf8").replace(/from "\.\/shared"/g, "from \"./shared.mjs\"");
	fs.writeFileSync(`${work}/${name}.mjs`, ts.transpileModule(source, options).outputText);
}
' "$BOARD" "$WORK"

evaluate() {
  TZ=UTC node --input-type=module -e '
import * as metrics from "'"$WORK"'/metrics.mjs";
const result = new Function("m", `return (${process.argv[1]});`)(metrics);
process.stdout.write(typeof result === "string" ? result : JSON.stringify(result));
' "$1"
}

NOW='Date.parse("2026-10-14T12:00:00Z")'

printf "Test group: a duration reads in the largest units that fit\n"

assert_eq "under a minute" "<1m" "$(evaluate 'm.span(20000)')"
assert_eq "minutes" "45m" "$(evaluate 'm.span(45 * 60000)')"
assert_eq "hours and minutes" "3h 20m" "$(evaluate 'm.span(200 * 60000)')"
assert_eq "days and hours" "2d 4h" "$(evaluate 'm.span((52 * 60) * 60000)')"
assert_eq "ten days or more drops the hours" "12d" "$(evaluate 'm.span(12.2 * 86400000)')"

printf "Test group: each stage runs until the next column was reached\n"

DONE_CARD='{"id":"FEAT-1","status":"Done","created":"2026-10-01T09:00:00Z","dates":{"In Dev":"2026-10-02T09:00:00Z","Ready for CR":"2026-10-02T13:00:00Z","Done":"2026-10-03T09:00:00Z"}}'
assert_eq "stages sort by when each was reached and end at the next" \
  '[["In Dev",14400000,false],["Ready for CR",72000000,false],["Done",null,false]]' \
  "$(evaluate "m.stagesOf($DONE_CARD, $NOW).map((s) => [s.column, s.ms, s.current])")"

OPEN_CARD='{"id":"FEAT-2","status":"In CR","created":"2026-10-13T09:00:00Z","dates":{"In CR":"2026-10-14T10:00:00Z","In Dev":"2026-10-13T10:00:00Z"}}'
assert_eq "the column a card is in runs to now" \
  '[["In Dev",86400000,false],["In CR",7200000,true]]' \
  "$(evaluate "m.stagesOf($OPEN_CARD, $NOW).map((s) => [s.column, s.ms, s.current])")"

UNSTAMPED='{"id":"FEAT-3","status":"Sprint Backlog","created":"2026-10-13T09:00:00Z","moved":"2026-10-14T11:00:00Z","dates":{"Ready for Sprint":"2026-10-14T09:00:00Z"}}'
assert_eq "a column that stamps no date runs from when the card moved into it to now" \
  '[["Ready for Sprint",7200000,false],["Sprint Backlog",3600000,true]]' \
  "$(evaluate "m.stagesOf($UNSTAMPED, $NOW).map((s) => [s.column, s.ms, s.current])")"

BACK='{"id":"BUG-6","status":"In CR","created":"2026-10-12T09:00:00Z","moved":"2026-10-14T06:30:00Z","dates":{"In CR":"2026-10-13T09:00:00Z","Done":"2026-10-13T12:00:00Z"}}'
assert_eq "a card moved back to an earlier column ends on that column, running to now" \
  '[["In CR",10800000,false],["Done",66600000,false],["In CR",19800000,true]]' \
  "$(evaluate "m.stagesOf($BACK, $NOW).map((s) => [s.column, s.ms, s.current])")"

UNMOVED='{"id":"BUG-7","status":"In Dev","created":"2026-10-12T09:00:00Z","dates":{"In Dev":"2026-10-13T09:00:00Z","In CR":"2026-10-13T12:00:00Z"}}'
assert_eq "a card back in a column with no record of when keeps that column last with no duration" \
  '[["In Dev",10800000,false],["In CR",null,false],["In Dev",null,true]]' \
  "$(evaluate "m.stagesOf($UNMOVED, $NOW).map((s) => [s.column, s.ms, s.current])")"

TIED='{"id":"FEAT-5","status":"Done","created":"2026-10-01T09:00:00Z","dates":{"Done":"2026-10-02T09:00:00Z","In CR":"2026-10-02T09:00:00Z","Ready for Validation":"2026-10-02T09:00:00Z"}}'
assert_eq "stages reached in the same minute keep the order of the board's columns" \
  'In CR,Ready for Validation,Done' "$(evaluate "m.stagesOf($TIED, $NOW).map((s) => s.column).join()")"

printf "Test group: lead time, cycle time and age\n"

assert_eq "a done card has a lead time from created and a cycle time from In Dev" \
  '{"lead":172800000,"cycle":86400000,"age":null}' "$(evaluate "m.flowOf($DONE_CARD, $NOW)")"
assert_eq "an open card has an age and a cycle time running to now" \
  '{"lead":null,"cycle":93600000,"age":97200000}' "$(evaluate "m.flowOf($OPEN_CARD, $NOW)")"
REDONE='{"id":"FEAT-4","status":"Done","created":"2026-10-01T09:00:00Z","moved":"2026-10-03T09:00:00Z","dates":{"Done":"2026-09-01T00:00:00Z"}}'
assert_eq "a card done again counts from when it was last moved to Done" \
  '172800000' "$(evaluate "m.flowOf($REDONE, $NOW).lead")"
assert_eq "an epic is done in Epic Done" \
  '86400000' "$(evaluate 'm.flowOf({id:"EPIC-1",status:"Epic Done",created:"2026-10-01T00:00:00Z",dates:{"Epic Done":"2026-10-02T00:00:00Z"}}).lead')"

printf "Test group: an epic's progress counts its cards and their points\n"

EPIC_CARDS='[{"status":"Done","complexity":3},{"status":"In Dev","complexity":5},{"status":"Backlog"},{"status":"Deprioritised","complexity":8}]'
assert_eq "a deprioritised card is left out of the total" \
  '{"total":3,"done":1,"dropped":1,"points":8,"donePoints":3}' "$(evaluate "m.progressOf($EPIC_CARDS)")"
assert_eq "the share done is by points when the cards are sized" \
  '0.375' "$(evaluate "m.progressShare(m.progressOf($EPIC_CARDS))")"
assert_eq "the share done is by cards when none is sized" \
  '0.5' "$(evaluate 'm.progressShare(m.progressOf([{status:"Done"},{status:"In CR"}]))')"
assert_eq "an epic with no cards has done nothing" \
  '0' "$(evaluate 'm.progressShare(m.progressOf([]))')"

printf "Test group: a sprint burns down over its working days\n"

assert_eq "a sprint's days leave out the weekend" \
  '["2026-10-09","2026-10-12","2026-10-13"]' "$(evaluate 'm.sprintDays("2026-10-09", "2026-10-13")')"
assert_eq "a sprint that ends before it starts has no days" '[]' "$(evaluate 'm.sprintDays("2026-10-13", "2026-10-09")')"

SPRINT='{"start":"2026-10-12","end":"2026-10-15"}'
SPRINT_CARDS='[{"status":"Done","complexity":3,"dates":{"Done":"2026-10-12T15:00:00Z"}},{"status":"Done","complexity":2,"moved":"2026-10-13T10:00:00Z","dates":{"Done":"2026-10-01T10:00:00Z"}},{"status":"In Dev","complexity":5,"dates":{"Done":"2026-10-12T09:00:00Z"}},{"status":"Deprioritised","complexity":8}]'
assert_eq "the points left drop on the day each card was done and stop at now" \
  '{"days":["2026-10-12","2026-10-13","2026-10-14","2026-10-15"],"total":10,"ideal":[10,7.5,5,2.5,0],"remaining":[10,7,5,5,null]}' \
  "$(evaluate "m.burndownOf($SPRINT, $SPRINT_CARDS, \"points\", $NOW)")"
assert_eq "counting cards weighs each card as one" \
  '[3,2,1,1,null]' "$(evaluate "m.burndownOf($SPRINT, $SPRINT_CARDS, \"cards\", $NOW).remaining")"
assert_eq "the current sprint is the one today falls in" \
  'SPR-2' "$(evaluate 'm.currentSprint([{id:"SPR-1",start:"2026-10-01",end:"2026-10-09"},{id:"SPR-2",start:"2026-10-12",end:"2026-10-16"}], new Date(Date.parse("2026-10-14T12:00:00Z"))).id')"
assert_eq "between sprints the last one started is current" \
  'SPR-1' "$(evaluate 'm.currentSprint([{id:"SPR-1",start:"2026-10-01",end:"2026-10-09"},{id:"SPR-2",start:"2026-10-19",end:"2026-10-23"}], new Date(Date.parse("2026-10-14T12:00:00Z"))).id')"

printf "Test group: throughput by week and the median\n"

WEEKLY='[{"status":"Done","complexity":2,"dates":{"Done":"2026-10-12T10:00:00Z"}},{"status":"Done","complexity":3,"dates":{"Done":"2026-10-09T10:00:00Z"}},{"status":"Done","dates":{"Done":"2026-10-05T00:30:00Z"}},{"status":"In Dev","dates":{"Done":"2026-10-13T10:00:00Z"}},{"status":"Done","dates":{"Done":"2026-09-01T10:00:00Z"}}]'
assert_eq "each card done counts in the week from the Monday it was done in, and an older one in none" \
  '[{"start":"2026-10-05","done":2,"points":3},{"start":"2026-10-12","done":1,"points":2}]' \
  "$(evaluate "m.throughputOf($WEEKLY, 2, new Date($NOW))")"
assert_eq "the median of an even count is the mean of the middle two" '2.5' "$(evaluate 'm.median([4, 1, 3, 2])')"
assert_eq "nothing has no median" 'null' "$(evaluate 'm.median([])')"

finish
