#!/usr/bin/env bash

repo_root_through_symlink() {
  cd "$(dirname "$0")" && cd "$(pwd -P)/../../.." && pwd
}

REPO="$(repo_root_through_symlink)"
BOARD="$REPO/board"

pass=0
fail=0

assert_ok() {
  printf "  OK  %s\n" "$1"
  pass=$((pass + 1))
}

assert_ko() {
  printf "  KO  %s — %s\n" "$1" "$2"
  fail=$((fail + 1))
}

finish() {
  printf "\n%d passed, %d failed\n" "$pass" "$fail"
  [ "$fail" -eq 0 ]
  exit
}

if [ ! -d "$BOARD/node_modules/typescript" ]; then
  assert_ko "the board's packages are installed" "run npm ci in $BOARD, or nothing below can be checked"
  finish
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

node -e '
const fs = require("node:fs");
const [board, work] = process.argv.slice(1);
const ts = require(`${board}/node_modules/typescript`);
const { outputText } = ts.transpileModule(fs.readFileSync(`${board}/lib/anchor.ts`, "utf8"), {
	compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
});
fs.writeFileSync(`${work}/anchor.mjs`, outputText);
' "$BOARD" "$WORK"

anchor() {
  node --input-type=module -e '
import { anchorFor } from "'"$WORK"'/anchor.mjs";
const found = anchorFor(process.argv[1], process.argv[2]);
process.stdout.write(found === null ? "<none>" : found);
' "$1" "$2"
}

check() {
  local name="$1" selected="$2" body="$3" expected="$4" actual
  actual="$(anchor "$selected" "$body")"
  if [ "$actual" = "$expected" ]; then
    assert_ok "$name"
  else
    assert_ko "$name" "expected '$expected', got '$actual'"
  fi
}

printf "Test group: a selection on the rendered page names the text in the card's source\n"

check "plain text is its own anchor" \
  "open the card" "- [ ] When I open the card on the board" "open the card"
check "a selection across bold text keeps the bold markers" \
  "is the open epic" "and that **is** the open epic" "**is** the open epic"
check "a selection across inline code keeps the backticks" \
  "moved from -1 to -2" 'the svg id moved from `-1` to `-2` and' 'moved from `-1` to `-2`'
check "a selection across a link keeps the link's target" \
  "see the docs now" "see [the docs](https://example.com) now" "see [the docs](https://example.com) now"
check "surrounding and doubled whitespace is ignored" \
  "  open   the card " "When I open the card" "open the card"
check "a selection spanning two lines has no anchor" \
  "first line second line" $'first line\n- second line' "<none>"
check "text the card does not hold has no anchor" \
  "nowhere" "some body" "<none>"
check "an empty selection has no anchor" \
  "   " "some body" "<none>"

finish
