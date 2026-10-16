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

lanes() {
  node --input-type=module -e '
import * as view from "'"$WORK"'/view.mjs";
const [kind, groupBy, stubs] = process.argv.slice(1);
const context = { names: { epic: { "EPIC-1": "One", "EPIC-2": "Two" } }, order: { epic: ["EPIC-2", "EPIC-1"] }, epicProjects: {} };
const lanes = view.swimlanesOf(JSON.parse(stubs), kind, groupBy, context);
process.stdout.write(lanes === null ? "none" : lanes.map((lane) => `${lane.label}=${lane.stubs.map((stub) => stub.id).join("+")}`).join(" "));
' "$1" "$2" "$3"
}

dropped() {
  node --input-type=module -e '
import * as view from "'"$WORK"'/view.mjs";
const [groupBy, stub, from, to] = process.argv.slice(1);
const lane = (text) => (text ? JSON.parse(text) : undefined);
const sets = view.droppedInto(JSON.parse(stub), lane(from), lane(to), groupBy, "card");
process.stdout.write(sets === null ? "refused" : sets.map((set) => `${set.field}=${set.value}`).join(" "));
' "$1" "$2" "$3" "$4"
}

CARDS='[{"id":"FEAT-1","epic":"EPIC-1","labels":["ui"]},{"id":"FEAT-2","epic":"EPIC-2","urgent":true},{"id":"FEAT-3","epic":"EPIC-1"}]'
URGENT='{"key":"urgent","label":"Urgent","value":"true","urgent":true,"stubs":[]}'

printf "Test group: the board's swimlanes\n"

assert_eq "no grouping and nothing urgent draws no swimlanes" "none" "$(lanes card '' '[{"id":"FEAT-1"}]')"
assert_eq "an urgent card sits in an Urgent lane above everything else" "Urgent=FEAT-2 Everything else=FEAT-1+FEAT-3" "$(lanes card '' "$CARDS")"
assert_eq "grouped by epic, the lanes follow the epics' priority under the Urgent lane" "Urgent=FEAT-2 One=FEAT-1+FEAT-3" "$(lanes card epic "$CARDS")"
assert_eq "grouped by label, a card with none goes last" "Urgent=FEAT-2 ui=FEAT-1 No label=FEAT-3" "$(lanes card label "$CARDS")"
assert_eq "an epic is never put in the Urgent lane" "One=FEAT-2" "$(lanes epic label '[{"id":"FEAT-2","urgent":true,"labels":["One"]}]')"

printf "\nTest group: dropping a card into a swimlane sets its field\n"

assert_eq "into the Urgent lane flags it urgent" "urgent=true" "$(dropped epic '{"id":"FEAT-1","epic":"EPIC-1"}' '' "$URGENT")"
assert_eq "out of the Urgent lane into an epic's takes the flag off and sets the epic" "urgent= epic=EPIC-2" \
  "$(dropped epic '{"id":"FEAT-1","epic":"EPIC-1","urgent":true}' "$URGENT" '{"key":"epic:EPIC-2","value":"EPIC-2","urgent":false}')"
assert_eq "into a lane with no epic is refused" "refused" \
  "$(dropped epic '{"id":"FEAT-1","epic":"EPIC-1"}' '{"key":"epic:EPIC-1","value":"EPIC-1","urgent":false}' '{"key":"epic:","value":null,"urgent":false}')"
assert_eq "from one label's lane to another swaps that label and keeps the rest" "labels=api, infra" \
  "$(dropped label '{"id":"FEAT-1","labels":["ui","infra"]}' '{"key":"label:ui","value":"ui","urgent":false}' '{"key":"label:api","value":"api","urgent":false}')"
assert_eq "into No label takes every label off" "labels=" \
  "$(dropped label '{"id":"FEAT-1","labels":["ui","infra"]}' '{"key":"label:ui","value":"ui","urgent":false}' '{"key":"label:","value":null,"urgent":false}')"
assert_eq "within its own lane changes nothing" "" \
  "$(dropped sprint '{"id":"FEAT-1","sprint":"SPR-1"}' '{"key":"sprint:SPR-1","value":"SPR-1","urgent":false}' '{"key":"sprint:SPR-1","value":"SPR-1","urgent":false}')"
assert_eq "into No sprint clears the sprint" "sprint=" \
  "$(dropped sprint '{"id":"FEAT-1","sprint":"SPR-1"}' '{"key":"sprint:SPR-1","value":"SPR-1","urgent":false}' '{"key":"sprint:","value":null,"urgent":false}')"

finish
