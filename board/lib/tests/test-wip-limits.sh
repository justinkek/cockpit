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
const { outputText } = ts.transpileModule(fs.readFileSync(`${board}/lib/shared.ts`, "utf8"), {
	compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
});
fs.writeFileSync(`${work}/shared.mjs`, outputText);
' "$BOARD" "$WORK"

limit() {
  node --input-type=module -e '
import { wipLimit } from "'"$WORK"'/shared.mjs";
const found = wipLimit(process.argv[1], process.argv[2]);
process.stdout.write(found === null ? "<none>" : String(found));
' "$1" "$2"
}

printf "Test group: a column's WIP limit\n"

assert_eq "In CR holds two" "2" "$(limit card "In CR")"
assert_eq "a column a card is worked in holds five" "5" "$(limit card "In Dev")"
assert_eq "a refinement queue holds five" "5" "$(limit card "Ready for BR by AI")"
assert_eq "the Backlog has no limit" "<none>" "$(limit card "Backlog")"
assert_eq "Ready for Sprint has no limit" "<none>" "$(limit card "Ready for Sprint")"
assert_eq "the Sprint Backlog has no limit" "<none>" "$(limit card "Sprint Backlog")"
assert_eq "Done has no limit" "<none>" "$(limit card "Done")"
assert_eq "Deprioritised has no limit" "<none>" "$(limit card "Deprioritised")"
assert_eq "an epic column has no limit" "<none>" "$(limit epic "In FD")"

finish
