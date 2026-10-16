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

export CLAUDE_SHARED_DIR="$REPO/agents/claude"
export COCKPIT_BOARD_DIR="$WORK/board"
export TICKET_CLAIM_LOCK_DIR="$WORK/claims"
export TICKET_STATE_DIR="$WORK/state"
export BOARD_CARD="$REPO/marketplace/plugins/cockpit/scripts/board-card"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

node -e '
const fs = require("node:fs");
const [board, work] = process.argv.slice(1);
const ts = require(`${board}/node_modules/typescript`);
const options = { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } };
for (const name of ["board", "shared"]) {
	const source = fs.readFileSync(`${board}/lib/${name}.ts`, "utf8").replace(/from "\.\/shared"/g, "from \"./shared.mjs\"");
	fs.writeFileSync(`${work}/${name}.mjs`, ts.transpileModule(source, options).outputText);
}
' "$BOARD" "$WORK"

"$BOARD_CARD" init >/dev/null
"$BOARD_CARD" create --kind project --name Home >/dev/null
"$BOARD_CARD" create --kind epic --name Home --project PRJ-1 >/dev/null
"$BOARD_CARD" create --epic EPIC-1 --name "Dragged" >/dev/null
"$BOARD_CARD" create --epic EPIC-1 --name "Dragged back" --status "In Dev" >/dev/null

change_status() {
  node --input-type=module -e '
import { changeStatus, readRecord } from "'"$WORK"'/board.mjs";
await changeStatus(await readRecord(process.argv[1]), process.argv[2]);
' "$1" "$2"
}

stamps() { "$BOARD_CARD" show "$1" --json | jq --raw-output '.dates | keys | join(",")'; }

printf "Test group: a card moved in the app is stamped only where it lands, as Notion's automation did\n"

change_status FEAT-1 Done
assert_eq "Backlog to Done lands the card in Done" "Done" "$("$BOARD_CARD" show FEAT-1 --json | jq --raw-output .status)"
assert_eq "and stamps Done alone, leaving every column it skipped empty" "Done" "$(stamps FEAT-1)"

change_status FEAT-2 "Ready for TR"
assert_eq "a move backwards stamps the column it lands in" "In Dev,Ready for TR" "$(stamps FEAT-2)"
before="$("$BOARD_CARD" show FEAT-2 --json | jq --raw-output '.dates["In Dev"]')"
change_status FEAT-2 "In Dev"
assert_eq "and coming back keeps the first arrival's stamp" "$before" "$("$BOARD_CARD" show FEAT-2 --json | jq --raw-output '.dates["In Dev"]')"

finish
