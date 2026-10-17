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
for (const [name, file] of [["shared", "lib/shared.ts"], ["view", "app/view.ts"]]) {
	const source = fs.readFileSync(`${board}/${file}`, "utf8").replace(/from "@\/lib\/shared"/g, "from \"./shared.mjs\"");
	fs.writeFileSync(`${work}/${name}.mjs`, ts.transpileModule(source, options).outputText);
}
' "$BOARD" "$WORK"

kept() {
  node --input-type=module -e '
import { matches, restoredView } from "'"$WORK"'/view.mjs";
const [cards, change] = process.argv.slice(1).map((text) => JSON.parse(text));
const view = restoredView("card", change);
process.stdout.write(cards.filter((card) => matches({ created: "", body: "", ...card }, view)).map((card) => card.id).join(" "));
' "$1" "$2"
}

restored() {
  node --input-type=module -e '
import { restoredView } from "'"$WORK"'/view.mjs";
const view = restoredView("card", JSON.parse(process.argv[1]));
process.stdout.write(`${JSON.stringify(view.projects)} ${JSON.stringify(view.epics)}`);
' "$1"
}

cycles() {
  node --input-type=module -e '
import { cycled, NO_CHOICE } from "'"$WORK"'/view.mjs";
const once = cycled(NO_CHOICE, process.argv[1]);
const twice = cycled(once, process.argv[1]);
process.stdout.write([once, twice, cycled(twice, process.argv[1])].map((choice) => JSON.stringify(choice)).join(" "));
' "$1"
}

NOW="$(node -e 'process.stdout.write(String(Date.now()))')"
stamp() {
  node -e 'process.stdout.write(new Date(Number(process.argv[1]) - Number(process.argv[2]) * 86400000).toISOString())' "$NOW" "$1"
}

CARDS='[
  {"id":"FEAT-1","name":"a","status":"Backlog","epic":null},
  {"id":"FEAT-2","name":"b","status":"Sprint Backlog","epic":"EPIC-1"},
  {"id":"FEAT-3","name":"c","status":"In CR","epic":null},
  {"id":"FEAT-4","name":"d","status":"Ready for Validation","epic":"EPIC-2"},
  {"id":"FEAT-5","name":"e","status":"Ready for Sprint","epic":null},
  {"id":"FEAT-6","name":"f","status":"Done","epic":null,"dates":{"Done":"'"$(stamp 2)"'"}},
  {"id":"FEAT-7","name":"g","status":"Done","epic":null,"dates":{"Done":"'"$(stamp 9)"'"}},
  {"id":"FEAT-8","name":"h","status":"Done","epic":null},
  {"id":"FEAT-9","name":"i","status":"Deprioritised","epic":null},
  {"id":"FEAT-10","name":"j","status":"In BR by AI","epic":null},
  {"id":"FEAT-11","name":"k","status":"Ready for TR","epic":"EPIC-1"},
  {"id":"FEAT-12","name":"l","status":"Done","epic":"EPIC-2","dates":{"Done":"'"$(stamp 30)"'"},"moved":"'"$(stamp 1)"'"}
]'

printf "Test group: the board shows every column\n"

assert_eq "a view with no filters keeps every card" \
  "FEAT-1 FEAT-2 FEAT-3 FEAT-4 FEAT-5 FEAT-6 FEAT-7 FEAT-8 FEAT-9 FEAT-10 FEAT-11 FEAT-12" "$(kept "$CARDS" '{}')"
assert_eq "a saved view naming a column preset the board no longer has keeps every card" \
  "FEAT-1 FEAT-2 FEAT-3 FEAT-4 FEAT-5 FEAT-6 FEAT-7 FEAT-8 FEAT-9 FEAT-10 FEAT-11 FEAT-12" "$(kept "$CARDS" '{"preset":"sprint"}')"

printf "Test group: the epic filter keeps the cards of any epic it includes and of none it excludes\n"

assert_eq "one included epic keeps its cards" "FEAT-2 FEAT-11" "$(kept "$CARDS" '{"epics":{"include":["EPIC-1"],"exclude":[]}}')"
assert_eq "two included epics keep the cards of either" "FEAT-2 FEAT-4 FEAT-11 FEAT-12" \
  "$(kept "$CARDS" '{"epics":{"include":["EPIC-1","EPIC-2"],"exclude":[]}}')"
assert_eq "an excluded epic keeps the cards of others and of none" \
  "FEAT-1 FEAT-3 FEAT-4 FEAT-5 FEAT-6 FEAT-7 FEAT-8 FEAT-9 FEAT-10 FEAT-12" "$(kept "$CARDS" '{"epics":{"include":[],"exclude":["EPIC-1"]}}')"
assert_eq "an epic both included and excluded keeps none of its cards" "FEAT-4 FEAT-12" \
  "$(kept "$CARDS" '{"epics":{"include":["EPIC-1","EPIC-2"],"exclude":["EPIC-1"]}}')"

printf "Test group: a view saved with one epic or all but one still loads\n"

assert_eq "an old view naming one epic keeps its cards" "FEAT-2 FEAT-11" "$(kept "$CARDS" '{"epic":"EPIC-1"}')"
assert_eq "an old view naming all but one epic keeps the cards of others and of none" \
  "FEAT-1 FEAT-3 FEAT-4 FEAT-5 FEAT-6 FEAT-7 FEAT-8 FEAT-9 FEAT-10 FEAT-12" "$(kept "$CARDS" '{"epic":"!EPIC-1"}')"
assert_eq "an old view naming no epic keeps every card" \
  "FEAT-1 FEAT-2 FEAT-3 FEAT-4 FEAT-5 FEAT-6 FEAT-7 FEAT-8 FEAT-9 FEAT-10 FEAT-11 FEAT-12" "$(kept "$CARDS" '{"epic":"none"}')"
assert_eq "an old view comes back in the new shape" '{"include":["PRJ-1"],"exclude":[]} {"include":[],"exclude":["EPIC-1"]}' \
  "$(restored '{"project":"PRJ-1","epic":"!EPIC-1"}')"

printf "Test group: the project filter keeps the cards whose own project or whose epic's project it includes and does not exclude\n"

PROJECTED='[{"id":"FEAT-1","name":"a","status":"Backlog","epic":"EPIC-2","project":"PRJ-2"},{"id":"FEAT-2","name":"b","status":"Backlog","epic":"EPIC-1","project":"PRJ-1"},{"id":"FEAT-3","name":"c","status":"Backlog","epic":"EPIC-3","project":"PRJ-3"}]'
assert_eq "an included project keeps the cards that carry it" "FEAT-2" \
  "$(kept "$PROJECTED" '{"projects":{"include":["PRJ-1"],"exclude":[]}}')"
assert_eq "two included projects keep the cards of either" "FEAT-1 FEAT-2" \
  "$(kept "$PROJECTED" '{"projects":{"include":["PRJ-1","PRJ-2"],"exclude":[]}}')"
assert_eq "an excluded project keeps the cards of the others" "FEAT-1 FEAT-3" \
  "$(kept "$PROJECTED" '{"projects":{"include":[],"exclude":["PRJ-1"]}}')"
assert_eq "no project keeps every card" "FEAT-1 FEAT-2 FEAT-3" "$(kept "$PROJECTED" '{}')"
assert_eq "an old view naming one project keeps its cards" "FEAT-2" "$(kept "$PROJECTED" '{"project":"PRJ-1"}')"

printf "Test group: a row of the filter list cycles through include, exclude and neither\n"

assert_eq "a row cycles from neither to include to exclude and back" \
  '{"include":["EPIC-1"],"exclude":[]} {"include":[],"exclude":["EPIC-1"]} {"include":[],"exclude":[]}' "$(cycles EPIC-1)"

printf "Test group: the Overrunning toggle and the days in column sort\n"

OVERRUN='[
  {"id":"FEAT-20","name":"a","status":"In Dev","overrunning":true,"days_in_column":4},
  {"id":"FEAT-21","name":"b","status":"Backlog","overrunning":true},
  {"id":"FEAT-22","name":"c","status":"In CR","overrunning":false,"days_in_column":9},
  {"id":"FEAT-23","name":"d","status":"Ready for Validation","overrunning":true,"days_in_column":1}
]'
assert_eq "Overrunning keeps the cards overrunning in dev, review or validation" \
  "FEAT-20 FEAT-23" "$(kept "$OVERRUN" '{"overrunning":true}')"

sorted_by() {
  node --input-type=module -e '
import { sorter } from "'"$WORK"'/view.mjs";
const cards = JSON.parse(process.argv[1]);
process.stdout.write(cards.map((card) => ({ created: "", body: "", ...card })).sort(sorter(process.argv[2])).map((card) => card.id).join(" "));
' "$1" "$2"
}
assert_eq "Longest in column puts the card in its column longest first" \
  "FEAT-22 FEAT-20 FEAT-23 FEAT-21" "$(sorted_by "$OVERRUN" days)"

finish
