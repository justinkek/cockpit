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
const { outputText } = ts.transpileModule(fs.readFileSync(`${board}/lib/blocks.ts`, "utf8"), {
	compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
});
fs.writeFileSync(`${work}/blocks.mjs`, outputText);
' "$BOARD" "$WORK"

blocks() {
  node --input-type=module -e '
import { appendBlock, blockSource, blockSpans, replaceBlock } from "'"$WORK"'/blocks.mjs";
const [operation, body, which, text] = process.argv.slice(1);
const spans = blockSpans(body);
if (operation === "spans") process.stdout.write(spans.map((span) => `${span.start}-${span.end}`).join(" "));
if (operation === "source") process.stdout.write(blockSource(body, spans[Number(which)]));
if (operation === "replace") process.stdout.write(replaceBlock(body, spans[Number(which)], text));
if (operation === "append") process.stdout.write(appendBlock(body, text));
if (operation === "roundtrip") process.stdout.write(spans.every((span) => replaceBlock(body, span, blockSource(body, span)) === body) ? "same" : "changed");
' "$@"
}

check() {
  local name="$1" expected="$2" actual
  shift 2
  actual="$(blocks "$@"; printf x)"
  actual="${actual%x}"
  if [ "$actual" = "$expected" ]; then
    assert_ok "$name"
  else
    assert_ko "$name" "expected '$expected', got '$actual'"
  fi
}

TECH=$'## Tech Steps\n\n```diff\n  board/\n+   lib/blocks.ts      the spans\n!   app/content.tsx    the editor\n```\n\n```mermaid\nsequenceDiagram\n  A->>B: save\n```\n\n<details>\n<summary>Board</summary>\n\n| Step | Change |\n| ---- | ------ |\n| 1 | add it |\n\n</details>\n'

printf "Test group: the content splits into the blocks a click edits\n"

check "headings, paragraphs and blank lines split apart" "0-0 2-3 5-5" spans $'# Title\n\nline one\nline two\n\nlast'
check "a list runs through its nested items and ends at a blank line" "0-3 5-5" spans $'- one\n  - nested\n  more of nested\n1. two\n\nafter'
check "a checklist is one block" "0-1" spans $'- [ ] first\n- [x] second'
check "a code block runs from its fence to its closing fence, blank lines and all" "0-4 6-6" spans $'```bash\necho a\n\n# not a heading\n```\n\nafter'
check "a quote is one block, a table another" "0-1 2-4" spans $'> one\n> two\n| a | b |\n| - | - |\n| 1 | 2 |'
check "toggle lines are not blocks, but what sits inside them is" "0-0 3-3 6-6" spans $'# Head\n<details>\n<summary>Title</summary>\ninside\n</details>\n\nafter'
check "an unclosed fence runs to the end" "0-2" spans $'```\ncode\nmore'

printf "\nTest group: a block's source is its exact lines\n"

check "the mermaid block's source keeps its fences" $'```mermaid\nsequenceDiagram\n  A->>B: save\n```' source "$TECH" 2
check "the file tree keeps its spacing" $'```diff\n  board/\n+   lib/blocks.ts      the spans\n!   app/content.tsx    the editor\n```' source "$TECH" 1

printf "\nTest group: saving a block changes only its own span\n"

check "putting every block back unchanged gives the body byte for byte" "same" roundtrip "$TECH"
check "putting a block back with trailing spaces and tabs elsewhere keeps them" "same" roundtrip $'a  \n\n\tb\t\n\n\n```\n  x  \n```\n'
check "editing a paragraph leaves the file tree and the diagram as they were" \
  "${TECH/\#\# Tech Steps/## Tech steps}" replace "$TECH" 0 "## Tech steps"
check "editing the file tree changes only its lines" \
  "${TECH/the editor/the block editor}" replace "$TECH" 1 $'```diff\n  board/\n+   lib/blocks.ts      the spans\n!   app/content.tsx    the block editor\n```'
check "a block saved with trailing newlines keeps the blank line after it as it was" \
  $'one\n\ntwo' replace $'old\n\ntwo' 0 $'one\n\n\n'
check "a block can grow to several lines" $'a\nb\nc\n\nd' replace $'x\n\nd' 0 $'a\nb\nc'

printf "\nTest group: emptying a block deletes it with the blank line that set it apart\n"

check "a middle block" $'a\n\nc' replace $'a\n\nb\n\nc' 1 ""
check "the first block" $'b\n' replace $'a\n\nb\n' 0 ""
check "the last block with a trailing newline" $'a\n' replace $'a\n\nb\n' 1 ""
check "the last block without one" "a" replace $'a\n\nb' 1 ""
check "the only block" "" replace "a" 0 "   "

printf "\nTest group: a new block goes at the end\n"

check "after the last block, keeping the trailing newline" $'a\n\nb\n' append $'a\n' 0 "b"
check "after a body with no trailing newline" $'a\n\nb' append "a" 0 $'b\n'
check "into an empty body" "b" append "" 0 "b"
check "nothing added for an empty block" "a" append "a" 0 "  "

finish
