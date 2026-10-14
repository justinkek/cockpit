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

run() {
  node --input-type=module -e '
import * as view from "'"$WORK"'/view.mjs";
const [kind, saved, steps] = process.argv.slice(1);
let current = view.restoredView(kind, JSON.parse(saved));
for (const [layout, column] of JSON.parse(steps)) {
	current = { ...current, layout };
	current = { ...current, ...view.toggledIn(current, column) };
}
const shown = (layout) => view.collapsedIn({ ...current, layout }).join(",");
process.stdout.write(`board:${shown("board")} list:${shown("list")}`);
' "$1" "$2" "$3"
}

printf "Test group: the Board and the List each keep their own collapsed columns\n"

assert_eq "a fresh card view collapses Done and Deprioritised in both" \
  "board:Done,Deprioritised list:Done,Deprioritised" "$(run card '{}' '[]')"
assert_eq "a fresh epic view collapses Epic Done in both" \
  "board:Epic Done list:Epic Done" "$(run epic '{}' '[]')"
assert_eq "opening a column on the Board leaves the List as it was" \
  "board:Deprioritised list:Done,Deprioritised" "$(run card '{}' '[["board","Done"]]')"
assert_eq "closing a group in the List leaves the Board as it was" \
  "board:Done,Deprioritised list:Done,Deprioritised,Backlog" "$(run card '{}' '[["list","Backlog"]]')"
assert_eq "a change in each stays in each" \
  "board:Done,Deprioritised,In Dev list:Deprioritised" "$(run card '{}' '[["board","In Dev"],["list","Done"]]')"

printf "\nTest group: a view saved before the split keeps what the Board had collapsed\n"

assert_eq "the Board keeps the saved collapse, and the List starts from it" \
  "board:Backlog,Done list:Backlog,Done" "$(run card '{"layout":"list","collapsed":["Backlog","Done"]}' '[]')"
assert_eq "an empty saved collapse stays empty" "board: list:" "$(run card '{"collapsed":[]}' '[]')"
assert_eq "a view saved after the split keeps both" \
  "board:Done list:Backlog" "$(run card '{"collapsed":["Done"],"listCollapsed":["Backlog"]}' '[]')"

finish
