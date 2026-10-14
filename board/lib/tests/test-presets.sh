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
import { matches, DEFAULT_VIEW } from "'"$WORK"'/view.mjs";
const [cards, change] = process.argv.slice(1).map((text) => JSON.parse(text));
const view = { ...DEFAULT_VIEW, ...change };
process.stdout.write(cards.filter((card) => matches({ created: "", body: "", ...card }, view)).map((card) => card.id).join(" "));
' "$1" "$2"
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

printf "Test group: a view keeps the cards of its columns\n"

assert_eq "All columns keeps every card" \
  "FEAT-1 FEAT-2 FEAT-3 FEAT-4 FEAT-5 FEAT-6 FEAT-7 FEAT-8 FEAT-9 FEAT-10 FEAT-11 FEAT-12" "$(kept "$CARDS" '{"preset":"all"}')"
assert_eq "the Sprint Board keeps Sprint Backlog to Ready for Validation" \
  "FEAT-2 FEAT-3 FEAT-4" "$(kept "$CARDS" '{"preset":"sprint"}')"
assert_eq "the current week keeps open cards and those done in the last 7 days" \
  "FEAT-1 FEAT-2 FEAT-3 FEAT-4 FEAT-5 FEAT-6 FEAT-10 FEAT-11 FEAT-12" "$(kept "$CARDS" '{"preset":"week"}')"
assert_eq "refinement triage keeps the BR and TR cards with no epic" \
  "FEAT-10" "$(kept "$CARDS" '{"preset":"triage"}')"
assert_eq "a view nobody knows reads as All columns" \
  "FEAT-1 FEAT-2 FEAT-3 FEAT-4 FEAT-5 FEAT-6 FEAT-7 FEAT-8 FEAT-9 FEAT-10 FEAT-11 FEAT-12" "$(kept "$CARDS" '{"preset":"nonsense"}')"

DONE_NOW='[{"id":"FEAT-13","name":"m","status":"Done","epic":null,"moved":"'"$(stamp 0)"'"}]'
assert_eq "a card moved to Done just now stays in the current week before its Done date arrives" \
  "FEAT-13" "$(kept "$DONE_NOW" '{"preset":"week"}')"

printf "Test group: the epic filter keeps one epic, no epic, or all but one\n"

assert_eq "one epic keeps its cards" "FEAT-2 FEAT-11" "$(kept "$CARDS" '{"epic":"EPIC-1"}')"
assert_eq "no epic keeps the cards that have none" \
  "FEAT-1 FEAT-3 FEAT-5 FEAT-6 FEAT-7 FEAT-8 FEAT-9 FEAT-10" "$(kept "$CARDS" '{"epic":"none"}')"
assert_eq "all but one epic keeps the cards of others and of none" \
  "FEAT-1 FEAT-3 FEAT-4 FEAT-5 FEAT-6 FEAT-7 FEAT-8 FEAT-9 FEAT-10 FEAT-12" "$(kept "$CARDS" '{"epic":"!EPIC-1"}')"
assert_eq "the epic filter stacks on a view" "FEAT-3" "$(kept "$CARDS" '{"preset":"sprint","epic":"none"}')"

finish
